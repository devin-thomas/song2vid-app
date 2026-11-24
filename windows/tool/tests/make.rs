//! `song2vid make` (SPEC sections 14.4, 14.5, 24 and 26.3), run as a separate process on generated
//! media. The checks that come before any encoding run anywhere the helpers do; the tests that
//! make a video need Microsoft's software H.264 encoder and run on Windows.

mod common;

use common::{json_line, run, skip_without_helpers, spawn_with_open_stdin, Run, Workspace};
use std::time::{Duration, Instant};

/// The Windows software encoder's `make`, with a song and a picture ready in the folder.
fn workspace() -> Workspace {
    let work: Workspace = Workspace::new();
    work.wav("song.wav", 2.0, 8_000, 1);
    work.png("cover.png", 400, 300, 1);
    work
}

fn make(work: &Workspace, extra: &[&str]) -> Run {
    let mut arguments: Vec<&str> = vec!["make", "song.wav", "cover.png"];
    arguments.extend_from_slice(extra);
    run(&arguments, &[], Some(&work.folder))
}

/// The last line of a `--json` run: its result or its error. A run that takes longer than the
/// quiet period to check its files has shown a progress line first, and no other kind may come
/// before the last.
fn final_line(text: &str) -> serde_json::Value {
    let lines: Vec<&str> = text.lines().collect();
    let (last, before) = lines.split_last().expect("a line");
    for line in before {
        let parsed: serde_json::Value = serde_json::from_str(line).expect("a JSON line");
        assert_eq!(parsed["type"], "progress", "{line}");
    }
    serde_json::from_str(last).expect("a JSON line")
}

fn nothing_left_behind(work: &Workspace, expected: &[&str]) -> () {
    let mut want: Vec<&str> = expected.to_vec();
    want.sort_unstable();
    assert_eq!(work.listing(), want);
}

// ---- Before anything is written ---------------------------------------------------------------

#[test]
fn a_dry_run_says_what_would_be_made_and_writes_nothing() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    let result: Run = make(&work, &["--dry-run"]);
    assert_eq!(result.status, 0, "{}", result.both());
    assert_eq!(result.stderr, "");
    assert_eq!(
        result.stdout,
        "Would make song.mp4 (H.264, software encoder). Nothing was written.\n  Size:       1920\u{d7}1080 pixels\n  Length:     0:02 (2.0 seconds)\n  Placement:  Fit with bars, image enlarged\n"
    );
    nothing_left_behind(&work, &["cover.png", "song.wav"]);

    let json: Run = make(
        &work,
        &["-n", "-j", "-s", "1:1", "-r", "480p", "-o", "out.mp4"],
    );
    assert_eq!(json.status, 0, "{}", json.both());
    assert_eq!(
        json_line(&json.stdout),
        serde_json::json!({
            "api_version": "1", "type": "result", "command": "make",
            "output": {"name": "out.mp4", "width": 480, "height": 480, "duration_seconds": 2.0, "bytes": null},
            "placement": "crop", "enlarged": true, "dry_run": true,
            "codec": "h264", "encoder": "software", "encoder_fallback": false
        })
    );
    nothing_left_behind(&work, &["cover.png", "song.wav"]);
}

#[test]
fn every_frame_shape_has_its_size_in_a_dry_run() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    for (shape, resolution, width, height) in [
        ("16:9", "480p", 854, 480),
        ("9:16", "480p", 480, 854),
        ("1:1", "480p", 480, 480),
        ("4:3", "480p", 640, 480),
        ("original", "", 400, 300),
        ("16:9", "2160p", 3840, 2160),
    ] {
        let mut arguments: Vec<&str> = vec!["-n", "-j", "-s", shape];
        if !resolution.is_empty() {
            arguments.extend_from_slice(&["-r", resolution]);
        }
        let result: Run = make(&work, &arguments);
        assert_eq!(result.status, 0, "{shape}: {}", result.both());
        let line = json_line(&result.stdout);
        assert_eq!(
            (
                line["output"]["width"].as_i64(),
                line["output"]["height"].as_i64()
            ),
            (Some(width), Some(height)),
            "{shape} {resolution}"
        );
    }
}

