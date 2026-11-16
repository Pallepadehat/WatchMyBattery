import AppKit
import SwiftUI

/// Shows the panel's shortcut; click it, then press the keys for a new one. Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    let model: AppModel
    @State private var isRecording = false
    @State private var monitor: Any?
    /// The last key press couldn't be a shortcut, because it had no ⌘, ⌥ or ⌃.
    @State private var needsModifier = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(title)
                    .monospacedDigit()
                    .frame(minWidth: 110)
                    .foregroundStyle(isRecording ? Color.accentColor : model.settings.panelShortcut == nil ? .secondary : .primary)
            }
            .help(isRecording ? "Press Escape to cancel, or Delete to remove the shortcut." : "Click, then press the keys you want.")
            if model.settings.panelShortcut != nil, !isRecording {
                Button {
                    model.setPanelShortcut(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove the shortcut")
                .accessibilityLabel("Remove the shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var title: String {
        if isRecording { return needsModifier ? String(localized: "Add ⌘, ⌥ or ⌃") : String(localized: "Type Shortcut…") }
        return model.settings.panelShortcut?.displayString ?? String(localized: "Record Shortcut")
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        needsModifier = false
        model.pausePanelShortcut()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let plain = event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        if plain && event.keyCode == 53 {  // Escape
            stopRecording()
        } else if plain && (event.keyCode == 51 || event.keyCode == 117) {  // Delete, Forward Delete
            model.setPanelShortcut(nil)
            stopRecording()
        } else if let hotkey = Hotkey(event: event) {
            model.setPanelShortcut(hotkey)
            stopRecording()
        } else {
            needsModifier = true
            NSSound.beep()
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { model.registerPanelShortcut() }
        isRecording = false
        needsModifier = false
    }
}
