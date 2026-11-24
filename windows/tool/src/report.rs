//! What `check` found, as text and as JSON (SPEC sections 14.3 and 24.8).
//!
//! The layout is the Mac command's, line for line, so the two commands print the same report for
//! the same files.

use crate::frame::{CropPosition, FrameShape, OutputFrame, PixelSize, Placement, Resolution};
use crate::json::{seconds_text, JsonKey, JsonValue};

/// What is known about a song.
#[derive(Clone, Debug, PartialEq)]
pub struct AudioFacts {
    /// The file name only: a folder never reaches the output.
    pub name: String,
    pub duration: f64,
    pub sample_rate: i64,
    pub channels: i64,
}

/// What is known about an image. `size` is in pixels after its orientation tag.
#[derive(Clone, Debug, PartialEq)]
pub struct ImageFacts {
    pub name: String,
    pub size: PixelSize,
}

/// One output the image could be made into.
#[derive(Clone, Debug)]
pub struct Row {
    pub shape: FrameShape,
    /// None for Original, which does not depend on Resolution.
    pub resolution: Option<Resolution>,
    /// None when Original can't be made because the image is under 16 pixels on a side.
    pub frame: Option<OutputFrame>,
}

impl Row {
    fn placement(&self) -> Option<Placement> {
        self.frame
            .as_ref()
            .map(|frame: &OutputFrame| -> Placement { Placement::of(self.shape, frame) })
    }

    fn json_value(&self) -> JsonValue {
        let size_or_null = |pick: fn(&PixelSize) -> i64| -> JsonValue {
            match &self.frame {
                Some(frame) => JsonValue::Int(pick(&frame.size)),
                None => JsonValue::Null,
            }
        };
        JsonValue::Object(vec![
            (
                JsonKey::Shape,
                JsonValue::String(String::from(self.shape.command_name())),
            ),
            (
                JsonKey::Resolution,
                match self.resolution {
                    Some(resolution) => JsonValue::String(resolution.command_name()),
                    None => JsonValue::Null,
                },
            ),
            (
                JsonKey::Width,
                size_or_null(|size: &PixelSize| -> i64 { size.width }),
            ),
            (
                JsonKey::Height,
                size_or_null(|size: &PixelSize| -> i64 { size.height }),
            ),
            (
                JsonKey::Placement,
                match self.placement() {
                    Some(placement) => JsonValue::String(String::from(placement.json_name())),
                    None => JsonValue::Null,
                },
            ),
            (
                JsonKey::Enlarged,
                match &self.frame {
                    Some(frame) => JsonValue::Bool(frame.is_enlarged),
                    None => JsonValue::Null,
                },
            ),
            (JsonKey::TooSmall, JsonValue::Bool(self.frame.is_none())),
        ])
    }
}

/// The files that were read and the output for every Frame Shape and Resolution.
#[derive(Clone, Debug)]
pub struct CheckReport {
    pub audio: Option<AudioFacts>,
    pub image: Option<ImageFacts>,
    /// The output sizes. Empty when only a song was checked.
    pub rows: Vec<Row>,
}

impl CheckReport {
    /// Every Frame Shape at every Resolution, then Original once, using `OutputFrame` for every size.
    pub fn new(audio: Option<AudioFacts>, image: Option<ImageFacts>) -> CheckReport {
        let mut rows: Vec<Row> = Vec::new();
        if let Some(facts) = &image {
            for shape in FrameShape::ALL {
                if shape == FrameShape::Original {
                    continue;
                }
                for resolution in Resolution::ALL {
                    let frame: Option<OutputFrame> =
                        OutputFrame::new(facts.size, shape, resolution, CropPosition::CENTER).ok();
                    rows.push(Row {
                        shape,
                        resolution: Some(resolution),
                        frame,
                    });
                }
            }
            // Resolution does not change Original, so any one stands in for it.
            let original: Option<OutputFrame> = OutputFrame::new(
                facts.size,
                FrameShape::Original,
                Resolution::P1080,
                CropPosition::CENTER,
            )
            .ok();
            rows.push(Row {
                shape: FrameShape::Original,
                resolution: None,
                frame: original,
            });
        }
        CheckReport { audio, image, rows }
    }

    /// The single `result` line. A single file leaves out the other file's keys (SPEC section 24.8).
    pub fn json_value(&self) -> JsonValue {
        let mut fields: Vec<(JsonKey, JsonValue)> =
            vec![(JsonKey::Command, JsonValue::String(String::from("check")))];
        if let Some(audio) = &self.audio {
            fields.push((
                JsonKey::Audio,
                JsonValue::Object(vec![
                    (JsonKey::Name, JsonValue::String(audio.name.clone())),
                    (JsonKey::DurationSeconds, JsonValue::Seconds(audio.duration)),
                    (JsonKey::SampleRate, JsonValue::Int(audio.sample_rate)),
                    (JsonKey::Channels, JsonValue::Int(audio.channels)),
                ]),
            ));
        }
        if let Some(image) = &self.image {
            fields.push((
                JsonKey::Image,
                JsonValue::Object(vec![
                    (JsonKey::Name, JsonValue::String(image.name.clone())),
                    (JsonKey::Width, JsonValue::Int(image.size.width)),
                    (JsonKey::Height, JsonValue::Int(image.size.height)),
                ]),
            ));
            fields.push((
                JsonKey::Frames,
                JsonValue::Array(
                    self.rows
                        .iter()
                        .map(|row: &Row| -> JsonValue { row.json_value() })
                        .collect(),
                ),
            ));
        }
        JsonValue::line_of_type("result", fields)
    }

