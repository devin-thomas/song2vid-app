enum EncodersCommand {
    static func run(_ line: ParsedCommandLine, environment: [String: String]) -> CommandOutput {
        let json = line.has(.json)
        guard line.operands.isEmpty else {
            let problem = UsageProblem(message: "encoders takes no files.", suggestion: nil, scope: .encoders, jsonRequested: json)
            return .failure(CommandError(problem), json: json)
        }

        let availability = withSystemOutputSilenced {
            Codec.allCases.map { ($0, AppleEncoder.isAvailable($0, environment: environment)) }
        }
        if json {
            let codecs: [(JSONKey, JSONValue)] = availability.map { codec, available in
                (codec == .h264 ? .h264 : .hevc, .object([
                    (.available, .bool(available)),
                    (.encoder, available ? .string(AppleEncoder.name) : .null),
                ]))
            }
            let result = JSONValue.line(type: "result", [(.command, .string("encoders")), (.codecs, .object(codecs))])
            return CommandOutput(stdout: result.line, status: 0)
        }

        let text = availability.map { codec, available in
            "\(codec.title): \(available ? AppleEncoder.title : "not available on this computer")\n"
        }.joined()
        return CommandOutput(stdout: text, status: 0)
    }
}
