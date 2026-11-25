//! The result of `make`: the video that was made, or with `--dry-run` the video that would be
//! made (SPEC sections 14.5 and 24.5). The layout is the Mac command's, line for line, with the
//! Windows Encoder's name.

use crate::encoder::Encoder;
use crate::frame::{FrameShape, OutputFrame, Placement};
use crate::json::{seconds_text, JsonKey, JsonValue};
use crate::make_options::Codec;
use crate::report::clock;

#[derive(Clone, Debug)]
pub struct MakeReport {
    /// The file name only, never the folder.
    pub output_name: String,
    pub frame: OutputFrame,
    pub shape: FrameShape,
    pub codec: Codec,
    pub encoder: Encoder,
    /// True when the first Encoder failed before its first frame and the next one made the video
    /// (SPEC section 23). The software step has no next one, so this is false until S2V-027.
    pub encoder_fallback: bool,
    /// The video is as long as the song (SPEC section 6.3).
    pub duration: f64,
    /// The size of the finished file. None for a dry run, which writes nothing.
    pub bytes: Option<i64>,
    pub dry_run: bool,
}

impl MakeReport {
    fn placement(&self) -> Placement {
        Placement::of(self.shape, &self.frame)
    }

    pub fn json_value(&self) -> JsonValue {
        JsonValue::line_of_type(
            "result",
            vec![
                (JsonKey::Command, JsonValue::String(String::from("make"))),
                (
                    JsonKey::Output,
                    JsonValue::Object(vec![
                        (JsonKey::Name, JsonValue::String(self.output_name.clone())),
                        (JsonKey::Width, JsonValue::Int(self.frame.size.width)),
                        (JsonKey::Height, JsonValue::Int(self.frame.size.height)),
                        (JsonKey::DurationSeconds, JsonValue::Seconds(self.duration)),
                        (
                            JsonKey::Bytes,
                            self.bytes.map_or(JsonValue::Null, JsonValue::Int),
                        ),
                    ]),
                ),
                (
                    JsonKey::Placement,
                    JsonValue::String(String::from(self.placement().json_name())),
                ),
                (JsonKey::Enlarged, JsonValue::Bool(self.frame.is_enlarged)),
                (JsonKey::DryRun, JsonValue::Bool(self.dry_run)),
                (
                    JsonKey::Codec,
                    JsonValue::String(String::from(self.codec.json_name())),
                ),
                (
                    JsonKey::Encoder,
                    JsonValue::String(String::from(self.encoder.json_name())),
                ),
                (
                    JsonKey::EncoderFallback,
                    JsonValue::Bool(self.encoder_fallback),
                ),
            ],
        )
    }

    pub fn text(&self) -> String {
        let description: String = format!(
            "{} ({}, {})",
            self.output_name,
            self.codec.title(),
            self.encoder.title()
        );
        let mut lines: Vec<String> = vec![
            if self.dry_run {
                format!("Would make {description}. Nothing was written.")
            } else {
                format!("Made {description}.")
            },
            format!(
                "  Size:       {}\u{d7}{} pixels",
                self.frame.size.width, self.frame.size.height
            ),
            format!(
                "  Length:     {} ({} seconds)",
                clock(self.duration),
                seconds_text(self.duration)
            ),
            format!(
                "  Placement:  {}{}",
                self.placement().title(self.shape),
                if self.frame.is_enlarged {
                    ", image enlarged"
                } else {
                    ""
                }
            ),
        ];
        if let Some(bytes) = self.bytes {
            lines.push(format!("  File size:  {bytes} bytes"));
        }
        let mut text: String = lines.join("\n");
        text.push('\n');
        text
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{CropPosition, PixelSize, Resolution};

    fn report(dry_run: bool, bytes: Option<i64>) -> MakeReport {
        MakeReport {
            output_name: String::from("song.mp4"),
            frame: OutputFrame::new(
                PixelSize {
                    width: 800,
                    height: 600,
                },
                FrameShape::SixteenByNine,
                Resolution::P1080,
                CropPosition::CENTER,
            )
            .unwrap(),
            shape: FrameShape::SixteenByNine,
            codec: Codec::H264,
            encoder: Encoder::Software,
            encoder_fallback: false,
            duration: 144.0,
            bytes,
            dry_run,
        }
    }

    #[test]
    fn a_dry_run_says_nothing_was_written() {
        assert_eq!(
            report(true, None).text(),
            "Would make song.mp4 (H.264, software encoder). Nothing was written.\n  Size:       1920\u{d7}1080 pixels\n  Length:     2:24 (144.0 seconds)\n  Placement:  Fit with bars, image enlarged\n"
        );
    }

    #[test]
    fn a_finished_video_adds_its_file_size() {
        let text: String = report(false, Some(6_153_216)).text();
        assert!(text.starts_with("Made song.mp4 (H.264, software encoder).\n"));
        assert!(text.ends_with("  File size:  6153216 bytes\n"));
    }

    #[test]
    fn the_json_has_the_keys_of_the_contract_in_order() {
        assert_eq!(
            report(false, Some(6_153_216)).json_value().line(),
            "{\"api_version\":\"1\",\"type\":\"result\",\"command\":\"make\",\"output\":{\"name\":\"song.mp4\",\"width\":1920,\"height\":1080,\"duration_seconds\":144.0,\"bytes\":6153216},\"placement\":\"fit\",\"enlarged\":true,\"dry_run\":false,\"codec\":\"h264\",\"encoder\":\"software\",\"encoder_fallback\":false}\n"
        );
        assert!(report(true, None)
            .json_value()
            .text()
            .contains("\"bytes\":null"));
    }
}
