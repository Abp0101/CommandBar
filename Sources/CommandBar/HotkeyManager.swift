import Carbon
import AppKit

/// Registers a process-level hot key using the Carbon Event Manager.
/// Falls back gracefully if the user hasn't granted Accessibility access yet.
final class HotkeyManager {

    // Carbon key codes
    private static let kVK_ANSI_A: UInt32 = 0x00

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    // MARK: - Public API

    func register() {
        // Load user-saved combo if present
        var keyCode   = Self.kVK_ANSI_A
        var modifiers = UInt32(cmdKey | optionKey)
        if let data  = UserDefaults.standard.data(forKey: "hotkeyCombo"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            keyCode   = combo.keyCode
            modifiers = combo.modifiers
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCC("CBAR")
        hotKeyID.id = 1

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            NSLog("CommandBar: Failed to register hotkey (error %d). Check Accessibility permissions.", status)
            return
        }

        installEventHandler()

        // Re-register when the user changes the combo in Preferences
        NotificationCenter.default.addObserver(
            forName: .hotkeyComboChanged,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.unregister()
            self?.register()
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    deinit { unregister() }

    // MARK: - Private

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let proc: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { manager.callback() }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            proc,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
    }

    private func fourCC(_ s: String) -> FourCharCode {
        s.utf8.prefix(4).reduce(0) { FourCharCode($0) << 8 | FourCharCode($1) }
    }
}
