import Foundation

/// Runs `body` with standard output and standard error pointed at /dev/null, then puts them back.
///
/// macOS's audio and image readers can write their own log lines to standard error when a file is not
/// what it claims to be, and those lines contain the full path of the file. The command's output carries
/// no folder path (SPEC section 14.5), so the readers run inside this, and only the command writes to the streams.
/// It is called from the command's single thread before anything else is running.
func withSystemOutputSilenced<T>(_ body: () -> T) -> T {
    let streams = [STDOUT_FILENO, STDERR_FILENO]
    fflush(stdout)
    fflush(stderr)
    let saved = streams.map { dup($0) }
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
    return body()
}
