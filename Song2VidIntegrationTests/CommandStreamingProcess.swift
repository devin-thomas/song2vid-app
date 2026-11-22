import Darwin
import Foundation

/// A run of the built command that records when each piece of output arrives, for the progress tests (SPEC section 18).
/// Times are seconds since the process was started.
final class CommandStreamingProcess: @unchecked Sendable {
    struct Chunk {
        let time: Double
        let text: String
    }

    enum Stderr {
        /// An ordinary pipe: the command is headless.
        case pipe
        /// A pseudo-terminal: the command believes a person is watching.
        case terminal
    }

    private let process = Process()
    private let lock = NSLock()
    private var outChunks: [Chunk] = []
    private var errChunks: [Chunk] = []
    private let started: Date
    private let readers = DispatchGroup()
    private var finishedAt: Double?

    init(_ arguments: [String], stderr: Stderr = .pipe, environment: [String: String]? = nil) throws {
        process.executableURL = CommandProcess.executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        var errReader: Int32
        switch stderr {
        case .pipe:
            let err = Pipe()
            process.standardError = err
            errReader = err.fileHandleForReading.fileDescriptor
            errPipe = err
        case .terminal:
            var master: Int32 = 0
            var slave: Int32 = 0
            guard openpty(&master, &slave, nil, nil, nil) == 0 else { throw CommandTestFailure("openpty failed") }
            var size = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(slave, TIOCSWINSZ, &size)
            process.standardError = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
            errReader = master
            terminalSlave = slave
        }
        started = Date()
        try process.run()
        if let slave = terminalSlave { close(slave) }
        read(out.fileHandleForReading.fileDescriptor) { [self] chunk in lock.lock(); outChunks.append(chunk); lock.unlock() }
        read(errReader) { [self] chunk in lock.lock(); errChunks.append(chunk); lock.unlock() }
    }

    private var errPipe: Pipe?
    private var terminalSlave: Int32?

    private func read(_ descriptor: Int32, store: @escaping @Sendable (Chunk) -> Void) {
        let started = started
        readers.enter()
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count <= 0 { break }
                store(Chunk(time: Date().timeIntervalSince(started), text: String(decoding: buffer[0..<count], as: UTF8.self)))
            }
            self.readers.leave()
        }
    }

    var isRunning: Bool { process.isRunning }
    func elapsed() -> Double { Date().timeIntervalSince(started) }

    /// What has arrived so far on standard output, split into lines with the time each line completed.
    var outputSoFar: [Chunk] { lock.lock(); defer { lock.unlock() }; return outChunks }
    var errorSoFar: [Chunk] { lock.lock(); defer { lock.unlock() }; return errChunks }

    func send(_ signal: Int32) { kill(process.processIdentifier, signal) }

    /// Waits for the command to end and for all its output to arrive.
    func finish() -> (status: Int32, duration: Double) {
        process.waitUntilExit()
        let duration = elapsed()
        // The terminal's reading end gives no end-of-file once the child has gone on every system, so wait briefly.
        _ = readers.wait(timeout: .now() + 2)
        return (process.terminationStatus, duration)
    }

    /// Complete lines from some chunks, each stamped with the time its last byte arrived.
    static func lines(_ chunks: [Chunk]) -> [Chunk] {
        var result: [Chunk] = []
        var pending = ""
        for chunk in chunks {
            pending += chunk.text
            while let newline = pending.firstIndex(of: "\n") {
                result.append(Chunk(time: chunk.time, text: String(pending[..<newline])))
                pending = String(pending[pending.index(after: newline)...])
            }
        }
        return result
    }
}
