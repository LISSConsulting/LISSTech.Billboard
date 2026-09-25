import Darwin
import AppKit
import SwiftUI
import BillboardShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct BillboardMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: BillboardViewModel

    init() {
        do {
            let consoleUser = try ConsoleSession.activeUser()
            guard consoleUser.uid == geteuid() else {
                throw BillboardError.transport(
                    "Billboard must run as the active console user; use lisstech-billboard-rmm from root.")
            }
            let request = try ConfigurationLoader.load()
            _model = StateObject(wrappedValue: BillboardViewModel(request: request))
        } catch {
            FileHandle.standardError.write(Data("Billboard: \(error.localizedDescription)\n".utf8))
            Darwin.exit(100)
        }
    }

    var body: some Scene {
        WindowGroup {
            BillboardContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
