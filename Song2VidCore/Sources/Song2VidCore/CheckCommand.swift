import Foundation
import UniformTypeIdentifiers

/// `song2vid check <audio> <image> [-j]` (SPEC section 14.3) and `song2vid check <file> [-j]` (section 24.8):
/// reads the files and reports what would be made. It writes nothing, and it uses the same readers and frame rules as the app.
enum CheckCommand {
    static func run(operands: [String], json: Bool) -> CommandOutput {
        do {
            switch operands.count {
            case 1: return output(CheckReport(try readOne(operands[0])), json: json)
            case 2: return output(CheckReport(try CommandInputs.read(audioPath: operands[0], imagePath: operands[1])), json: json)
            default:
                let problem = UsageProblem(
                    message: "check needs one audio file and one image file, or a single file.",
                    suggestion: nil, scope: .check, jsonRequested: json
                )
                return .failure(CommandError(problem), json: json)
            }
        } catch {
            return .failure(error, json: json)
        }
    }

    private static func output(_ report: CheckReport, json: Bool) -> CommandOutput {
        CommandOutput(stdout: json ? report.jsonValue.line : report.text, status: 0)
    }

    /// Reads a file alone (SPEC section 24.8). Its type comes from its contents, as `make` reads it: a file the audio
    /// reader accepts is a song, else one the image reader accepts is an image. A file that is neither, or is missing,
    /// is reported as the kind its extension says (a section 7 audio type means audio, anything else means image).
    private static func readOne(_ path: String) throws(CommandError) -> CheckReport.Files {
        let url = URL(fileURLWithPath: path)
        let extensionIsAudio = UTType(filenameExtension: url.pathExtension)
            .map { type in SupportedTypes.audio.contains { type.conforms(to: $0) } } ?? false
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw extensionIsAudio ? .audioNotFound : .imageNotFound
        }
        // The system readers may log the file's path to the terminal; none of that may reach the output.
        if let audio = withSystemOutputSilenced({ try? AudioInfo.read(from: url, isCancelled: { false }) }) {
            return CheckReport.Files(audio: .init(name: url.lastPathComponent, info: audio), image: nil)
        }
        if let image = withSystemOutputSilenced({ try? ImageInfo.read(from: url) }) {
            return CheckReport.Files(audio: nil, image: .init(name: url.lastPathComponent, info: image))
        }
        throw extensionIsAudio ? .audioUnreadable : .imageUnreadable
    }
}

/// What `check` found: the two files and the output for every Frame Shape and Resolution.
struct CheckReport: Sendable {
    /// One output the image could be made into.
    struct Row: Sendable {
        let shape: FrameShape
        /// Nil for Original, which does not depend on Resolution.
        let resolution: Resolution?
        /// Nil when Original can't be made because the image is under 16 pixels on a side.
        let frame: OutputFrame?

        var placement: PlacementKind? { frame.map { PlacementKind(shape: shape, frame: $0) } }
    }

    /// The files that were read: both for a two-file check, one of them for a single file (SPEC section 24.8).
    struct Files: Sendable {
        struct Audio: Sendable { let name: String; let info: AudioInfo }
        struct Image: Sendable { let name: String; let info: ImageInfo }
        let audio: Audio?
        let image: Image?
    }

    let files: Files
    /// The output sizes. Empty when only a song was checked.
    let rows: [Row]

    init(_ inputs: CommandInputs) {
        self.init(Files(
            audio: .init(name: inputs.audioName, info: inputs.audio),
            image: .init(name: inputs.imageName, info: inputs.image)
        ))
    }

