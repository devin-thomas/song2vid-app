import Dispatch
import Foundation

/// Watches for Ctrl-C (SIGINT) and a stop request (SIGTERM) while a command runs (SPEC section 14.4 step 5).
///
/// The default action for both ends the process on the spot, which would leave a half-made video behind. Here the
/// default is ignored and the signal arrives as an ordinary event on a dispatch queue, so the command can cancel the
/// export, delete its temporary file and report "Cancelled." before it exits.
final class CancelSignals: @unchecked Sendable {
    private static let watched = [SIGINT, SIGTERM]

    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []
    private var requested = false
    private var action: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "song2vid.signals")

    /// Starts watching. Call `stop()` when the command no longer needs to be cancelled.
    init() {
        for number in Self.watched {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in self?.fire() }
            source.resume()
            sources.append(source)
        }
    }

    /// True once Ctrl-C or SIGTERM has arrived.
    var isRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    /// Sets what to do on cancel. If a signal has already arrived, it runs now.
    func onCancel(_ newAction: @escaping @Sendable () -> Void) {
        lock.lock()
        action = newAction
        let already = requested
        lock.unlock()
        if already { newAction() }
    }

    /// Forgets the action, so a late signal does nothing to a finished export.
    func clearAction() {
        lock.lock()
        action = nil
        lock.unlock()
    }

    private func fire() {
        lock.lock()
        requested = true
        let pending = action
        lock.unlock()
        pending?()
    }

    /// Stops watching and gives the signals back their default action.
    func stop() {
        for source in sources { source.cancel() }
        sources.removeAll()
        for number in Self.watched { signal(number, SIG_DFL) }
    }
}
