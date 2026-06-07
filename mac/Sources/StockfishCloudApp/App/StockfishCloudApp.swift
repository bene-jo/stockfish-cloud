import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct StockfishCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 840, minHeight: 560)
                .task {
                    await store.refreshServerStatus()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Server") {
                Button("Refresh Status") {
                    Task { await store.refreshServerStatus() }
                }
                .keyboardShortcut("r")

                Divider()

                Button(store.server.running ? "Delete Server" : "Start Server") {
                    Task {
                        if store.server.running {
                            await store.deleteServer()
                        } else {
                            await store.startServer()
                        }
                    }
                }
            }

            CommandMenu("Position") {
                Button("Start Analysis") {
                    store.startAnalysis()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.canStartAnalysis)

                Button("Stop Analysis") {
                    Task { await store.stopSelectedPosition() }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(store.selectedPosition?.status != .running)

                Button("Increase Target Depth") {
                    store.increaseSelectedTargetDepth()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(store.selectedPosition == nil)
            }
        }
    }
}
