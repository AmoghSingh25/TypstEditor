import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - FileNode

struct FileNode: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var children: [FileNode]?
    var name: String   { url.lastPathComponent }
    var isFolder: Bool { children != nil }
    var isTyp: Bool    { url.pathExtension == "typ" }
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
}

// MARK: - Tab

struct EditorTab: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var isDirty: Bool = false
    var name: String { url.lastPathComponent }
    var isTyp: Bool  { url.pathExtension == "typ" }
    static func == (lhs: EditorTab, rhs: EditorTab) -> Bool { lhs.url == rhs.url }
}

// MARK: - AppState

final class AppState: ObservableObject {

    // Project
    @Published var projectURL: URL?     = nil
    @Published var fileTree: [FileNode] = []

    // Tabs
    @Published var tabs: [EditorTab]    = []
    @Published var activeTabID: UUID?   = nil

    private var tabContents:   [URL: String]      = [:]
    private var savedContents: [URL: String]      = [:]
    // Per-tab PDF cache — keeps the last good rendered PDF for each open file
    private var tabPDFs:       [URL: PDFDocument] = [:]
    private var tabExportData: [URL: Data]        = [:]

    var activeTab: EditorTab? { tabs.first { $0.id == activeTabID } }
    var activeURL: URL?       { activeTab?.url }
    var activeIsTyp: Bool     { activeTab?.isTyp ?? false }

    var activeSource: String {
        get { activeURL.flatMap { tabContents[$0] } ?? "" }
        set {
            guard let url = activeURL else { return }
            tabContents[url] = newValue
            let dirty = savedContents[url] != newValue
            if let i = tabs.firstIndex(where: { $0.url == url }), tabs[i].isDirty != dirty {
                tabs[i].isDirty = dirty
            }
        }
    }
    var isDirty: Bool { activeTab?.isDirty ?? false }

    // Compile / preview
    @Published var pdfDocument: PDFDocument? = nil
    @Published var lastExportURL: URL?       = nil
    @Published var lastExportData: Data?     = nil
    @Published var errorMessage: String      = ""
    @Published var isCompiling: Bool         = false
    @Published var compileCount: Int         = 0

    // Page tracking for the preview toolbar
    @Published var currentPage: Int  = 1
    @Published var totalPages: Int   = 1
    @Published var sourceProgress: Double = 0

    // Diagnostic error details
    @Published var errorLine: Int?   = nil
    @Published var errorColumn: Int? = nil

    // Preview zoom
    @Published var zoomMode: ZoomMode = .fitWidth
    @Published var zoomScale: CGFloat = 1.0

    // A persistent in-process Typst compiler runs away from the UI thread.
    private let compileQueue = DispatchQueue(label: "com.typsteditor.compiler", qos: .userInitiated)
    private var compileTimer: Timer?
    private var compileGeneration = 0
    private let generationLock = NSLock()
    private var latestRequestedGeneration = 0
    private var nativeCompiler: TypstNativeCompiler?
    private var nativeCompilerRoot: URL?
    private var previewSources: [URL: URL] = [:]

    init() {
        NotificationCenter.default.addObserver(
            forName: .previewZoomChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let info = note.object as? (scale: CGFloat, mode: ZoomMode) else { return }
            self.zoomScale = info.scale
            self.zoomMode = info.mode
        }
    }

    // MARK: - Project

