import Foundation

/// The Codec the window remembers (SPEC section 23, ADR-026). H.264 until the person chooses otherwise.
public enum CodecPreference {
    static let key = "videoCodec"

    /// The remembered Codec. An empty or unrecognised value reads as H.264.
    public static func read(from defaults: UserDefaults) -> Codec {
        defaults.string(forKey: key).flatMap(Codec.init(rawValue:)) ?? .h264
    }

    public static func write(_ codec: Codec, to defaults: UserDefaults) {
        defaults.set(codec.rawValue, forKey: key)
    }
}

/// Whether this Mac can make each Codec, asked of VideoToolbox once per launch.
/// The `SONG2VID_TEST_DISABLE_HEVC` test seam applies here as it does in the command: it can switch HEVC off, never on.
public enum CodecSupport {
    private static let hevc = AppleEncoder.isAvailable(.hevc, environment: ProcessInfo.processInfo.environment)

    public static func isAvailable(_ codec: Codec) -> Bool {
        codec == .h264 ? Codec.h264.isAvailable : hevc
    }
}