#[test]
fn the_checks_come_in_the_order_the_mac_command_makes_them() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    work.not_media("notes.txt");
    work.png("tiny.png", 15, 40, 1);
    let code = |arguments: &[&str]| -> (i32, String) {
        let result: Run = run(arguments, &[], Some(&work.folder));
        let line: serde_json::Value = final_line(&result.stdout);
        (
            result.status,
            line["error"]["code"].as_str().unwrap_or("").to_string(),
        )
    };
    // Missing files first (1), the audio before the image; then unreadable (3), the audio first.
    assert_eq!(
        code(&["make", "gone.wav", "gone.png", "-j"]),
        (1, "audio_not_found".into())
    );
    assert_eq!(
        code(&["make", "song.wav", "gone.png", "-j"]),
        (1, "image_not_found".into())
    );
    assert_eq!(
        code(&["make", "notes.txt", "notes.txt", "-j"]),
        (3, "audio_unreadable".into())
    );
    assert_eq!(
        code(&["make", "song.wav", "notes.txt", "-j"]),
        (3, "image_unreadable".into())
    );
    assert_eq!(
        code(&["make", "cover.png", "cover.png", "-j"]),
        (3, "audio_unreadable".into())
    );
    assert_eq!(
        code(&["make", "song.wav", "song.wav", "-j"]),
        (3, "image_unreadable".into())
    );
    // Original needs 16 by 16 pixels, and that is checked before the output.
    assert_eq!(
        code(&["make", "song.wav", "tiny.png", "-s", "original", "-o", "bad.txt", "-j"]),
        (3, "image_too_small".into())
    );
    // The output: its name, its folder, an existing file.
    assert_eq!(
        code(&["make", "song.wav", "cover.png", "-o", "out.mov", "-j"]),
        (4, "output_not_mp4".into())
    );
    assert_eq!(
        code(&["make", "song.wav", "cover.png", "-o", ".mp4", "-j"]),
        (4, "output_not_mp4".into())
    );
    assert_eq!(
        code(&[
            "make",
            "song.wav",
            "cover.png",
            "-o",
            "missing/out.mp4",
            "-j"
        ]),
        (4, "output_not_writable".into())
    );
    // The Codec is checked after the output and before encoding.
    assert_eq!(
        code(&["make", "song.wav", "cover.png", "-C", "hevc", "-j"]),
        (3, "codec_unavailable".into())
    );
    assert_eq!(
        code(&[
            "make",
            "song.wav",
            "cover.png",
            "-C",
            "hevc",
            "-o",
            "out.txt",
            "-j"
        ]),
        (4, "output_not_mp4".into())
    );
    nothing_left_behind(&work, &["cover.png", "notes.txt", "song.wav", "tiny.png"]);
}

#[test]
fn an_existing_output_needs_overwrite_and_is_never_an_input() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    std::fs::write(work.path("song.mp4"), "existing").expect("a file");
    let result: Run = make(&work, &["-j"]);
    assert_eq!(result.status, 4, "{}", result.both());
    assert_eq!(final_line(&result.stdout)["error"]["code"], "output_exists");
    // A dry run checks it too.
    let dry: Run = make(&work, &["-j", "-n"]);
    assert_eq!(final_line(&dry.stdout)["error"]["code"], "output_exists");
    assert_eq!(
        std::fs::read_to_string(work.path("song.mp4")).unwrap(),
        "existing"
    );
    // The person's own files are never the output, with or without --overwrite.
    let input: Run = make(&work, &["-j", "-w", "-o", "song.wav"]);
    assert_eq!(input.status, 4);
    let in_place: Run = run(
        &[
            "make",
            "song.wav",
            "cover.png",
            "-j",
            "-w",
            "-n",
            "-o",
            "./cover.png",
        ],
        &[],
        Some(&work.folder),
    );
    assert_eq!(in_place.status, 4);
    assert_eq!(
        json_line(&in_place.stdout)["error"]["code"],
        "output_not_mp4"
    );
}

