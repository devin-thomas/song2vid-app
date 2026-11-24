// Generates the media for the Windows command's parity check (S2V-025). Host tools only: this runs on
// the Mac, and nothing it writes is committed or shipped. The pictures are four coloured quadrants
// as stored (red top left, green top right, blue bottom left, yellow bottom right), so a wrong turn or
// flip shows in the colours; the orientation tag is written by ImageIO, the same writer the Mac's own
// tests use.
//
// usage: media <folder>
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func drawQuadrants(width: Int, height: Int, transparent: Bool = false, halfTransparent: Bool = false) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha = transparent || halfTransparent ? CGImageAlphaInfo.premultipliedFirst : CGImageAlphaInfo.noneSkipFirst
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    if transparent { return context.makeImage()! }
    // CGContext's origin is the bottom left, so "top" is the larger y.
    let halfW = width / 2, halfH = height / 2
    func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect) {
        context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        context.fill(rect)
    }
    fill(1, 0, 0, CGRect(x: 0, y: halfH, width: halfW, height: height - halfH))
    fill(0, 1, 0, CGRect(x: halfW, y: halfH, width: width - halfW, height: height - halfH))
    fill(0, 0, 1, CGRect(x: 0, y: 0, width: halfW, height: halfH))
    fill(1, 1, 0, CGRect(x: halfW, y: 0, width: width - halfW, height: halfH))
    if halfTransparent {
        // The right half is made fully transparent: the quadrants there are cleared.
        context.clear(CGRect(x: halfW, y: 0, width: width - halfW, height: height))
    }
    return context.makeImage()!
}

func writeImage(_ name: String, _ type: UTType, _ width: Int, _ height: Int, orientation: Int = 1,
                transparent: Bool = false, halfTransparent: Bool = false) throws {
    let image = drawQuadrants(width: width, height: height, transparent: transparent, halfTransparent: halfTransparent)
    let url = folder.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw NSError(domain: "media", code: 1)
    }
    let properties: [CFString: Any] = orientation == 1 ? [:] : [kCGImagePropertyOrientation: orientation]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "media", code: 2) }
}

enum Kind { case wav, aiff, caf, aac, alac }

func writeTone(_ name: String, seconds: Double, sampleRate: Double, channels: Int, kind: Kind = .wav) throws {
    var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
    switch kind {
    case .wav, .caf:
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
    case .aiff:
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = true
    case .aac: settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
    case .alac: settings[AVFormatIDKey] = kAudioFormatAppleLossless
    }
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))!
    let frames = AVAudioFrameCount((seconds * sampleRate).rounded())
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<channels {
        let samples = buffer.floatChannelData![channel]
        for frame in 0..<Int(frames) { samples[frame] = Float(0.3 * sin(2 * Double.pi * 440 * Double(frame) / sampleRate)) }
    }
    let file = try AVAudioFile(forWriting: folder.appendingPathComponent(name), settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
}

// Pictures that the shapes and Original treat differently.
try writeImage("fit-1000x800.png", .png, 1000, 800)
try writeImage("wide-1920x1080.png", .png, 1920, 1080)
try writeImage("tall-1000x5000.png", .png, 1000, 5000)
try writeImage("big-4000x3000.png", .png, 4000, 3000)
try writeImage("trim-3860x2160.png", .png, 3860, 2160)
try writeImage("scale-4000x2000.png", .png, 4000, 2000)
try writeImage("odd-1001x801.png", .png, 1001, 801)
try writeImage("small-16x16.png", .png, 16, 16)
try writeImage("tiny-15x40.png", .png, 15, 40)
try writeImage("square-640x640.png", .png, 640, 640)
try writeImage("preview-3000x1500.png", .png, 3000, 1500)
try writeImage("preview-3001x2000.jpg", .jpeg, 3001, 2000)
// A name that looks like the other kind of file (the type comes from the contents).
try writeImage("picture-named-like-a-song.mp3", .png, 320, 200)

// Every orientation, as JPEG; the rest of the formats that carry one.
for orientation in 1...8 { try writeImage("or\(orientation).jpg", .jpeg, 600, 400, orientation: orientation) }
for orientation in [5, 6, 7, 8] { try writeImage("or\(orientation).tiff", .tiff, 600, 400, orientation: orientation) }
for orientation in [3, 6, 8] { try writeImage("or\(orientation).png", .png, 600, 400, orientation: orientation) }
for orientation in 1...8 { try writeImage("or\(orientation).heic", .heic, 800, 400, orientation: orientation) }
// Large enough for the HEIC writer to tile it.
for orientation in [1, 6, 8] { try writeImage("grid-or\(orientation).heic", .heic, 3000, 1500, orientation: orientation) }

try writeImage("transparent.png", .png, 60, 40, transparent: true)
try writeImage("half-transparent.png", .png, 100, 100, halfTransparent: true)
try writeImage("still.gif", .gif, 320, 240)
try writeImage("still.bmp", .bmp, 320, 240)
try writeImage("still.tiff", .tiff, 320, 240)

// Songs. 2.5 s at 22,050 Hz mono and 3 s at 44,100 Hz stereo are whole numbers of frames.
try writeTone("tone-22k-mono.wav", seconds: 2.5, sampleRate: 22_050, channels: 1)
try writeTone("tone-44k-stereo.wav", seconds: 3, sampleRate: 44_100, channels: 2)
try writeTone("tone-8k-stereo.wav", seconds: 125, sampleRate: 8_000, channels: 2)
try writeTone("tone-48k-stereo.aiff", seconds: 2, sampleRate: 48_000, channels: 2, kind: .aiff)
try writeTone("tone-44k-mono.caf", seconds: 2.37, sampleRate: 44_100, channels: 1, kind: .caf)
try writeTone("tone-aac.m4a", seconds: 2.37, sampleRate: 44_100, channels: 1, kind: .aac)
try writeTone("tone-alac.m4a", seconds: 2.37, sampleRate: 44_100, channels: 2, kind: .alac)
// A song named like a picture.
try FileManager.default.copyItem(
    at: folder.appendingPathComponent("tone-22k-mono.wav"), to: folder.appendingPathComponent("song-named-like-a-picture.png"))

// Files that are not media, and a folder.
try Data("this is plain text, not media".utf8).write(to: folder.appendingPathComponent("not-a-song.mp3"))
try Data("this is plain text, not media".utf8).write(to: folder.appendingPathComponent("not-a-picture.png"))
try Data("this is plain text, not media".utf8).write(to: folder.appendingPathComponent("notes.txt"))
try Data("this is plain text, not media".utf8).write(to: folder.appendingPathComponent("no-extension"))
try FileManager.default.createDirectory(at: folder.appendingPathComponent("a-folder"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: folder.appendingPathComponent("a-folder.wav"), withIntermediateDirectories: true)
print("media written")
