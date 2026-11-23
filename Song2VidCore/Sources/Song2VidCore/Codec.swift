import CoreMedia
import VideoToolbox

/// The video Codec selected for an export. H.264 is the default for existing callers.
public enum Codec: String, CaseIterable, Sendable {
    case h264, hevc

    public var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }

    var videoToolboxType: CMVideoCodecType {
        switch self {
        case .h264: kCMVideoCodecType_H264
        case .hevc: kCMVideoCodecType_HEVC
        }
    }

    var profile: CFString {
        switch self {
        case .h264: kVTProfileLevel_H264_High_AutoLevel
        case .hevc: kVTProfileLevel_HEVC_Main_AutoLevel
        }
    }

    /// Checks that VideoToolbox can start this Codec, using the same settings as an export.
    public var isAvailable: Bool {
        EncodedStill.canEncode(self)
    }
}

enum AppleEncoder {
    static let name = "apple"
    static let title = "Apple encoder"

    /// Process test seam. It can suppress HEVC, but cannot claim to provide an encoder the Mac lacks.
    static func isAvailable(_ codec: Codec, environment: [String: String]) -> Bool {
        if codec == .hevc, environment["SONG2VID_TEST_DISABLE_HEVC"] == "1" { return false }
        return codec.isAvailable
    }
}
