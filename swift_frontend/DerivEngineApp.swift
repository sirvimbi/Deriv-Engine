import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct DerivEngineApp: App {
    init() {
        #if os(macOS)
        // This app does not use document-style window tabs. Disabling
        // automatic tabbing also avoids AppKit trying to index tabs before a
        // Swift Package executable has a full application bundle.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, idealWidth: 1200, maxWidth: 1600,
                       minHeight: 700, idealHeight: 800, maxHeight: 1000)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
    }
}
