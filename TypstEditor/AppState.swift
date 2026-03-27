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

    private var tabContents:   [URL: String] = [:]
    private var savedContents: [URL: String] = [:]

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
    @Published var errorMessage: String      = ""
    @Published var isCompiling: Bool         = false
    @Published var compileCount: Int         = 0

    // Page tracking for the preview toolbar
    @Published var currentPage: Int  = 1
    @Published var totalPages: Int   = 1

    // Watch-mode state
    private var watchProcess: Process?
    private var watchSrcURL: URL?          // stable temp .typ file fed to typst watch
    private var watchOutURL: URL?          // stable .pdf output
    private var watchTimer: Timer?         // debounce writes (50 ms)
    private var outputPoller: Timer?       // poll for new PDF (100 ms)
    private var lastPDFModDate: Date?      // detect when typst rewrites the PDF

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
            switchWatchToActive()
            return
        }
        saveActive()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let tab = EditorTab(id: UUID(), url: url)
        tabContents[url]   = text
        savedContents[url] = text
        tabs.append(tab)
        activeTabID = tab.id
        clearPDF()
        if url.pathExtension == "typ" { startWatch() }
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
        clearPDF()
        if tab.isTyp { switchWatchToActive() }
    }

    func closeTab(_ tab: EditorTab) {
        saveContentForTab(tab)
        guard let idx = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: idx)
        tabContents.removeValue(forKey: tab.url)
        savedContents.removeValue(forKey: tab.url)
        if tabs.isEmpty {
            activeTabID = nil
            stopWatch()
            clearPDF()
        } else {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx].id
            clearPDF()
            if tabs[newIdx].isTyp { switchWatchToActive() }
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

    // MARK: - Source change  (called on every keystroke — no debounce here)

    func sourceDidChange(_ newValue: String) {
        activeSource = newValue
        if activeIsTyp { scheduleWatchWrite() }
    }

    // MARK: - Watch mode
    //
    // Instead of spawning a new `typst compile` on every edit (expensive),
    // we spawn ONE `typst watch` process that stays alive and re-renders
    // whenever its input file changes on disk.  We write the current source
    // to the stable watch-src file on a 50 ms debounce, then poll the output
    // PDF's mtime at 100 ms to detect when typst has finished re-rendering.

    private func startWatch() {
        stopWatch()
        guard let typst = findTypst(), let url = activeURL else { return }

        let srcDir = url.deletingLastPathComponent()
        let root   = projectURL ?? srcDir

        // watchSrc MUST live inside --root so typst doesn't reject it.
        // We put it next to the real file with a hidden-ish name.
        let safeBase = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
        let watchSrc = srcDir.appendingPathComponent(".__watch_\(safeBase).typ")

        // watchOut can live anywhere — tmp is fine for the PDF output
        let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("typsteditor", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let watchOut = tmp.appendingPathComponent("watch_\(safeBase).pdf")

        watchSrcURL = watchSrc
        watchOutURL = watchOut

        // Write current source immediately so typst has something to compile
        try? activeSource.write(to: watchSrc, atomically: false, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: typst)
        proc.arguments = ["watch", "--root", root.path, watchSrc.path, watchOut.path]

        let errPipe = Pipe()
        proc.standardError  = errPipe
        proc.standardOutput = Pipe()

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            DispatchQueue.main.async {
                let lines = text.components(separatedBy: .newlines)
                    .filter { !$0.hasPrefix("watching") && !$0.hasPrefix("Watching") && !$0.isEmpty }
                guard !lines.isEmpty else { return }
                let joined = lines.joined(separator: "\n")
                if joined.lowercased().contains("error") {
                    self?.errorMessage = joined
                        .replacingOccurrences(of: watchSrc.path, with: url.path)
                } else {
                    self?.errorMessage = ""
                }
            }
        }

        try? proc.run()
        watchProcess = proc
        isCompiling  = true

        lastPDFModDate = nil
        outputPoller = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollPDFOutput()
        }
    }

    private func switchWatchToActive() {
        // Reuse the existing watch process — just rewrite the src file
        guard activeIsTyp else { stopWatch(); return }
        if watchProcess?.isRunning == true {
            scheduleWatchWrite()
        } else {
            startWatch()
        }
    }

    func stopWatch() {
        watchTimer?.invalidate();   watchTimer   = nil
        outputPoller?.invalidate(); outputPoller = nil
        watchProcess?.terminate();  watchProcess = nil
        // Delete the temp source file we placed next to the user's real file
        if let src = watchSrcURL { try? FileManager.default.removeItem(at: src) }
        watchSrcURL    = nil
        watchOutURL    = nil
        lastPDFModDate = nil
    }

    private func scheduleWatchWrite() {
        // 50 ms debounce — fast enough to feel instant, avoids hammering disk
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.writeWatchSrc()
        }
    }

    private func writeWatchSrc() {
        guard let src = watchSrcURL else { return }
        let snapshot = activeSource
        try? snapshot.write(to: src, atomically: false, encoding: .utf8)
        // atomically:false is intentional — atomic writes use a rename which
        // some watchers miss; direct write modifies the inode typst is watching
    }

    private func pollPDFOutput() {
        guard let outURL = watchOutURL else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path)
        let modDate = attrs?[.modificationDate] as? Date
        guard let mod = modDate, mod != lastPDFModDate else { return }
        lastPDFModDate = mod

        // New PDF written — load it
        guard let doc = PDFDocument(url: outURL) else { return }
        let prevPDF = lastExportURL
        pdfDocument = nil
        if let prev = prevPDF, prev != outURL {
            try? FileManager.default.removeItem(at: prev)
        }
        pdfDocument   = doc
        lastExportURL = outURL
        compileCount += 1
        errorMessage  = ""
        isCompiling   = false
        totalPages    = doc.pageCount
    }

    // MARK: - Page navigation

    func jumpToPage(_ page: Int) {
        // Notify PDFPreview via a published value it observes
        let clamped = max(1, min(page, totalPages))
        currentPage = clamped
        // Post a notification the PDFPreview NSViewRepresentable can act on
        NotificationCenter.default.post(name: .jumpToPage, object: clamped)
    }

    // MARK: - Export

    func exportPDF() {
        guard let src = lastExportURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            (activeURL?.deletingPathExtension().lastPathComponent ?? "document") + ".pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    func findTypst() -> String? {
        ["/usr/local/bin/typst", "/opt/homebrew/bin/typst", "/usr/bin/typst",
         "\(NSHomeDirectory())/.cargo/bin/typst"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func cleanupTempDirectory() {
        stopWatch()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("typsteditor", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func clearPDF() {
        pdfDocument   = nil
        errorMessage  = ""
        // Don't delete lastExportURL here — watch reuses the same output file
    }
}

extension Notification.Name {
    static let jumpToPage = Notification.Name("jumpToPage")
}
