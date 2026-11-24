//! Which Encoder makes the video (SPEC sections 23 and 26.3, ADR-025).
//!
//! The Encoder is chosen by the command, never by the person. On Windows the order is NVIDIA's
//! NVENC, then a hardware encoder through Media Foundation (AMD or Intel), then Microsoft's
//! software H.264 encoder. HEVC has no software step.
//!
//! S2V-026 builds the software step. The hardware Encoders have their place in the order and in
//! `Encoder::video_arguments`, which says `None` for them until S2V-027 writes the FFmpeg
//! arguments, the test encode that finds out whether the computer has them, and the fallback.

use std::ffi::OsString;

use crate::context::Environment;
use crate::error::CommandError;
use crate::make_options::Codec;

/// How many frames make one group of pictures: a key frame about every ten seconds at 30 frames
/// a second (the Mac's `EncodedStill.groupLength`).
pub const GROUP_LENGTH: i64 = 300;

/// The Encoders, in the order they are tried.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Encoder {
    Nvenc,
    MediaFoundation,
    Software,
}

impl Encoder {
    pub const ORDER: [Encoder; 3] = [Encoder::Nvenc, Encoder::MediaFoundation, Encoder::Software];

    /// The value in JSON (SPEC section 24.2).
    pub fn json_name(self) -> &'static str {
        match self {
            Encoder::Nvenc => "nvenc",
            Encoder::MediaFoundation => "media_foundation",
            Encoder::Software => "software",
        }
    }

    /// The name in the text output.
    pub fn title(self) -> &'static str {
        match self {
            Encoder::Nvenc => "NVIDIA encoder",
            Encoder::MediaFoundation => "graphics hardware encoder",
            Encoder::Software => "software encoder",
        }
    }

    /// The word the test seam uses (`SONG2VID_TEST_ENCODER`).
    fn from_seam(word: &str) -> Option<Encoder> {
        Encoder::ORDER
            .into_iter()
            .find(|encoder: &Encoder| -> bool { encoder.json_name() == word })
    }

    /// FFmpeg's arguments for the video stream of the encoded group, or None when this Encoder
    /// can't make the Codec (or, until S2V-027, is not built). The software Encoder is Microsoft's
    /// H.264 encoder through FFmpeg's `h264_mf`: High profile, no B-frames (every frame after the
    /// first only refers back), one key frame per group.
    pub fn video_arguments(self, codec: Codec) -> Option<Vec<OsString>> {
        match (self, codec) {
            (Encoder::Software, Codec::H264) => Some(
                [
                    "-c:v",
                    "h264_mf",
                    // The numeric value of AV_PROFILE_H264_HIGH: h264_mf names no profiles.
                    "-profile:v",
                    "100",
                    "-g",
                    &GROUP_LENGTH.to_string(),
                    "-bf",
                    "0",
                    "-rate_control",
                    "quality",
                    "-quality",
                    SOFTWARE_QUALITY,
                ]
                .iter()
                .map(|word: &&str| -> OsString { OsString::from(*word) })
                .collect(),
            ),
            _ => None,
        }
    }

    /// True when this Encoder can make the Codec on this computer. S2V-027 replaces this answer
    /// for the hardware Encoders with a tiny test encode.
    pub fn can_make(self, codec: Codec) -> bool {
        self.video_arguments(codec).is_some()
    }
}

/// The software Encoder's quality, 0 to 100. The picture is still, so the setting is spent on
/// making that one picture sharp (the Mac asks VideoToolbox for 0.75).
const SOFTWARE_QUALITY: &str = "75";

/// The Encoder for a Codec: the one the test seam forces, or the first in the order that can make
/// it. A forced Encoder that can't make the Codec, and a Codec no Encoder can make, are
/// `codec_unavailable` (SPEC section 24.6), found before any file is written.
pub fn choose(codec: Codec, environment: &Environment) -> Result<Encoder, CommandError> {
    let unavailable = || -> CommandError { CommandError::codec_unavailable(codec.title()) };
    let candidates: Vec<Encoder> = match environment
        .test_encoder
        .as_deref()
        .and_then(Encoder::from_seam)
    {
        Some(forced) => vec![forced],
        None => Encoder::ORDER.to_vec(),
    };
    candidates
        .into_iter()
        .find(|encoder: &Encoder| -> bool { encoder.can_make(codec) })
        .ok_or_else(unavailable)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn environment(forced: Option<&str>) -> Environment {
        Environment {
            test_encoder: forced.map(String::from),
            ..Environment::default()
        }
    }

    #[test]
    fn names_follow_the_contract() {
        assert_eq!(Encoder::Nvenc.json_name(), "nvenc");
        assert_eq!(Encoder::MediaFoundation.json_name(), "media_foundation");
        assert_eq!(Encoder::Software.json_name(), "software");
        assert_eq!(Encoder::Nvenc.title(), "NVIDIA encoder");
        assert_eq!(
            Encoder::MediaFoundation.title(),
            "graphics hardware encoder"
        );
        assert_eq!(Encoder::Software.title(), "software encoder");
    }

    #[test]
    fn h264_is_made_by_the_software_encoder() {
        assert_eq!(
            choose(Codec::H264, &environment(None)),
            Ok(Encoder::Software)
        );
        assert_eq!(
            choose(Codec::H264, &environment(Some("software"))),
            Ok(Encoder::Software)
        );
    }

    #[test]
    fn hevc_has_no_software_step() {
        let error: CommandError = choose(Codec::Hevc, &environment(None)).unwrap_err();
        assert_eq!(error.message, "This computer can't make HEVC videos.");
        assert_eq!(error.status(), 3);
        assert!(choose(Codec::Hevc, &environment(Some("software"))).is_err());
    }

    #[test]
    fn a_forced_encoder_that_is_not_built_is_unavailable() {
        for word in ["nvenc", "media_foundation"] {
            let error: CommandError = choose(Codec::H264, &environment(Some(word))).unwrap_err();
            assert_eq!(
                error.code,
                crate::error::ErrorCode::CodecUnavailable,
                "{word}"
            );
        }
    }

    #[test]
    fn an_unknown_seam_word_forces_nothing() {
        assert_eq!(
            choose(Codec::H264, &environment(Some("quantum"))),
            Ok(Encoder::Software)
        );
    }
}
