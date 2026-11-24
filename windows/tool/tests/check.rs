//! `song2vid check`, run as a separate process on generated media (SPEC sections 14.3 and 24.8).
//! Expected sizes come from the SPEC section 5 table and the Mac command's tests, not from this code.

mod common;

use common::{json_line, run, skip_without_helpers, Run, Workspace, FOLDER_MARKER};

/// One row per Frame Shape and Resolution, as SPEC section 5 gives them.
const SPEC_TABLE: [(&str, &str, i64, i64, &str); 12] = [
    ("16:9", "480p", 854, 480, "fit"),
    ("16:9", "1080p", 1920, 1080, "fit"),
    ("16:9", "2160p", 3840, 2160, "fit"),
    ("9:16", "480p", 480, 854, "fit"),
    ("9:16", "1080p", 1080, 1920, "fit"),
    ("9:16", "2160p", 2160, 3840, "fit"),
    ("1:1", "480p", 480, 480, "crop"),
    ("1:1", "1080p", 1080, 1080, "crop"),
    ("1:1", "2160p", 2160, 2160, "crop"),
    ("4:3", "480p", 640, 480, "crop"),
    ("4:3", "1080p", 1440, 1080, "crop"),
    ("4:3", "2160p", 2880, 2160, "crop"),
];

#[test]
fn two_files_give_the_facts_and_every_size() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    // 2.5 s at 22,050 Hz mono is 55,125 frames, so the length is exactly 2.5.
    let song = work.wav("short song.wav", 2.5, 22_050, 1);
    let picture = work.png("front.png", 1000, 800, 1);
    let result: Run = run(
        &[
            "check",
            song.to_str().unwrap(),
            picture.to_str().unwrap(),
            "--json",
        ],
        &[],
        None,
    );
    assert_eq!(result.status, 0, "{}", result.both());
    assert_eq!(result.stderr, "");
    let line = json_line(&result.stdout);
    assert_eq!(line["api_version"], "1");
    assert_eq!(line["type"], "result");
    assert_eq!(line["command"], "check");
    assert_eq!(line["audio"]["name"], "short song.wav");
    assert_eq!(line["audio"]["duration_seconds"], 2.5);
    assert_eq!(line["audio"]["sample_rate"], 22_050);
    assert_eq!(line["audio"]["channels"], 1);
    assert_eq!(line["image"]["name"], "front.png");
    assert_eq!(line["image"]["width"], 1000);
    let frames = line["frames"].as_array().expect("frames");
    assert_eq!(frames.len(), 13);
    for (shape, resolution, width, height, placement) in SPEC_TABLE {
        let row = frames
            .iter()
            .find(|row| row["shape"] == shape && row["resolution"] == resolution)
            .unwrap_or_else(|| panic!("{shape} {resolution} is missing"));
        assert_eq!(
            (row["width"].as_i64(), row["height"].as_i64()),
            (Some(width), Some(height))
        );
        assert_eq!(row["placement"], placement);
        // 1000x800 is enlarged exactly when the frame's short side is 1080 or 2160.
        assert_eq!(
            row["enlarged"],
            resolution != "480p",
            "{shape} {resolution}"
        );
        assert_eq!(row["too_small"], false);
    }
    let original = frames
        .iter()
        .find(|row| row["shape"] == "original")
        .expect("original");
    assert_eq!(
        (original["width"].as_i64(), original["height"].as_i64()),
        (Some(1000), Some(800))
    );
    assert!(original["resolution"].is_null());
}

#[test]
fn text_names_both_files_and_has_no_folder() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    let song = work.wav("song.wav", 3.0, 44_100, 2);
    let picture = work.png("cover.png", 1000, 800, 1);
    let result: Run = run(
        &["check", song.to_str().unwrap(), picture.to_str().unwrap()],
        &[],
        None,
    );
    assert_eq!(result.status, 0);
    for part in [
        "song.wav",
        "cover.png",
        "0:03",
        "44100 Hz",
        "2 (stereo)",
        "1000\u{d7}800",
        "Fit with bars",
        "Crop",
        "will be enlarged",
    ] {
        assert!(result.stdout.contains(part), "missing {part}");
    }
    assert!(!result.stdout.contains(FOLDER_MARKER));
    assert!(result.stdout.ends_with('\n') && !result.stdout.ends_with("\n\n"));
}

#[test]
fn an_orientation_tag_swaps_the_sides() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    for (orientation, width, height) in [
        (1, 600, 400),
        (3, 600, 400),
        (5, 400, 600),
        (6, 400, 600),
        (8, 400, 600),
    ] {
        let picture = work.png("turned.png", 600, 400, orientation);
        let result: Run = run(&["check", picture.to_str().unwrap(), "-j"], &[], None);
        let line = json_line(&result.stdout);
        assert_eq!(line["image"]["width"], width, "orientation {orientation}");
        assert_eq!(line["image"]["height"], height, "orientation {orientation}");
    }
}