    /// The report for people.
    pub fn text(&self) -> String {
        let mut lines: Vec<String> = Vec::new();
        if let Some(audio) = &self.audio {
            lines.push(String::from("Audio"));
            lines.push(format!("  File:         {}", audio.name));
            lines.push(format!(
                "  Length:       {} ({} seconds)",
                clock(audio.duration),
                seconds_text(audio.duration)
            ));
            lines.push(format!("  Sample rate:  {} Hz", audio.sample_rate));
            lines.push(format!("  Channels:     {}", channels_text(audio.channels)));
        }
        let Some(image) = &self.image else {
            return format!("{}\n", lines.join("\n"));
        };
        if !lines.is_empty() {
            lines.push(String::new());
        }
        lines.push(String::from("Image"));
        lines.push(format!("  File:         {}", image.name));
        lines.push(format!(
            "  Size:         {}\u{d7}{} pixels",
            image.size.width, image.size.height
        ));
        lines.push(String::new());
        lines.push(String::from("Output sizes"));

        let table: Vec<[String; 5]> = self
            .rows
            .iter()
            .map(|row: &Row| -> [String; 5] { Self::cells(row) })
            .collect();
        let mut widths: [usize; 4] = [0; 4];
        for cells in &table {
            for (column, width) in widths.iter_mut().enumerate() {
                *width = (*width).max(cells[column].chars().count());
            }
        }
        for cells in &table {
            let mut line: String = String::from("  ");
            for column in 0..4 {
                line.push_str(&cells[column]);
                let padding: usize = widths[column] + 2 - cells[column].chars().count();
                line.push_str(&" ".repeat(padding));
            }
            line.push_str(&cells[4]);
            lines.push(String::from(line.trim_end_matches(' ')));
        }
        format!("{}\n", lines.join("\n"))
    }

    fn cells(row: &Row) -> [String; 5] {
        let size: String = match &row.frame {
            Some(frame) => format!("{}\u{d7}{}", frame.size.width, frame.size.height),
            None => String::from("too small"),
        };
        let placement: String = match row.placement() {
            Some(placement) => String::from(placement.title(row.shape)),
            None => String::from("-"),
        };
        let note: &str = match &row.frame {
            None => "Original needs an image of at least 16\u{d7}16 pixels.",
            Some(frame) if frame.is_enlarged => "will be enlarged",
            Some(_) => "",
        };
        [
            String::from(row.shape.command_name()),
            row.resolution
                .map_or(String::from("-"), |resolution: Resolution| -> String {
                    resolution.command_name()
                }),
            size,
            placement,
            String::from(note),
        ]
    }
}

/// `2:24`, or `1:02:03` for an hour or more.
pub fn clock(duration: f64) -> String {
    let total: i64 = duration.round() as i64;
    let hours: i64 = total / 3600;
    let minutes: i64 = total % 3600 / 60;
    let seconds: i64 = total % 60;
    if hours > 0 {
        format!("{hours}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes}:{seconds:02}")
    }
}

fn channels_text(count: i64) -> String {
    match count {
        1 => String::from("1 (mono)"),
        2 => String::from("2 (stereo)"),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn image(width: i64, height: i64) -> ImageFacts {
        ImageFacts {
            name: String::from("front.png"),
            size: PixelSize { width, height },
        }
    }

    #[test]
    fn the_clock_has_minutes_or_hours() {
        assert_eq!(clock(144.0), "2:24");
        assert_eq!(clock(125.0), "2:05");
        assert_eq!(clock(3723.4), "1:02:03");
        assert_eq!(clock(2.5), "0:03");
    }

    #[test]
    fn a_song_alone_reports_only_the_audio() {
        let report: CheckReport = CheckReport::new(
            Some(AudioFacts {
                name: String::from("song.wav"),
                duration: 125.0,
                sample_rate: 8000,
                channels: 2,
            }),
            None,
        );
        assert_eq!(
            report.text(),
            "Audio\n  File:         song.wav\n  Length:       2:05 (125.0 seconds)\n  Sample rate:  8000 Hz\n  Channels:     2 (stereo)\n"
        );
        assert_eq!(
            report.json_value().text(),
            "{\"api_version\":\"1\",\"type\":\"result\",\"command\":\"check\",\"audio\":{\"name\":\"song.wav\",\"duration_seconds\":125.0,\"sample_rate\":8000,\"channels\":2}}"
        );
    }

    #[test]
    fn an_image_lists_thirteen_rows() {
        let report: CheckReport = CheckReport::new(None, Some(image(1000, 800)));
        assert_eq!(report.rows.len(), 13);
        let text: String = report.text();
        assert!(text.starts_with("Image\n  File:         front.png\n  Size:         1000\u{d7}800 pixels\n\nOutput sizes\n"));
        assert!(text.contains("  16:9      480p   854\u{d7}480    Fit with bars\n"));
        assert!(
            text.contains("  1:1       1080p  1080\u{d7}1080  Crop           will be enlarged\n")
        );
        assert!(text.contains("will be enlarged"));
        assert!(text.ends_with("  original  -      1000\u{d7}800   Whole image\n"));
    }

    #[test]
    fn original_under_sixteen_pixels_is_too_small() {
        let report: CheckReport = CheckReport::new(None, Some(image(15, 40)));
        let last: &Row = report.rows.last().unwrap();
        assert!(last.frame.is_none());
        assert!(report.text().contains(
            "too small  -              Original needs an image of at least 16\u{d7}16 pixels.\n"
        ));
        assert!(report.json_value().text().ends_with(
            "{\"shape\":\"original\",\"resolution\":null,\"width\":null,\"height\":null,\"placement\":null,\"enlarged\":null,\"too_small\":true}]}"
        ));
    }
}
