//! Extracts raster images from a PDF and returns a copy with them replaced by
//! 1x1 white pixels, so OCR sees a small text-only PDF with the layout intact.

use std::collections::{BTreeMap, HashSet};

use image::{ColorType, ImageEncoder};
use lopdf::{Dictionary, Document, Object, ObjectId, Stream};

/// One raster image recovered from the PDF.
pub struct ExtractedImage {
    /// 1-based page the image is drawn on. When an image is shared by several
    /// pages this is the first one that referenced it.
    pub page: u32,
    /// Position of this image within its page, in resource order.
    pub index_on_page: u32,
    /// The XObject's resource name, e.g. `Im1`.
    pub name: String,
    pub width: u32,
    pub height: u32,
    /// `image/jpeg` or `image/png`.
    pub media_type: String,
    pub bytes: Vec<u8>,
}

/// The result of one strip pass.
pub struct StrippedPdf {
    /// The image-free PDF, ready to be base64'd and uploaded.
    pub pdf: Vec<u8>,
    pub images: Vec<ExtractedImage>,
    pub page_count: u32,
    /// Byte size of the original file, for logging the saving.
    pub original_bytes: u64,
    /// Images that were found but could not be decoded, and so were left in
    /// the PDF for the OCR pass to deal with.
    pub skipped: u32,
}

/// Extracts every raster image at least `min_width` x `min_height` and blanks it out.
/// Smaller images (rules, logos, glyphs) are left untouched.
pub fn extract_and_strip_images(
    pdf_path: String,
    min_width: u32,
    min_height: u32,
) -> Result<StrippedPdf, String> {
    let original_bytes = std::fs::metadata(&pdf_path)
        .map_err(|e| format!("Failed to read PDF metadata: {e}"))?
        .len();

    let mut doc = Document::load(&pdf_path).map_err(|e| format!("Failed to open PDF: {e}"))?;

    let pages: BTreeMap<u32, ObjectId> = doc.get_pages();
    let page_count = pages.len() as u32;

    let mut images = Vec::new();
    let mut skipped = 0u32;
    // An XObject can be shared between pages; extract and blank it once.
    let mut seen: HashSet<ObjectId> = HashSet::new();
    let mut to_blank: Vec<ObjectId> = Vec::new();

    for (page_number, page_id) in pages {
        let xobjects = match page_image_xobjects(&doc, page_id) {
            Some(list) => list,
            None => continue,
        };

        let mut index_on_page = 0u32;
        for (name, object_id) in xobjects {
            if seen.contains(&object_id) {
                continue;
            }

            let stream = match doc.get_object(object_id).and_then(|o| o.as_stream()) {
                Ok(stream) => stream,
                Err(_) => continue,
            };
            if !is_image(&stream.dict) {
                continue;
            }

            let width = dict_u32(&doc, &stream.dict, b"Width").unwrap_or(0);
            let height = dict_u32(&doc, &stream.dict, b"Height").unwrap_or(0);
            if width < min_width || height < min_height {
                continue;
            }

            match decode_image(&doc, stream) {
                Some((media_type, bytes)) => {
                    seen.insert(object_id);
                    to_blank.push(object_id);
                    images.push(ExtractedImage {
                        page: page_number,
                        index_on_page,
                        name,
                        width,
                        height,
                        media_type,
                        bytes,
                    });
                    index_on_page += 1;
                }
                // Undecodable: leave it in place so the OCR pass still sees it.
                None => skipped += 1,
            }
        }
    }

    for object_id in to_blank {
        if let Some(object) = doc.objects.get_mut(&object_id) {
            *object = Object::Stream(blank_pixel());
        }
    }

    let mut pdf = Vec::new();
    doc.save_to(&mut pdf)
        .map_err(|e| format!("Failed to write stripped PDF: {e}"))?;

    Ok(StrippedPdf {
        pdf,
        images,
        page_count,
        original_bytes,
        skipped,
    })
}

