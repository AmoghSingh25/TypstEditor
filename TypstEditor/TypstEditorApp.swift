import SwiftUI
import AppKit

@main
struct TypstEditorApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppDelegate.applyAppIcon()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onAppear { appDelegate.appState = state }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New .typ File…") { state.newFile() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open File…") { state.openFilePanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open Project…") { state.openProject() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { state.saveActive() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { state.saveActiveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export PDF…") { state.exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(state.lastExportData == nil)
                Button("Export High-Res PNG (3×)…") { state.exportPNG() }
                    .disabled(state.pdfDocument == nil)
                Button("Export Vector SVG…") { state.exportSVG() }
                    .disabled(state.activeURL == nil || !state.activeIsTyp)
            }
            CommandMenu("View") {
                Button("Zoom In") { state.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { state.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size (100%)") { state.zoomSetPercentage(100) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Fit to Width") { state.zoomFitWidth() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Fit to Page") { state.zoomFitPage() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                Button("Previous Page") { state.jumpToPage(state.currentPage - 1) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(state.currentPage <= 1)
                Button("Next Page") { state.jumpToPage(state.currentPage + 1) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(state.currentPage >= state.totalPages)
            }
        }
    }
}

// Handles app lifecycle for save-on-quit and temp file cleanup
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    static func applyAppIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                         Bundle.main.url(forResource: "logo", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyAppIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.saveActive()
        appState?.cleanupTempDirectory()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
