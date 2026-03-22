import AppKit
import ApplicationServices

/// Captures ambient context at bar-open time:
///   • Which app is frontmost
///   • What text the user currently has selected (via Accessibility API)
///
/// The bar can prepend this context to AI queries automatically when relevant.
@MainActor
final class ContextCapture {

    static let shared = ContextCapture()

    // MARK: - Public properties (set when bar opens)

    private(set) var frontmostApp: FrontmostApp? = nil
    private(set) var selectedText: String? = nil

    // MARK: - Snapshot

    /// Call this just before showing the bar so context is fresh.
    func snapshot() {
        captureFrontmostApp()
        captureSelectedText()
    }

    func clear() {
        frontmostApp = nil
        selectedText = nil
    }

    // MARK: - Frontmost App

    private func captureFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            frontmostApp = nil
            return
        }
        frontmostApp = FrontmostApp(
            name:      app.localizedName ?? "Unknown",
            bundleID:  app.bundleIdentifier ?? "",
            processID: app.processIdentifier
        )
    }

    // MARK: - Selected Text via Accessibility

    private func captureSelectedText() {
        selectedText = nil

        guard AXIsProcessTrusted() else { return }

        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return }

        var selection: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXSelectedTextAttribute as CFString,
                                            &selection) == .success,
              let text = selection as? String,
              !text.isEmpty else { return }

        // Cap at 2 000 chars to avoid bloating the prompt
        selectedText = text.count > 2000
            ? String(text.prefix(2000)) + "\n…[truncated]"
            : text
    }
}

// MARK: - Model

struct FrontmostApp: Equatable {
    let name: String
    let bundleID: String
    let processID: pid_t

    /// A brief description to inject into the AI system prompt.
    var contextString: String { "The user's active app is \(name) (\(bundleID))." }
}