#[test]
fn a_song_alone_reports_only_the_audio_and_an_image_alone_only_the_image() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    let song = work.wav("song.wav", 125.0, 8_000, 2);
    let picture = work.png("front.png", 1000, 800, 1);
    let alone: Run = run(&["check", song.to_str().unwrap()], &[], None);
    assert_eq!(
        alone.stdout,
        "Audio\n  File:         song.wav\n  Length:       2:05 (125.0 seconds)\n  Sample rate:  8000 Hz\n  Channels:     2 (stereo)\n"
    );
    let song_json = json_line(&run(&["check", song.to_str().unwrap(), "-j"], &[], None).stdout);
    let keys: Vec<&String> = song_json.as_object().unwrap().keys().collect();
    assert_eq!(keys.len(), 4);
    for key in ["api_version", "type", "command", "audio"] {
        assert!(song_json.get(key).is_some(), "{key}");
    }
    let image_json = json_line(&run(&["check", picture.to_str().unwrap(), "-j"], &[], None).stdout);
    for key in ["api_version", "type", "command", "image", "frames"] {
        assert!(image_json.get(key).is_some(), "{key}");
    }
    assert!(image_json.get("audio").is_none());
    let both = run(
        &["check", song.to_str().unwrap(), picture.to_str().unwrap()],
        &[],
        None,
    );
    let image_text = run(&["check", picture.to_str().unwrap()], &[], None);
    assert!(both.stdout.starts_with(&alone.stdout));
    assert!(both.stdout.ends_with(&image_text.stdout));
}

#[test]
fn the_kind_comes_from_the_contents_not_the_name() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    std::fs::copy(
        work.png("real.png", 320, 200, 1),
        work.path("looks-like-a-song.mp3"),
    )
    .unwrap();
    std::fs::copy(
        work.wav("real.wav", 1.0, 8_000, 1),
        work.path("looks-like-a-picture.png"),
    )
    .unwrap();
    let picture = json_line(
        &run(
            &[
                "check",
                work.path("looks-like-a-song.mp3").to_str().unwrap(),
                "-j",
            ],
            &[],
            None,
        )
        .stdout,
    );
    assert_eq!(picture["image"]["name"], "looks-like-a-song.mp3");
    assert_eq!(picture["image"]["width"], 320);
    assert!(picture.get("audio").is_none());
    let song = json_line(
        &run(
            &[
                "check",
                work.path("looks-like-a-picture.png").to_str().unwrap(),
                "-j",
            ],
            &[],
            None,
        )
        .stdout,
    );
    assert_eq!(song["audio"]["name"], "looks-like-a-picture.png");
    assert!(song.get("image").is_none() && song.get("frames").is_none());
}

#[test]
fn a_missing_or_unreadable_input_gives_its_status_and_code_in_text_and_json() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    let song = work.wav("song.wav", 1.0, 8_000, 1);
    let picture = work.png("cover.png", 300, 200, 1);
    let fake_song = work.not_media("not-a-song.mp3");
    let fake_picture = work.not_media("not-a-picture.png");
    std::fs::create_dir(work.path("a-folder")).unwrap();
    let folder = work.path("a-folder");
    let gone_song = work.path("no-such-song.wav");
    let gone_picture = work.path("no-such-picture.png");
    let s = |path: &std::path::PathBuf| -> String { path.to_string_lossy().into_owned() };

    let cases: Vec<(Vec<String>, i32, &str, &str)> = vec![
        (
            vec![s(&gone_song), s(&picture)],
            1,
            "audio_not_found",
            "The audio file was not found.",
        ),
        (
            vec![s(&song), s(&gone_picture)],
            1,
            "image_not_found",
            "The image file was not found.",
        ),
        (
            vec![s(&gone_song), s(&gone_picture)],
            1,
            "audio_not_found",
            "The audio file was not found.",
        ),
        (
            vec![s(&fake_song), s(&picture)],
            3,
            "audio_unreadable",
            "Song2Vid can't read this audio file.",
        ),
        (
            vec![s(&song), s(&fake_picture)],
            3,
            "image_unreadable",
            "Song2Vid can't read this image file.",
        ),
        (
            vec![s(&folder), s(&picture)],
            3,
            "audio_unreadable",
            "Song2Vid can't read this audio file.",
        ),
        (
            vec![s(&song), s(&folder)],
            3,
            "image_unreadable",
            "Song2Vid can't read this image file.",
        ),
        (
            vec![s(&fake_song), s(&fake_picture)],
            3,
            "audio_unreadable",
            "Song2Vid can't read this audio file.",
        ),
        (
            vec![s(&fake_song), s(&gone_picture)],
            1,
            "image_not_found",
            "The image file was not found.",
        ),
        // A single file: the kind its name suggests.
        (
            vec![s(&gone_song)],
            1,
            "audio_not_found",
            "The audio file was not found.",
        ),
        (
            vec![s(&gone_picture)],
            1,
            "image_not_found",
            "The image file was not found.",
        ),
        (
            vec![s(&work.path("gone"))],
            1,
            "image_not_found",
            "The image file was not found.",
        ),
        (
            vec![s(&fake_song)],
            3,
            "audio_unreadable",
            "Song2Vid can't read this audio file.",
        ),
        (
            vec![s(&fake_picture)],
            3,
            "image_unreadable",
            "Song2Vid can't read this image file.",
        ),
        (
            vec![s(&work.not_media("notes.txt"))],
            3,
            "image_unreadable",
            "Song2Vid can't read this image file.",
        ),
    ];
    for (files, status, code, message) in cases {
        let mut args: Vec<&str> = vec!["check"];
        args.extend(files.iter().map(String::as_str));
        let text: Run = run(&args, &[], None);
        assert_eq!(
            (text.status, text.stdout.as_str()),
            (status, ""),
            "{args:?}"
        );
        assert_eq!(text.stderr, format!("{message}\n"), "{args:?}");
        args.push("--json");
        let json: Run = run(&args, &[], None);
        assert_eq!(json.status, status);
        assert_eq!(json.stderr, "");
        let line = json_line(&json.stdout);
        assert_eq!(line["type"], "error");
        assert_eq!(line["error"]["code"], code);
        assert_eq!(line["error"]["message"], message);
        for private in [FOLDER_MARKER, "plain text", "no-such", "not-a-"] {
            assert!(
                !json.stdout.contains(private) && !text.stderr.contains(private),
                "{args:?} printed {private}"
            );
        }
    }
}

