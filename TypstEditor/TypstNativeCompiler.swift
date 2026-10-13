import Foundation
import Darwin

/// Loads the bundled Rust/Typst engine. A single instance is reused for edits
/// in a project so Typst can retain its compilation cache between previews.
final class TypstNativeCompiler {
    private typealias CreateFunction = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    private typealias DestroyFunction = @convention(c) (OpaquePointer?) -> Void
    private typealias CompileFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias CompileSVGFunction = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FreePDFFunction = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void
    private typealias FreeErrorFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private static var loadErrorDescription: String?

    private static let libraryHandle: UnsafeMutableRawPointer? = {
        var candidateURLs: [URL] = []
        if let frameworks = Bundle.main.privateFrameworksURL {
            candidateURLs.append(frameworks.appendingPathComponent("libtypst_editor_native.dylib"))
        }
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libtypst_editor_native.dylib"))
        if let shared = Bundle.main.sharedFrameworksURL {
            candidateURLs.append(shared.appendingPathComponent("libtypst_editor_native.dylib"))
        }
        if let res = Bundle.main.resourceURL {
            candidateURLs.append(res.deletingLastPathComponent().appendingPathComponent("Frameworks/libtypst_editor_native.dylib"))
        }
        // Development build fallback
        let devURL = URL(fileURLWithPath: "/Users/amogh/Projects/TypstEditor/native/typst-engine/target/aarch64-apple-darwin/release/libtypst_editor_native.dylib")
        candidateURLs.append(devURL)

        var lastError = "No candidate dylib found on disk"
        for url in candidateURLs {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                return handle
            } else if let err = dlerror() {
                lastError = "dlopen(\(path)) failed: \(String(cString: err))"
                NSLog("[TypstNativeCompiler] %@", lastError)
            }
        }
        loadErrorDescription = lastError
        return nil
    }()

    private let engine: OpaquePointer
    private let destroyEngine: DestroyFunction
    private let compileSource: CompileFunction
    private let compileSVGSource: CompileSVGFunction
    private let freePDF: FreePDFFunction
    private let freeError: FreeErrorFunction
    private let freeString: FreeStringFunction

    init(rootURL: URL) throws {
        guard let library = Self.libraryHandle else {
            let detail = Self.loadErrorDescription ?? "dylib handle is nil"
            throw CompilerError("The in-app Typst engine could not be loaded (\(detail)).")
        }

        let create: CreateFunction = try Self.symbol("typst_engine_create", in: library)
        destroyEngine = try Self.symbol("typst_engine_destroy", in: library)
        compileSource = try Self.symbol("typst_engine_compile", in: library)
        compileSVGSource = try Self.symbol("typst_engine_compile_svg", in: library)
        freePDF = try Self.symbol("typst_engine_free_pdf", in: library)
        freeError = try Self.symbol("typst_engine_free_error", in: library)
        freeString = try Self.symbol("typst_engine_free_string", in: library)

        let created = rootURL.path.withCString { create($0) }
        guard let created else {
            throw CompilerError("The in-app Typst engine could not initialize.")
        }
        engine = created
    }

    deinit {
        destroyEngine(engine)
    }

    func compileSVG(sourcePath: String) throws -> String {
        var svg: UnsafeMutablePointer<CChar>?
        var error: UnsafeMutablePointer<CChar>?

        let status = sourcePath.withCString { path in
            withUnsafeMutablePointer(to: &svg) { svgOut in
                withUnsafeMutablePointer(to: &error) { errorOut in
                    compileSVGSource(engine, path, svgOut, errorOut)
                }
            }
        }

        defer {
            if let svg { freeString(svg) }
            if let error { freeError(error) }
        }

        guard status == 0, let svg else {
            let message = error.map { String(cString: $0) } ?? "Typst SVG export failed."
            throw CompilerError(message)
        }
        return String(cString: svg)
    }

    func compile(sourcePath: String) throws -> Data {
        var pdf: UnsafeMutablePointer<UInt8>?
        var pdfLength = 0
        var error: UnsafeMutablePointer<CChar>?

        let status = sourcePath.withCString { path in
            withUnsafeMutablePointer(to: &pdf) { pdfOut in
                withUnsafeMutablePointer(to: &pdfLength) { lengthOut in
                    withUnsafeMutablePointer(to: &error) { errorOut in
                        compileSource(engine, path, pdfOut, lengthOut, errorOut)
                    }
                }
            }
        }

        defer {
            if let pdf { freePDF(pdf, pdfLength) }
            if let error { freeError(error) }
        }

        guard status == 0, let pdf, pdfLength > 0 else {
            let message = error.map { String(cString: $0) } ?? "Typst compilation failed."
            throw CompilerError(message)
        }
        return Data(bytes: pdf, count: pdfLength)
    }

    private static func symbol<T>(_ name: String, in library: UnsafeMutableRawPointer) throws -> T {
        guard let address = dlsym(library, name) else {
            throw CompilerError("The in-app Typst engine is missing \(name).")
        }
        return unsafeBitCast(address, to: T.self)
    }

    struct CompilerError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