#[test]
fn the_test_encoder_seam_forces_one_encoder_and_a_missing_one_is_unavailable() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    let forced = |word: &str, codec: &str| -> Run {
        run(
            &["make", "song.wav", "cover.png", "-n", "-j", "-C", codec],
            &[("SONG2VID_TEST_ENCODER", word)],
            Some(&work.folder),
        )
    };
    let software: Run = forced("software", "h264");
    assert_eq!(software.status, 0, "{}", software.both());
    assert_eq!(json_line(&software.stdout)["encoder"], "software");
    // HEVC has no software step, and the hardware steps are S2V-027's.
    for word in ["software", "nvenc", "media_foundation"] {
        let result: Run = forced(word, "hevc");
        assert_eq!(result.status, 3, "{word}: {}", result.both());
        let line = final_line(&result.stdout);
        assert_eq!(line["error"]["code"], "codec_unavailable");
        assert_eq!(
            line["error"]["message"],
            "This computer can't make HEVC videos."
        );
    }
}

#[test]
fn a_closed_standard_input_cancels_with_cancel_on_eof_and_leaves_nothing() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    for flag in ["-E", "--cancel-on-eof"] {
        let result: Run = make(&work, &["-j", flag]);
        assert_eq!(result.status, 130, "{flag}: {}", result.both());
        assert_eq!(final_line(&result.stdout)["error"]["code"], "cancelled");
        assert_eq!(result.stderr, "");
    }
    let text: Run = make(&work, &["-E"]);
    assert_eq!(text.status, 130);
    assert_eq!(text.stdout, "");
    assert_eq!(text.stderr, "Cancelled.\n");
    nothing_left_behind(&work, &["cover.png", "song.wav"]);
}

#[test]
fn no_output_holds_a_folder_or_a_planted_secret() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    let secret: (&str, &str) = ("S2V_PLANTED", "planted-fake-environment-value");
    for arguments in [
        vec!["make", "song.wav", "cover.png", "-n"],
        vec!["make", "song.wav", "cover.png", "-n", "-j"],
        vec!["make", "gone.wav", "cover.png", "-j"],
        vec!["make", "song.wav", "cover.png", "-o", "missing/out.mp4"],
    ] {
        let result: Run = run(&arguments, &[secret], Some(&work.folder));
        let both: String = result.both();
        assert!(!both.contains("planted-"), "{arguments:?}: {both}");
        assert!(
            !both.contains(&*work.folder.to_string_lossy()),
            "{arguments:?}: {both}"
        );
    }
}

#[test]
fn make_does_not_read_standard_input_without_cancel_on_eof() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = workspace();
    let mut child = spawn_with_open_stdin(
        &["make", "song.wav", "cover.png", "-n", "-j"],
        Some(&work.folder),
    );
    let started: Instant = Instant::now();
    let output = loop {
        if child.try_wait().expect("wait").is_some() {
            break child.wait_with_output().expect("output");
        }
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "make waited for its input"
        );
        std::thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(output.status.code(), Some(0));
}

// ---- Making videos (Windows: Microsoft's software H.264 encoder) --------------------------------

#[cfg(windows)]
mod encoding {
    use super::*;
    use common::{helper_folder, write_to_stdin};
    use serde_json::Value;
    use std::path::Path;
    use std::process::Command;

