import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var commandBarController: CommandBarWindowController?
    private var hotkeyManager: HotkeyManager?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — this is a menu-bar accessory app
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()

        commandBarController = CommandBarWindowController()

        hotkeyManager = HotkeyManager { [weak self] in
            self?.commandBarController?.toggle()
        }
        hotkeyManager?.register()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never quit when windows close — we live in the menu bar
        return false
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "command.circle.fill",
                               accessibilityDescription: "CommandBar")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show CommandBar  ⌘⌥A",
                     action: #selector(showBar), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…",
                     action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CommandBar",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Wire actions to self
        for item in menu.items { item.target = self }
        statusItem?.menu = menu
    }

    @objc private func showBar() {
        commandBarController?.show()
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
