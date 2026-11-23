import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PreviewCommand {
    static func run(_ line: ParsedCommandLine) -> CommandOutput {
        let json = line.has(.json)
        guard line.operands.count == 1, let path = line.value(of: .out), !path.isEmpty else {
            return usage("preview needs one image file and an output file (-o).", json: json)
        }
        let output = URL(fileURLWithPath: path)
        let name = output.lastPathComponent
        guard name.count > 4, name.lowercased().hasSuffix(".png") else {
            return usage("The preview output file name must end in .png.", json: json)
        }

        let signals = CancelSignals(watchStdin: line.has(.cancelOnEOF))
        defer { signals.stop() }
        return withSystemOutputSilenced {
            do throws(CommandError) {
                return try write(
                    image: URL(fileURLWithPath: line.operands[0]), to: output,
                    overwrite: line.has(.overwrite), json: json, signals: signals
                )
            } catch {
                return .failure(signals.isRequested ? CommandError.cancelled : error, json: json)
            }
        }
    }

    private static func usage(_ message: String, json: Bool) -> CommandOutput {
        let problem = UsageProblem(message: message, suggestion: nil, scope: .preview, jsonRequested: json)
        return .failure(CommandError(problem), json: json)
    }

    private static func write(
        image url: URL, to outputURL: URL, overwrite: Bool, json: Bool, signals: CancelSignals
    ) throws(CommandError) -> CommandOutput {
        if signals.isRequested { throw .cancelled }
        guard FileManager.default.fileExists(atPath: url.path) else { throw .imageNotFound }
        let decoded: (image: CGImage, size: PixelSize)
        do throws(ExportError) { decoded = try decodeImage(at: url, maxLongSide: 2048) }
        catch { throw CommandError(exportFailure: error) }

        if signals.isRequested { throw .cancelled }
        let output = try CommandDestination.plan(url: outputURL, inputs: [url], overwrite: overwrite)
        let data = try png(of: decoded.image)
        if signals.isRequested { throw .cancelled }

        let temporary = output.temporaryURL()
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain, failure.code == NSFileWriteOutOfSpaceError {
                throw CommandError(exportFailure: .diskFull)
            }
            throw .outputFolderNotWritable
        }
        if signals.isRequested { throw .cancelled }
        try output.place(temporary, overwrite: overwrite)

        let width = decoded.image.width, height = decoded.image.height
        let result = JSONValue.line(type: "result", [
            (.command, .string("preview")),
            (.output, .object([(.name, .string(output.name)), (.width, .int(width)), (.height, .int(height))])),
            (.source, .object([(.width, .int(decoded.size.width)), (.height, .int(decoded.size.height))])),
        ])
        return CommandOutput(stdout: json ? result.line : "Saved \(output.name) (\(width)x\(height)).\n", status: 0)
    }

    /// Compositing over black matches StillFrame, including for pictures with partial alpha.
    private static func png(of image: CGImage) throws(CommandError) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let failure = CommandError(code: .exportFailed, message: "Couldn't make the preview.")
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw failure }
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)

        let data = NSMutableData()
        guard let flattened = context.makeImage(),
              let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw failure }
        CGImageDestinationAddImage(writer, flattened, nil)
        guard CGImageDestinationFinalize(writer) else { throw failure }
        return data as Data
    }
}
