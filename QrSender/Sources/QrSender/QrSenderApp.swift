import AppKit
import SwiftUI

@main
struct QrSenderApp: App {
    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("QrSender") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
