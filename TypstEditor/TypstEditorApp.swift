import SwiftUI
import AppKit

@main
struct TypstEditorApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            }
        }
    }
}

// Handles app lifecycle for save-on-quit and temp file cleanup
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.saveActive()
        appState?.cleanupTempDirectory()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
