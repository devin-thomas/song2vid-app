//! What a `make` command line asks for, after the rules in SPEC sections 14.2 and 24.1 are applied
//! to the parsed options. Anything that breaks a rule is a usage problem (exit status 2), found
//! before any file is looked at.
//!
//! The encoding itself is S2V-026. The checks live here, with the option table, so that the
//! command line is read once and the same way for every command.

use crate::frame::{CropPosition, FrameShape, Resolution};
use crate::options::{Argument, CommandOption, CommandScope, ParsedCommandLine, UsageProblem};

/// The Codec of a video (SPEC section 23).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Codec {
    H264,
    Hevc,
}

impl Codec {
    fn from_command_name(name: &str) -> Option<Codec> {
        match name {
            "h264" => Some(Codec::H264),
            "hevc" => Some(Codec::Hevc),
            _ => None,
        }
    }
}

/// The options of `make`.
#[derive(Clone, Debug)]
pub struct MakeOptions {
    pub audio: Argument,
    pub image: Argument,
    pub shape: FrameShape,
    pub resolution: Resolution,
    pub crop: CropPosition,
    pub codec: Codec,
    pub cancel_on_eof: bool,
    /// The `--out` value, or None for the default name.
    pub output: Option<Argument>,
    pub overwrite: bool,
    pub dry_run: bool,
    pub quiet: bool,
    pub json: bool,
}

impl MakeOptions {
    pub fn resolve(line: &ParsedCommandLine) -> Result<MakeOptions, UsageProblem> {
        let json: bool = line.has(CommandOption::Json);
        let problem = |message: &str| -> UsageProblem {
            UsageProblem::new(message, CommandScope::Make, json)
        };

        let [audio, image] = line.operands.as_slice() else {
            return Err(problem("make needs one audio file and one image file."));
        };
        let mut shape: FrameShape = FrameShape::SixteenByNine;
        if let Some(name) = line.value_of(CommandOption::Shape) {
            shape = FrameShape::from_command_name(&name.text).ok_or_else(|| -> UsageProblem {
                problem("Shape must be 16:9, 9:16, 1:1, 4:3 or original.")
            })?;
        }
        let mut resolution: Resolution = Resolution::P1080;
        if let Some(name) = line.value_of(CommandOption::Resolution) {
            resolution =
                Resolution::from_command_name(&name.text).ok_or_else(|| -> UsageProblem {
                    problem("Resolution must be 480p, 1080p or 2160p.")
                })?;
        }
        let mut crop: CropPosition = CropPosition::CENTER;
        if let Some(text) = line.value_of(CommandOption::Crop) {
            crop = parse_crop(&text.text).ok_or_else(|| -> UsageProblem {
                problem("Crop must be two numbers from 0 to 1, like 0.5,0.5.")
            })?;
        }
        // Rules that join two options. Resolution makes no difference to Original, and a crop position
        // means nothing where the whole image is shown, so both are refused rather than quietly ignored.
        if line.has(CommandOption::Resolution) && shape == FrameShape::Original {
            return Err(problem("Resolution does not apply to the original shape."));
        }
        if line.has(CommandOption::Crop)
            && shape != FrameShape::OneByOne
            && shape != FrameShape::FourByThree
        {
            return Err(problem("Crop applies only to the 1:1 and 4:3 shapes."));
        }
        let codec_name: &str = line
            .value_of(CommandOption::Codec)
            .map_or("h264", |value: &Argument| -> &str { &value.text });
        let codec: Codec = Codec::from_command_name(codec_name)
            .ok_or_else(|| -> UsageProblem { problem("Codec must be h264 or hevc.") })?;

        Ok(MakeOptions {
            audio: audio.clone(),
            image: image.clone(),
            shape,
            resolution,
            crop,
            codec,
            cancel_on_eof: line.has(CommandOption::CancelOnEof),
            output: line.value_of(CommandOption::Out).cloned(),
            overwrite: line.has(CommandOption::Overwrite),
            dry_run: line.has(CommandOption::DryRun),
            quiet: line.has(CommandOption::Quiet),
            json,
        })
    }
}

