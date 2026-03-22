import SwiftUI

@main
struct CommandBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — we're a menu-bar-only app.
        // The Settings scene provides the Preferences window.
        Settings {
            SettingsView()
        }
    }
}
