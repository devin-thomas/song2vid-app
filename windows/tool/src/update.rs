//! `song2vid --update` (SPEC section 14.7): asks GitHub for the latest release and says whether it
//! is newer. It downloads and replaces nothing (ADR-020), and it sends nothing about the person:
//! one plain GET.

use std::fs;

use serde_json::Value;

use crate::context::Environment;
use crate::error::{CommandError, CommandOutput};
use crate::http;
use crate::json::{JsonKey, JsonValue};
use crate::VERSION;

const RELEASE_URL: &str = "https://api.github.com/repos/devin-thomas/song2vid-app/releases/latest";
const DOWNLOAD_PAGE: &str = "https://song2vid.pages.dev";

pub fn run(json: bool, environment: &Environment) -> CommandOutput {
    let url: String = lookup_url(environment);
    let Some(latest) = latest_version(&url) else {
        return CommandOutput::failure(&CommandError::network(), json);
    };
    // `latest_version` only returns a text that parses, and VERSION is ours.
    let (Some(newest), Some(current)) = (Version::parse(&latest), Version::parse(VERSION)) else {
        return CommandOutput::failure(&CommandError::network(), json);
    };
    let available: bool = newest > current;
    if json {
        let line: JsonValue = JsonValue::line_of_type(
            "result",
            vec![
                (JsonKey::Command, JsonValue::String(String::from("update"))),
                (JsonKey::Current, JsonValue::String(String::from(VERSION))),
                (JsonKey::Latest, JsonValue::String(latest)),
                (JsonKey::UpdateAvailable, JsonValue::Bool(available)),
                (
                    JsonKey::DownloadPage,
                    JsonValue::String(String::from(DOWNLOAD_PAGE)),
                ),
            ],
        );
        return CommandOutput::success(line.line());
    }
    let text: String = if available {
        format!("Song2Vid {latest} is available (you have {VERSION}). Download it from {DOWNLOAD_PAGE}.\n")
    } else {
        format!("Song2Vid {VERSION} is up to date.\n")
    };
    CommandOutput::success(text)
}

/// The release address: GitHub's, or a local stub named in the environment.
pub fn lookup_url(environment: &Environment) -> String {
    match &environment.update_url {
        Some(stub) if is_local(stub) => stub.clone(),
        Some(_) | None => String::from(RELEASE_URL),
    }
}

/// Only a file or this computer: a test stub can't send the request anywhere else.
fn is_local(url: &str) -> bool {
    if url.starts_with("file:") {
        return true;
    }
    let Some(rest) = url.strip_prefix("http://") else {
        return false;
    };
    let authority: &str = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host: &str = if let Some(bracketed) = authority.strip_prefix('[') {
        bracketed.split(']').next().unwrap_or("")
    } else {
        authority.split(':').next().unwrap_or("")
    };
    host == "localhost" || host == "::1"
}

/// The `tag_name` of the release at the URL as a plain version (`1.2.0`), or None when the answer
/// isn't one.
fn latest_version(url: &str) -> Option<String> {
    let body: Vec<u8> = fetch(url)?;
    let object: Value = serde_json::from_slice(&body).ok()?;
    let tag: &str = object.get("tag_name")?.as_str()?;
    let version: &str = tag.strip_prefix('v').unwrap_or(tag);
    Version::parse(version).map(|_parsed: Version| -> String { String::from(version) })
}

fn fetch(url: &str) -> Option<Vec<u8>> {
    if let Some(path) = url.strip_prefix("file:") {
        return fs::read(file_path(path)?).ok();
    }
    http::get(url)
}

/// The file a `file:` address names (`file:///C:/folder/name.json` or `file:///folder/name.json`).
fn file_path(rest: &str) -> Option<String> {
    let path: &str = rest.strip_prefix("//").map_or(rest, |after: &str| -> &str {
        // The authority (usually empty) ends at the next slash.
        after
            .find('/')
            .map_or("", |index: usize| -> &str { &after[index..] })
    });
    if path.is_empty() {
        return None;
    }
    let bytes: &[u8] = path.as_bytes();
    // `/C:/...` is a drive path on Windows.
    if bytes.len() >= 3 && bytes[0] == b'/' && bytes[1].is_ascii_alphabetic() && bytes[2] == b':' {
        return Some(String::from(&path[1..]));
    }
    Some(String::from(path))
}

/// A dotted version of one to three numbers, ordered as numbers (`1.10.0` is after `1.9.0`).
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Version {
    parts: [u32; 3],
}

impl Version {
    fn parse(text: &str) -> Option<Version> {
        let pieces: Vec<&str> = text.split('.').collect();
        if !(1..=3).contains(&pieces.len()) {
            return None;
        }
        let mut parts: [u32; 3] = [0; 3];
        for (index, piece) in pieces.iter().enumerate() {
            if piece.is_empty()
                || piece.len() > 6
                || !piece
                    .bytes()
                    .all(|byte: u8| -> bool { byte.is_ascii_digit() })
            {
                return None;
            }
            parts[index] = piece.parse::<u32>().ok()?;
        }
        Some(Version { parts })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_are_ordered_as_numbers() {
        let parse = |text: &str| -> Version { Version::parse(text).unwrap() };
        assert!(parse("1.10.0") > parse("1.9.0"));
        assert!(parse("1.2.0") > parse("1.1.9"));
        assert!(parse("2") > parse("1.99.99"));
        assert_eq!(parse("1.2"), parse("1.2.0"));
        assert!(Version::parse("1.2.0-beta").is_none());
        assert!(Version::parse("1..0").is_none());
        // Four parts is not a version of ours.
        assert!(Version::parse(&["1", "2", "3", "4"].join(".")).is_none());
    }

    #[test]
    fn only_a_file_or_this_computer_is_a_stub() {
        for url in [
            "file:///x.json",
            "http://localhost:8080/x",
            "http://[::1]:9/x",
            "http://localhost/",
        ] {
            assert!(is_local(url), "{url}");
        }
        for url in [
            "https://localhost/x",
            "http://example.com/",
            "http://localhost.example.com/",
            "ftp://localhost/",
        ] {
            assert!(!is_local(url), "{url}");
        }
        let environment: Environment = Environment {
            update_url: Some(String::from("http://example.com/")),
            ..Environment::default()
        };
        assert_eq!(lookup_url(&environment), RELEASE_URL);
    }

    #[test]
    fn file_addresses_name_paths() {
        assert_eq!(file_path("///C:/a/b.json").as_deref(), Some("C:/a/b.json"));
        assert_eq!(file_path("///tmp/b.json").as_deref(), Some("/tmp/b.json"));
        assert_eq!(file_path("").as_deref(), None);
    }
}
