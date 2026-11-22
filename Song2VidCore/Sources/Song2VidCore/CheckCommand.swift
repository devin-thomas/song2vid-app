import Foundation

/// `song2vid check <audio> <image> [-j]` (SPEC section 14.3): reads both files and reports what would be made.
/// It writes nothing, and it uses the same readers and frame rules as the app.
enum CheckCommand {
    static func run(operands: [String], json: Bool) -> CommandOutput {
        guard operands.count == 2 else {
            let problem = UsageProblem(
                message: "check needs one audio file and one image file.", suggestion: nil, scope: .check, jsonRequested: json
            )
            return .failure(CommandError(problem), json: json)
        }
        do {
            let report = CheckReport(try CommandInputs.read(audioPath: operands[0], imagePath: operands[1]))
            return CommandOutput(stdout: json ? report.jsonValue.line : report.text, status: 0)
        } catch {
            return .failure(error, json: json)
        }
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

    let inputs: CommandInputs
    let rows: [Row]

    /// Every Frame Shape at every Resolution, then Original once, using `OutputFrame` for every size.
    init(_ inputs: CommandInputs) {
        self.inputs = inputs
        var rows: [Row] = []
        for shape in FrameShape.allCases where shape != .original {
            for resolution in Resolution.allCases {
                let frame = try? OutputFrame(imageSize: inputs.image.size, frameShape: shape, resolution: resolution)
                rows.append(Row(shape: shape, resolution: resolution, frame: frame))
            }
        }
        // Resolution does not change Original, so any one stands in for it.
        let original = try? OutputFrame(imageSize: inputs.image.size, frameShape: .original, resolution: .p1080)
        rows.append(Row(shape: .original, resolution: nil, frame: original))
        self.rows = rows
    }

    // MARK: JSON

    /// The single `result` line (SPEC section 14.5).
    var jsonValue: JSONValue {
        .line(type: "result", [
            (.command, .string("check")),
            (.audio, .object([
                (.name, .string(inputs.audioName)),
                (.durationSeconds, .seconds(inputs.audio.duration)),
                (.sampleRate, .int(Int(inputs.audio.sampleRate.rounded()))),
                (.channels, .int(inputs.audio.channelCount)),
            ])),
            (.image, .object([
                (.name, .string(inputs.imageName)),
                (.width, .int(inputs.image.size.width)),
                (.height, .int(inputs.image.size.height)),
            ])),
            (.frames, .array(rows.map(\.jsonValue))),
        ])
    }

    // MARK: Text

    var text: String {
        let audio = inputs.audio
        let image = inputs.image
        var lines = [
            "Audio",
            "  File:         \(inputs.audioName)",
            "  Length:       \(Self.clock(audio.duration)) (\(Self.seconds(audio.duration)) seconds)",
            "  Sample rate:  \(Int(audio.sampleRate.rounded())) Hz",
            "  Channels:     \(Self.channels(audio.channelCount))",
            "",
            "Image",
            "  File:         \(inputs.imageName)",
            "  Size:         \(image.size.width)×\(image.size.height) pixels",
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

    private static func seconds(_ value: Double) -> String {
        JSONValue.seconds(value).text
    }

    /// `2:24`, or `1:02:03` for an hour or more.
    private static func clock(_ duration: Double) -> String {
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
