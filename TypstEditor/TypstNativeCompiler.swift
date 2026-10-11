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
    private typealias FreePDFFunction = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void
    private typealias FreeErrorFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private static let libraryHandle: UnsafeMutableRawPointer? = {
        guard let path = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("libtypst_editor_native.dylib").path else { return nil }
        return dlopen(path, RTLD_NOW | RTLD_LOCAL)
    }()

    private let engine: OpaquePointer
    private let destroyEngine: DestroyFunction
    private let compileSource: CompileFunction
    private let freePDF: FreePDFFunction
    private let freeError: FreeErrorFunction

    init(rootURL: URL) throws {
        guard let library = Self.libraryHandle else {
            throw CompilerError("The in-app Typst engine could not be loaded.")
        }

        let create: CreateFunction = try Self.symbol("typst_engine_create", in: library)
        destroyEngine = try Self.symbol("typst_engine_destroy", in: library)
        compileSource = try Self.symbol("typst_engine_compile", in: library)
        freePDF = try Self.symbol("typst_engine_free_pdf", in: library)
        freeError = try Self.symbol("typst_engine_free_error", in: library)

        let created = rootURL.path.withCString { create($0) }
        guard let created else {
            throw CompilerError("The in-app Typst engine could not initialize.")
        }
        engine = created
    }

    deinit {
        destroyEngine(engine)
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
