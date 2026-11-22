import Foundation

/// Runs the built `song2vid` command as a separate process (SPEC section 18, seam 5).
/// The command under test is the copy inside the built app, `Song2Vid.app/Contents/Helpers/song2vid`,
/// which is the file a person or agent links onto their PATH.
enum CommandProcess {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private final class BundleToken {}

    /// The built command, found next to the test bundle in the build products folder.
    static var executableURL: URL {
        let products = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        return products.appendingPathComponent("Song2Vid.app/Contents/Helpers/song2vid")
    }

    /// Runs the command with the given arguments and returns what it wrote and how it ended.
    static func run(
        _ arguments: [String], environment: [String: String]? = nil, currentDirectory: URL? = nil
    ) throws -> Result {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Read both pipes to the end before waiting, so a full pipe can never block the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// A command that is running, so a test can watch the folder and send it a signal before it ends.
    final class Running {
        private let process = Process()
        private let out = Pipe()
        private let err = Pipe()

        init(_ arguments: [String], environment: [String: String]? = nil, currentDirectory: URL? = nil) throws {
            process.executableURL = CommandProcess.executableURL
            process.arguments = arguments
            if let environment { process.environment = environment }
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }

        var isRunning: Bool { process.isRunning }

        /// Sends Ctrl-C (SIGINT) or SIGTERM to the command.
        func send(_ signal: Int32) { kill(process.processIdentifier, signal) }

        /// Waits for the command to end and returns what it wrote. The tests' commands write only a few lines,
        /// so the pipes can't fill while the test is not reading.
        func finish() -> Result {
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(
                status: process.terminationStatus,
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self)
            )
        }
    }
}
