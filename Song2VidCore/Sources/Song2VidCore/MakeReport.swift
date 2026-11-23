import Foundation

/// The result of `make`: the video that was made, or with `--dry-run` the video that would be made (SPEC section 14.5).
struct MakeReport: Sendable {
    let inputs: CommandInputs
    let frame: OutputFrame
    let shape: FrameShape
    let codec: Codec
    /// The file name only, never the folder.
    let outputName: String
    /// The size of the finished file. Nil for a dry run, which writes nothing.
    var bytes: Int?
    let dryRun: Bool

    private var placement: PlacementKind { PlacementKind(shape: shape, frame: frame) }
    /// The video is as long as the song (SPEC section 6.3).
    private var duration: Double { inputs.audio.duration }

    var jsonValue: JSONValue {
        .line(type: "result", [
            (.command, .string("make")),
            (.output, .object([
                (.name, .string(outputName)),
                (.width, .int(frame.size.width)),
                (.height, .int(frame.size.height)),
                (.durationSeconds, .seconds(duration)),
                (.bytes, bytes.map { .int($0) } ?? .null),
            ])),
            (.placement, .string(placement.rawValue)),
            (.enlarged, .bool(frame.isEnlarged)),
            (.dryRun, .bool(dryRun)),
            (.codec, .string(codec.rawValue)),
            (.encoder, .string(AppleEncoder.name)),
            (.encoderFallback, .bool(false)),
        ])
    }

    var text: String {
        let description = "\(outputName) (\(codec.title), \(AppleEncoder.title))"
        var lines = [
            dryRun ? "Would make \(description). Nothing was written." : "Made \(description).",
            "  Size:       \(frame.size.width)×\(frame.size.height) pixels",
            "  Length:     \(CheckReport.clock(duration)) (\(CheckReport.seconds(duration)) seconds)",
            "  Placement:  \(placement.title(for: shape))" + (frame.isEnlarged ? ", image enlarged" : ""),
        ]
        if let bytes { lines.append("  File size:  \(bytes) bytes") }
        return lines.joined(separator: "\n") + "\n"
    }
}