/// `h,v`: two plain decimal numbers, each from 0 to 1. Nothing else is accepted (no signs, spaces,
/// exponents, `nan` or `inf`), and a value outside 0 to 1 is refused, never clamped.
fn parse_crop(text: &str) -> Option<CropPosition> {
    let parts: Vec<&str> = text.split(',').collect();
    let [horizontal, vertical] = parts.as_slice() else {
        return None;
    };
    let mut values: [f64; 2] = [0.0; 2];
    for (index, part) in [horizontal, vertical].into_iter().enumerate() {
        if !is_plain_decimal(part) {
            return None;
        }
        let value: f64 = part.parse::<f64>().ok()?;
        if !(0.0..=1.0).contains(&value) {
            return None;
        }
        values[index] = value;
    }
    Some(CropPosition::new(values[0], values[1]))
}

/// Digits, then optionally a point and more digits: `^[0-9]+(\.[0-9]+)?$`.
fn is_plain_decimal(text: &str) -> bool {
    let (whole, fraction): (&str, Option<&str>) = match text.split_once('.') {
        Some((whole, fraction)) => (whole, Some(fraction)),
        None => (text, None),
    };
    let digits = |part: &str| -> bool {
        !part.is_empty()
            && part
                .bytes()
                .all(|byte: u8| -> bool { byte.is_ascii_digit() })
    };
    digits(whole) && fraction.is_none_or(digits)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::options::parse;
    use std::ffi::OsString;

    fn resolve(words: &[&str]) -> Result<MakeOptions, UsageProblem> {
        let arguments: Vec<Argument> = words
            .iter()
            .map(|word: &&str| -> Argument { Argument::new(OsString::from(*word)) })
            .collect();
        MakeOptions::resolve(&parse(&arguments).unwrap())
    }

    fn message(words: &[&str]) -> String {
        resolve(words).unwrap_err().message
    }

    #[test]
    fn the_defaults_are_16_9_1080p_h264_centred() {
        let options: MakeOptions = resolve(&["make", "a.wav", "b.png"]).unwrap();
        assert_eq!(options.shape, FrameShape::SixteenByNine);
        assert_eq!(options.resolution, Resolution::P1080);
        assert_eq!(options.codec, Codec::H264);
        assert_eq!(options.crop, CropPosition::CENTER);
        assert!(options.output.is_none());
    }

    #[test]
    fn options_that_break_a_rule_are_usage_problems() {
        assert_eq!(
            message(&["make", "a"]),
            "make needs one audio file and one image file."
        );
        assert_eq!(
            message(&["make", "a", "b", "-s", "5:4"]),
            "Shape must be 16:9, 9:16, 1:1, 4:3 or original."
        );
        assert_eq!(
            message(&["make", "a", "b", "-r", "720p"]),
            "Resolution must be 480p, 1080p or 2160p."
        );
        assert_eq!(
            message(&["make", "a", "b", "-s", "original", "-r", "480p"]),
            "Resolution does not apply to the original shape."
        );
        assert_eq!(
            message(&["make", "a", "b", "-c", "0.5,0.5"]),
            "Crop applies only to the 1:1 and 4:3 shapes."
        );
        assert_eq!(
            message(&["make", "a", "b", "-C", "av1"]),
            "Codec must be h264 or hevc."
        );
        assert_eq!(
            message(&["make", "a", "b", "-C", "HEVC"]),
            "Codec must be h264 or hevc."
        );
    }

    #[test]
    fn crop_takes_two_plain_fractions() {
        for good in ["0,0", "1,1", "0.25,0.75", "0.5,1"] {
            assert!(
                resolve(&["make", "a", "b", "-s", "1:1", "-c", good]).is_ok(),
                "{good}"
            );
        }
        for bad in [
            "0.5",
            "1.5,0",
            "-0.1,0",
            "+0.5,0.5",
            " 0.5,0.5",
            "1e0,0",
            "nan,0",
            "0.5,0.5,0.5",
            ".5,.5",
            "5.,0",
            "",
        ] {
            let attached: String = format!("--crop={bad}");
            assert!(
                resolve(&["make", "a", "b", "-s", "1:1", attached.as_str()]).is_err(),
                "{bad}"
            );
        }
        let options: MakeOptions = resolve(&[
            "make",
            "a",
            "b",
            "-s",
            "4:3",
            "--crop=0.25,0.75",
            "-C",
            "hevc",
        ])
        .unwrap();
        assert_eq!(options.crop, CropPosition::new(0.25, 0.75));
        assert_eq!(options.codec, Codec::Hevc);
    }
}
