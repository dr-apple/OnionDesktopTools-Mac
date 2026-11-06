import AppKit
import SwiftUI

// Onion Desktop Tools for Mac
//   OnionDesktopTools                        the app
//   APP_STORE=<dir> OnionDesktopTools        keep downloads and backups in another folder (tests, snapshots)
//   APP_FAKE_CARD=<dir> OnionDesktopTools    add a folder as a pretend SD card (tests, snapshots)
//   APP_SNAPSHOT=<dir> OnionDesktopTools     save a PNG of every page in light and dark mode, then quit
//   OnionDesktopTools --selftest             run the self-test on /tmp folders and quit with 0 or 1 (tools/selftest.sh)
//   APP_GRID=1 OnionDesktopTools             draw the grid and layout probes over the window

@main
struct OnionDesktopToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Onion Desktop Tools", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1080, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {}
            CommandMenu("SD-Karte") {
                Button("Karten neu suchen") { Task { await model.refreshCards() } }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
                Button("Auswerfen") { model.eject() }
                    .keyboardShortcut("e")
                    .disabled(model.isBusy || !model.cardIsReal || model.root == nil)
                Divider()
                Button("macOS-Hilfsdateien entfernen") { model.cleanMacFiles() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.isBusy || model.root == nil)
                Button("Auf Fehler prüfen") { model.checkDisk(repair: false) }
                    .disabled(model.isBusy || !model.cardIsReal)
                Button("In FAT32 formatieren…") { model.confirmFormat() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(model.isBusy || !model.cardIsReal)
                Divider()
                Button("Im Finder öffnen") { if let root = model.root { NSWorkspace.shared.open(root) } }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(model.root == nil)
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, page in
                    if index < 9 {
                        Button(page.title) { model.sidebar = page }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
