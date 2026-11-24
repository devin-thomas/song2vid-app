//! `song2vid preview` (SPEC section 24.3), run as a separate process on generated pictures.

mod common;

use common::{
    json_line, run, skip_without_helpers, spawn_with_open_stdin, write_to_stdin, Run, Workspace,
};
use std::time::{Duration, Instant};

fn png_size(path: &std::path::Path) -> (u32, u32) {
    let bytes: Vec<u8> = std::fs::read(path).expect("the preview file");
    assert_eq!(
        &bytes[..8],
        &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A],
        "not a PNG"
    );
    (
        u32::from_be_bytes([bytes[16], bytes[17], bytes[18], bytes[19]]),
        u32::from_be_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]),
    )
}

#[test]
fn a_large_turned_picture_is_made_upright_and_fits_within_2048() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    // Orientation 6 turns a 2400x1200 picture on its side: 1200 wide and 2400 high, so 1024x2048.
    work.png("photo.png", 2400, 1200, 6);
    let result: Run = run(
        &["preview", "photo.png", "-o", "cover.png", "-j"],
        &[],
        Some(&work.folder),
    );
    assert_eq!(result.status, 0, "{}", result.both());
    assert_eq!(result.stderr, "");
    let line = json_line(&result.stdout);
    assert_eq!(line["command"], "preview");
    assert_eq!(line["output"]["name"], "cover.png");
    assert_eq!(
        (
            line["output"]["width"].as_i64(),
            line["output"]["height"].as_i64()
        ),
        (Some(1024), Some(2048))
    );
    assert_eq!(
        (
            line["source"]["width"].as_i64(),
            line["source"]["height"].as_i64()
        ),
        (Some(1200), Some(2400))
    );
    assert_eq!(png_size(&work.path("cover.png")), (1024, 2048));
    assert_eq!(work.listing(), vec!["cover.png", "photo.png"]);
}

#[test]
fn a_small_picture_is_never_enlarged_and_text_says_what_was_saved() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    work.transparent_png("transparent.png", 60, 40);
    let result: Run = run(
        &["preview", "transparent.png", "--out", "out.png"],
        &[],
        Some(&work.folder),
    );
    assert_eq!(
        (result.status, result.stdout.as_str()),
        (0, "Saved out.png (60x40).\n")
    );
    assert_eq!(png_size(&work.path("out.png")), (60, 40));
}

#[test]
fn an_existing_output_needs_overwrite_and_is_untouched_without_it() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    work.png("photo.png", 100, 80, 1);
    std::fs::write(work.path("cover.png"), "existing output").unwrap();
    let args: [&str; 5] = ["preview", "photo.png", "-o", "cover.png", "-j"];
    let refused: Run = run(&args, &[], Some(&work.folder));
    assert_eq!(refused.status, 4);
    assert_eq!(json_line(&refused.stdout)["error"]["code"], "output_exists");
    assert_eq!(
        std::fs::read(work.path("cover.png")).unwrap(),
        b"existing output"
    );
    assert_eq!(work.listing(), vec!["cover.png", "photo.png"]);
    let accepted: Run = run(
        &[args[0], args[1], args[2], args[3], args[4], "-w"],
        &[],
        Some(&work.folder),
    );
    assert_eq!(accepted.status, 0, "{}", accepted.both());
    assert_eq!(png_size(&work.path("cover.png")), (100, 80));
    assert_eq!(work.listing(), vec!["cover.png", "photo.png"]);
}

