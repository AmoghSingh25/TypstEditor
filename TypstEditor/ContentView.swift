import SwiftUI
import PDFKit

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var sidebarWidth: CGFloat = 220
    private let minSidebar: CGFloat = 140
    private let maxSidebar: CGFloat = 400

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
            DragHandle { sidebarWidth = min(max(sidebarWidth + $0, minSidebar), maxSidebar) }
            VStack(spacing: 0) {
                if !state.tabs.isEmpty { TabBar() }
                Group {
                    if state.activeURL == nil    { WelcomeView() }
                    else if state.activeIsTyp    { TypEditorView() }
                    else                         { PlainTextEditorView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) { ForEach(state.tabs) { TabItem(tab: $0) } }
        }
        .frame(height: 34)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Rectangle().frame(height:0.5).foregroundColor(Color(NSColor.separatorColor)), alignment:.bottom)
    }
}

struct TabItem: View {
    let tab: EditorTab
    @EnvironmentObject var state: AppState
    private var isActive: Bool { state.activeTabID == tab.id }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tab.isTyp ? "doc.text" : "doc")
                .font(.system(size:11))
                .foregroundColor(isActive ? .accentColor : .secondary)
            Text(tab.name)
                .font(.system(size:12, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
            ZStack {
                if tab.isDirty { Circle().fill(Color.orange).frame(width:6,height:6) }
                Image(systemName:"xmark").font(.system(size:9,weight:.medium))
                    .foregroundColor(.secondary).opacity(tab.isDirty ? 0 : 1)
            }
            .frame(width:14,height:14).contentShape(Rectangle())
            .onTapGesture { state.closeTab(tab) }
        }
        .padding(.horizontal, 12).frame(height:34)
        .background(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .overlay(Rectangle().frame(height:2).foregroundColor(isActive ? .accentColor : .clear), alignment:.bottom)
        .contentShape(Rectangle())
        .onTapGesture { state.selectTab(tab) }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject var state: AppState

    private var appLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            if let logo = appLogo {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
            }
            VStack(spacing: 6) {
                Text("TypstEditor")
                    .font(.system(size: 22, weight: .bold))
                Text("Fast, live typography & document preview")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Text("Open a project folder and pick a file from the sidebar,\nor create a new document.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Open Project…")  { state.openProject() }.buttonStyle(.borderedProminent)
                Button("Open File…")     { state.openFilePanel() }.buttonStyle(.bordered)
                Button("New .typ File…") { state.newFile() }.buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - .typ editor + live preview

struct TypEditorView: View {
    @EnvironmentObject var state: AppState
    @State private var editorFraction: CGFloat = 0.5
    @State private var pageInput: String = "1"

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Editor
                VStack(spacing: 0) {
                    editorToolbar
                    Divider()
                    TypstTextEditor(
                        text: Binding(get: { state.activeSource }, set: { _ in }),
                        totalPages: state.totalPages,
                        onTextChange: { state.sourceDidChange($0) },
                        onCaretChange: { state.sourcePositionDidChange($0) }
                    )
                    .frame(maxWidth:.infinity, maxHeight:.infinity)
                }
                .frame(width: geo.size.width * editorFraction)

                DragHandle {
                    let p = (geo.size.width * editorFraction + $0) / geo.size.width
                    editorFraction = min(max(p, 0.2), 0.8)
                }

                // Preview
                VStack(spacing: 0) {
                    previewToolbar(pageInput: $pageInput)
                    Divider()
                    previewContent
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfPageChanged)) { note in
            if let page = note.object as? Int {
                pageInput = "\(page)"
                state.currentPage = page
            }
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            Text(state.activeURL?.lastPathComponent ?? "")
                .font(.system(size:11, weight:.medium)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Save")     { state.saveActive() }
                .buttonStyle(.borderless).font(.system(size:11)).disabled(!state.isDirty)
            Button("Save As…") { state.saveActiveAs() }
                .buttonStyle(.borderless).font(.system(size:11))
        }
        .padding(.horizontal,12).padding(.vertical,6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var zoomTitle: String {
        switch state.zoomMode {
        case .fitWidth:
            return "Fit Width"
        case .fitPage:
            return "Fit Page"
        case .custom:
            return "\(Int(round(state.zoomScale * 100)))%"
        }
    }

    @ViewBuilder
    private func previewToolbar(pageInput: Binding<String>) -> some View {
        HStack(spacing: 8) {
            // Status icon
            if state.isCompiling {
                ProgressView().controlSize(.small)
            } else if !state.errorMessage.isEmpty {
                Image(systemName:"exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size:11))
                    .help("Compilation has issues")
            } else if state.pdfDocument != nil {
                Image(systemName:"checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size:11))
                    .help("Document up to date")
            }

            Spacer()

            // Page indicator + jump
            if state.totalPages > 0 {
                HStack(spacing: 4) {
                    Button(action: { jumpPage(by: -1, current: pageInput.wrappedValue) }) {
                        Image(systemName:"chevron.left").font(.system(size:10,weight:.medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.currentPage <= 1)
                    .help("Previous Page (⌘[)")

                    TextField("", text: pageInput)
                        .multilineTextAlignment(.center)
                        .font(.system(size:11, design:.monospaced))
                        .frame(width:32)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitPageJump(pageInput.wrappedValue) }

                    Text("/ \(state.totalPages)")
                        .font(.system(size:11)).foregroundColor(.secondary)

                    Button(action: { jumpPage(by: 1, current: pageInput.wrappedValue) }) {
                        Image(systemName:"chevron.right").font(.system(size:10,weight:.medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.currentPage >= state.totalPages)
                    .help("Next Page (⌘])")
                }
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 2) {
                Button(action: { state.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Zoom Out (⌘-)")

                Menu {
                    Button("Fit Width") { state.zoomFitWidth() }
                    Button("Fit Page")  { state.zoomFitPage() }
                    Divider()
                    Button("50%")  { state.zoomSetPercentage(50) }
                    Button("75%")  { state.zoomSetPercentage(75) }
                    Button("100%") { state.zoomSetPercentage(100) }
                    Button("125%") { state.zoomSetPercentage(125) }
                    Button("150%") { state.zoomSetPercentage(150) }
                    Button("200%") { state.zoomSetPercentage(200) }
                } label: {
                    Text(zoomTitle)
                        .font(.system(size: 11))
                        .frame(minWidth: 54)
                }
                .menuStyle(.borderlessButton)

                Button(action: { state.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Zoom In (⌘+)")
            }

            Divider().frame(height: 14)

            // Export Menu
            Menu {
                Button(action: { state.exportPDF() }) {
                    Label("Export PDF…", systemImage: "doc.richtext")
                }
                Button(action: { state.exportPNG() }) {
                    Label("Export High-Res PNG (3×)…", systemImage: "photo")
                }
                Button(action: { state.exportSVG() }) {
                    Label("Export Vector SVG…", systemImage: "square.stack.3d.up")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                    Text("Export")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(state.lastExportData == nil)
        }
        .padding(.horizontal,12).padding(.vertical,6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func cleanErrorMessage(_ message: String) -> String {
        var text = message
        if let regex = try? NSRegularExpression(pattern: #"([^\s:]+\.__typsteditor_preview_[A-Za-z0-9\-]+\.typ:\d+:\d+:\s*)"#) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
        } else if let regex = try? NSRegularExpression(pattern: #"([^\s:]+\.__typsteditor_preview_[A-Za-z0-9\-]+\.typ:\s*)"#) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var previewContent: some View {
        if let doc = state.pdfDocument {
            VStack(spacing: 0) {
                if !state.errorMessage.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text(cleanErrorMessage(state.errorMessage))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Spacer()
                        if let line = state.errorLine {
                            Button(action: { state.jumpToError() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 10))
                                    Text("Line \(line)\(state.errorColumn.map { ":\($0)" } ?? "")")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.orange.opacity(0.4)), alignment: .bottom)
                }
                PDFPreview(document: doc,
                           isCompiling: state.isCompiling,
                           sourceProgress: state.sourceProgress,
                           zoomMode: state.zoomMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if !state.errorMessage.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                    Text("Compilation Failed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                    Spacer()
                    if let line = state.errorLine {
                        Button(action: { state.jumpToError() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 10))
                                Text("Jump to Line \(line)\(state.errorColumn.map { ":\($0)" } ?? "")")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.12))
                Divider()
                ScrollView {
                    Text(cleanErrorMessage(state.errorMessage))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            Color(NSColor.windowBackgroundColor)
                .frame(maxWidth:.infinity, maxHeight:.infinity)
                .overlay(
                    VStack(spacing: 8) {
                        if state.isCompiling {
                            ProgressView().scaleEffect(0.8)
                            Text("Rendering preview…").foregroundColor(.secondary).font(.system(size:12))
                        } else {
                            Text("Open a .typ file to see a preview")
                                .foregroundColor(.secondary).font(.system(size:13))
                        }
                    }
                )
        }
    }

    private func jumpPage(by delta: Int, current: String) {
        let page = (Int(current) ?? state.currentPage) + delta
        commitPageJump("\(page)")
    }

    private func commitPageJump(_ raw: String) {
        guard let page = Int(raw) else { return }
        state.jumpToPage(page)
    }
}

// MARK: - Plain text editor

struct PlainTextEditorView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(state.activeURL?.lastPathComponent ?? "")
                    .font(.system(size:11,weight:.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Save")     { state.saveActive() }
                    .buttonStyle(.borderless).font(.system(size:11)).disabled(!state.isDirty)
                Button("Save As…") { state.saveActiveAs() }
                    .buttonStyle(.borderless).font(.system(size:11))
            }
            .padding(.horizontal,12).padding(.vertical,6)
            .background(Color(NSColor.windowBackgroundColor))
            Divider()
            TypstTextEditor(
                text: Binding(get: { state.activeSource }, set: { _ in }),
                onTextChange: { state.sourceDidChange($0) }
            )
            .frame(maxWidth:.infinity, maxHeight:.infinity)
        }
    }
}

// MARK: - PDF Preview
//
// Continuous, smooth, flicker-free preview.
// Pages are rendered directly to GPU-backed CALayer textures using background CoreGraphics,
// eliminating PDFKit's document reload white-flash completely while keeping scrolling
// and live updates instantaneous without flicker like the Typst web editor.

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument
    let isCompiling: Bool
    let sourceProgress: Double
    let zoomMode: ZoomMode

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SmoothPDFContainer {
        let container = SmoothPDFContainer()
        container.setZoomMode(zoomMode)
        container.setDocument(document)

        context.coordinator.container = container
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleJump(_:)),
            name: .jumpToPage,
            object: nil
        )
        return container
    }

    func updateNSView(_ container: SmoothPDFContainer, context: Context) {
        if container.zoomMode != zoomMode {
            container.setZoomMode(zoomMode)
        }
        if container.currentDocument !== document {
            context.coordinator.lastSourceProgress = sourceProgress
            container.setDocument(document)
        } else if abs(context.coordinator.lastSourceProgress - sourceProgress) > 0.001 {
            context.coordinator.lastSourceProgress = sourceProgress
            container.scrollToSourceProgress(sourceProgress)
        }
    }

    final class Coordinator: NSObject {
        weak var container: SmoothPDFContainer?
        var lastSourceProgress: Double = -1

        @objc func handleJump(_ note: Notification) {
            guard let page = note.object as? Int, let c = container else { return }
            c.jumpToPage(page)
        }
    }
}

// MARK: - SmoothPDFContainer

final class SmoothPDFContainer: NSView {
    private let scrollView = NSScrollView()
    private let canvasView = FlippedCanvasView()
    private(set) var pageViews: [SinglePageView] = []
    private(set) var currentDocument: PDFDocument?
    private var renderGeneration = 0
    private let renderQueue = DispatchQueue(label: "com.typsteditor.previewrender", qos: .userInteractive)
    private var lastReportedPage = 1
    private(set) var currentDisplayScale: CGFloat = 1.0
    private(set) var zoomMode: ZoomMode = .fitWidth
    private var initialPinchScale: CGFloat = 1.0

    private let pageSpacing: CGFloat = 18
    private let horizontalMargin: CGFloat = 20
    private let verticalMargin: CGFloat = 20

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(name: nil, dynamicProvider: { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
                : NSColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
        })

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = canvasView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollNotification(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Trackpad pinch-to-zoom
        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        pinch.delaysPrimaryMouseButtonEvents = false
        scrollView.addGestureRecognizer(pinch)

        // Zoom shortcuts and toolbar notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleZoomInNote), name: .zoomIn, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleZoomOutNote), name: .zoomOut, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleZoomFitWidthNote), name: .zoomReset, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleZoomFitPageNote), name: .zoomFitPage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleZoomSetPercentageNote(_:)), name: .zoomSetPercentage, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        layoutPages()
    }

    func setZoomMode(_ mode: ZoomMode) {
        guard zoomMode != mode else { return }
        zoomMode = mode
        layoutPages()
    }

    @objc private func handleZoomInNote() {
        let presets: [CGFloat] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
        let cur = currentDisplayScale
        let next = presets.first { $0 > cur + 0.05 } ?? min(cur * 1.25, 4.0)
        zoomMode = .custom(next)
        layoutPages()
    }

    @objc private func handleZoomOutNote() {
        let presets: [CGFloat] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0].reversed()
        let cur = currentDisplayScale
        let prev = presets.first { $0 < cur - 0.05 } ?? max(cur * 0.8, 0.25)
        zoomMode = .custom(prev)
        layoutPages()
    }

    @objc private func handleZoomFitWidthNote() {
        zoomMode = .fitWidth
        layoutPages()
    }

    @objc private func handleZoomFitPageNote() {
        zoomMode = .fitPage
        layoutPages()
    }

    @objc private func handleZoomSetPercentageNote(_ note: Notification) {
        guard let percent = note.object as? Int else { return }
        zoomMode = .custom(CGFloat(percent) / 100.0)
        layoutPages()
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialPinchScale = currentDisplayScale
        case .changed:
            let newScale = max(0.25, min(4.0, initialPinchScale * (1.0 + gesture.magnification)))
            zoomMode = .custom(newScale)
            currentDisplayScale = newScale
            layoutPagesFast()
            notifyZoomChanged()
        case .ended, .cancelled:
            if let doc = currentDocument {
                renderPages(doc: doc, generation: renderGeneration)
            }
        default:
            break
        }
    }

    private func notifyZoomChanged() {
        NotificationCenter.default.post(
            name: .previewZoomChanged,
            object: (scale: currentDisplayScale, mode: zoomMode)
        )
    }

    func setDocument(_ doc: PDFDocument) {
        guard currentDocument !== doc else { return }
        currentDocument = doc
        renderGeneration += 1
        let generation = renderGeneration
        let count = doc.pageCount

        // Synchronize page view count without removing existing views to avoid flicker
        while pageViews.count < count {
            let pv = SinglePageView()
            canvasView.addSubview(pv)
            pageViews.append(pv)
        }
        while pageViews.count > count {
            let last = pageViews.removeLast()
            last.removeFromSuperview()
        }

        for (i, pv) in pageViews.enumerated() {
            pv.pageIndex = i
            pv.onClick = { [weak self] clickPoint, pageIndex in
                self?.handlePageClick(at: clickPoint, pageIndex: pageIndex)
            }
        }

        layoutPages()
        renderPages(doc: doc, generation: generation)
    }

    private func handlePageClick(at clickPoint: NSPoint, pageIndex: Int) {
        guard let doc = currentDocument, let page = doc.page(at: pageIndex) else { return }
        let box = page.bounds(for: .mediaBox)
        guard pageIndex < pageViews.count else { return }
        let pv = pageViews[pageIndex]
        guard pv.bounds.width > 0, pv.bounds.height > 0 else { return }

        let relX = max(0, min(1, clickPoint.x / pv.bounds.width))
        let relY = max(0, min(1, clickPoint.y / pv.bounds.height))

        let pdfX = box.minX + relX * box.width
        let pdfY = box.minY + (1.0 - relY) * box.height
        let pdfPoint = NSPoint(x: pdfX, y: pdfY)

        var extractedWord = page.selectionForWord(at: pdfPoint)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        var extractedLine = page.selectionForLine(at: pdfPoint)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)

        if (extractedWord == nil || extractedWord?.isEmpty == true) && (extractedLine == nil || extractedLine?.isEmpty == true) {
            // Broaden search area around click point
            let rect = NSRect(x: box.minX + 20, y: max(box.minY, pdfY - 25), width: max(50, box.width - 40), height: 50)
            let nearby = page.selection(for: rect)?.string?.components(separatedBy: "\n")
            extractedLine = nearby?.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let line = extractedLine {
                extractedWord = line.components(separatedBy: .whitespaces).first
            }
        }

        NotificationCenter.default.post(
            name: .previewPageClicked,
            object: (pageIndex: pageIndex, relativeY: relY, extractedLine: extractedLine, extractedWord: extractedWord)
        )
    }

    private func layoutPages() {
        guard let doc = currentDocument, doc.pageCount > 0 else {
            canvasView.frame = bounds
            return
        }

        let viewportWidth = scrollView.contentSize.width
        let viewportHeight = scrollView.contentSize.height
        guard viewportWidth > 0 else { return }

        let availableWidth = max(100, viewportWidth - horizontalMargin * 2)
        let availableHeight = max(100, viewportHeight - verticalMargin * 2)
        let firstPageBox = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)

        let scale: CGFloat
        switch zoomMode {
        case .fitWidth:
            scale = availableWidth / max(1, firstPageBox.width)
        case .fitPage:
            let scaleW = availableWidth / max(1, firstPageBox.width)
            let scaleH = availableHeight / max(1, firstPageBox.height)
            scale = min(scaleW, scaleH)
        case .custom(let customScale):
            scale = customScale
        }

        let scaleChanged = abs(currentDisplayScale - scale) > 0.02
        currentDisplayScale = scale

        var maxPageWidth: CGFloat = 0
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i) {
                let w = page.bounds(for: .mediaBox).width * scale
                if w > maxPageWidth { maxPageWidth = w }
            }
        }

        let canvasWidth = max(viewportWidth, maxPageWidth + horizontalMargin * 2)

        var currentY: CGFloat = verticalMargin
        for (i, pv) in pageViews.enumerated() {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let w = box.width * scale
            let h = box.height * scale
            let x = (canvasWidth - w) / 2
            pv.frame = NSRect(x: round(x), y: round(currentY), width: round(w), height: round(h))
            pv.pageIndex = i
            currentY += h + pageSpacing
        }

        let totalHeight = currentY - pageSpacing + verticalMargin
        canvasView.frame = NSRect(
            x: 0,
            y: 0,
            width: canvasWidth,
            height: max(viewportHeight, totalHeight)
        )

        notifyZoomChanged()

        if scaleChanged {
            renderPages(doc: doc, generation: renderGeneration)
        }
    }

    private func layoutPagesFast() {
        guard let doc = currentDocument, doc.pageCount > 0 else { return }
        let viewportWidth = scrollView.contentSize.width
        let viewportHeight = scrollView.contentSize.height
        guard viewportWidth > 0 else { return }

        let scale = currentDisplayScale
        var maxPageWidth: CGFloat = 0
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i) {
                let w = page.bounds(for: .mediaBox).width * scale
                if w > maxPageWidth { maxPageWidth = w }
            }
        }

        let canvasWidth = max(viewportWidth, maxPageWidth + horizontalMargin * 2)

        var currentY: CGFloat = verticalMargin
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, pv) in pageViews.enumerated() {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let w = box.width * scale
            let h = box.height * scale
            let x = (canvasWidth - w) / 2
            pv.frame = NSRect(x: round(x), y: round(currentY), width: round(w), height: round(h))
            currentY += h + pageSpacing
        }

        let totalHeight = currentY - pageSpacing + verticalMargin
        canvasView.frame = NSRect(
            x: 0,
            y: 0,
            width: canvasWidth,
            height: max(viewportHeight, totalHeight)
        )
        CATransaction.commit()
    }

    private func renderPages(doc: PDFDocument, generation: Int) {
        let count = doc.pageCount
        let scaleFactor = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let displayScale = currentDisplayScale

        renderQueue.async { [weak self] in
            guard let self else { return }
            for index in 0..<count {
                guard self.renderGeneration == generation else { return }
                guard let page = doc.page(at: index) else { continue }

                let mediaBox = page.bounds(for: .mediaBox)
                let pixelWidth = Int(ceil(mediaBox.width * displayScale * scaleFactor))
                let pixelHeight = Int(ceil(mediaBox.height * displayScale * scaleFactor))
                guard pixelWidth > 0, pixelHeight > 0 else { continue }

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let ctx = CGContext(
                    data: nil,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { continue }

                ctx.interpolationQuality = .high
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

                let renderScale = CGFloat(pixelWidth) / mediaBox.width
                ctx.scaleBy(x: renderScale, y: renderScale)
                page.draw(with: .mediaBox, to: ctx)

                guard let cgImage = ctx.makeImage() else { continue }

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.renderGeneration == generation else { return }
                    if index < self.pageViews.count {
                        self.pageViews[index].setImage(cgImage)
                    }
                }
            }
        }
    }

    @objc private func handleScrollNotification(_ note: Notification) {
        guard let doc = currentDocument, doc.pageCount > 0 else { return }
        let visibleMidY = scrollView.contentView.bounds.midY
        var activeIndex = 0
        for (i, pv) in pageViews.enumerated() {
            if pv.frame.minY <= visibleMidY && pv.frame.maxY >= visibleMidY {
                activeIndex = i
                break
            } else if pv.frame.minY > visibleMidY {
                activeIndex = max(0, i - 1)
                break
            }
            activeIndex = i
        }
        let pageNum = activeIndex + 1
        if pageNum != lastReportedPage {
            lastReportedPage = pageNum
            NotificationCenter.default.post(name: .pdfPageChanged, object: pageNum)
        }
    }

    func jumpToPage(_ page: Int) {
        let index = max(0, min(page - 1, pageViews.count - 1))
        guard pageViews.indices.contains(index) else { return }
        let targetY = max(0, pageViews[index].frame.minY - verticalMargin)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func scrollToSourceProgress(_ progress: Double) {
        let maxY = max(0, canvasView.bounds.height - scrollView.contentSize.height)
        guard maxY > 0 else { return }
        let targetY = maxY * min(max(progress, 0), 1)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - Canvas and Page Views

private final class FlippedCanvasView: NSView {
    override var isFlipped: Bool { true }
}

final class SinglePageView: NSView {
    private let contentLayer = CALayer()
    var pageIndex: Int = 0
    var onClick: ((_ clickPoint: NSPoint, _ pageIndex: Int) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 2
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        contentLayer.contentsGravity = .resizeAspect
        contentLayer.masksToBounds = true
        layer?.addSublayer(contentLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = bounds
        CATransaction.commit()
    }

    func setImage(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = image
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 || event.modifierFlags.contains(.command) {
            let clickPoint = convert(event.locationInWindow, from: nil)
            showClickRipple(at: clickPoint)
            onClick?(clickPoint, pageIndex)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func showClickRipple(at point: NSPoint) {
        let ripple = CALayer()
        ripple.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        ripple.position = point
        ripple.cornerRadius = 14
        ripple.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.35).cgColor
        layer?.addSublayer(ripple)

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = 0.35
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        ripple.add(anim, forKey: "fade")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            ripple.removeFromSuperlayer()
        }
    }
}

extension Notification.Name {
    static let pdfPageChanged = Notification.Name("pdfPageChanged")
}

// MARK: - Drag handle

struct DragHandle: View {
    var onDrag: (CGFloat) -> Void
    @State private var isDragging = false
    var body: some View {
        Rectangle().fill(Color(NSColor.separatorColor)).frame(width:1)
            .overlay(
                Color.clear.frame(width:8).contentShape(Rectangle())
                    .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance:0)
                        .onChanged { v in isDragging = true; onDrag(v.translation.width) }
                        .onEnded   { _ in isDragging = false })
            )
    }
}
