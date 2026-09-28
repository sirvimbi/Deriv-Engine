#if os(macOS)
import AppKit

final class DerivEngineAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Perform any macOS-specific setup here if needed.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources specific to macOS if needed.
    }
}
#endif
