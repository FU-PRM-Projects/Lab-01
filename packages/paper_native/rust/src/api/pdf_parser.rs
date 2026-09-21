use regex::Regex;
use std::fs;
use std::path::Path;

pub const TARGET_CHUNK_CHARS: usize = 2400;
pub const CEILING_CHUNK_CHARS: usize = 3200;
pub const OVERLAP_CHARS: usize = 300;

#[derive(Clone, Debug, PartialEq)]
pub struct RustPaperChunk {
    pub id: String,
    pub page: i32,
    pub ordinal: i32,
    pub section: String,
    pub start_char: i32,
    pub end_char: i32,
    pub text: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustPdfProcessedResult {
    pub title: String,
    pub page_count: i32,
    pub chunks: Vec<RustPaperChunk>,
    pub empty_pages: Vec<i32>,
    pub pdf_type: String,
    pub needs_ocr_pages: Vec<i32>,
}

pub fn parse_pdf(
    file_path: String,
    document_id: String,
    fallback_title: Option<String>,
) -> Result<RustPdfProcessedResult, String> {
    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(format!("PDF file not found at: {file_path}"));
    }

    let buffer = fs::read(path).map_err(|e| format!("Failed to read PDF file: {e}"))?;

    // 1. Process metadata & classification using pdf-inspector
    let process_info = pdf_inspector::process_pdf_mem(&buffer)
        .map_err(|e| format!("pdf-inspector processing error: {e:?}"))?;

    let pdf_type_str = format!("{:?}", process_info.pdf_type);
    let needs_ocr_pages: Vec<i32> = process_info
        .pages_needing_ocr
        .iter()
        .map(|&p| p as i32)
        .collect();

    // 2. Extract per-page markdown/text
    let pages_extraction = pdf_inspector::extract_pages_markdown_mem(&buffer, None)
        .map_err(|e| format!("pdf-inspector page extraction error: {e:?}"))?;

    let page_count = if process_info.page_count > 0 {
        process_info.page_count as i32
    } else {
        pages_extraction.pages.len() as i32
    };

    let section_regex = Regex::new(
        r"(?i)^(?:\d+(?:\.\d+)*\s+)?(Abstract|Introduction|Background|Related\s+Work|Methodology|Method|Architecture|Implementation|Evaluation|Experiments?|Results?|Discussion|Conclusion|References)\b",
    ).map_err(|e| e.to_string())?;

    let mut detected_title = fallback_title.clone().unwrap_or_else(|| {
        path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("document.pdf")
            .to_string()
    });

    if let Some(meta_title) = &process_info.title {
        let trimmed = meta_title.trim();
        if !trimmed.is_empty() && trimmed.len() > 3 && trimmed.len() < 200 {
            detected_title = trimmed.to_string();
        }
    }

    let mut all_chunks = Vec::new();
    let mut empty_pages = Vec::new();
    let mut current_section = "Introduction".to_string();
    let mut ordinal = 0;

    for page_item in &pages_extraction.pages {
        let page_num = (page_item.page + 1) as i32;
        let page_text = &page_item.markdown;

        if page_text.trim().is_empty() {
            empty_pages.push(page_num);
            continue;
        }

        // Check if page 1 can refine title if fallback wasn't explicitly supplied and meta title was empty
        if page_num == 1 && process_info.title.as_ref().map_or(true, |t| t.trim().is_empty()) && fallback_title.is_none() {
            for line in page_text.lines() {
                let trimmed = line.trim().trim_start_matches('#').trim();
                if trimmed.len() > 5 && trimmed.len() < 150 {
                    detected_title = trimmed.to_string();
                    break;
                }
            }
        }

        // Section header scanning
        for line in page_text.lines() {
            let trimmed = line.trim().trim_start_matches('#').trim();
            if let Some(mat) = section_regex.find(trimmed) {
                current_section = mat.as_str().to_string();
                break;
            }
        }

        let page_chunks = chunk_text(
            page_text,
            page_num,
            &document_id,
            &current_section,
            ordinal,
        );

        ordinal += page_chunks.len() as i32;
        all_chunks.extend(page_chunks);
    }

    Ok(RustPdfProcessedResult {
        title: detected_title,
        page_count,
        chunks: all_chunks,
        empty_pages,
        pdf_type: pdf_type_str,
        needs_ocr_pages,
    })
}

