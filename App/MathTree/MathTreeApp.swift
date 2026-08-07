import AppKit
import SwiftUI

@main
struct MathTreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Knowledge Tree", id: "graph") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
    }
}

/// A SwiftPM executable is not launched as a bundled app during `swift run`, so
/// the activation policy has to be set explicitly or no window fronts.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--smoke-test") {
            runSmokeTest()
        }
    }

    /// Headless-friendly launch check: report the windows the app actually put
    /// on screen, then exit. Used by CI and by the Phase 0 exit criterion,
    /// where screen capture isn't available.
    private func runSmokeTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let windows = NSApplication.shared.windows.filter { $0.isVisible }
            for window in windows {
                let size = window.frame.size
                print("window: \"\(window.title)\" \(Int(size.width))x\(Int(size.height))")
            }
            print("visible windows: \(windows.count)")
            exit(windows.isEmpty ? 1 : 0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
