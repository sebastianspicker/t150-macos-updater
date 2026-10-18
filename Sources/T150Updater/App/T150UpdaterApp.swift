import SwiftUI
import AppKit

@main
struct T150UpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = UpdateModel()

    var body: some Scene {
        Window("T150 Firmware Updater", id: "main") {
            ContentView(model: model)
                .onAppear { delegate.model = model; delegate.protectWindows() }
                .frame(minWidth: 860, minHeight: 680)
        }
        .defaultSize(width: 960, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Thrustmaster Installer…", action: model.chooseInstaller)
                    .keyboardShortcut("o").disabled(!model.canAct || model.stage == .updating)
            }
            CommandGroup(replacing: .help) {
                Button("T150 Updater Help") { model.helpVisible = true }
                Button("Official Thrustmaster Downloads", action: model.showOfficialWebsite)
                Button("Show Saved Sessions", action: model.showAllSessions)
            }
        }
    }
}

/// SwiftUI owns all state. AppKit is used only for native lifecycle guards.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: UpdateModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        protectWindows()
    }
    func protectWindows() { for window in NSApp.windows where window.canBecomeMain { window.delegate = self } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.busy == true else { return .terminateNow }
        NSSound.beep()
        return .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model?.busy == true { NSSound.beep(); return false }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
