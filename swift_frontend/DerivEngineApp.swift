import SwiftUI

@main
struct DerivEngineApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(DerivEngineAppDelegate.self) private var appDelegate
#endif

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

