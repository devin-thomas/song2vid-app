import Foundation
import UniformTypeIdentifiers

/// A throwaway folder with generated media for the command tests, removed by `remove()`.
/// The folder's name carries a marker so a test can prove that no output ever contains a folder path.
struct CommandWorkspace {
    static let folderMarker = "planted-folder-marker"

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.folderMarker)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }

    func url(_ name: String) -> URL { folder.appendingPathComponent(name) }
    func path(_ name: String) -> String { url(name).path }

    /// A generated tone. Seconds, rate and channels are exact, so the tests know what `check` must report.
    @discardableResult
    func tone(_ name: String = "song.wav", seconds: Double = 3, sampleRate: Double = 44_100, channels: Int = 2) throws -> String {
        try TestMedia.writeTone(to: url(name), seconds: seconds, sampleRate: sampleRate, channels: channels)
        return path(name)
    }

    /// A generated image of the given pixel size, with an EXIF orientation tag.
    @discardableResult
    func picture(_ name: String = "cover.png", width: Int, height: Int, orientation: Int = 1) throws -> String {
        try TestMedia.writeImage(to: url(name), width: width, height: height, orientation: orientation)
        return path(name)
    }

    /// A silent 48 kHz stereo WAV of the given length that takes the command several seconds to encode, for tests that
    /// need a run still going when they act. Only the header is written: the rest of the file is a hole, which reads as
    /// zeros (silence) and takes no disk space.
    @discardableResult
    func longSong(_ name: String = "long.wav", seconds: Int = 3600) throws -> String {
        let rate = 48_000, channels = 2
        let dataBytes = seconds * rate * channels * 2
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        var header = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(channels)) + le(UInt32(rate))
        header += le(UInt32(rate * channels * 2)) + le(UInt16(channels * 2)) + le(UInt16(16))
        header += Array("data".utf8) + le(UInt32(dataBytes))
        try Data(header).write(to: url(name))
        let handle = try FileHandle(forWritingTo: url(name))
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(header.count + dataBytes))
        return path(name)
    }

    /// A file that is not media at all.
    @discardableResult
    func notMedia(_ name: String) throws -> String {
        try Data("this is plain text, not media".utf8).write(to: url(name))
        return path(name)
    }

    /// What is in the folder now, so a test can prove a command wrote nothing.
    func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}

/// One line of `--json` output, parsed.
struct JSONOutputLine {
    let object: [String: Any]

    init(_ output: String) throws {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == 2, lines[1].isEmpty, !lines[0].isEmpty else {
            throw CommandTestFailure("expected exactly one line ending in a newline, got \(lines.count) pieces")
        }
        guard let parsed = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any] else {
            throw CommandTestFailure("the line is not a JSON object")
        }
        object = parsed
    }

    /// The last line of a `make --json` run: every line before it must be a progress line (SPEC section 14.5), and the
    /// last must be the one `result` or `error`.
    static func final(_ output: String) throws -> JSONOutputLine {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2, lines.last?.isEmpty == true else { throw CommandTestFailure("output does not end in a newline") }
        for line in lines.dropLast(2) {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            guard object?["type"] as? String == "progress", object?["api_version"] as? String == "1" else {
                throw CommandTestFailure("a line before the last is not a progress line: \(line)")
            }
        }
        return try JSONOutputLine(String(lines[lines.count - 2]) + "\n")
    }

    /// What `make` wrote to stderr in plain headless mode before its final message: only progress lines.
    static func plainProgressLinesOnly(_ lines: [Substring]) -> Bool {
        let stages = ["Checking files", "Preparing", "Encoding", "Finishing"]
        return lines.allSatisfy { line in stages.contains { line.hasPrefix($0) } && !line.contains("\u{1B}") }
    }

    subscript(key: String) -> Any? { object[key] }
    func child(_ key: String) -> [String: Any]? { object[key] as? [String: Any] }
    var frames: [[String: Any]] { object["frames"] as? [[String: Any]] ?? [] }
}

struct CommandTestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
