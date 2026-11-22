import Foundation

// The command's JSON (SPEC section 14.5): one object per line, every key from a fixed list.

/// Every key the command may write. An object can only be built from these, so a key that is not
/// listed here cannot reach the output. Keys change only with a new `api_version`.
enum JSONKey: String, CaseIterable, Sendable {
    case apiVersion = "api_version"
    case type
    case command
    case audio
    case image
    case name
    case durationSeconds = "duration_seconds"
    case sampleRate = "sample_rate"
    case channels
    case width
    case height
    case frames
    case shape
    case resolution
    case placement
    case enlarged
    case tooSmall = "too_small"
    case error
    case code
    case message
    case output
    case bytes
    case dryRun = "dry_run"
}

/// A JSON value. Objects keep their keys in the order given, so the output is the same every run.
indirect enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    /// A number with at most three decimals, always written with a decimal point (`144.0`).
    case seconds(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([(JSONKey, JSONValue)])

    /// The value as compact JSON text.
    var text: String {
        switch self {
        case .string(let value): Self.quoted(value)
        case .int(let value): String(value)
        case .seconds(let value): Self.decimal(value)
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        case .array(let values): "[" + values.map(\.text).joined(separator: ",") + "]"
        case .object(let pairs): "{" + pairs.map { Self.quoted($0.0.rawValue) + ":" + $0.1.text }.joined(separator: ",") + "}"
        }
    }

    /// One line of output: the value, then a newline.
    var line: String { text + "\n" }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func decimal(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") && !text.hasSuffix(".0") { text.removeLast() }
        return text
    }
}

extension JSONValue {
    /// The start of every line the command writes (SPEC section 14.5).
    static func line(type: String, _ fields: [(JSONKey, JSONValue)]) -> JSONValue {
        .object([(.apiVersion, .string("1")), (.type, .string(type))] + fields)
    }
}
