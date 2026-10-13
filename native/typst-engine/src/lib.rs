use std::{
    ffi::{c_char, c_int, CStr, CString},
    panic::{catch_unwind, AssertUnwindSafe},
    path::PathBuf,
    ptr,
};

use typst::layout::PagedDocument;
use typst_as_lib::{
    file_resolver::FileSystemResolver,
    typst_kit_options::TypstKitFontOptions,
    TypstAsLibError, TypstEngine as TypstLibEngine,
};
use typst_pdf::PdfOptions;

pub struct EngineHandle {
    engine: TypstLibEngine,
    root: PathBuf,
}

#[no_mangle]
pub extern "C" fn typst_engine_create(root: *const c_char) -> *mut EngineHandle {
    if root.is_null() {
        return ptr::null_mut();
    }

    let result = catch_unwind(AssertUnwindSafe(|| {
        let root_str = unsafe { CStr::from_ptr(root) }.to_string_lossy().into_owned();
        let root_path = PathBuf::from(root_str);
        let mut builder = TypstLibEngine::builder()
            // Do not wrap this resolver in an in-memory cache: the live source
            // and project assets can change between preview compilations.
            .add_file_resolver(FileSystemResolver::new(root_path.clone()))
            .with_package_file_resolver()
            .search_fonts_with(TypstKitFontOptions::default());
        builder.comemo_evict_max_age(Some(3));
        let engine = builder.build();
        Box::into_raw(Box::new(EngineHandle {
            engine,
            root: root_path,
        }))
    }));

    result.unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn typst_engine_destroy(handle: *mut EngineHandle) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Compiles a source file already written beneath the engine root.
#[no_mangle]
pub extern "C" fn typst_engine_compile(
    handle: *mut EngineHandle,
    source_path: *const c_char,
    pdf_out: *mut *mut u8,
    pdf_len_out: *mut usize,
    error_out: *mut *mut c_char,
) -> c_int {
    if handle.is_null()
        || source_path.is_null()
        || pdf_out.is_null()
        || pdf_len_out.is_null()
        || error_out.is_null()
    {
        return -1;
    }

    unsafe {
        *pdf_out = ptr::null_mut();
        *pdf_len_out = 0;
        *error_out = ptr::null_mut();
    }

    let result = catch_unwind(AssertUnwindSafe(|| {
        let source_path = unsafe { CStr::from_ptr(source_path) }
            .to_string_lossy()
            .into_owned();
        let handle = unsafe { &*handle };
        let document: PagedDocument = handle
            .engine
            .compile::<_, PagedDocument>(source_path.as_str())
            .output
            .map_err(|e| format_engine_error(e, &handle.root))?;
        typst_pdf::pdf(&document, &PdfOptions::default())
            .map_err(|diagnostics| format_diagnostics(&diagnostics, &handle.root))
    }));

    match result {
        Ok(Ok(pdf)) => {
            let mut boxed = pdf.into_boxed_slice();
            unsafe {
                *pdf_len_out = boxed.len();
                *pdf_out = boxed.as_mut_ptr();
            }
            std::mem::forget(boxed);
            0
        }
        Ok(Err(message)) => {
            unsafe { *error_out = c_string(message) };
            1
        }
        Err(_) => {
            unsafe { *error_out = c_string("Typst compilation failed unexpectedly") };
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn typst_engine_compile_svg(
    handle: *mut EngineHandle,
    source_path: *const c_char,
    svg_out: *mut *mut c_char,
    error_out: *mut *mut c_char,
) -> c_int {
    if handle.is_null() || source_path.is_null() || svg_out.is_null() || error_out.is_null() {
        return -1;
    }

    unsafe {
        *svg_out = ptr::null_mut();
        *error_out = ptr::null_mut();
    }

    let result = catch_unwind(AssertUnwindSafe(|| {
        let source_path = unsafe { CStr::from_ptr(source_path) }
            .to_string_lossy()
            .into_owned();
        let handle = unsafe { &*handle };
        let document: PagedDocument = handle
            .engine
            .compile::<_, PagedDocument>(source_path.as_str())
            .output
            .map_err(|e| format_engine_error(e, &handle.root))?;
        let svg = typst_svg::svg_merged(&document, typst::layout::Abs::pt(10.0));
        Ok::<String, String>(svg)
    }));

    match result {
        Ok(Ok(svg)) => {
            unsafe { *svg_out = c_string(svg) };
            0
        }
        Ok(Err(message)) => {
            unsafe { *error_out = c_string(message) };
            1
        }
        Err(_) => {
            unsafe { *error_out = c_string("Typst compilation failed unexpectedly") };
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn typst_engine_free_pdf(data: *mut u8, length: usize) {
    if !data.is_null() {
        let slice = ptr::slice_from_raw_parts_mut(data, length);
        unsafe { drop(Box::from_raw(slice)) };
    }
}

#[no_mangle]
pub extern "C" fn typst_engine_free_error(message: *mut c_char) {
    if !message.is_null() {
        unsafe { drop(CString::from_raw(message)) };
    }
}

#[no_mangle]
pub extern "C" fn typst_engine_free_string(string: *mut c_char) {
    if !string.is_null() {
        unsafe { drop(CString::from_raw(string)) };
    }
}

fn c_string(value: impl Into<String>) -> *mut c_char {
    CString::new(value.into())
        .unwrap_or_else(|_| CString::new("Typst error message contained invalid data").unwrap())
        .into_raw()
}

fn format_diagnostics(diagnostics: &[typst::diag::SourceDiagnostic], root: &std::path::Path) -> String {
    diagnostics
        .iter()
        .map(|diagnostic| {
            let mut loc = String::new();
            if let Some(id) = diagnostic.span.id() {
                let rel = id.vpath().as_rootless_path();
                let full = root.join(rel);
                if let Ok(content) = std::fs::read_to_string(&full) {
                    let source = typst::syntax::Source::new(id, content);
                    if let Some(range) = source.range(diagnostic.span) {
                        let line = source.byte_to_line(range.start).unwrap_or(0) + 1;
                        let col = source.byte_to_column(range.start).unwrap_or(0) + 1;
                        loc = format!("{}:{}:{}: ", rel.display(), line, col);
                    } else {
                        loc = format!("{}: ", rel.display());
                    }
                } else {
                    loc = format!("{}: ", rel.display());
                }
            }
            format!("{}{:?}: {}", loc, diagnostic.severity, diagnostic.message)
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn format_engine_error(error: TypstAsLibError, root: &std::path::Path) -> String {
    match error {
        TypstAsLibError::TypstSource(diagnostics) => format_diagnostics(&diagnostics, root),
        TypstAsLibError::TypstFile(error) => error.to_string(),
        other => other.to_string(),
    }
}