#[test]
fn usage_is_checked_first_and_the_file_count_is_one_or_two() -> () {
    let message: &str = "check needs one audio file and one image file, or a single file. Run 'song2vid check --help'.\n";
    for files in [vec![], vec!["one", "two", "three"]] {
        let mut args: Vec<&str> = vec!["check"];
        args.extend(files);
        let result: Run = run(&args, &[], None);
        assert_eq!(
            (
                result.status,
                result.stdout.as_str(),
                result.stderr.as_str()
            ),
            (2, "", message)
        );
        args.push("-j");
        let json: Run = run(&args, &[], None);
        assert_eq!(json.status, 2);
        assert_eq!(json_line(&json.stdout)["error"]["code"], "usage");
    }
    assert_eq!(
        run(
            &["check", "no-such-song", "no-such-picture", "--nope"],
            &[],
            None
        )
        .status,
        2
    );
    let scope: &str = "That option does not apply here. Run 'song2vid check --help'.\n";
    for option in [
        "--version",
        "-v",
        "--repo",
        "-o",
        "-s",
        "-n",
        "-q",
        "--overwrite",
        "-S",
        "-u",
        "--update",
    ] {
        let result: Run = run(&["check", "a", "b", option], &[], None);
        assert_eq!(
            (result.status, result.stderr.as_str()),
            (2, scope),
            "{option}"
        );
    }
    for option in ["--zzz-typed-text", "-Q", "-jj", "-hj", "--", "-"] {
        let result: Run = run(&["check", "a", "b", option], &[], None);
        assert_eq!(
            (result.status, result.stderr.as_str()),
            (2, "Unknown option. Run 'song2vid check --help'.\n"),
            "{option}"
        );
        let json: Run = run(&["check", "a", "b", option, "--json"], &[], None);
        assert_eq!(json.stderr, "");
        assert!(!json.stdout.contains("zzz-typed-text"));
    }
}

#[test]
fn check_writes_nothing_and_the_json_uses_only_listed_keys() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    let song = work.wav("song.wav", 1.0, 8_000, 1);
    let picture = work.png("cover.png", 300, 200, 1);
    let before: Vec<String> = work.listing();
    let result: Run = run(
        &["check", "song.wav", "cover.png", "--json"],
        &[("S2V_PLANTED", "planted-fake-environment-value")],
        Some(&work.folder),
    );
    assert_eq!(result.status, 0, "{}", result.both());
    assert_eq!(work.listing(), before);
    assert!(!result.both().contains("planted-fake-environment-value"));
    let allowed: [&str; 21] = [
        "api_version",
        "type",
        "command",
        "audio",
        "image",
        "name",
        "duration_seconds",
        "sample_rate",
        "channels",
        "width",
        "height",
        "frames",
        "shape",
        "resolution",
        "placement",
        "enlarged",
        "too_small",
        "error",
        "code",
        "message",
        "frames",
    ];
    fn keys(value: &serde_json::Value, found: &mut Vec<String>) -> () {
        match value {
            serde_json::Value::Object(map) => {
                for (key, inner) in map {
                    found.push(key.clone());
                    keys(inner, found);
                }
            }
            serde_json::Value::Array(items) => items.iter().for_each(|item| keys(item, found)),
            _ => {}
        }
    }
    let mut found: Vec<String> = Vec::new();
    keys(&json_line(&result.stdout), &mut found);
    for key in &found {
        assert!(allowed.contains(&key.as_str()), "unexpected key {key}");
    }
    drop((song, picture));
}