pub fn chunk_text(
    page_text: &str,
    page_num: i32,
    document_id: &str,
    section: &str,
    start_ordinal: i32,
) -> Vec<RustPaperChunk> {
    let mut chunks = Vec::new();
    let text_len = page_text.chars().count();

    if text_len <= CEILING_CHUNK_CHARS {
        chunks.push(RustPaperChunk {
            id: format!("{document_id}:p{page_num}:c0"),
            page: page_num,
            ordinal: start_ordinal,
            section: section.to_string(),
            start_char: 0,
            end_char: text_len as i32,
            text: page_text.to_string(),
        });
        return chunks;
    }

    let char_indices: Vec<(usize, char)> = page_text.char_indices().collect();
    let mut start_char_idx = 0;
    let mut chunk_idx = 0;

    let sentence_regex = Regex::new(r"\.\s").unwrap();

    while start_char_idx < text_len {
        let mut end_char_idx = start_char_idx + TARGET_CHUNK_CHARS;
        if end_char_idx >= text_len {
            end_char_idx = text_len;
        } else {
            let search_start = (start_char_idx + TARGET_CHUNK_CHARS).saturating_sub(400).max(start_char_idx);
            let search_end = (start_char_idx + TARGET_CHUNK_CHARS + 400).min(text_len);

            let byte_start = char_indices[search_start].0;
            let byte_end = if search_end < text_len {
                char_indices[search_end].0
            } else {
                page_text.len()
            };

            let search_window = &page_text[byte_start..byte_end];

            // 1. Paragraph break
            if let Some(pos) = search_window.rfind("\n\n") {
                let break_byte = byte_start + pos + 2;
                end_char_idx = char_indices
                    .iter()
                    .position(|&(b, _)| b >= break_byte)
                    .unwrap_or(search_end);
            } else if let Some(mat) = sentence_regex.find_iter(search_window).last() {
                // 2. Sentence break
                let break_byte = byte_start + mat.end();
                end_char_idx = char_indices
                    .iter()
                    .position(|&(b, _)| b >= break_byte)
                    .unwrap_or(search_end);
            } else if let Some(pos) = search_window.rfind(' ') {
                // 3. Word boundary
                let break_byte = byte_start + pos + 1;
                end_char_idx = char_indices
                    .iter()
                    .position(|&(b, _)| b >= break_byte)
                    .unwrap_or(search_end);
            }
        }

        let chunk_byte_start = char_indices[start_char_idx].0;
        let chunk_byte_end = if end_char_idx < text_len {
            char_indices[end_char_idx].0
        } else {
            page_text.len()
        };

        let chunk_content = &page_text[chunk_byte_start..chunk_byte_end];
        if !chunk_content.trim().is_empty() {
            chunks.push(RustPaperChunk {
                id: format!("{document_id}:p{page_num}:c{chunk_idx}"),
                page: page_num,
                ordinal: start_ordinal + chunk_idx,
                section: section.to_string(),
                start_char: start_char_idx as i32,
                end_char: end_char_idx as i32,
                text: chunk_content.to_string(),
            });
            chunk_idx += 1;
        }

        if end_char_idx >= text_len {
            break;
        }

        let mut next_start = end_char_idx.saturating_sub(OVERLAP_CHARS);
        if next_start <= start_char_idx {
            next_start = end_char_idx;
        } else {
            // Align overlap start to next space
            let next_byte = char_indices[next_start].0;
            if let Some(pos) = page_text[next_byte..chunk_byte_end].find(' ') {
                let space_byte = next_byte + pos + 1;
                if let Some(idx) = char_indices.iter().position(|&(b, _)| b >= space_byte) {
                    if idx < end_char_idx {
                        next_start = idx;
                    }
                }
            }
        }
        start_char_idx = next_start;
    }

    chunks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chunk_small_text() {
        let text = "This is a short paragraph of text.";
        let chunks = chunk_text(text, 1, "doc_123", "Introduction", 0);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].id, "doc_123:p1:c0");
        assert_eq!(chunks[0].text, text);
        assert_eq!(chunks[0].start_char, 0);
        assert_eq!(chunks[0].end_char, text.chars().count() as i32);
    }

    #[test]
    fn test_chunk_large_text_splits_with_overlap() {
        let para = "Paragraph one with some meaningful sentences. ".repeat(70);
        let para2 = "Paragraph two with additional detailed explanation. ".repeat(70);
        let full_text = format!("{para}\n\n{para2}");
        assert!(full_text.chars().count() > CEILING_CHUNK_CHARS);

        let chunks = chunk_text(&full_text, 1, "doc_456", "Methodology", 5);
        assert!(chunks.len() >= 2);
        assert_eq!(chunks[0].ordinal, 5);
        assert_eq!(chunks[1].ordinal, 6);
        assert_eq!(chunks[0].section, "Methodology");
        assert_eq!(chunks[1].section, "Methodology");
    }
}
