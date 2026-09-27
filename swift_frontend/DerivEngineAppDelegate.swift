import AppKit

final class DerivEngineAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Deriv Engine is a single-window app. Prevent AppKit from trying to
        // register automatic document/window tabs during startup on macOS 26+.
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
