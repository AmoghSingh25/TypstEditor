use std::path::PathBuf;
use typst_as_lib::{
    file_resolver::FileSystemResolver,
    typst_kit_options::TypstKitFontOptions,
    TypstEngine,
};
use typst::layout::PagedDocument;

fn main() {
    let mut builder = TypstEngine::builder()
        .add_file_resolver(FileSystemResolver::new(PathBuf::from("/Users/amogh/Academic/Cambridge/LitReview")))
        .with_package_file_resolver()
        .search_fonts_with(TypstKitFontOptions::default());
    let engine = builder.build();
    let res = engine.compile::<_, PagedDocument>("/main.typ");
    match res.output {
        Ok(_) => println!("Compilation succeeded!"),
        Err(e) => println!("Compilation failed: {:?}", e),
    }
}
