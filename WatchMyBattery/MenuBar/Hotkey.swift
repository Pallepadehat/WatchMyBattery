import AppKit
import Carbon.HIToolbox

/// A key combination that works from any app, like ⌥⌘B.
struct Hotkey: Equatable, Codable {
    /// The key's virtual key code (`kVK_…`), the same whatever the keyboard layout.
    var keyCode: UInt32
    /// ⌘ ⌥ ⌃ ⇧, as `NSEvent.ModifierFlags` raw values.
    var modifierFlags: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    /// A shortcut from a key press, if it makes a good global one: it needs ⌘, ⌥ or ⌃, so typing
    /// never triggers it, except for the function keys, which can stand alone.
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        let keyCode = UInt32(event.keyCode)
        guard !modifiers.isDisjoint(with: [.command, .option, .control]) || Self.functionKeys[keyCode] != nil else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// "⌥⌘B", in the order menus use.
    var displayString: String {
        var string = ""
        if modifiers.contains(.control) { string += "⌃" }
        if modifiers.contains(.option) { string += "⌥" }
        if modifiers.contains(.shift) { string += "⇧" }
        if modifiers.contains(.command) { string += "⌘" }
        return string + keyName
    }

    /// Modifiers in the form `RegisterEventHotKey` takes.
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    // MARK: - Naming the key

    private var keyName: String {
        if let name = Self.functionKeys[keyCode] ?? Self.specialKeys[keyCode] { return name }
        return Self.character(for: keyCode) ?? "#\(keyCode)"
    }

    private static let functionKeys: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12", UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    private static let specialKeys: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_ANSI_KeypadEnter): "⌤", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
    ]

    /// The character the key types on the current keyboard layout, so ⌘Z reads ⌘Y on a German keyboard, as it should.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { buffer in
            UCKeyTranslate(
                buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length,
                &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string.uppercased()
    }
}

/// Listens for one global hotkey, with Carbon's `RegisterEventHotKey`: it needs no
/// Accessibility permission, and only our combination ever reaches the app.
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// Runs on the main thread when the hotkey is pressed.
    var action: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Listens for `hotkey` instead of any before it; `nil` stops listening. Returns `false` when
    /// macOS won't have it, usually because another app already uses the combination.
    @discardableResult
    func register(_ hotkey: Hotkey?) -> Bool {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard let hotkey else { return true }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x574D_4254), id: 1)  // "WMBT"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyPressed, 1, &eventType, nil, &handlerRef)
    }
}

/// Carbon delivers hotkey events on the main thread.
nonisolated private func hotkeyPressed(_ handler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    MainActor.assumeIsolated { GlobalHotkey.shared.action() }
    return noErr
}
