import SwiftUI
import AppKit

// MARK: - Syntax highlighting
// Applied on the main thread using NSTextStorage, triggered after each edit.
// We only rehighlight the visible range plus a small buffer for performance.

private struct HighlightRule {
    let pattern: NSRegularExpression
    let color: NSColor
    let bold: Bool
    let italic: Bool
}

private let highlightRules: [HighlightRule] = {
    func rule(_ pat: String, _ color: NSColor, bold: Bool = false, italic: Bool = false,
              options: NSRegularExpression.Options = []) -> HighlightRule {
        let re = try! NSRegularExpression(pattern: pat, options: options)
        return HighlightRule(pattern: re, color: color, bold: bold, italic: italic)
    }
    return [
        // Comments (must come first so they override everything inside)
        rule(#"//[^\n]*"#,          .init(red:0.42,green:0.52,blue:0.60,alpha:1)),
        rule(#"/\*[\s\S]*?\*/"#,    .init(red:0.42,green:0.52,blue:0.60,alpha:1)),
        // Block math  $$ ... $$
        rule(#"\$\$[\s\S]*?\$\$"#,  .init(red:0.78,green:0.55,blue:1.00,alpha:1)),
        // Inline math  $ ... $
        rule(#"\$[^$\n]+\$"#,       .init(red:0.78,green:0.55,blue:1.00,alpha:1)),
        // Fenced code blocks  ``` ... ```
        rule(#"```[\s\S]*?```"#,    .init(red:0.49,green:0.81,blue:0.58,alpha:1)),
        // Inline code  ` ... `
        rule(#"`[^`\n]+`"#,         .init(red:0.49,green:0.81,blue:0.58,alpha:1)),
        // Headings  = Heading
        rule(#"^={1,6} .+$"#,      .init(red:0.40,green:0.75,blue:1.00,alpha:1), bold: true,
             options: .anchorsMatchLines),
        // Bold  *text*
        rule(#"\*[^*\n]+\*"#,       .init(red:0.95,green:0.95,blue:0.95,alpha:1), bold: true),
        // Italic  _text_
        rule(#"_[^_\n]+_"#,         .init(red:0.90,green:0.85,blue:1.00,alpha:1), italic: true),
        // Strings  "..."
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, .init(red:1.00,green:0.72,blue:0.42,alpha:1)),
        // Labels  <label>  and refs @label
        rule(#"<[a-zA-Z][a-zA-Z0-9_-]*>"#, .init(red:0.60,green:0.90,blue:0.70,alpha:1)),
        rule(#"@[a-zA-Z][a-zA-Z0-9_-]*"#,  .init(red:0.60,green:0.90,blue:0.70,alpha:1)),
        // Numbers with units
        rule(#"\b\d+(\.\d+)?(pt|em|cm|mm|in|%|fr|px)?\b"#, .init(red:1.00,green:0.78,blue:0.42,alpha:1)),
        // Keywords  #set #show #let #if etc.
        rule(#"#(set|show|let|import|include|if|else|for|while|return|none|auto|true|false)\b"#,
             .init(red:0.95,green:0.55,blue:0.65,alpha:1)),
        // Function calls  #funcname
        rule(#"#([a-zA-Z][a-zA-Z0-9_-]*)"#, .init(red:0.40,green:0.80,blue:1.00,alpha:1)),
    ]
}()

private let baseFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
private let boldFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
private let italicFont  = NSFont(name: "Menlo-Italic", size: 13)
                          ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
private let baseColor   = NSColor(red:0.85,green:0.87,blue:0.90,alpha:1)

func applyHighlighting(to storage: NSTextStorage) {
    let text     = storage.string
    let fullNS   = NSRange(text.startIndex..., in: text)
    let full     = NSRange(location: 0, length: (text as NSString).length)

    storage.beginEditing()
    storage.setAttributes([.font: baseFont, .foregroundColor: baseColor], range: full)

    for rule in highlightRules {
        rule.pattern.enumerateMatches(in: text, range: fullNS) { match, _, _ in
            guard let r = match?.range else { return }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: rule.color]
            if rule.bold   { attrs[.font] = boldFont }
            if rule.italic { attrs[.font] = italicFont }
            storage.addAttributes(attrs, range: r)
        }
    }
    storage.endEditing()
}

// MARK: - Autocomplete data

struct Completion: Identifiable {
    let id = UUID()
    let insert: String
    let label: String
    let detail: String
    let kind: Kind
    enum Kind { case function, variable, keyword, type, constant }
}

let typstCompletions: [Completion] = [
    // set rules
    .init(insert:"set page(",    label:"set page",    detail:"Page layout settings",       kind:.keyword),
    .init(insert:"set text(",    label:"set text",    detail:"Text appearance settings",   kind:.keyword),
    .init(insert:"set heading(", label:"set heading", detail:"Heading style settings",     kind:.keyword),
    .init(insert:"set par(",     label:"set par",     detail:"Paragraph settings",         kind:.keyword),
    .init(insert:"set list(",    label:"set list",    detail:"Bullet list settings",       kind:.keyword),
    .init(insert:"set enum(",    label:"set enum",    detail:"Numbered list settings",     kind:.keyword),
    .init(insert:"set table(",   label:"set table",   detail:"Table settings",             kind:.keyword),
    .init(insert:"set figure(",  label:"set figure",  detail:"Figure settings",            kind:.keyword),
    .init(insert:"set math(",    label:"set math",    detail:"Math settings",              kind:.keyword),
    .init(insert:"set raw(",     label:"set raw",     detail:"Raw text settings",          kind:.keyword),
    // show rules
    .init(insert:"show heading:", label:"show heading", detail:"Style all headings",       kind:.keyword),
    .init(insert:"show link:",    label:"show link",    detail:"Style all links",          kind:.keyword),
    .init(insert:"show figure:",  label:"show figure",  detail:"Style all figures",        kind:.keyword),
    // keywords
    .init(insert:"let ",      label:"let",     detail:"Bind a variable or function",      kind:.keyword),
    .init(insert:"include \"",label:"include", detail:"Include another .typ file",        kind:.keyword),
    .init(insert:"import \"", label:"import",  detail:"Import from a module",             kind:.keyword),
    .init(insert:"if ",       label:"if",      detail:"Conditional expression",           kind:.keyword),
    .init(insert:"else {",    label:"else",    detail:"Else branch",                      kind:.keyword),
    .init(insert:"for  in ",  label:"for",     detail:"For loop",                         kind:.keyword),
    .init(insert:"while ",    label:"while",   detail:"While loop",                       kind:.keyword),
    .init(insert:"return ",   label:"return",  detail:"Return a value",                   kind:.keyword),
    // layout functions
    .init(insert:"align(center)[",  label:"align",     detail:"align(alignment)[content]",kind:.function),
    .init(insert:"block(",          label:"block",     detail:"block(..args)[content]",   kind:.function),
    .init(insert:"box(",            label:"box",       detail:"box(..args)[content]",     kind:.function),
    .init(insert:"circle(",         label:"circle",    detail:"circle(..args)",           kind:.function),
    .init(insert:"cite(",           label:"cite",      detail:"cite(key)",                kind:.function),
    .init(insert:"colbreak()",      label:"colbreak",  detail:"Insert column break",      kind:.function),
    .init(insert:"columns(2)[",     label:"columns",   detail:"columns(n)[content]",      kind:.function),
    .init(insert:"datetime.today()",label:"datetime.today",detail:"Current date",         kind:.function),
    .init(insert:"ellipse(",        label:"ellipse",   detail:"ellipse(..args)",          kind:.function),
    .init(insert:"emph[",           label:"emph",      detail:"Italic emphasis",          kind:.function),
    .init(insert:"figure(\n  image(\"file.png\"),\n  caption: [],\n)", label:"figure", detail:"Figure with caption", kind:.function),
    .init(insert:"footnote[",       label:"footnote",  detail:"footnote[content]",        kind:.function),
    .init(insert:"grid(\n  columns: (1fr, 1fr),\n  ", label:"grid", detail:"grid(columns:, ..cells)", kind:.function),
    .init(insert:"h(1em)",          label:"h",         detail:"Horizontal space",         kind:.function),
    .init(insert:"hide[",           label:"hide",      detail:"Invisible content",        kind:.function),
    .init(insert:"highlight[",      label:"highlight", detail:"Highlighted text",         kind:.function),
    .init(insert:"image(\"",        label:"image",     detail:"image(\"path\", ..args)",  kind:.function),
    .init(insert:"line(length: 100%)", label:"line",   detail:"Horizontal rule",          kind:.function),
    .init(insert:"link(\"https://\")[", label:"link",  detail:"Hyperlink",                kind:.function),
    .init(insert:"lorem(20)",       label:"lorem",     detail:"Placeholder text",         kind:.function),
    .init(insert:"lower[",          label:"lower",     detail:"Lowercase text",           kind:.function),
    .init(insert:"move(dx: 0pt, dy: 0pt)[", label:"move", detail:"Offset content",       kind:.function),
    .init(insert:"overline[",       label:"overline",  detail:"Overline text",            kind:.function),
    .init(insert:"pagebreak()",     label:"pagebreak", detail:"Force page break",         kind:.function),
    .init(insert:"pad(",            label:"pad",       detail:"pad(insets)[content]",     kind:.function),
    .init(insert:"place(top, ",     label:"place",     detail:"Absolute placement",       kind:.function),
    .init(insert:"polygon(",        label:"polygon",   detail:"polygon(..vertices)",      kind:.function),
    .init(insert:"quote[",          label:"quote",     detail:"Block quote",              kind:.function),
    .init(insert:"raw(\"",          label:"raw",       detail:"raw(text, lang:)",         kind:.function),
    .init(insert:"rect(",           label:"rect",      detail:"Rectangle shape",          kind:.function),
    .init(insert:"ref(",            label:"ref",       detail:"Reference a label",        kind:.function),
    .init(insert:"rotate(",         label:"rotate",    detail:"rotate(angle)[content]",   kind:.function),
    .init(insert:"scale(",          label:"scale",     detail:"scale(factor)[content]",   kind:.function),
    .init(insert:"smallcaps[",      label:"smallcaps", detail:"Small capitals",           kind:.function),
    .init(insert:"stack(",          label:"stack",     detail:"stack(..items)",           kind:.function),
    .init(insert:"strike[",         label:"strike",    detail:"Strikethrough text",       kind:.function),
    .init(insert:"strong[",         label:"strong",    detail:"Bold text",                kind:.function),
    .init(insert:"sub[",            label:"sub",       detail:"Subscript",                kind:.function),
    .init(insert:"super[",          label:"super",     detail:"Superscript",              kind:.function),
    .init(insert:"table(\n  columns: (auto, 1fr),\n  ", label:"table", detail:"table(columns:, ..cells)", kind:.function),
    .init(insert:"text(size: 12pt)[", label:"text",    detail:"Styled text span",         kind:.function),
    .init(insert:"underline[",      label:"underline", detail:"Underlined text",          kind:.function),
    .init(insert:"upper[",          label:"upper",     detail:"Uppercase text",           kind:.function),
    .init(insert:"v(1em)",          label:"v",         detail:"Vertical space",           kind:.function),
    .init(insert:"luma(",           label:"luma",      detail:"Gray shade color",         kind:.function),
    .init(insert:"rgb(",            label:"rgb",       detail:"rgb(r, g, b)",             kind:.function),
    .init(insert:"frac(",           label:"frac",      detail:"Math fraction",            kind:.function),
    .init(insert:"vec(",            label:"vec",       detail:"Math vector",              kind:.function),
    .init(insert:"mat(",            label:"mat",       detail:"Math matrix",              kind:.function),
    // constants & values
    .init(insert:"none",    label:"none",    detail:"Empty value",         kind:.constant),
    .init(insert:"auto",    label:"auto",    detail:"Automatic value",     kind:.constant),
    .init(insert:"true",    label:"true",    detail:"Boolean true",        kind:.constant),
    .init(insert:"false",   label:"false",   detail:"Boolean false",       kind:.constant),
    .init(insert:"center",  label:"center",  detail:"Center alignment",    kind:.constant),
    .init(insert:"left",    label:"left",    detail:"Left alignment",      kind:.constant),
    .init(insert:"right",   label:"right",   detail:"Right alignment",     kind:.constant),
    .init(insert:"top",     label:"top",     detail:"Top alignment",       kind:.constant),
    .init(insert:"bottom",  label:"bottom",  detail:"Bottom alignment",    kind:.constant),
    .init(insert:"horizon", label:"horizon", detail:"Vertical center",     kind:.constant),
    .init(insert:"black",   label:"black",   detail:"Color",               kind:.constant),
    .init(insert:"white",   label:"white",   detail:"Color",               kind:.constant),
    .init(insert:"gray",    label:"gray",    detail:"Color",               kind:.constant),
    .init(insert:"red",     label:"red",     detail:"Color",               kind:.constant),
    .init(insert:"blue",    label:"blue",    detail:"Color",               kind:.constant),
    .init(insert:"green",   label:"green",   detail:"Color",               kind:.constant),
    .init(insert:"yellow",  label:"yellow",  detail:"Color",               kind:.constant),
    .init(insert:"orange",  label:"orange",  detail:"Color",               kind:.constant),
    .init(insert:"purple",  label:"purple",  detail:"Color",               kind:.constant),
    .init(insert:"sum",     label:"sum",     detail:"∑ summation",         kind:.constant),
    .init(insert:"integral",label:"integral",detail:"∫ integral",          kind:.constant),
    .init(insert:"infinity",label:"infinity",detail:"∞",                   kind:.constant),
    .init(insert:"pi",      label:"pi",      detail:"π",                   kind:.constant),
    .init(insert:"alpha",   label:"alpha",   detail:"α",                   kind:.constant),
    .init(insert:"beta",    label:"beta",    detail:"β",                   kind:.constant),
    .init(insert:"gamma",   label:"gamma",   detail:"γ",                   kind:.constant),
    .init(insert:"delta",   label:"delta",   detail:"δ",                   kind:.constant),
    .init(insert:"lambda",  label:"lambda",  detail:"λ",                   kind:.constant),
    .init(insert:"mu",      label:"mu",      detail:"μ",                   kind:.constant),
    .init(insert:"sigma",   label:"sigma",   detail:"σ",                   kind:.constant),
    .init(insert:"theta",   label:"theta",   detail:"θ",                   kind:.constant),
    .init(insert:"omega",   label:"omega",   detail:"ω",                   kind:.constant),
]

// MARK: - NSTextView wrapper

struct TypstTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }

        tv.delegate = context.coordinator
        context.coordinator.textView = tv

        tv.isAutomaticQuoteSubstitutionEnabled  = false
        tv.isAutomaticDashSubstitutionEnabled   = false
        tv.isAutomaticTextReplacementEnabled    = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled      = false
        tv.isContinuousSpellCheckingEnabled     = false
        tv.isGrammarCheckingEnabled             = false
        tv.usesFindBar                          = true   // ⌘F search built-in

        tv.font            = baseFont
        tv.textColor       = baseColor
        tv.backgroundColor = NSColor(red:0.11,green:0.12,blue:0.14,alpha:1)
        tv.isRichText      = false
        tv.allowsUndo      = true
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false

        let para = NSMutableParagraphStyle()
        para.defaultTabInterval = 14
        para.tabStops = []
        tv.defaultParagraphStyle = para

        tv.string = text
        if let ts = tv.textStorage { applyHighlighting(to: ts) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            if let ts = tv.textStorage { applyHighlighting(to: ts) }
            tv.setSelectedRange(NSRange(location: min(sel.location, tv.string.count), length: 0))
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TypstTextEditor
        weak var textView: NSTextView?

        var completionWindow: NSWindow?
        var completionController: CompletionWindowController?
        var currentCompletions: [Completion] = []
        var completionTriggerRange: NSRange = .init(location: NSNotFound, length: 0)

        init(_ parent: TypstTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Highlight first (fast, synchronous)
            if let ts = tv.textStorage { applyHighlighting(to: ts) }
            parent.onTextChange(tv.string)
            checkForCompletion(tv)
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if completionWindow != nil {
                switch sel {
                case #selector(NSResponder.insertNewline(_:)),
                     #selector(NSResponder.insertTab(_:)):
                    if let c = completionController?.selected() { applyCompletion(c) }
                    else { dismissCompletion() }
                    return true
                case #selector(NSResponder.moveDown(_:)):
                    completionController?.moveDown(); return true
                case #selector(NSResponder.moveUp(_:)):
                    completionController?.moveUp(); return true
                case #selector(NSResponder.cancelOperation(_:)):
                    dismissCompletion(); return true
                default: break
                }
            }
            switch sel {
            case #selector(NSResponder.insertTab(_:)):
                tv.insertText("  ", replacementRange: tv.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let str    = tv.string as NSString
                let loc    = tv.selectedRange().location
                let line   = str.substring(with: str.lineRange(for: NSRange(location: loc, length: 0)))
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                tv.insertText("\n" + indent, replacementRange: tv.selectedRange())
                return true
            default: return false
            }
        }

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString text: String?) -> Bool { true }

        // MARK: Autocomplete

        private func checkForCompletion(_ tv: NSTextView) {
            let str = tv.string as NSString
            let loc = tv.selectedRange().location
            guard loc > 0 else { dismissCompletion(); return }

            var start = loc
            while start > 0 {
                let ch = str.character(at: start - 1)
                let s  = Unicode.Scalar(ch)!
                if CharacterSet.alphanumerics.union(.init(charactersIn: "_#.")).contains(s) { start -= 1 }
                else { break }
            }

            let prefix = str.substring(with: NSRange(location: start, length: loc - start))
            guard prefix.hasPrefix("#") else { dismissCompletion(); return }

            let query = String(prefix.dropFirst())
            guard query.count >= 1 else { dismissCompletion(); return }

            let matches = typstCompletions.filter { $0.label.lowercased().hasPrefix(query.lowercased()) }
            if matches.isEmpty { dismissCompletion() }
            else {
                completionTriggerRange = NSRange(location: start + 1, length: loc - start - 1)
                showCompletion(matches, in: tv)
            }
        }

        private func showCompletion(_ completions: [Completion], in tv: NSTextView) {
            currentCompletions = completions
            let loc = tv.selectedRange().location
            let gr  = tv.layoutManager!.glyphRange(
                forCharacterRange: NSRange(location: loc, length: 0), actualCharacterRange: nil)
            var cr = tv.layoutManager!.boundingRect(forGlyphRange: gr, in: tv.textContainer!)
            cr.origin.x += tv.textContainerOrigin.x
            cr.origin.y += tv.textContainerOrigin.y
            let inWin   = tv.convert(cr, to: nil)
            let onScr   = tv.window?.convertToScreen(inWin) ?? inWin

            if completionWindow == nil {
                let cc = CompletionWindowController { [weak self] c in self?.applyCompletion(c) }
                completionController = cc
                completionWindow = cc.window
                tv.window?.addChildWindow(cc.window!, ordered: .above)
            }
            completionController?.update(completions: completions,
                                         caretBottom: NSPoint(x: onScr.minX, y: onScr.minY),
                                         caretTop:    NSPoint(x: onScr.minX, y: onScr.maxY))
        }

        func dismissCompletion() {
            completionController?.window?.orderOut(nil)
            if let w = completionWindow { textView?.window?.removeChildWindow(w) }
            completionWindow = nil
            completionController = nil
        }

        private func applyCompletion(_ c: Completion) {
            guard let tv = textView else { return }
            let replaceRange = completionTriggerRange
            dismissCompletion()
            guard replaceRange.location != NSNotFound else { return }
            tv.insertText(c.insert, replacementRange: replaceRange)
            let last = c.insert.last
            if last == "(" || last == "[" || last == "\"" {
                let newLoc = replaceRange.location + (c.insert as NSString).length
                tv.setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }
    }
}

// MARK: - Completion popup window

private let popupWidth:   CGFloat = 430
private let popupRowH:    CGFloat = 22
private let popupMaxRows: CGFloat = 10
private let popupBG        = NSColor(red:0.13,green:0.13,blue:0.15,alpha:1)
private let popupSelBG     = NSColor(red:0.20,green:0.37,blue:0.65,alpha:1)
private let popupBorder    = NSColor(white:1,alpha:0.10)
private let popupLabel     = NSColor(white:0.92,alpha:1)
private let popupDetail    = NSColor(white:0.55,alpha:1)
private let popupSelLabel  = NSColor.white
private let popupSelDetail = NSColor(white:0.85,alpha:1)

final class CompletionWindowController: NSObject {
    private(set) var window: NSWindow?
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var completions: [Completion] = []
    private var onSelect: (Completion) -> Void
    private var selectedIndex: Int = 0

    init(onSelect: @escaping (Completion) -> Void) { self.onSelect = onSelect; super.init(); buildWindow() }

    private func buildWindow() {
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .popUpMenu
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.appearance = NSAppearance(named: .darkAqua)

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = popupBG.cgColor
        container.layer?.cornerRadius    = 9
        container.layer?.masksToBounds   = true
        container.layer?.borderColor     = popupBorder.cgColor
        container.layer?.borderWidth     = 0.5

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false
        scrollView.backgroundColor       = .clear
        scrollView.scrollerStyle         = .overlay
        scrollView.autoresizingMask      = [.width, .height]

        tableView = CompletionTableView()
        tableView.backgroundColor         = .clear
        tableView.selectionHighlightStyle = .none
        tableView.headerView              = nil
        tableView.rowHeight               = popupRowH
        tableView.intercellSpacing        = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(didDoubleClick)
        tableView.target = self
        let col = NSTableColumn(identifier: .init("main"))
        col.isEditable = false
        tableView.addTableColumn(col)

        scrollView.documentView = tableView
        scrollView.frame = .zero
        container.addSubview(scrollView)
        w.contentView = container
        window = w
    }

    func update(completions: [Completion], caretBottom: NSPoint, caretTop: NSPoint) {
        self.completions = completions
        selectedIndex = 0
        let height = min(CGFloat(completions.count), popupMaxRows) * popupRowH
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let spaceBelow = caretBottom.y - screen.minY
        let spaceAbove = screen.maxY - caretTop.y
        let originY = (spaceBelow >= height + 6 || spaceBelow >= spaceAbove)
            ? caretBottom.y - height - 4
            : caretTop.y + 4
        let frame = NSRect(x: caretBottom.x, y: originY, width: popupWidth, height: height)
        window?.setFrame(frame, display: false)
        let bounds = NSRect(origin: .zero, size: frame.size)
        window?.contentView?.frame = bounds
        scrollView.frame = bounds
        tableView.frame = NSRect(x:0, y:0, width:popupWidth, height:height)
        tableView.reloadData()
        if !completions.isEmpty {
            tableView.selectRowIndexes(.init(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        window?.orderFront(nil)
    }

    func moveDown() { select(min(selectedIndex + 1, completions.count - 1)) }
    func moveUp()   { select(max(selectedIndex - 1, 0)) }

    private func select(_ idx: Int) {
        let old = selectedIndex; selectedIndex = idx
        tableView.reloadData(forRowIndexes: [old, idx], columnIndexes: IndexSet(integer: 0))
        tableView.scrollRowToVisible(idx)
    }

    func selected() -> Completion? { completions.indices.contains(selectedIndex) ? completions[selectedIndex] : nil }

    @objc func didDoubleClick() { if let c = selected() { onSelect(c) } }
}

extension CompletionWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { completions.count }
    func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { CompletionRowView() }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let c = completions[row]; let sel = row == selectedIndex
        let cell = NSView(); cell.wantsLayer = true
        cell.layer?.backgroundColor = sel ? popupSelBG.cgColor : .none

        let pill = NSView(); pill.wantsLayer = true
        pill.layer?.cornerRadius = 2
        pill.layer?.backgroundColor = kindColor(c.kind).withAlphaComponent(0.85).cgColor
        pill.frame = NSRect(x:8, y:(Int(popupRowH)-12)/2, width:3, height:12)

        let label = NSTextField(labelWithString: c.label)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = sel ? popupSelLabel : popupLabel
        label.frame = NSRect(x:18, y:(Int(popupRowH)-13)/2, width:150, height:13)

        let badge = NSTextField(labelWithString: kindBadge(c.kind))
        badge.font = .systemFont(ofSize: 9, weight: .regular)
        badge.textColor = kindColor(c.kind).withAlphaComponent(sel ? 1 : 0.8)
        badge.frame = NSRect(x:172, y:(Int(popupRowH)-11)/2, width:46, height:11)

        let detail = NSTextField(labelWithString: c.detail)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = sel ? popupSelDetail : popupDetail
        detail.lineBreakMode = .byTruncatingTail
        detail.frame = NSRect(x:222, y:(Int(popupRowH)-11)/2, width:Int(popupWidth)-230, height:11)

        [pill, label, badge, detail].forEach { cell.addSubview($0) }
        return cell
    }

    func tableViewSelectionDidChange(_ n: Notification) {
        let idx = tableView.selectedRow; guard idx >= 0 else { return }; select(idx)
    }

    private func kindColor(_ k: Completion.Kind) -> NSColor {
        switch k {
        case .function: return NSColor(red:0.36,green:0.68,blue:1.00,alpha:1)
        case .keyword:  return NSColor(red:0.78,green:0.52,blue:1.00,alpha:1)
        case .variable: return NSColor(red:1.00,green:0.72,blue:0.35,alpha:1)
        case .type:     return NSColor(red:0.42,green:0.90,blue:0.58,alpha:1)
        case .constant: return NSColor(red:0.35,green:0.90,blue:0.85,alpha:1)
        }
    }
    private func kindBadge(_ k: Completion.Kind) -> String {
        switch k {
        case .function: return "fn"
        case .keyword:  return "kw"
        case .variable: return "var"
        case .type:     return "type"
        case .constant: return "const"
        }
    }
}

private final class CompletionRowView: NSTableRowView {
    override var isSelected: Bool { get { false } set {} }
    override func drawSelection(in _: NSRect) {}
    override func drawBackground(in _: NSRect) {}
}

private final class CompletionTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let row = self.row(at: pt)
        if row >= 0 {
            selectRowIndexes(.init(integer: row), byExtendingSelection: false)
            if let t = target as? CompletionWindowController { t.didDoubleClick() }
        }
    }
}
