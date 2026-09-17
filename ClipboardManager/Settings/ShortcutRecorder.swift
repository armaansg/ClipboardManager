import AppKit
import SwiftUI

/// Click, then press the combination you want. Esc cancels. Uses a local event monitor, which only sees
/// events for this app's own windows and therefore needs no Accessibility permission.
struct ShortcutRecorder: View {
    @Binding var hotKey: HotKeyDefinition
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: isRecording ? "record.circle" : "keyboard")
                        .foregroundStyle(isRecording ? Color.red : Color.secondary)
                    Text(isRecording ? "Press shortcut…" : hotKey.displayString)
                        .font(isRecording ? .body : .system(.body, design: .rounded).weight(.semibold))
                        .frame(minWidth: 110)
                }
            }
            .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to record a new shortcut")

            Button("Reset") {
                stop()
                hotKey = AppConfig.toggleHotKey
            }
            .disabled(hotKey == AppConfig.toggleHotKey)
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            if let candidate = HotKeyDefinition(event: event), candidate.isUsableAsGlobalShortcut {
                hotKey = candidate
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
