//! The global options and the usage rules (SPEC section 14.2), run as a separate process.
//! The expected text comes from the SPEC and from the Mac command's own tests, not from this code.

mod common;

use common::{bare_copy, json_line, run, run_in, Run, FOLDER_MARKER, SKILL_TEXT};

const USAGE_ERROR: &str = "Unknown option. Run 'song2vid --help'.\n";

#[test]
fn version_repo_and_help() -> () {
    for option in ["--version", "-v"] {
        let result: Run = run(&[option], &[], None);
        assert_eq!(
            (
                result.status,
                result.stdout.as_str(),
                result.stderr.as_str()
            ),
            (0, "song2vid 1.2.0\n", "")
        );
    }
    for option in ["--repo", "-R"] {
        let result: Run = run(&[option], &[], None);
        assert_eq!(
            (
                result.status,
                result.stdout.as_str(),
                result.stderr.as_str()
            ),
            (0, "https://github.com/devin-thomas/song2vid-app\n", "")
        );
    }
    for option in ["--help", "-h"] {
        let result: Run = run(&[option], &[], None);
        assert_eq!(result.status, 0);
        assert_eq!(result.stderr, "");
        for part in [
            "Usage:",
            "Examples:",
            "Exit statuses:",
            "--help",
            "--version",
            "--repo",
            "--skill",
            "--update",
        ] {
            assert!(result.stdout.contains(part), "help is missing {part}");
        }
    }
    for command in ["check", "make", "encoders", "preview"] {
        for flag in ["--help", "-h"] {
            let result: Run = run(&[command, flag], &[], None);
            assert_eq!(result.status, 0, "{command} {flag}");
            for heading in ["Usage:", "Examples:", "Exit statuses:"] {
                assert!(
                    result.stdout.contains(heading),
                    "{command} help is missing {heading}"
                );
            }
        }
    }
}

#[test]
fn an_unknown_option_is_a_usage_error_that_does_not_echo_it() -> () {
    for option in ["--frobnicate", "-Z", "-vh", "--", "-U", "-X", "-", "-wn"] {
        let result: Run = run(&[option], &[], None);
        assert_eq!(result.status, 2, "{option}");
        assert_eq!(result.stdout, "");
        assert_eq!(result.stderr, USAGE_ERROR, "{option}");
    }
}

#[test]
fn commands_and_counts_that_do_not_exist_are_usage_errors() -> () {
    let unknown: Run = run(&["frobnicate-the-widget"], &[], None);
    assert_eq!(
        (unknown.status, unknown.stderr.as_str()),
        (2, "Unknown command. Run 'song2vid --help'.\n")
    );
    let none: Run = run(&[], &[], None);
    assert_eq!(
        (none.status, none.stderr.as_str()),
        (2, "Missing command. Run 'song2vid --help'.\n")
    );
    let two: Run = run(&["--version", "--help"], &[], None);
    assert_eq!(
        (two.status, two.stderr.as_str()),
        (2, "Use one option at a time. Run 'song2vid --help'.\n")
    );
}

#[test]
fn a_near_miss_names_the_known_option_without_echoing_what_was_typed() -> () {
    for (typed, suggested) in [
        ("--versoin", "--version"),
        ("--hlep", "--help"),
        ("--version=2", "--version"),
        ("--repoo", "--repo"),
    ] {
        let result: Run = run(&[typed], &[], None);
        assert_eq!(result.status, 2);
        assert_eq!(
            result.stderr,
            format!("Unknown option. Run 'song2vid --help'. Did you mean {suggested}?\n")
        );
        assert!(!result.stderr.contains(typed));
    }
}

#[test]
fn json_alone_is_a_usage_error_as_json() -> () {
    for option in ["--json", "-j"] {
        let result: Run = run(&[option], &[], None);
        assert_eq!(result.status, 2);
        assert_eq!(result.stderr, "");
        let line: serde_json::Value = json_line(&result.stdout);
        assert_eq!(line["type"], "error");
        assert_eq!(line["error"]["code"], "usage");
        assert_eq!(
            line["error"]["message"],
            "Use one option at a time. Run 'song2vid --help'."
        );
    }
}

#[test]
fn the_skill_is_printed_byte_for_byte_and_missing_is_an_export_failure() -> () {
    for option in ["--skill", "-S"] {
        let result: Run = run(&[option], &[], None);
        assert_eq!(
            (
                result.status,
                result.stdout.as_str(),
                result.stderr.as_str()
            ),
            (0, SKILL_TEXT, "")
        );
    }
    let bare = bare_copy();
    let missing: Run = run_in(&bare, &["-S"], &[], None, true);
    assert_eq!(missing.status, 5);
    assert_eq!(
        missing.stderr,
        "The agent skill is missing from this copy of Song2Vid.\n"
    );
}

#[test]
fn output_holds_no_environment_value_and_no_folder() -> () {
    let planted: &str = "planted-fake-environment-value";
    for args in [
        vec!["--version"],
        vec!["--help"],
        vec!["--repo"],
        vec!["--nope"],
        vec!["check"],
        vec!["-S"],
    ] {
        let result: Run = run(&args, &[("S2V_PLANTED", planted)], None);
        let everything: String = result.both();
        assert!(!everything.contains(planted), "{args:?}");
        for forbidden in [FOLDER_MARKER, "\\Users\\", "/Users/", "\\\\?\\"] {
            assert!(
                !everything.contains(forbidden),
                "{args:?} printed {forbidden}"
            );
        }
    }
}

