//! Frame math parity (SPEC sections 26.1 and 31): every case in `fixtures/frame-math.json`, which
//! the Swift tests write from `OutputFrame`, must come out of the Rust port exactly.

use std::fs;
use std::path::PathBuf;

use serde_json::Value;
use song2vid::frame::{CropPosition, FrameError, FrameShape, OutputFrame, PixelSize, Resolution};

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/frame-math.json")
}

fn number(value: &Value, key: &str) -> f64 {
    value[key]
        .as_f64()
        .unwrap_or_else(|| panic!("{key} is not a number in {value}"))
}

fn size(value: &Value) -> PixelSize {
    PixelSize {
        width: number(value, "width") as i64,
        height: number(value, "height") as i64,
    }
}

#[test]
fn every_fixture_case_matches_exactly() -> () {
    let text: String = fs::read_to_string(fixture_path()).expect("the shared fixture file");
    let cases: Vec<Value> = serde_json::from_str(&text).expect("the fixture is JSON");
    assert!(
        cases.len() >= 200,
        "the fixture has only {} cases",
        cases.len()
    );

    let mut checked_sizes: usize = 0;
    let mut checked_errors: usize = 0;
    for case in &cases {
        let image: PixelSize = size(&case["image"]);
        let shape: FrameShape =
            FrameShape::from_command_name(case["shape"].as_str().expect("shape"))
                .expect("known shape");
        let resolution: Resolution =
            Resolution::from_command_name(case["resolution"].as_str().expect("resolution"))
                .expect("known resolution");
        let crop: CropPosition = CropPosition::new(
            number(&case["crop"], "horizontal"),
            number(&case["crop"], "vertical"),
        );
        let label: String = format!(
            "{image:?} {} {} {crop:?}",
            shape.command_name(),
            resolution.command_name()
        );

        let made: Result<OutputFrame, FrameError> =
            OutputFrame::new(image, shape, resolution, crop);
        match case["error"].as_str() {
            Some(code) => {
                assert_eq!(code, "image_too_small", "{label}");
                assert_eq!(made, Err(FrameError::ImageTooSmall), "{label}");
                checked_errors += 1;
            }
            None => {
                let frame: OutputFrame = made.unwrap_or_else(|_error: FrameError| -> OutputFrame {
                    panic!("{label} should have a frame")
                });
                let expected: &Value = &case["output"];
                assert_eq!(frame.size, size(&expected["size"]), "size of {label}");
                assert_eq!(
                    frame.is_enlarged,
                    expected["enlarged"].as_bool().expect("enlarged"),
                    "enlarged of {label}"
                );
                let placement: &Value = &expected["placement"];
                assert_eq!(
                    frame.image_placement.x,
                    number(placement, "x"),
                    "x of {label}"
                );
                assert_eq!(
                    frame.image_placement.y,
                    number(placement, "y"),
                    "y of {label}"
                );
                assert_eq!(
                    frame.image_placement.width,
                    number(placement, "width"),
                    "width of {label}"
                );
                assert_eq!(
                    frame.image_placement.height,
                    number(placement, "height"),
                    "height of {label}"
                );
                checked_sizes += 1;
            }
        }
    }
    assert!(checked_sizes > 0 && checked_errors > 0);
    println!(
        "{} cases matched: {checked_sizes} frames, {checked_errors} image_too_small",
        cases.len()
    );
}
