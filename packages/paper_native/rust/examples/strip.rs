// Dev helper: strip <in.pdf> to <out.pdf> and report what was extracted.
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let result = lab_05_rust::api::pdf_images::extract_and_strip_images(args[1].clone(), 64, 64)
        .expect("strip failed");
    std::fs::write(&args[2], &result.pdf).unwrap();
    println!(
        "pages={} images={} skipped={} original={}B stripped={}B ({:.1}% smaller)",
        result.page_count,
        result.images.len(),
        result.skipped,
        result.original_bytes,
        result.pdf.len(),
        100.0 - (result.pdf.len() as f64 / result.original_bytes as f64) * 100.0
    );
    for (i, img) in result.images.iter().enumerate() {
        let path = format!(
            "{}.fig{}.{}",
            args[2],
            i,
            if img.media_type == "image/jpeg" {
                "jpg"
            } else {
                "png"
            }
        );
        std::fs::write(&path, &img.bytes).unwrap();
        println!(
            "  p{} {} {}x{} {} {}B -> {}",
            img.page,
            img.name,
            img.width,
            img.height,
            img.media_type,
            img.bytes.len(),
            path
        );
    }
}
