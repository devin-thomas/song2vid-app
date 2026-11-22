import Foundation

/// The command's own way to write to the real standard output and standard error while the system's streams
/// are silenced (see `withSystemOutputSilenced`). It holds private copies of the two file descriptors, so what is
/// written here reaches the terminal, pipe or file the person started the command with, and nothing a macOS
/// framework prints can come out through it.
///
/// S2V-013 draws live progress through this: the progress handler gets a channel with every event.
public struct CommandChannel: Sendable {
    /// A private copy of the real standard output, or -1 when it could not be copied.
    public let outputDescriptor: Int32
    /// A private copy of the real standard error, or -1 when it could not be copied.
    public let errorDescriptor: Int32
    /// True when the command was asked for `--json`, so progress is a JSON line on `outputDescriptor`
    /// rather than text on `errorDescriptor` (SPEC section 14.5).
    public let isJSON: Bool

    public init(outputDescriptor: Int32, errorDescriptor: Int32, isJSON: Bool) {
        self.outputDescriptor = outputDescriptor
        self.errorDescriptor = errorDescriptor
        self.isJSON = isJSON
    }

    public func writeOutput(_ text: String) { Self.write(text, to: outputDescriptor) }
    public func writeError(_ text: String) { Self.write(text, to: errorDescriptor) }

    /// Writes every byte, retrying when a signal interrupts it. A closed or full pipe is not an error here:
    /// progress that can't be shown is dropped, and the result still goes out when the command ends.
    private static func write(_ text: String, to descriptor: Int32) {
        guard descriptor >= 0 else { return }
        var bytes = Array(text.utf8)[...]
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                bytes = bytes.dropFirst(written)
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                return
            }
        }
    }
}

/// Runs `body` with standard output and standard error pointed at /dev/null, then puts them back. `body` gets
/// a `CommandChannel` for the command's own output.
///
/// macOS's audio, image and video code can write log lines to standard error, and those lines contain the full
/// path of the file. The command's output carries no folder path (SPEC section 14.5), so every call into those
/// frameworks runs inside this, and only the command writes to the real streams.
/// The streams are redirected for the whole process, so this is safe while the export works on other threads.
/// Call it from the command's own thread. Calls may nest: an inner call puts back what the outer one set.
func withSystemOutputSilenced<T>(json: Bool = false, _ body: (CommandChannel) -> T) -> T {
    let streams = [STDOUT_FILENO, STDERR_FILENO]
    fflush(stdout)
    fflush(stderr)
    let saved = streams.map { dup($0) }
    // The copies must not leak into any process the command might start.
    for copy in saved where copy >= 0 { _ = fcntl(copy, F_SETFD, FD_CLOEXEC) }
    let null = open("/dev/null", O_WRONLY)
    if null >= 0 {
        for stream in streams { dup2(null, stream) }
    }
    defer {
        for (stream, copy) in zip(streams, saved) where copy >= 0 {
            dup2(copy, stream)
            close(copy)
        }
        if null >= 0 { close(null) }
    }
    return body(CommandChannel(outputDescriptor: saved[0], errorDescriptor: saved[1], isJSON: json))
}

/// The same, for a body that writes nothing itself.
func withSystemOutputSilenced<T>(_ body: () -> T) -> T {
    withSystemOutputSilenced { _ in body() }
}
