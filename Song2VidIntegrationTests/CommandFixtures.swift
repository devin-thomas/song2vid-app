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

    subscript(key: String) -> Any? { object[key] }
    func child(_ key: String) -> [String: Any]? { object[key] as? [String: Any] }
    var frames: [[String: Any]] { object["frames"] as? [[String: Any]] ?? [] }
}

struct CommandTestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