    fn probe(path: &Path) -> Value {
        let folder: std::path::PathBuf = helper_folder().expect("helpers");
        let output = Command::new(folder.join("ffprobe.exe"))
            .args([
                "-v",
                "error",
                "-show_streams",
                "-show_format",
                "-print_format",
                "json",
            ])
            .arg(path)
            .output()
            .expect("ffprobe runs");
        assert!(output.status.success(), "ffprobe failed on {path:?}");
        serde_json::from_slice(&output.stdout).expect("ffprobe JSON")
    }

    fn stream<'a>(probed: &'a Value, kind: &str) -> &'a Value {
        probed["streams"]
            .as_array()
            .expect("streams")
            .iter()
            .find(|stream: &&Value| -> bool { stream["codec_type"] == kind })
            .unwrap_or_else(|| panic!("no {kind} stream"))
    }

    fn number(value: &Value) -> f64 {
        value
            .as_str()
            .expect("a string number")
            .parse::<f64>()
            .expect("a number")
    }

    /// A video made from the workspace's own files must be a correct H.264 file.
    fn check_video(path: &Path, width: i64, height: i64, seconds: f64) -> () {
        let probed: Value = probe(path);
        let video: &Value = stream(&probed, "video");
        assert_eq!(video["codec_name"], "h264");
        assert_eq!(video["profile"], "High");
        assert_eq!(video["width"].as_i64(), Some(width));
        assert_eq!(video["height"].as_i64(), Some(height));
        assert_eq!(video["pix_fmt"], "yuv420p");
        assert_eq!(video["color_space"], "bt709");
        assert_eq!(video["color_primaries"], "bt709");
        assert_eq!(video["color_transfer"], "bt709");
        assert_eq!(video["color_range"], "tv");
        assert_eq!(video["r_frame_rate"], "30/1");
        let audio: &Value = stream(&probed, "audio");
        assert_eq!(audio["codec_name"], "aac");
        let length: f64 = number(&probed["format"]["duration"]);
        assert!(
            (length - seconds).abs() <= 0.1,
            "length {length}, wanted {seconds}"
        );
        let video_length: f64 = number(&video["duration"]);
        assert!(
            (video_length - seconds).abs() <= 0.1,
            "video {video_length}, wanted {seconds}"
        );
    }

    #[test]
    fn every_frame_shape_is_made_at_480p_with_the_right_size_length_and_tags() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = Workspace::new();
        work.wav("song.wav", 3.0, 44_100, 2);
        work.png("cover.png", 400, 300, 1);
        let before_song: Vec<u8> = std::fs::read(work.path("song.wav")).unwrap();
        let before_cover: Vec<u8> = std::fs::read(work.path("cover.png")).unwrap();
        for (shape, width, height) in [
            ("16:9", 854, 480),
            ("9:16", 480, 854),
            ("1:1", 480, 480),
            ("4:3", 640, 480),
            ("original", 400, 300),
        ] {
            let name: String = format!("{}.mp4", shape.replace(':', "x"));
            let mut arguments: Vec<&str> = vec![
                "make",
                "song.wav",
                "cover.png",
                "-s",
                shape,
                "-o",
                &name,
                "-j",
            ];
            if shape != "original" {
                arguments.extend_from_slice(&["-r", "480p"]);
            }
            let result: Run = run(&arguments, &[], Some(&work.folder));
            assert_eq!(result.status, 0, "{shape}: {}", result.both());
            let lines: Vec<&str> = result.stdout.lines().collect();
            let last: Value = serde_json::from_str(lines.last().expect("a line")).expect("JSON");
            assert_eq!(last["type"], "result", "{shape}");
            assert_eq!(last["output"]["width"].as_i64(), Some(width));
            assert_eq!(last["encoder"], "software");
            let bytes: u64 = std::fs::metadata(work.path(&name))
                .expect("the video")
                .len();
            assert_eq!(last["output"]["bytes"].as_u64(), Some(bytes), "{shape}");
            check_video(&work.path(&name), width, height, 3.0);
        }
        // The files the person gave are exactly as they were, and nothing else is left.
        assert_eq!(std::fs::read(work.path("song.wav")).unwrap(), before_song);
        assert_eq!(std::fs::read(work.path("cover.png")).unwrap(), before_cover);
        assert!(work
            .listing()
            .iter()
            .all(|name: &String| -> bool { !name.starts_with(".song2vid-") }));
    }

    #[test]
    fn a_2160p_video_is_made() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = Workspace::new();
        work.wav("song.wav", 12.0, 48_000, 2);
        work.png("cover.png", 1600, 1200, 1);
        for (shape, width, height) in [("16:9", 3840, 2160), ("9:16", 2160, 3840)] {
            let name: String = format!("{}.mp4", shape.replace(':', "x"));
            let result: Run = run(
                &[
                    "make",
                    "song.wav",
                    "cover.png",
                    "-s",
                    shape,
                    "-r",
                    "2160p",
                    "-o",
                    &name,
                    "-j",
                ],
                &[],
                Some(&work.folder),
            );
            assert_eq!(result.status, 0, "{shape}: {}", result.both());
            check_video(&work.path(&name), width, height, 12.0);
        }
    }

    #[test]
    fn audio_follows_the_rate_and_channel_rules() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = Workspace::new();
        work.png("cover.png", 64, 64, 1);
        // (source rate, channels, rate written, channels written, bit rate)
        for (rate, channels, wrote_rate, wrote_channels, bit_rate) in [
            (44_100, 2, 44_100, 2, 256_000),
            (48_000, 1, 48_000, 1, 256_000),
            (96_000, 2, 48_000, 2, 256_000),
            (22_050, 1, 22_050, 1, 64_000),
            (8_000, 2, 8_000, 2, 48_000),
        ] {
            let song: String = format!("song-{rate}-{channels}.wav");
            work.wav(&song, 2.0, rate, channels);
            let out: String = format!("out-{rate}-{channels}.mp4");
            let result: Run = run(
                &[
                    "make",
                    &song,
                    "cover.png",
                    "-s",
                    "1:1",
                    "-r",
                    "480p",
                    "-o",
                    &out,
                ],
                &[],
                Some(&work.folder),
            );
            assert_eq!(result.status, 0, "{rate}/{channels}: {}", result.both());
            let probed: Value = probe(&work.path(&out));
            let audio: &Value = stream(&probed, "audio");
            assert_eq!(
                audio["sample_rate"].as_str(),
                Some(wrote_rate.to_string().as_str())
            );
            assert_eq!(audio["channels"].as_i64(), Some(wrote_channels));
            // The header says what was asked for; silence needs far fewer bits than it allows.
            let declared: i64 = audio["max_bit_rate"]
                .as_str()
                .or_else(|| audio["bit_rate"].as_str())
                .and_then(|text: &str| -> Option<i64> { text.parse::<i64>().ok() })
                .unwrap_or(0);
            assert!(
                declared <= bit_rate,
                "{rate}/{channels}: {declared} over {bit_rate}"
            );
        }
    }

    #[test]
    fn an_existing_output_is_replaced_only_with_overwrite() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = workspace();
        std::fs::write(work.path("song.mp4"), "existing").expect("a file");
        let refused: Run = make(&work, &["-j"]);
        assert_eq!(refused.status, 4);
        assert_eq!(
            std::fs::read_to_string(work.path("song.mp4")).unwrap(),
            "existing"
        );
        let replaced: Run = make(&work, &["-j", "-w", "-s", "1:1", "-r", "480p"]);
        assert_eq!(replaced.status, 0, "{}", replaced.both());
        check_video(&work.path("song.mp4"), 480, 480, 2.0);
        assert!(work
            .listing()
            .iter()
            .all(|name: &String| -> bool { !name.starts_with(".song2vid-") }));
    }

    #[test]
    fn json_lines_all_parse_and_end_with_exactly_one_result() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = Workspace::new();
        work.wav("song.wav", 240.0, 8_000, 1);
        work.png("cover.png", 1000, 800, 1);
        let result: Run = run(
            &["make", "song.wav", "cover.png", "--json", "-r", "480p"],
            &[],
            Some(&work.folder),
        );
        assert_eq!(result.status, 0, "{}", result.both());
        assert_eq!(result.stderr, "");
        let lines: Vec<Value> = result
            .stdout
            .lines()
            .map(|line: &str| -> Value { serde_json::from_str(line).expect("every line is JSON") })
            .collect();
        let (last, progress): (&Value, &[Value]) = lines.split_last().expect("lines");
        assert_eq!(last["type"], "result");
        assert_eq!(
            progress
                .iter()
                .filter(|line: &&Value| -> bool { line["type"] == "result" })
                .count(),
            0
        );
        let mut position: usize = 0;
        let order: [&str; 4] = ["checking", "preparing", "encoding", "finishing"];
        for line in progress {
            assert_eq!(line["api_version"], "1");
            assert_eq!(line["type"], "progress");
            let stage: usize = order
                .iter()
                .position(|name: &&str| -> bool { line["stage"] == *name })
                .expect("a known stage");
            assert!(stage >= position, "the stage went back: {line}");
            position = stage;
            if stage >= 2 {
                assert_eq!(line["encoder"], "software");
            }
        }
        // Stages start by themselves, so the run was seen to prepare.
        assert!(progress
            .iter()
            .any(|line: &Value| -> bool { line["stage"] == "preparing" }));
    }

    #[test]
    fn plain_progress_lines_hold_no_control_characters() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = Workspace::new();
        work.wav("song.wav", 120.0, 8_000, 1);
        work.png("cover.png", 1000, 800, 1);
        let result: Run = run(
            &["make", "song.wav", "cover.png", "-r", "480p"],
            &[],
            Some(&work.folder),
        );
        assert_eq!(result.status, 0, "{}", result.both());
        assert!(result
            .stdout
            .starts_with("Made song.mp4 (H.264, software encoder).\n"));
        for line in result.stderr.lines() {
            assert!(
                line.chars()
                    .all(|character: char| -> bool { !character.is_control() }),
                "{line:?}"
            );
        }
        assert!(result.stderr.contains("Preparing ("), "{}", result.stderr);
        let quiet: Run = run(
            &["make", "song.wav", "cover.png", "-r", "480p", "-q", "-w"],
            &[],
            Some(&work.folder),
        );
        assert_eq!(quiet.status, 0);
        assert_eq!(quiet.stderr, "");
    }

    #[test]
    fn cancel_on_a_cancel_line_stops_within_two_seconds_and_leaves_no_file() -> () {
        if skip_without_helpers() {
            return;
        }
        let work: Workspace = Workspace::new();
        work.wav("song.wav", 180.0, 8_000, 1);
        work.png("cover.png", 4000, 3000, 1);
        let mut child = spawn_with_open_stdin(
            &["make", "song.wav", "cover.png", "-r", "2160p", "-j", "-E"],
            Some(&work.folder),
        );
        std::thread::sleep(Duration::from_millis(1500));
        assert!(
            child.try_wait().expect("wait").is_none(),
            "the job ended before the cancel"
        );
        let asked: Instant = Instant::now();
        write_to_stdin(&mut child, "cancel\n");
        let output = child.wait_with_output().expect("output");
        let took: Duration = asked.elapsed();
        let stdout: String = String::from_utf8_lossy(&output.stdout).into_owned();
        assert_eq!(output.status.code(), Some(130), "{stdout}");
        assert!(took < Duration::from_secs(2), "took {took:?}");
        let last: &str = stdout.lines().last().expect("a line");
        assert_eq!(
            serde_json::from_str::<Value>(last).unwrap()["error"]["code"],
            "cancelled"
        );
        assert_eq!(work.listing(), vec!["cover.png", "song.wav"]);
    }
}
