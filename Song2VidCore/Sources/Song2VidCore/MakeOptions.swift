import Foundation

/// What a `make` command line asks for, after the rules in SPEC section 14.2 are applied to the parsed options.
/// Anything that breaks a rule is a usage problem (exit status 2), found before any file is looked at.
struct MakeOptions: Sendable {
    let audioPath: String
    let imagePath: String
    let shape: FrameShape
    let resolution: Resolution
    let crop: CropPosition
    /// The `--out` value, or nil for the default name.
    let output: String?
    let overwrite: Bool
    let dryRun: Bool
    let quiet: Bool
    let json: Bool

    static func resolve(_ line: ParsedCommandLine) -> Result<MakeOptions, UsageProblem> {
        let json = line.has(.json)
        func problem(_ message: String) -> Result<MakeOptions, UsageProblem> {
            .failure(UsageProblem(message: message, suggestion: nil, scope: .make, jsonRequested: json))
        }

        guard line.operands.count == 2 else { return problem("make needs one audio file and one image file.") }

        var shape = FrameShape.sixteenByNine
        if let name = line.value(of: .shape) {
            guard let named = FrameShape(commandName: name) else {
                return problem("Shape must be 16:9, 9:16, 1:1, 4:3 or original.")
            }
            shape = named
        }
        var resolution = Resolution.p1080
        if let name = line.value(of: .resolution) {
            guard let named = Resolution(commandName: name) else { return problem("Resolution must be 480p, 1080p or 2160p.") }
            resolution = named
        }
        var crop = CropPosition.center
        if let text = line.value(of: .crop) {
            guard let parsed = parseCrop(text) else { return problem("Crop must be two numbers from 0 to 1, like 0.5,0.5.") }
            crop = parsed
        }
        // Rules that join two options. Resolution makes no difference to Original, and a crop position means nothing
        // where the whole image is shown, so both are refused rather than quietly ignored.
        if line.has(.resolution) && shape == .original { return problem("Resolution does not apply to the original shape.") }
        if line.has(.crop) && shape != .oneByOne && shape != .fourByThree {
            return problem("Crop applies only to the 1:1 and 4:3 shapes.")
        }

        return .success(MakeOptions(
            audioPath: line.operands[0], imagePath: line.operands[1], shape: shape, resolution: resolution, crop: crop,
            output: line.value(of: .out), overwrite: line.has(.overwrite), dryRun: line.has(.dryRun),
            quiet: line.has(.quiet), json: json
        ))
    }

    /// `h,v`: two plain decimal numbers, each from 0 to 1. Nothing else is accepted (no signs, spaces, exponents,
    /// `nan` or `inf`), and a value outside 0 to 1 is refused, never clamped.
    private static func parseCrop(_ text: String) -> CropPosition? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        var values: [Double] = []
        for part in parts {
            guard part.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let value = Double(part), (0...1).contains(value)
            else { return nil }
            values.append(value)
        }
        return CropPosition(horizontal: values[0], vertical: values[1])
    }
}