/// The image XObjects a page's resources expose, in a stable order.
fn page_image_xobjects(doc: &Document, page_id: ObjectId) -> Option<Vec<(String, ObjectId)>> {
    let (resource_dict, resource_ids) = doc.get_page_resources(page_id).ok()?;

    let mut out = Vec::new();
    let mut collect = |resources: &Dictionary| {
        if let Ok(xobject) = resources.get(b"XObject").and_then(|o| {
            if let Ok(id) = o.as_reference() {
                doc.get_object(id).and_then(|o| o.as_dict())
            } else {
                o.as_dict()
            }
        }) {
            for (key, value) in xobject.iter() {
                if let Ok(id) = value.as_reference() {
                    out.push((String::from_utf8_lossy(key).into_owned(), id));
                }
            }
        }
    };

    if let Some(resources) = resource_dict {
        collect(resources);
    }
    for id in resource_ids {
        if let Ok(resources) = doc.get_object(id).and_then(|o| o.as_dict()) {
            collect(resources);
        }
    }

    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

fn is_image(dict: &Dictionary) -> bool {
    dict.get(b"Subtype")
        .and_then(|o| o.as_name())
        .map(|name| name == b"Image")
        .unwrap_or(false)
}

/// Decodes an image XObject: JPEG (DCTDecode) passes through, others become PNG.
fn decode_image(doc: &Document, stream: &Stream) -> Option<(String, Vec<u8>)> {
    let filters = filter_names(&stream.dict);

    if filters.iter().any(|f| f == "DCTDecode") {
        return Some(("image/jpeg".to_string(), stream.content.clone()));
    }
    // JPX is a valid JPEG 2000 file but is not decodable here and is not
    // widely supported downstream; leave it in the PDF.
    if filters
        .iter()
        .any(|f| f == "JPXDecode" || f == "JBIG2Decode")
    {
        return None;
    }

    let width = dict_u32(doc, &stream.dict, b"Width")?;
    let height = dict_u32(doc, &stream.dict, b"Height")?;
    let bits = dict_u32(doc, &stream.dict, b"BitsPerComponent").unwrap_or(8);
    if bits != 8 {
        // 1-bit masks and 16-bit samples would each need their own unpacking
        // path; they are rare as figures and not worth the surface area.
        return None;
    }

    let components = color_space_components(doc, &stream.dict)?;
    let mut data = stream.decompressed_content().ok()?;

    let expected = (width as usize) * (height as usize) * components;
    if data.len() < expected {
        return None;
    }
    data.truncate(expected);

    // CMYK has no PNG representation; convert to RGB first.
    let (color, pixels) = match components {
        1 => (ColorType::L8, data),
        3 => (ColorType::Rgb8, data),
        4 => {
            let mut rgb = Vec::with_capacity((width as usize) * (height as usize) * 3);
            for pixel in data.as_chunks::<4>().0 {
                let (c, m, y, k) = (
                    pixel[0] as u32,
                    pixel[1] as u32,
                    pixel[2] as u32,
                    pixel[3] as u32,
                );
                // CMYK samples are ink amounts, so complement before applying black.
                rgb.push(((255 - c) * (255 - k) / 255) as u8);
                rgb.push(((255 - m) * (255 - k) / 255) as u8);
                rgb.push(((255 - y) * (255 - k) / 255) as u8);
            }
            (ColorType::Rgb8, rgb)
        }
        _ => return None,
    };

    let mut png = Vec::new();
    image::codecs::png::PngEncoder::new(&mut png)
        .write_image(&pixels, width, height, color.into())
        .ok()?;
    Some(("image/png".to_string(), png))
}

fn filter_names(dict: &Dictionary) -> Vec<String> {
    match dict.get(b"Filter") {
        Ok(Object::Name(name)) => vec![String::from_utf8_lossy(name).into_owned()],
        Ok(Object::Array(items)) => items
            .iter()
            .filter_map(|o| o.as_name().ok())
            .map(|n| String::from_utf8_lossy(n).into_owned())
            .collect(),
        _ => Vec::new(),
    }
}

/// How many samples per pixel the image's colour space uses.
fn color_space_components(doc: &Document, dict: &Dictionary) -> Option<usize> {
    let object = resolve(doc, dict.get(b"ColorSpace").ok()?)?;
    match object {
        Object::Name(name) => match name.as_slice() {
            b"DeviceGray" | b"CalGray" | b"G" => Some(1),
            b"DeviceRGB" | b"CalRGB" | b"RGB" => Some(3),
            b"DeviceCMYK" | b"CMYK" => Some(4),
            _ => None,
        },
        Object::Array(items) => {
            let family = items.first()?.as_name().ok()?;
            match family {
                // [/ICCBased stream] — the stream's /N gives the count.
                b"ICCBased" => {
                    let stream_object = resolve(doc, items.get(1)?)?;
                    let stream = stream_object.as_stream().ok()?;
                    dict_u32(doc, &stream.dict, b"N").map(|n| n as usize)
                }
                b"CalGray" => Some(1),
                b"CalRGB" | b"Lab" => Some(3),
                // Indexed images store palette entries, not colours; skip.
                _ => None,
            }
        }
        _ => None,
    }
}

fn resolve<'a>(doc: &'a Document, object: &'a Object) -> Option<&'a Object> {
    match object {
        Object::Reference(id) => doc.get_object(*id).ok(),
        other => Some(other),
    }
}

fn dict_u32(doc: &Document, dict: &Dictionary, key: &[u8]) -> Option<u32> {
    let object = resolve(doc, dict.get(key).ok()?)?;
    object.as_i64().ok().map(|v| v as u32)
}

/// A 1x1 opaque white image, used to stand in for every extracted figure.
fn blank_pixel() -> Stream {
    let mut dict = Dictionary::new();
    dict.set("Type", Object::Name(b"XObject".to_vec()));
    dict.set("Subtype", Object::Name(b"Image".to_vec()));
    dict.set("Width", Object::Integer(1));
    dict.set("Height", Object::Integer(1));
    dict.set("ColorSpace", Object::Name(b"DeviceGray".to_vec()));
    dict.set("BitsPerComponent", Object::Integer(8));

    let mut stream = Stream::new(dict, vec![0xFF]);
    // Keep it uncompressed: one byte does not benefit, and compressing would
    // need a /Filter entry to match.
    stream.set_plain_content(vec![0xFF]);
    stream
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Round-trips the fixture PDF: one 200x150 FlateDecode RGB image on page
    /// 2, which exercises the decompress-and-re-encode path.
    #[test]
    fn extracts_and_blanks_a_flate_image() {
        let path = match std::env::var("PROBE_PDF") {
            Ok(path) => path,
            Err(_) => return,
        };
        let result = extract_and_strip_images(path, 64, 64).expect("strip should succeed");

        assert_eq!(result.page_count, 2);
        assert_eq!(result.images.len(), 1, "expected one figure");
        assert_eq!(result.skipped, 0);

        let figure = &result.images[0];
        assert_eq!(figure.page, 2);
        assert_eq!((figure.width, figure.height), (200, 150));
        assert_eq!(figure.media_type, "image/png");
        assert_eq!(&figure.bytes[..8], b"\x89PNG\r\n\x1a\n", "not a PNG");

        assert!(
            (result.pdf.len() as u64) < result.original_bytes,
            "stripped PDF ({}) should be smaller than the original ({})",
            result.pdf.len(),
            result.original_bytes
        );
        // The stripped document must still be a loadable PDF.
        let reloaded = Document::load_mem(&result.pdf).expect("stripped PDF should reload");
        assert_eq!(reloaded.get_pages().len(), 2);
    }
}