#[test]
fn update_reads_a_local_stub_and_says_so_in_text_and_json() -> () {
    let workspace = common::Workspace::new();
    let write = |name: &str, tag: &str| -> String {
        let path = workspace.path(name);
        std::fs::write(&path, format!("{{\"tag_name\":\"{tag}\"}}")).expect("a stub file");
        // A file address: forward slashes work on both systems.
        format!(
            "file:///{}",
            path.to_string_lossy()
                .replace('\\', "/")
                .trim_start_matches('/')
        )
    };
    let current: String = write("current.json", "v1.2.0");
    let newer: String = write("newer.json", "1.10.0");
    let older: String = write("older.json", "v1.1.0");

    let same: Run = run(&["-u"], &[("SONG2VID_UPDATE_URL", &current)], None);
    assert_eq!(
        (same.status, same.stdout.as_str()),
        (0, "Song2Vid 1.2.0 is up to date.\n")
    );
    let older_run: Run = run(&["--update"], &[("SONG2VID_UPDATE_URL", &older)], None);
    assert_eq!(
        (older_run.status, older_run.stdout.as_str()),
        (0, "Song2Vid 1.2.0 is up to date.\n")
    );
    let available: Run = run(&["--update"], &[("SONG2VID_UPDATE_URL", &newer)], None);
    assert_eq!(available.status, 0);
    assert_eq!(
        available.stdout,
        "Song2Vid 1.10.0 is available (you have 1.2.0). Download it from https://song2vid.pages.dev.\n"
    );
    let json: Run = run(&["-u", "--json"], &[("SONG2VID_UPDATE_URL", &newer)], None);
    assert_eq!(
        json.stdout,
        "{\"api_version\":\"1\",\"type\":\"result\",\"command\":\"update\",\"current\":\"1.2.0\",\"latest\":\"1.10.0\",\"update_available\":true,\"download_page\":\"https://song2vid.pages.dev\"}\n"
    );

    // An answer that is not a release, and a file that is not there, are network failures.
    let garbage = workspace.path("garbage.json");
    std::fs::write(&garbage, "not json").expect("a file");
    let garbage_url: String = format!(
        "file:///{}",
        garbage
            .to_string_lossy()
            .replace('\\', "/")
            .trim_start_matches('/')
    );
    for url in [garbage_url.as_str(), "file:///no/such/file.json"] {
        let failed: Run = run(&["-u"], &[("SONG2VID_UPDATE_URL", url)], None);
        assert_eq!(failed.status, 5);
        assert_eq!(
            failed.stderr,
            "Couldn't check for updates. Check the internet connection and try again.\n"
        );
        let failed_json: Run = run(&["-u", "-j"], &[("SONG2VID_UPDATE_URL", url)], None);
        assert_eq!(failed_json.status, 5);
        assert_eq!(json_line(&failed_json.stdout)["error"]["code"], "network");
    }
}

/// `--update` over HTTP reaches only this computer when a stub is named. Windows has WinHTTP; the
/// other systems the tests also run on have no HTTP client, so the lookup there is a network failure.
#[cfg(windows)]
#[test]
fn update_over_http_reaches_a_stub_on_this_computer() -> () {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;

    let listener: TcpListener = TcpListener::bind("127.0.0.1:0").expect("a port");
    let port: u16 = listener.local_addr().expect("an address").port();
    let server = thread::spawn(move || -> String {
        let (mut stream, _) = listener.accept().expect("a request");
        let mut request: [u8; 2048] = [0; 2048];
        let count: usize = stream.read(&mut request).expect("the request");
        let body: &str = "{\"tag_name\":\"v1.3.0\"}";
        let answer: String = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(answer.as_bytes()).expect("the answer");
        String::from_utf8_lossy(&request[..count]).into_owned()
    });
    let url: String = format!("http://localhost:{port}/releases/latest");
    let result: Run = run(&["--update"], &[("SONG2VID_UPDATE_URL", &url)], None);
    let request: String = server.join().expect("the server");
    assert_eq!(result.status, 0, "{}", result.both());
    assert_eq!(
        result.stdout,
        "Song2Vid 1.3.0 is available (you have 1.2.0). Download it from https://song2vid.pages.dev.\n"
    );
    assert!(
        request.starts_with("GET /releases/latest HTTP/1.1"),
        "{request}"
    );
    assert!(
        request.to_lowercase().contains("user-agent: song2vid"),
        "{request}"
    );
    // Nothing about the person goes in the request: no cookie, no authorisation, no query.
    assert!(
        !request.to_lowercase().contains("cookie")
            && !request.to_lowercase().contains("authorization")
    );
}

#[test]
fn make_and_encoders_check_their_usage_and_encoders_says_it_is_not_built_yet() -> () {
    let usage: Run = run(&["make", "a.wav", "b.png", "-s", "5:4", "-j"], &[], None);
    assert_eq!(usage.status, 2);
    assert_eq!(
        json_line(&usage.stdout)["error"]["message"],
        "Shape must be 16:9, 9:16, 1:1, 4:3 or original. Run 'song2vid make --help'."
    );
    assert_eq!(run(&["make", "a.wav", "b.png", "-wn"], &[], None).status, 2);
    assert_eq!(run(&["make", "a.wav"], &[], None).status, 2);
    assert_eq!(run(&["encoders", "unused", "-j"], &[], None).status, 2);
    // `make` is S2V-026's (tests/make.rs); `encoders` is S2V-027's.
    let result: Run = run(&["encoders"], &[], None);
    assert_eq!(result.status, 5);
    assert_eq!(
        result.stderr,
        "This build of song2vid.exe can't make videos yet.\n"
    );
}
