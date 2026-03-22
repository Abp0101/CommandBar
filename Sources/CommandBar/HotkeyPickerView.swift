import SwiftUI
import Carbon

// MARK: - Model

struct KeyCombo: Codable, Equatable {
    var keyCode:   UInt32
    var modifiers: UInt32   // Carbon modifier flags

    static let `default` = KeyCombo(keyCode: 0x00, modifiers: UInt32(cmdKey | optionKey))

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyCodeToString(keyCode)
        return s
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            0x00:"A", 0x0B:"B", 0x08:"C", 0x02:"D", 0x0E:"E",
            0x03:"F", 0x05:"G", 0x04:"H", 0x22:"I", 0x26:"J",
            0x28:"K", 0x25:"L", 0x2E:"M", 0x2D:"N", 0x1F:"O",
            0x23:"P", 0x0C:"Q", 0x0F:"R", 0x01:"S", 0x11:"T",
            0x20:"U", 0x09:"V", 0x0D:"W", 0x07:"X", 0x10:"Y",
            0x06:"Z",
            0x31:"Space", 0x24:"Return", 0x35:"Escape",
            0x7A:"F1",  0x78:"F2",  0x63:"F3",  0x76:"F4",
            0x60:"F5",  0x61:"F6",  0x62:"F7",  0x64:"F8",
            0x65:"F9",  0x6D:"F10", 0x67:"F11", 0x6F:"F12",
        ]
        return map[code] ?? "(\(code))"
    }
}

// MARK: - SwiftUI Picker

/// Renders a badge that starts recording when clicked; confirms on the next key combo.
struct HotkeyPickerView: View {

    @Binding var keyCombo: KeyCombo
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            RecorderButton(keyCombo: $keyCombo, isRecording: $isRecording)

            if isRecording {
                Text("Press any shortcut…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }
}

// MARK: - NSView wrapper that captures key events

private struct RecorderButton: NSViewRepresentable {

    @Binding var keyCombo: KeyCombo
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderNSButton {
        let btn = RecorderNSButton()
        btn.coordinator = context.coordinator
        return btn
    }

    func updateNSView(_ btn: RecorderNSButton, context: Context) {
        btn.title       = isRecording ? "…" : keyCombo.displayString
        btn.isRecording = isRecording
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator {
        var parent: RecorderButton
        init(_ parent: RecorderButton) { self.parent = parent }

        func recordingStarted()                  { parent.isRecording = true  }
        func recordingCancelled()                { parent.isRecording = false }
        func recorded(keyCode: UInt32, mods: UInt32) {
            parent.keyCombo   = KeyCombo(keyCode: keyCode, modifiers: mods)
            parent.isRecording = false
            // Persist and re-register
            if let data = try? JSONEncoder().encode(parent.keyCombo) {
                UserDefaults.standard.set(data, forKey: "hotkeyCombo")
            }
            NotificationCenter.default.post(name: .hotkeyComboChanged, object: parent.keyCombo)
        }
    }
}

final class RecorderNSButton: NSButton {

    fileprivate var coordinator: RecorderButton.Coordinator?
    var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        coordinator?.recordingStarted()
        isRecording = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        if event.keyCode == 53 { // Escape — cancel
            coordinator?.recordingCancelled()
            isRecording = false
            needsDisplay = true
            return
        }

        let carbonMods = cocoaToCarbonModifiers(event.modifierFlags)
        // Require at least one modifier
        guard carbonMods != 0 else { return }

        coordinator?.recorded(keyCode: UInt32(event.keyCode), mods: carbonMods)
        isRecording = false
        needsDisplay = true
    }

    private func cocoaToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey)     }
        if flags.contains(.option)  { mods |= UInt32(optionKey)  }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey)   }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }
}

// MARK: - Notification

extension Notification.Name {
    static let hotkeyComboChanged = Notification.Name("CommandBarHotkeyComboChanged")
}
