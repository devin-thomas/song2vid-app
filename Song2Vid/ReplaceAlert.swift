import AppKit
import Song2VidCore

/// The Replace / Keep Current question (SPEC section 4a), shown as a sheet on the window.
/// Keep Current is the first button, so it is the default (Return), and Esc chooses it too.
@MainActor
enum ReplaceAlert {
    static func present(_ dialog: ReplaceDialog, answer: @escaping @MainActor (_ replace: Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = dialog.title
        alert.informativeText = dialog.detail
        alert.alertStyle = .informational
        let keep = alert.addButton(withTitle: dialog.keepButton)
        alert.addButton(withTitle: dialog.replaceButton)
        keep.keyEquivalent = "\r"

        // NSAlert maps Esc only to a button named Cancel, so Esc is routed to Keep Current here.
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, alert.window.isVisible else { return event }
            keep.performClick(nil)
            return nil
        }

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            if let monitor { NSEvent.removeMonitor(monitor) }
            answer(response == .alertSecondButtonReturn)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