#[test]
fn errors_use_the_shared_codes_and_leave_the_folder_as_it_was() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    work.png("photo.png", 100, 80, 1);
    work.not_media("invalid.jpg");
    std::fs::create_dir(work.path("a-folder")).unwrap();
    let before: Vec<String> = work.listing();
    let cases: [(&str, &str, i32, &str); 8] = [
        ("missing.jpg", "out.png", 1, "image_not_found"),
        ("invalid.jpg", "out.png", 3, "image_unreadable"),
        ("a-folder", "out.png", 3, "image_unreadable"),
        ("photo.png", "out.jpg", 2, "usage"),
        (
            "photo.png",
            "missing-folder/out.png",
            4,
            "output_not_writable",
        ),
        ("photo.png", "photo.png", 4, "output_not_writable"),
        ("photo.png", "a-folder", 2, "usage"),
        ("photo.png", ".png", 2, "usage"),
    ];
    for (image, output, status, code) in cases {
        let result: Run = run(
            &["preview", image, "-o", output, "-j", "-w"],
            &[],
            Some(&work.folder),
        );
        assert_eq!(result.status, status, "{image} {output}: {}", result.both());
        assert_eq!(result.stderr, "");
        assert_eq!(
            json_line(&result.stdout)["error"]["code"],
            code,
            "{image} {output}"
        );
        assert_eq!(
            work.listing(),
            before,
            "{image} {output} changed the folder"
        );
    }
}

#[test]
fn preview_needs_one_image_and_an_output() -> () {
    let message: &str =
        "preview needs one image file and an output file (-o). Run 'song2vid preview --help'.\n";
    for args in [
        vec!["preview", "-o", "x.png"],
        vec!["preview", "a.png"],
        vec!["preview", "a.png", "b.png", "-o", "x.png"],
    ] {
        let result: Run = run(&args, &[], None);
        assert_eq!(
            (result.status, result.stderr.as_str()),
            (2, message),
            "{args:?}"
        );
    }
    let named: Run = run(&["preview", "a.png", "-o", "x.jpg"], &[], None);
    assert_eq!(
        named.stderr,
        "The preview output file name must end in .png. Run 'song2vid preview --help'.\n"
    );
}

#[test]
fn a_closed_standard_input_cancels_with_cancel_on_eof_and_leaves_no_file() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    work.png("photo.png", 100, 80, 1);
    for flag in ["-E", "--cancel-on-eof"] {
        let result: Run = run(
            &["preview", "photo.png", "-o", "out.png", "-j", flag],
            &[],
            Some(&work.folder),
        );
        assert_eq!(result.status, 130, "{}", result.both());
        assert_eq!(json_line(&result.stdout)["error"]["code"], "cancelled");
        assert_eq!(work.listing(), vec!["photo.png"]);
    }
    // Without the option the command never reads standard input, so a closed one changes nothing.
    let without: Run = run(
        &["preview", "photo.png", "-o", "out.png", "-j"],
        &[],
        Some(&work.folder),
    );
    assert_eq!(without.status, 0);
}

#[test]
fn an_open_standard_input_does_not_cancel_until_a_cancel_line_or_the_end() -> () {
    if skip_without_helpers() {
        return;
    }
    let work: Workspace = Workspace::new();
    work.png("photo.png", 100, 80, 1);
    let mut child = spawn_with_open_stdin(
        &["preview", "photo.png", "-o", "out.png", "-j", "-E"],
        Some(&work.folder),
    );
    write_to_stdin(&mut child, "something else\n");
    let started: Instant = Instant::now();
    let output = child.wait_with_output_after(Duration::from_secs(30));
    assert!(started.elapsed() < Duration::from_secs(30));
    assert_eq!(output.0, 0, "{}", output.1);
    assert_eq!(work.listing(), vec!["out.png", "photo.png"]);
}

trait FinishWithStdinOpen {
    fn wait_with_output_after(self, patience: Duration) -> (i32, String);
}

impl FinishWithStdinOpen for std::process::Child {
    /// Waits for the command with its standard input still open (it was never written to end), then
    /// ends the input so a stuck command can't outlive the test.
    fn wait_with_output_after(mut self, patience: Duration) -> (i32, String) {
        let started: Instant = Instant::now();
        loop {
            if let Some(status) = self.try_wait().expect("wait") {
                let mut text: String = String::new();
                if let Some(mut out) = self.stdout.take() {
                    std::io::Read::read_to_string(&mut out, &mut text).expect("stdout");
                }
                return (status.code().unwrap_or(-1), text);
            }
            if started.elapsed() > patience {
                let _ = self.kill();
                return (-1, String::from("did not finish"));
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}
