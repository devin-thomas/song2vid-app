import Dispatch
import Foundation

/// Watches for SIGINT, SIGTERM and, when requested, EOF or a `cancel` line on stdin.
///
/// The default action for both ends the process on the spot, which would leave a half-made video behind. Here the
/// default is ignored and the signal arrives as an ordinary event on a dispatch queue, so the command can cancel the
/// export, delete its temporary file and report "Cancelled." before it exits.
final class CancelSignals: @unchecked Sendable {
    private static let watched = [SIGINT, SIGTERM]

    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []
    private var input: DispatchSourceRead?
    private var inputLine: [UInt8] = []
    private var discardingLine = false
    private var requested = false
    private var action: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "song2vid.signals")

    /// Starts watching. Call `stop()` when the command no longer needs to be cancelled.
    init(watchStdin: Bool) {
        for number in Self.watched {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in self?.fire() }
            source.resume()
            sources.append(source)
        }
        if watchStdin { startReadingStdin() }
    }

    /// True once a cancellation request has arrived.
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
        guard !requested else { lock.unlock(); return }
        requested = true
        let pending = action
        lock.unlock()
        pending?()
    }

    private func startReadingStdin() {
        let descriptor = fcntl(STDIN_FILENO, F_DUPFD_CLOEXEC, 3)
        guard descriptor >= 0 else { fire(); return }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readInput(descriptor) }
        source.setCancelHandler { close(descriptor) }
        input = source
        source.resume()
    }

    /// Read only when the descriptor is ready. Keep at most `cancel` plus a possible CR across reads.
    private func readInput(_ descriptor: Int32) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        if count < 0, errno == EINTR || errno == EAGAIN { return }
        if count <= 0 {
            input?.cancel()
            fire()
            return
        }
        let command = Array("cancel".utf8)
        for byte in bytes.prefix(count) {
            if byte == 10 {
                if !discardingLine, inputLine == command || inputLine == command + [13] {
                    input?.cancel()
                    fire()
                    return
                }
                inputLine.removeAll(keepingCapacity: true)
                discardingLine = false
            } else if inputLine.count < command.count + 1 {
                inputLine.append(byte)
            } else {
                discardingLine = true
            }
        }
    }

    /// Stops watching and gives the signals back their default action.
    func stop() {
        input?.cancel()
        for source in sources { source.cancel() }
        sources.removeAll()
        for number in Self.watched { signal(number, SIG_DFL) }
    }
}
