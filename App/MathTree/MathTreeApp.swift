import AppKit
import SwiftUI

@main
struct MathTreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Runs before the run loop starts and exits the process when
        // `MATHTREE_SNAPSHOT` is set: rendering is offscreen, so a snapshot needs
        // no window and never reaches the window server.
        Snapshot.runIfRequested()
    }

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
        #if DEBUG
            // The corpus self-check (D4.9): `MATHTREE_MATH_CHECK=1` renders every
            // LaTeX-bearing field of the content *and* the problem bank, prints the
            // linearised statements to be read, and exits non-zero on a finding.
            // Needs the artifacts loaded, so it runs here.
            if let scene = SceneStore.shared.scene {
                MathText.Check.runIfRequested(
                    document: scene.document, problems: SceneStore.shared.problems)
            }
            // Runs here rather than in `MathTreeApp.init` because `NSHostingView`
            // needs a live run loop to complete a layout pass; a snapshot taken
            // before launch finishes captures an unlaid-out view.
            PanelShot.runIfRequested()
        #endif
        // Both of these are *trailing boolean* flags with no operand — D3.7:
        // AppKit turns leftover `-key value` tokens into `NSUserDefaults` and a
        // flag with a following token stopped SwiftUI from ever calling
        // `makeNSView`, hanging the process against a window that never existed.
        if Probe.isRequested {
            if let renderer = SceneStore.shared.renderer {
                Probe.install(on: renderer)
                Probe.installWatchdog()
            } else {
                FileHandle.standardError.write(
                    Data("probe: \(SceneStore.shared.errorMessage ?? "no renderer")\n".utf8))
                exit(3)
            }
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
