//! The command's JSON (SPEC sections 14.5 and 24.5): one object per line, every key from the
//! documented list.
//!
//! An object can only be built from `JsonKey`, so a key that is not listed here cannot reach the
//! output. Existing keys and their meanings stay fixed within an `api_version`.

use std::fmt::Write;

/// Every key the command may write.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JsonKey {
    ApiVersion,
    Type,
    Command,
    Audio,
    Image,
    Name,
    DurationSeconds,
    SampleRate,
    Channels,
    Width,
    Height,
    Frames,
    Shape,
    Resolution,
    Placement,
    Enlarged,
    TooSmall,
    Error,
    Code,
    Message,
    Output,
    Source,
    Current,
    Latest,
    UpdateAvailable,
    DownloadPage,
    Codecs,
    H264,
    Hevc,
    Available,
    Encoder,
    Bytes,
    DryRun,
    Codec,
    EncoderFallback,
    Stage,
    Percent,
    ElapsedSeconds,
    RemainingSeconds,
}

impl JsonKey {
    /// The key as it is written.
    pub fn text(self) -> &'static str {
        match self {
            JsonKey::ApiVersion => "api_version",
            JsonKey::Type => "type",
            JsonKey::Command => "command",
            JsonKey::Audio => "audio",
            JsonKey::Image => "image",
            JsonKey::Name => "name",
            JsonKey::DurationSeconds => "duration_seconds",
            JsonKey::SampleRate => "sample_rate",
            JsonKey::Channels => "channels",
            JsonKey::Width => "width",
            JsonKey::Height => "height",
            JsonKey::Frames => "frames",
            JsonKey::Shape => "shape",
            JsonKey::Resolution => "resolution",
            JsonKey::Placement => "placement",
            JsonKey::Enlarged => "enlarged",
            JsonKey::TooSmall => "too_small",
            JsonKey::Error => "error",
            JsonKey::Code => "code",
            JsonKey::Message => "message",
            JsonKey::Output => "output",
            JsonKey::Source => "source",
            JsonKey::Current => "current",
            JsonKey::Latest => "latest",
            JsonKey::UpdateAvailable => "update_available",
            JsonKey::DownloadPage => "download_page",
            JsonKey::Codecs => "codecs",
            JsonKey::H264 => "h264",
            JsonKey::Hevc => "hevc",
            JsonKey::Available => "available",
            JsonKey::Encoder => "encoder",
            JsonKey::Bytes => "bytes",
            JsonKey::DryRun => "dry_run",
            JsonKey::Codec => "codec",
            JsonKey::EncoderFallback => "encoder_fallback",
            JsonKey::Stage => "stage",
            JsonKey::Percent => "percent",
            JsonKey::ElapsedSeconds => "elapsed_seconds",
            JsonKey::RemainingSeconds => "remaining_seconds",
        }
    }
}

/// A JSON value. Objects keep their keys in the order given, so the output is the same every run.
#[derive(Clone, Debug, PartialEq)]
pub enum JsonValue {
    String(String),
    Int(i64),
    /// A number with at most three decimals, always written with a decimal point (`144.0`).
    Seconds(f64),
    Bool(bool),
    Null,
    Array(Vec<JsonValue>),
    Object(Vec<(JsonKey, JsonValue)>),
}

impl JsonValue {
    /// The value as compact JSON text.
    pub fn text(&self) -> String {
        match self {
            JsonValue::String(value) => Self::quoted(value),
            JsonValue::Int(value) => value.to_string(),
            JsonValue::Seconds(value) => Self::decimal(*value),
            JsonValue::Bool(value) => String::from(if *value { "true" } else { "false" }),
            JsonValue::Null => String::from("null"),
            JsonValue::Array(values) => {
                let parts: Vec<String> = values
                    .iter()
                    .map(|value: &JsonValue| -> String { value.text() })
                    .collect();
                format!("[{}]", parts.join(","))
            }
            JsonValue::Object(pairs) => {
                let parts: Vec<String> = pairs
                    .iter()
                    .map(|(key, value): &(JsonKey, JsonValue)| -> String {
                        format!("{}:{}", Self::quoted(key.text()), value.text())
                    })
                    .collect();
                format!("{{{}}}", parts.join(","))
            }
        }
    }

    /// One line of output: the value, then a newline.
    pub fn line(&self) -> String {
        let mut text: String = self.text();
        text.push('\n');
        text
    }

    /// The start of every line the command writes: `api_version`, `type`, then the fields.
    pub fn line_of_type(line_type: &str, fields: Vec<(JsonKey, JsonValue)>) -> JsonValue {
        let mut pairs: Vec<(JsonKey, JsonValue)> = vec![
            (JsonKey::ApiVersion, JsonValue::String(String::from("1"))),
            (JsonKey::Type, JsonValue::String(String::from(line_type))),
        ];
        pairs.extend(fields);
        JsonValue::Object(pairs)
    }

    fn quoted(value: &str) -> String {
        let mut result: String = String::from("\"");
        for character in value.chars() {
            match character {
                '"' => result.push_str("\\\""),
                '\\' => result.push_str("\\\\"),
                '\n' => result.push_str("\\n"),
                '\r' => result.push_str("\\r"),
                '\t' => result.push_str("\\t"),
                other if (other as u32) < 0x20 || other as u32 == 0x7F => {
                    // Writing to a String cannot fail.
                    let _ = write!(result, "\\u{:04x}", other as u32);
                }
                other => result.push(other),
            }
        }
        result.push('"');
        result
    }

    /// `%.3f` with trailing zeros dropped, keeping one decimal (`2.5`, `144.0`, `2.403`).
    fn decimal(value: f64) -> String {
        let mut text: String = format!("{value:.3}");
        while text.ends_with('0') && !text.ends_with(".0") {
            text.pop();
        }
        text
    }
}

/// A number of seconds as the text output writes it (`125.0`, `2.37`).
pub fn seconds_text(value: f64) -> String {
    JsonValue::Seconds(value).text()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seconds_keep_one_decimal_and_drop_trailing_zeros() {
        assert_eq!(seconds_text(144.0), "144.0");
        assert_eq!(seconds_text(2.5), "2.5");
        assert_eq!(seconds_text(2.403), "2.403");
        assert_eq!(seconds_text(0.1 + 0.2), "0.3");
    }

    #[test]
    fn strings_escape_quotes_backslashes_and_control_characters() {
        let value: JsonValue =
            JsonValue::String(String::from("s\u{f3}ng \"live\" \\ \u{1}\u{7f}\n"));
        assert_eq!(
            value.text(),
            "\"s\u{f3}ng \\\"live\\\" \\\\ \\u0001\\u007f\\n\""
        );
    }

    #[test]
    fn a_line_starts_with_the_version_and_type() {
        let line: JsonValue = JsonValue::line_of_type(
            "result",
            vec![(JsonKey::Command, JsonValue::String(String::from("check")))],
        );
        assert_eq!(
            line.line(),
            "{\"api_version\":\"1\",\"type\":\"result\",\"command\":\"check\"}\n"
        );
    }
}
