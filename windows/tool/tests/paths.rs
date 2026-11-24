//! The path matrix (SPEC section 26.3): any name the system allows works, including spaces,
//! apostrophes, non-Latin text, a leading dash (given as a path), shell characters, percent signs
//! and brackets, and paths over 260 characters. No output holds a folder.

mod common;

use common::{json_line, run, skip_without_helpers, Run, Workspace, FOLDER_MARKER};
use std::path::PathBuf;

/// Names that are valid on Windows and on the systems the tests also run on.
const NAMES: [&str; 20] = [
    "plain",
    "with space",
    "it's an apostrophe",
    "caf\u{e9} \u{e7}a va",
    "\u{540d}\u{524d}\u{306e}\u{30d5}\u{30a1}\u{30a4}\u{30eb}",
    "\u{43f}\u{440}\u{438}\u{432}\u{435}\u{442}",
    "-leading-dash",
    "100%",
    "a%d",
    "%03d",
    "[1] (2) {3}",
    "a&b;c",
    "$HOME `tick`",
    "^caret!bang",
    "#hash @at ~tilde",
    "a,b=c",
    "two  spaces",
    "trailing-dot-inside.name",
    "UPPER lower",
    "emoji-\u{1f3b5}",
];

fn leaks(output: &str, folder: &std::path::Path) -> bool {
    output.contains(FOLDER_MARKER) || output.contains(&*folder.to_string_lossy())
}

#[test]
fn check_and_preview_work_for_every_name_given_relative_or_absolute() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    for name in NAMES {
        let song_name: String = format!("{name}.wav");
        let picture_name: String = format!("{name}.png");
        let song: PathBuf = work.wav(&song_name, 1.0, 8_000, 1);
        let picture: PathBuf = work.png(&picture_name, 200, 100, 1);
        // A name that starts with a dash is given as a path, which is how a person reaches it.
        let relative_song: String = format!("./{song_name}");
        let relative_picture: String = format!("./{picture_name}");
        let absolute_song: String = song.to_string_lossy().into_owned();
        let absolute_picture: String = picture.to_string_lossy().into_owned();
        for (given_song, given_picture) in [
            (&relative_song, &relative_picture),
            (&absolute_song, &absolute_picture),
        ] {
            let result: Run = run(
                &["check", given_song, given_picture, "--json"],
                &[],
                Some(&work.folder),
            );
            assert_eq!(result.status, 0, "{name}: {}", result.both());
            let line = json_line(&result.stdout);
            assert_eq!(line["audio"]["name"], song_name.as_str(), "{name}");
            assert_eq!(line["image"]["name"], picture_name.as_str(), "{name}");
            assert!(
                !leaks(&result.both(), &work.folder),
                "{name} leaked a folder"
            );
            let one: Run = run(&["check", given_picture], &[], Some(&work.folder));
            assert_eq!(one.status, 0, "{name}: {}", one.both());
            assert!(one.stdout.contains(&picture_name), "{name}");

            let output_name: String = format!("preview of {name}.png");
            let out: String = format!("./{output_name}");
            let made: Run = run(
                &["preview", given_picture, "-o", &out, "-w", "-j"],
                &[],
                Some(&work.folder),
            );
            assert_eq!(made.status, 0, "{name}: {}", made.both());
            assert_eq!(
                json_line(&made.stdout)["output"]["name"],
                output_name.as_str()
            );
            assert!(work.path(&output_name).is_file(), "{name}: no preview file");
            assert!(!leaks(&made.both(), &work.folder));
        }
    }
    // Nothing but the files the test made: no temporary file is left.
    for entry in work.listing() {
        assert!(
            !entry.starts_with(".song2vid-"),
            "a temporary file was left: {entry}"
        );
    }
}

#[test]
fn a_path_over_260_characters_works() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    let mut deep: PathBuf = work.folder.clone();
    for part in 0..6 {
        deep.push(format!(
            "a-folder-with-a-long-name-to-pass-the-limit-{part}-{}",
            "x".repeat(30)
        ));
    }
    std::fs::create_dir_all(&deep).expect("a deep folder");
    assert!(
        deep.to_string_lossy().len() > 260,
        "the folder is not deep enough: {}",
        deep.to_string_lossy().len()
    );
    common::write_wav(&deep.join("long song.wav"), 1.0, 8_000, 1);
    common::write_png(&deep.join("long picture.png"), 200, 100, 1, false);

    let song: String = deep.join("long song.wav").to_string_lossy().into_owned();
    let picture: String = deep.join("long picture.png").to_string_lossy().into_owned();
    let checked: Run = run(&["check", &song, &picture, "--json"], &[], None);
    assert_eq!(checked.status, 0, "{}", checked.both());
    let line = json_line(&checked.stdout);
    assert_eq!(line["audio"]["name"], "long song.wav");
    assert_eq!(line["image"]["name"], "long picture.png");
    assert!(!leaks(&checked.both(), &work.folder));

    let out: String = deep.join("long preview.png").to_string_lossy().into_owned();
    let made: Run = run(&["preview", &picture, "-o", &out, "-j"], &[], None);
    assert_eq!(made.status, 0, "{}", made.both());
    assert_eq!(
        json_line(&made.stdout)["output"]["name"],
        "long preview.png"
    );
    assert!(deep.join("long preview.png").is_file());
    assert!(!leaks(&made.both(), &work.folder));
    let leftovers: Vec<String> = std::fs::read_dir(&deep)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|name: &String| name.starts_with(".song2vid-"))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");
}