    /// Every Frame Shape at every Resolution, then Original once, using `OutputFrame` for every size.
    init(_ files: Files) {
        self.files = files
        guard let image = files.image else {
            rows = []
            return
        }
        var rows: [Row] = []
        for shape in FrameShape.allCases where shape != .original {
            for resolution in Resolution.allCases {
                let frame = try? OutputFrame(imageSize: image.info.size, frameShape: shape, resolution: resolution)
                rows.append(Row(shape: shape, resolution: resolution, frame: frame))
            }
        }
        // Resolution does not change Original, so any one stands in for it.
        let original = try? OutputFrame(imageSize: image.info.size, frameShape: .original, resolution: .p1080)
        rows.append(Row(shape: .original, resolution: nil, frame: original))
        self.rows = rows
    }

    // MARK: JSON

    /// The single `result` line (SPEC section 14.5). A single file leaves out the other file's keys (section 24.8).
    var jsonValue: JSONValue {
        var fields: [(JSONKey, JSONValue)] = [(.command, .string("check"))]
        if let audio = files.audio {
            fields.append((.audio, .object([
                (.name, .string(audio.name)),
                (.durationSeconds, .seconds(audio.info.duration)),
                (.sampleRate, .int(Int(audio.info.sampleRate.rounded()))),
                (.channels, .int(audio.info.channelCount)),
            ])))
        }
        if let image = files.image {
            fields.append((.image, .object([
                (.name, .string(image.name)),
                (.width, .int(image.info.size.width)),
                (.height, .int(image.info.size.height)),
            ])))
            fields.append((.frames, .array(rows.map(\.jsonValue))))
        }
        return .line(type: "result", fields)
    }

    // MARK: Text

    var text: String {
        var lines: [String] = []
        if let audio = files.audio {
            lines += [
                "Audio",
                "  File:         \(audio.name)",
                "  Length:       \(Self.clock(audio.info.duration)) (\(Self.seconds(audio.info.duration)) seconds)",
                "  Sample rate:  \(Int(audio.info.sampleRate.rounded())) Hz",
                "  Channels:     \(Self.channels(audio.info.channelCount))",
            ]
        }
        guard let image = files.image else { return lines.joined(separator: "\n") + "\n" }
        if !lines.isEmpty { lines.append("") }
        lines += [
            "Image",
            "  File:         \(image.name)",
            "  Size:         \(image.info.size.width)×\(image.info.size.height) pixels",
            "",
            "Output sizes",
        ]
        let table = rows.map { row in
            [
                row.shape.commandName,
                row.resolution?.commandName ?? "-",
                row.frame.map { "\($0.size.width)×\($0.size.height)" } ?? "too small",
                row.placement.map { $0.title(for: row.shape) } ?? "-",
                row.frame == nil ? "Original needs an image of at least 16×16 pixels."
                    : row.frame?.isEnlarged == true ? "will be enlarged" : "",
            ]
        }
        let widths = (0..<4).map { column in table.map { $0[column].count }.max() ?? 0 }
        for cells in table {
            var line = "  "
            for column in 0..<4 { line += cells[column].padding(toLength: widths[column] + 2, withPad: " ", startingAt: 0) }
            line += cells[4]
            lines.append(line.replacingOccurrences(of: " +$", with: "", options: .regularExpression))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func seconds(_ value: Double) -> String {
        JSONValue.seconds(value).text
    }

    /// `2:24`, or `1:02:03` for an hour or more.
    static func clock(_ duration: Double) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600, minutes = total % 3600 / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private static func channels(_ count: Int) -> String {
        switch count {
        case 1: "1 (mono)"
        case 2: "2 (stereo)"
        default: String(count)
        }
    }
}

extension CheckReport.Row {
    var jsonValue: JSONValue {
        .object([
            (.shape, .string(shape.commandName)),
            (.resolution, resolution.map { .string($0.commandName) } ?? .null),
            (.width, frame.map { .int($0.size.width) } ?? .null),
            (.height, frame.map { .int($0.size.height) } ?? .null),
            (.placement, placement.map { .string($0.rawValue) } ?? .null),
            (.enlarged, frame.map { .bool($0.isEnlarged) } ?? .null),
            (.tooSmall, .bool(frame == nil)),
        ])
    }
}
