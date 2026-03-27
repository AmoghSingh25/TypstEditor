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
                .overlay(Text(state.findTypst() == nil
                    ? "typst not found — brew install typst" : "Waiting for typst watch…")
                    .foregroundColor(.secondary).font(.system(size:13)))
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

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument
    let compileCount: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .white
        v.document = document

        // Observe page changes and forward to SwiftUI via notification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: v)

        // Observe jump-to-page requests
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleJump(_:)),
            name: .jumpToPage,
            object: nil)
        context.coordinator.pdfView = v
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        guard v.document !== document else { return }

        let scrollView = v.documentView?.enclosingScrollView
        let docView    = v.documentView
        var scrollFraction: CGFloat = 0
        if let dv = docView, dv.bounds.height > 0 {
            let vis = scrollView?.documentVisibleRect ?? dv.visibleRect
            scrollFraction = vis.minY / dv.bounds.height
        }
        let pageIndex = v.currentPage.flatMap { v.document?.index(for: $0) }
        var pageOffset: CGFloat = 0
        if let page = v.currentPage, let dv = docView {
            let pageRect = v.convert(page.bounds(for: v.displayBox), from: page)
            let visMin   = scrollView?.documentVisibleRect.minY ?? dv.visibleRect.minY
            pageOffset   = visMin - pageRect.minY
        }

        v.document = document

        DispatchQueue.main.async {
            guard let dv = v.documentView else { return }
            if let idx = pageIndex, let newPage = document.page(at: idx) {
                let pageRect = v.convert(newPage.bounds(for: v.displayBox), from: newPage)
                let targetY  = pageRect.minY + pageOffset
                let maxY     = dv.bounds.height - (scrollView?.contentSize.height ?? 0)
                dv.scroll(NSPoint(x: 0, y: max(0, min(targetY, maxY))))
            } else {
                dv.scroll(NSPoint(x: 0, y: scrollFraction * dv.bounds.height))
            }
        }
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?

        @objc func pageChanged(_ note: Notification) {
            guard let v = note.object as? PDFView,
                  let page = v.currentPage,
                  let doc = v.document else { return }
            let idx = doc.index(for: page) + 1
            NotificationCenter.default.post(name: .pdfPageChanged, object: idx)
        }

        @objc func handleJump(_ note: Notification) {
            guard let page = note.object as? Int,
                  let v = pdfView,
                  let doc = v.document,
                  let p = doc.page(at: page - 1) else { return }
            DispatchQueue.main.async { v.go(to: p) }
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