    func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Open Project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectURL = url
        fileTree   = buildTree(at: url)
    }

    func refreshTree() {
        guard let root = projectURL else { return }
        fileTree = buildTree(at: root)
    }

    private func buildTree(at url: URL) -> [FileNode] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles) else { return [] }
        return items
            .sorted {
                let aD = (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) ?? false
                let bD = (try? $1.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) ?? false
                if aD != bD { return aD }
                return $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            .map { child in
                let isDir = (try? child.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) ?? false
                return FileNode(id: UUID(), url: child, children: isDir ? buildTree(at: child) : nil)
            }
    }

    // MARK: - Open

    func open(node: FileNode) {
        guard !node.isFolder else { return }
        openURL(node.url)
    }

    func openURL(_ url: URL) {
        if let existing = tabs.first(where: { $0.url == url }) {
            activeTabID = existing.id
            sourceProgress = 0
            switchCompilerToActive()
            return
        }
        saveActive()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let tab = EditorTab(id: UUID(), url: url)
        tabContents[url]   = text
        savedContents[url] = text
        tabs.append(tab)
        activeTabID = tab.id
        sourceProgress = 0
        clearPDF()  // fresh tab — no cached PDF yet, blank is correct
        if url.pathExtension == "typ" { scheduleCompile() }
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openURL(url)
    }

    func newFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "untitled.typ"
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
        refreshTree()
        openURL(url)
    }

    // MARK: - Tab management

    func selectTab(_ tab: EditorTab) {
        saveActive()
        activeTabID = tab.id
        sourceProgress = 0
        // Restore the last good PDF for this tab (don't blank out)
        restoreCachedPDF(for: tab.url)
        switchCompilerToActive()
    }

    func closeTab(_ tab: EditorTab) {
        saveContentForTab(tab)
        if let previewURL = previewSources[tab.url] {
            try? FileManager.default.removeItem(at: previewURL)
            previewSources.removeValue(forKey: tab.url)
        }
        guard let idx = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: idx)
        tabContents.removeValue(forKey: tab.url)
        savedContents.removeValue(forKey: tab.url)
        tabPDFs.removeValue(forKey: tab.url)
        tabExportData.removeValue(forKey: tab.url)
        if tabs.isEmpty {
            activeTabID = nil
            stopCompiler()
            clearPDF()
        } else {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx].id
            restoreCachedPDF(for: tabs[newIdx].url)
            switchCompilerToActive()
        }
    }

    // MARK: - Save

    func saveActive() {
        guard let tab = activeTab else { return }
        saveContentForTab(tab)
    }

    private func saveContentForTab(_ tab: EditorTab) {
        guard let content = tabContents[tab.url],
              savedContents[tab.url] != content else { return }
        try? content.write(to: tab.url, atomically: true, encoding: .utf8)
        savedContents[tab.url] = content
        if let i = tabs.firstIndex(of: tab) { tabs[i].isDirty = false }
    }

    func saveActiveAs() {
        guard let tab = activeTab else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tab.name
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = tabContents[tab.url] ?? ""
        try? content.write(to: url, atomically: true, encoding: .utf8)
        let newTab = EditorTab(id: tab.id, url: url)
        tabContents[url]   = content
        savedContents[url] = content
        if let i = tabs.firstIndex(of: tab) { tabs[i] = newTab }
        refreshTree()
    }

    // MARK: - Source change

    func sourceDidChange(_ newValue: String) {
        activeSource = newValue
        if activeIsTyp { scheduleCompile() }
    }

    func sourcePositionDidChange(_ progress: Double) {
        sourceProgress = min(max(progress, 0), 1)
    }

    // MARK: - In-process Typst preview

    private func switchCompilerToActive() {
        guard activeIsTyp else {
            compileTimer?.invalidate()
            compileTimer = nil
            compileGeneration += 1
            isCompiling = false
            return
        }
        scheduleCompile()
    }

    private func scheduleCompile() {
        compileGeneration += 1
        let generation = compileGeneration
        generationLock.lock()
        latestRequestedGeneration = generation
        generationLock.unlock()

        compileTimer?.invalidate()
        isCompiling = true
        let timer = Timer(timeInterval: 0.03, repeats: false) { [weak self] _ in
            self?.compileActiveSource(generation: generation)
        }
        RunLoop.main.add(timer, forMode: .common)
        compileTimer = timer
    }

    private func compileActiveSource(generation: Int) {
        guard let url = activeURL, activeIsTyp else { return }
        let source = activeSource
        let root = compilerRoot(for: url)
        let sourceDirectory = url.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL
        let sourceURL = previewSources[url] ?? sourceDirectory
            .appendingPathComponent(".__typsteditor_preview_\(UUID().uuidString).typ")
        previewSources[url] = sourceURL

        do {
            try source.write(to: sourceURL, atomically: false, encoding: .utf8)
        } catch {
            errorMessage = "Could not prepare Typst preview: \(error.localizedDescription)"
            isCompiling = false
            return
        }

        let normalizedRootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let normalizedSourcePath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPrefix = normalizedRootPath.hasSuffix("/") ? normalizedRootPath : normalizedRootPath + "/"
        guard normalizedSourcePath.hasPrefix(rootPrefix) else {
            errorMessage = "Could not map preview source into the Typst project root."
            isCompiling = false
            return
        }
        let relativePath = String(normalizedSourcePath.dropFirst(rootPrefix.count))
            .replacingOccurrences(of: "\\", with: "/")
        let typstPath = "/" + relativePath

        compileQueue.async { [weak self] in
            guard let self else { return }
            self.generationLock.lock()
            let isLatest = (self.latestRequestedGeneration == generation)
            self.generationLock.unlock()
            guard isLatest else { return }

            do {
                if self.nativeCompilerRoot != root || self.nativeCompiler == nil {
                    self.nativeCompiler = try TypstNativeCompiler(rootURL: root)
                    self.nativeCompilerRoot = root
                }
                guard let compiler = self.nativeCompiler else {
                    throw TypstNativeCompiler.CompilerError("The in-app Typst engine is unavailable.")
                }
                let pdf = try compiler.compile(sourcePath: typstPath)
                DispatchQueue.main.async {
                    guard self.compileGeneration == generation, self.activeURL == url else { return }
                    guard let document = PDFDocument(data: pdf), document.pageCount > 0 else {
                        self.errorMessage = "Typst returned an invalid PDF preview."
                        self.isCompiling = false
                        return
                    }
                    self.tabPDFs[url] = document
                    self.tabExportData[url] = pdf
                    self.pdfDocument = document
                    self.lastExportURL = nil
                    self.lastExportData = pdf
                    self.compileCount += 1
                    self.errorMessage = ""
                    self.errorLine = nil
                    self.errorColumn = nil
                    self.isCompiling = false
                    self.totalPages = document.pageCount
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.compileGeneration == generation, self.activeURL == url else { return }
                    self.errorMessage = error.localizedDescription
                    let loc = self.parseDiagnosticLocation(error.localizedDescription)
                    self.errorLine = loc.line
                    self.errorColumn = loc.col
                    self.isCompiling = false
                }
            }
        }
    }

    private func parseDiagnosticLocation(_ message: String) -> (line: Int?, col: Int?) {
        let parts = message.components(separatedBy: ":")
        if parts.count >= 3 {
            for i in 0..<(parts.count - 2) {
                if let line = Int(parts[i].trimmingCharacters(in: .whitespaces)),
                   let col = Int(parts[i+1].trimmingCharacters(in: .whitespaces)) {
                    return (line, col)
                }
            }
        }
        return (nil, nil)
    }

    func jumpToError() {
        guard let line = errorLine else { return }
        NotificationCenter.default.post(name: .jumpToSourceLine, object: line)
    }

    private func compilerRoot(for sourceURL: URL) -> URL {
        let resolvedSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        let sourcePath = resolvedSource.path
        if let project = projectURL?.resolvingSymlinksInPath().standardizedFileURL,
           sourcePath.hasPrefix(project.path + "/") {
            return project
        }
        return resolvedSource.deletingLastPathComponent().standardizedFileURL
    }

    private func stopCompiler() {
        compileGeneration += 1
        compileTimer?.invalidate()
        compileTimer = nil
        isCompiling = false
        let files = Array(previewSources.values)
        previewSources.removeAll()
        compileQueue.async { [weak self] in
            self?.nativeCompiler = nil
            self?.nativeCompilerRoot = nil
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    // MARK: - Page navigation

    func jumpToPage(_ page: Int) {
        let clamped = max(1, min(page, totalPages))
        currentPage = clamped
        NotificationCenter.default.post(name: .jumpToPage, object: clamped)
    }

    // MARK: - Export

    func exportPDF() {
        guard let data = lastExportData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            (activeURL?.deletingPathExtension().lastPathComponent ?? "document") + ".pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? data.write(to: dest, options: .atomic)
    }

    func exportPNG() {
        guard let doc = pdfDocument, let page = doc.page(at: max(0, min(currentPage - 1, doc.pageCount - 1))) else { return }
        let panel = NSSavePanel()
        let baseName = activeURL?.deletingPathExtension().lastPathComponent ?? "document"
        panel.nameFieldStringValue = "\(baseName)_page\(currentPage).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let box = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3.0 // 3x ultra-sharp resolution
        let width = Int(ceil(box.width * scale))
        let height = Int(ceil(box.height * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: dest, options: .atomic)
    }

    func exportSVG() {
        guard let url = activeURL, activeIsTyp else { return }
        let root = compilerRoot(for: url)
        guard let sourceURL = previewSources[url] else { return }
        let normalizedRootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let normalizedSourcePath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPrefix = normalizedRootPath.hasSuffix("/") ? normalizedRootPath : normalizedRootPath + "/"
        let relativePath = String(normalizedSourcePath.dropFirst(rootPrefix.count)).replacingOccurrences(of: "\\", with: "/")
        let typstPath = "/" + relativePath

        let panel = NSSavePanel()
        let baseName = url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName).svg"
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        compileQueue.async { [weak self] in
            guard let self, let compiler = self.nativeCompiler else { return }
            do {
                let svg = try compiler.compileSVG(sourcePath: typstPath)
                try svg.write(to: dest, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to export SVG: \(error.localizedDescription)"
                }
            }
        }
    }

    func cleanupTempDirectory() {
        stopCompiler()
        compileQueue.sync {}
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("typsteditor", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func clearPDF() {
        pdfDocument   = nil
        errorMessage  = ""
        errorLine     = nil
        errorColumn   = nil
        lastExportURL = nil
        lastExportData = nil
        totalPages    = 0
        currentPage   = 1
    }

    private func restoreCachedPDF(for url: URL) {
        if let cached = tabPDFs[url] {
            pdfDocument   = cached
            lastExportURL = nil
            lastExportData = tabExportData[url]
            totalPages    = cached.pageCount
            errorMessage  = ""
            errorLine     = nil
            errorColumn   = nil
        } else {
            clearPDF()
        }
    }

    // MARK: - Zoom Controls

    func zoomIn() {
        NotificationCenter.default.post(name: .zoomIn, object: nil)
    }

    func zoomOut() {
        NotificationCenter.default.post(name: .zoomOut, object: nil)
    }

    func zoomFitWidth() {
        NotificationCenter.default.post(name: .zoomReset, object: nil)
    }

    func zoomFitPage() {
        NotificationCenter.default.post(name: .zoomFitPage, object: nil)
    }

    func zoomSetPercentage(_ percent: Int) {
        NotificationCenter.default.post(name: .zoomSetPercentage, object: percent)
    }
}

// MARK: - Zoom Mode

enum ZoomMode: Equatable {
    case fitWidth
    case fitPage
    case custom(CGFloat)
}

extension Notification.Name {
    static let jumpToPage = Notification.Name("jumpToPage")
    static let jumpToSourceLine = Notification.Name("jumpToSourceLine")
    static let previewPageClicked = Notification.Name("previewPageClicked")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let zoomFitPage = Notification.Name("zoomFitPage")
    static let zoomSetPercentage = Notification.Name("zoomSetPercentage")
    static let previewZoomChanged = Notification.Name("previewZoomChanged")
}
