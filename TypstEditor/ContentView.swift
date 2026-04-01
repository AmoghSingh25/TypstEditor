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
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName:"doc.text.magnifyingglass").font(.system(size:44)).foregroundColor(.secondary)
            Text("No file open").font(.title2)
            Text("Open a project folder and pick a file from the sidebar,\nor open a file directly.")
                .font(.system(size:13)).foregroundColor(.secondary).multilineTextAlignment(.center)
            HStack(spacing:10) {
                Button("Open Project…")  { state.openProject() }.buttonStyle(.borderedProminent)
                Button("Open File…")     { state.openFilePanel() }.buttonStyle(.bordered)
                Button("New .typ File…") { state.newFile() }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth:.infinity, maxHeight:.infinity)
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
                        onTextChange: { state.sourceDidChange($0) }
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

    @ViewBuilder
    private func previewToolbar(pageInput: Binding<String>) -> some View {
        HStack(spacing: 6) {
            // Status icon
            if state.isCompiling {
                ProgressView().controlSize(.small)
            } else if !state.errorMessage.isEmpty {
                Image(systemName:"exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size:11))
            } else if state.pdfDocument != nil {
                Image(systemName:"checkmark.circle.fill").foregroundColor(.green).font(.system(size:11))
            }

            Spacer()

            // Page indicator + jump
            if state.totalPages > 0 {
                HStack(spacing: 4) {
                    Button(action: { jumpPage(by: -1, current: pageInput.wrappedValue) }) {
                        Image(systemName:"chevron.left").font(.system(size:10,weight:.medium))
                    }
                    .buttonStyle(.borderless).disabled(state.currentPage <= 1)

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
                    .buttonStyle(.borderless).disabled(state.currentPage >= state.totalPages)
                }
            }

            Spacer()

            Button("Export PDF…") { state.exportPDF() }
                .buttonStyle(.borderless).font(.system(size:11))
                .disabled(state.lastExportURL == nil)
        }
        .padding(.horizontal,12).padding(.vertical,6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var previewContent: some View {
        if !state.errorMessage.isEmpty {
            ScrollView {
                Text(state.errorMessage)
                    .font(.system(size:12,design:.monospaced)).foregroundColor(.red)
                    .frame(maxWidth:.infinity, alignment:.leading).padding(12)
            }
            .frame(maxWidth:.infinity, maxHeight:.infinity).background(Color.red.opacity(0.05))
        } else if let doc = state.pdfDocument {
            PDFPreview(document: doc, compileCount: state.compileCount)
                .frame(maxWidth:.infinity, maxHeight:.infinity)
        } else {
            Color(NSColor.windowBackgroundColor)
                .frame(maxWidth:.infinity, maxHeight:.infinity)
                .overlay(
                    VStack(spacing: 8) {
                        if state.findTypst() == nil {
                            Text("typst not found — brew install typst")
                                .foregroundColor(.secondary).font(.system(size:13))
                        } else if state.isCompiling {
                            ProgressView().scaleEffect(0.8)
                            Text("Starting…").foregroundColor(.secondary).font(.system(size:12))
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
// Uses a wrapper NSView that holds the PDFView as a child.  When a new document
// arrives we:
//   1. Snapshot the current PDFView pixels into a CALayer (freeze the screen).
//   2. Swap the PDFDocument (PDFView goes blank internally for one frame).
//   3. Wait one runloop pass for PDFView to finish layout.
//   4. Restore scroll position.
//   5. Fade the snapshot layer out — by the time it's gone PDFView is painted.
// This completely hides the internal blank flash.

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument
    let compileCount: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FlickerFreePDFContainer {
        let container = FlickerFreePDFContainer()
        container.setDocument(document, animate: false)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: container.pdfView)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleJump(_:)),
            name: .jumpToPage,
            object: nil)
        context.coordinator.container = container
        return container
    }

    func updateNSView(_ container: FlickerFreePDFContainer, context: Context) {
        guard container.pdfView.document !== document else { return }
        container.setDocument(document, animate: true)
    }

    final class Coordinator: NSObject {
        weak var container: FlickerFreePDFContainer?

        @objc func pageChanged(_ note: Notification) {
            guard let v = note.object as? PDFView,
                  let page = v.currentPage,
                  let doc = v.document else { return }
            let idx = doc.index(for: page) + 1
            NotificationCenter.default.post(name: .pdfPageChanged, object: idx)
        }

        @objc func handleJump(_ note: Notification) {
            guard let page = note.object as? Int,
                  let c = container,
                  let doc = c.pdfView.document,
                  let p = doc.page(at: page - 1) else { return }
            DispatchQueue.main.async { c.pdfView.go(to: p) }
        }
    }
}

// MARK: - FlickerFreePDFContainer

final class FlickerFreePDFContainer: NSView {
    let pdfView = PDFView()
    private var snapshotLayer: CALayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .white
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setDocument(_ doc: PDFDocument, animate: Bool) {
        if animate {
            swapWithSnapshot(doc)
        } else {
            pdfView.document = doc
        }
    }

    private func swapWithSnapshot(_ newDoc: PDFDocument) {
        // 1. Capture the current pixels
        let snapshot = makeSnapshot()

        // 2. Save scroll position
        let scrollInfo = captureScrollPosition()

        // 3. Swap the document — PDFView blanks internally here
        pdfView.document = newDoc

        // 4. Immediately overlay the snapshot so the user sees no blank
        if let snap = snapshot {
            snap.frame = bounds
            snap.zPosition = 1000
            layer?.addSublayer(snap)
            snapshotLayer = snap
        }

        // 5. Give PDFView one runloop pass to layout, then restore scroll
        //    and fade the snapshot out
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreScrollPosition(scrollInfo, in: newDoc)

            // Short delay so PDFView finishes painting before we remove cover
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, let snap = self.snapshotLayer else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.08)
                CATransaction.setCompletionBlock { snap.removeFromSuperlayer() }
                snap.opacity = 0
                CATransaction.commit()
                self.snapshotLayer = nil
            }
        }
    }

    private func makeSnapshot() -> CALayer? {
        guard let contentLayer = pdfView.layer else { return nil }
        let snap = CALayer()
        snap.contents = contentLayer.contents
        // Walk subviews to find the scroll content and render it
        if let bitmapRep = pdfView.bitmapImageRepForCachingDisplay(in: pdfView.bounds) {
            pdfView.cacheDisplay(in: pdfView.bounds, to: bitmapRep)
            if let cgImage = bitmapRep.cgImage {
                let imageLayer = CALayer()
                imageLayer.frame = bounds
                imageLayer.contents = cgImage
                imageLayer.contentsGravity = .resize
                return imageLayer
            }
        }
        return nil
    }

    private struct ScrollInfo {
        let pageIndex: Int?
        let pageOffset: CGFloat
        let fraction: CGFloat
    }

    private func captureScrollPosition() -> ScrollInfo {
        let sv = pdfView.documentView?.enclosingScrollView
        let dv = pdfView.documentView
        var fraction: CGFloat = 0
        if let dv, dv.bounds.height > 0 {
            let vis = sv?.documentVisibleRect ?? dv.visibleRect
            fraction = vis.minY / dv.bounds.height
        }
        let pageIndex = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) }
        var pageOffset: CGFloat = 0
        if let page = pdfView.currentPage, let dv {
            let pageRect = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
            let visMin   = sv?.documentVisibleRect.minY ?? dv.visibleRect.minY
            pageOffset   = visMin - pageRect.minY
        }
        return ScrollInfo(pageIndex: pageIndex, pageOffset: pageOffset, fraction: fraction)
    }

    private func restoreScrollPosition(_ info: ScrollInfo, in doc: PDFDocument) {
        guard let dv = pdfView.documentView else { return }
        let sv = dv.enclosingScrollView
        if let idx = info.pageIndex, let newPage = doc.page(at: idx) {
            let pageRect = pdfView.convert(newPage.bounds(for: pdfView.displayBox), from: newPage)
            let targetY  = pageRect.minY + info.pageOffset
            let maxY     = dv.bounds.height - (sv?.contentSize.height ?? 0)
            dv.scroll(NSPoint(x: 0, y: max(0, min(targetY, maxY))))
        } else {
            dv.scroll(NSPoint(x: 0, y: info.fraction * dv.bounds.height))
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
