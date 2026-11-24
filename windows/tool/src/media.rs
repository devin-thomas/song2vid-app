//! Reading media through FFprobe, and making the preview picture through FFmpeg (SPEC sections 7,
//! 24.3, 24.8 and 26.3).
//!
//! A file's kind comes from what is inside it, as the Mac command reads it: a file with an audio
//! stream is a song; a still picture in one of the section 7 image formats is an image; anything
//! else is neither.

use std::ffi::OsString;
use std::path::Path;
use std::time::Duration;

use serde_json::Value;

use crate::cancel::CancelToken;
use crate::frame::PixelSize;
use crate::heif;
use crate::orientation::{self, Orientation};
use crate::process::{run_tool, RunError, RunLimits, ToolRun, Tools};

/// FFprobe answers in a fraction of a second; this only stops one that hangs.
const PROBE_TIMEOUT: Duration = Duration::from_secs(30);
const PROBE_MAX_OUTPUT: usize = 16 * 1024 * 1024;
/// Listing a long song's packets is fast; this stops one that hangs.
const COUNT_TIMEOUT: Duration = Duration::from_secs(60);
/// A packet list for a long song is a few megabytes of JSON; this stops one that is not.
const PACKET_LIST_LIMIT: usize = 256 * 1024 * 1024;
/// A preview of a very large picture still finishes well inside this.
const PREVIEW_TIMEOUT: Duration = Duration::from_secs(120);
const PREVIEW_MAX_OUTPUT: usize = 256 * 1024 * 1024;
/// The longest side of a preview (SPEC section 24.3).
pub const PREVIEW_LIMIT: i64 = 2048;

/// A song's facts, read from its container.
#[derive(Clone, Debug, PartialEq)]
pub struct AudioStream {
    pub duration: f64,
    pub sample_rate: i64,
    pub channels: i64,
    /// The stream's time unit as numerator and denominator, for adding up packet lengths.
    pub time_base: (i64, i64),
    /// The number of frames the encoder says the song has, from the `iTunSMPB` tag Apple's and
    /// others' AAC encoders write. It is exact where the packets alone would count the padding.
    pub declared_frames: Option<i64>,
    /// True when the container's length is the exact count of the song's frames (PCM, FLAC, ALAC).
    /// Otherwise it can include encoder padding or be an estimate, and the length is counted by
    /// decoding.
    pub exact_in_container: bool,
}

/// Which stream or stream group of the file holds the picture.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PictureInput {
    /// A video stream, by its index in the file.
    Stream(i64),
    /// A tile grid (HEIC), by its group index. The grid is the whole picture; a single stream is
    /// only one tile.
    Group(i64),
}

/// A picture's facts, read from its container and its orientation tag.
#[derive(Clone, Debug, PartialEq)]
pub struct Picture {
    /// The size as stored.
    pub stored: PixelSize,
    pub orientation: Orientation,
    pub input: PictureInput,
}

impl Picture {
    /// The size after the orientation tag.
    pub fn size(&self) -> PixelSize {
        if self.orientation.swaps_sides() {
            PixelSize {
                width: self.stored.height,
                height: self.stored.width,
            }
        } else {
            self.stored
        }
    }
}

/// What a file turned out to be.
#[derive(Clone, Debug, PartialEq)]
pub enum Inspection {
    Audio(AudioStream),
    Picture(Picture),
    Neither,
}

/// Why a file could not be inspected at all.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MediaError {
    /// FFprobe or FFmpeg could not be started.
    ToolUnavailable,
    Cancelled,
}

/// Looks inside a file. `path` must be a path the helper programs can open.
pub fn inspect(tools: &Tools, path: &Path, cancel: &CancelToken) -> Result<Inspection, MediaError> {
    let arguments: Vec<OsString> = [
        "-v",
        "error",
        "-hide_banner",
        "-show_format",
        "-show_streams",
        "-show_stream_groups",
        "-print_format",
        "json",
    ]
    .iter()
    .map(|word: &&str| -> OsString { OsString::from(*word) })
    .chain(std::iter::once(path.as_os_str().to_os_string()))
    .collect();
    let limits: RunLimits = RunLimits {
        timeout: PROBE_TIMEOUT,
        max_stdout: PROBE_MAX_OUTPUT,
    };
    let run: ToolRun = match run_tool(&tools.ffprobe, &arguments, limits, cancel) {
        Ok(run) => run,
        Err(RunError::Cancelled) => return Err(MediaError::Cancelled),
        Err(RunError::CouldNotStart) => return Err(MediaError::ToolUnavailable),
        // A probe that hangs or floods is not a readable file.
        Err(RunError::TimedOut | RunError::TooMuchOutput) => return Ok(Inspection::Neither),
    };
    if run.exit_code != 0 {
        return Ok(Inspection::Neither);
    }
    let Ok(root) = serde_json::from_slice::<Value>(&run.stdout) else {
        return Ok(Inspection::Neither);
    };
    let mut found: Inspection = classify(&root, path);
    if let Inspection::Audio(audio) = &mut found {
        if !audio.exact_in_container {
            // If the packets can't be read, the container's length stands.
            if let Some(counted) = count_length(tools, path, audio, cancel)? {
                audio.duration = counted;
            }
        }
    }
    Ok(found)
}

/// How long the song is, counted from its packets as the Mac command counts it: every frame the
/// packets hold, less the encoder padding the file says to skip at the start and drop at the end.
/// An MP3 header's estimate is not trusted, and a song with no padding information counts every
/// frame. The Windows FFmpeg has no muxer that could decode to nowhere, so the packets are listed
/// by FFprobe instead of decoded.
fn count_length(
    tools: &Tools,
    path: &Path,
    audio: &AudioStream,
    cancel: &CancelToken,
) -> Result<Option<f64>, MediaError> {
    let mut arguments: Vec<OsString> = [
        "-v",
        "error",
        "-hide_banner",
        "-select_streams",
        "a:0",
        "-show_entries",
        "packet=duration:packet_side_data",
        "-of",
        "json",
    ]
    .iter()
    .map(|word: &&str| -> OsString { OsString::from(*word) })
    .collect();
    arguments.push(path.as_os_str().to_os_string());
    let limits: RunLimits = RunLimits {
        timeout: COUNT_TIMEOUT,
        max_stdout: PACKET_LIST_LIMIT,
    };
    let run: ToolRun = match run_tool(&tools.ffprobe, &arguments, limits, cancel) {
        Ok(run) => run,
        Err(RunError::Cancelled) => return Err(MediaError::Cancelled),
        Err(RunError::CouldNotStart) => return Err(MediaError::ToolUnavailable),
        Err(RunError::TimedOut | RunError::TooMuchOutput) => return Ok(None),
    };
    if run.exit_code != 0 {
        return Ok(None);
    }
    let Ok(root) = serde_json::from_slice::<Value>(&run.stdout) else {
        return Ok(None);
    };
    Ok(packet_length(&root, audio))
}

/// The length in seconds that a packet list adds up to, or None when there are no packets.
pub fn packet_length(root: &Value, audio: &AudioStream) -> Option<f64> {
    let packets: &Vec<Value> = root.get("packets")?.as_array()?;
    let mut ticks: i64 = 0;
    let mut padding: i64 = 0;
    for packet in packets {
        ticks += integer_of(packet, "duration").unwrap_or(0);
        let Some(list) = packet.get("side_data_list").and_then(Value::as_array) else {
            continue;
        };
        for entry in list {
            if text_of(entry, "side_data_type") == Some("Skip Samples") {
                padding += integer_of(entry, "skip_samples").unwrap_or(0);
                padding += integer_of(entry, "discard_padding").unwrap_or(0);
            }
        }
    }
    if ticks <= 0 {
        return None;
    }
    let (numerator, denominator): (i64, i64) = audio.time_base;
    // A declared count wins when it fits inside what the packets hold.
    if let Some(declared) = audio.declared_frames {
        let held: f64 =
            ticks as f64 * numerator as f64 / denominator as f64 * audio.sample_rate as f64;
        if declared as f64 <= held + 1.0 {
            return Some(declared as f64 / audio.sample_rate as f64);
        }
    }
    let seconds: f64 = if numerator == 1 && denominator == audio.sample_rate {
        // The packets are counted in frames: whole numbers all the way, as the Mac counts.
        let frames: i64 = ticks - padding;
        frames as f64 / audio.sample_rate as f64
    } else {
        ticks as f64 * numerator as f64 / denominator as f64
            - padding as f64 / audio.sample_rate as f64
    };
    if seconds > 0.0 {
        Some(seconds)
    } else {
        None
    }
}

/// Decides what FFprobe's answer describes.
pub fn classify(root: &Value, path: &Path) -> Inspection {
    let streams: &[Value] = root
        .get("streams")
        .and_then(Value::as_array)
        .map_or(&[][..], |list: &Vec<Value>| -> &[Value] { list.as_slice() });
    if let Some(audio) = streams
        .iter()
        .find(|stream: &&Value| -> bool { text_of(stream, "codec_type") == Some("audio") })
    {
        return match audio_stream(audio, root.get("format")) {
            Some(facts) => Inspection::Audio(facts),
            None => Inspection::Neither,
        };
    }
    match picture(root, streams, path) {
        Some(picture) => Inspection::Picture(picture),
        None => Inspection::Neither,
    }
}

/// The frame count in an `iTunSMPB` tag: `" 00000000 <start padding> <end padding> <frames> ..."`, each
/// a hexadecimal number.
fn declared_frames(format: &Value) -> Option<i64> {
    let tags: &Value = format.get("tags")?;
    let tag: &str = tags
        .as_object()?
        .iter()
        .find(|(name, _value): &(&String, &Value)| -> bool {
            name.eq_ignore_ascii_case("itunsmpb")
        })?
        .1
        .as_str()?;
    let fields: Vec<&str> = tag.split_whitespace().collect();
    let frames: i64 = i64::from_str_radix(fields.get(3)?, 16).ok()?;
    if frames > 0 {
        Some(frames)
    } else {
        None
    }
}

fn time_base_of(stream: &Value) -> Option<(i64, i64)> {
    let (numerator, denominator): (&str, &str) = text_of(stream, "time_base")?.split_once('/')?;
    let numerator: i64 = numerator.parse::<i64>().ok()?;
    let denominator: i64 = denominator.parse::<i64>().ok()?;
    if numerator > 0 && denominator > 0 {
        Some((numerator, denominator))
    } else {
        None
    }
}

/// Codecs whose container length is the exact number of frames: raw samples and the lossless
/// formats, which carry their frame count and have no encoder padding.
fn counts_frames_exactly(codec: &str) -> bool {
    codec.starts_with("pcm_") || codec == "flac" || codec == "alac"
}

fn text_of<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn integer_of(value: &Value, key: &str) -> Option<i64> {
    let found: &Value = value.get(key)?;
    found
        .as_i64()
        .or_else(|| -> Option<i64> { found.as_str()?.parse::<i64>().ok() })
}

/// A song's length counted in its own time units when the container has them, so a WAV of 104517
/// frames at 44100 Hz is exactly 2.37 seconds, as the Mac command measures it.
fn audio_stream(stream: &Value, format: Option<&Value>) -> Option<AudioStream> {
    let sample_rate: i64 = integer_of(stream, "sample_rate")?;
    let channels: i64 = integer_of(stream, "channels")?;
    if sample_rate <= 0 || channels <= 0 {
        return None;
    }
    let counted: Option<f64> =
        integer_of(stream, "duration_ts").and_then(|ticks: i64| -> Option<f64> {
            let base: &str = text_of(stream, "time_base")?;
            let (numerator, denominator): (&str, &str) = base.split_once('/')?;
            let numerator: f64 = numerator.parse::<f64>().ok()?;
            let denominator: f64 = denominator.parse::<f64>().ok()?;
            if denominator <= 0.0 {
                return None;
            }
            Some(ticks as f64 * numerator / denominator)
        });
    let written = |value: Option<&Value>| -> Option<f64> {
        value.and_then(|found: &Value| -> Option<f64> {
            text_of(found, "duration")?.parse::<f64>().ok()
        })
    };
    let duration: f64 = counted
        .or_else(|| -> Option<f64> { written(Some(stream)) })
        .or_else(|| -> Option<f64> { written(format) })?;
    if !duration.is_finite() || duration <= 0.0 {
        return None;
    }
    let codec: &str = text_of(stream, "codec_name").unwrap_or("");
    let exact_in_container: bool = counts_frames_exactly(codec) && counted.is_some();
    Some(AudioStream {
        duration,
        sample_rate,
        channels,
        time_base: time_base_of(stream).unwrap_or((1, sample_rate)),
        declared_frames: format.and_then(|found: &Value| -> Option<i64> { declared_frames(found) }),
        exact_in_container,
    })
}

/// The container names FFprobe gives the still-picture formats of SPEC section 7.
const PICTURE_FORMATS: [&str; 7] = [
    "image2",
    "png_pipe",
    "jpeg_pipe",
    "tiff_pipe",
    "webp_pipe",
    "bmp_pipe",
    "gif",
];
const HEIF_BRANDS: [&str; 8] = [
    "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1",
];

fn picture(root: &Value, streams: &[Value], path: &Path) -> Option<Picture> {
    let format: &Value = root.get("format")?;
    let names: &str = text_of(format, "format_name")?;
    let is_heif: bool =
        names.split(',').any(|name: &str| -> bool { name == "mov" }) && has_heif_brand(format);
    let is_still: bool = names
        .split(',')
        .any(|name: &str| -> bool { PICTURE_FORMATS.contains(&name) });
    if !is_heif && !is_still {
        return None;
    }

    // FFprobe 8.1 reports a plain picture's turn as a display matrix but leaves a tile grid's out,
    // so the turn comes from the file's own boxes, with the matrix as the fallback.
    let heif_turn: Option<Orientation> = if is_heif {
        heif::read_from_file(path)
    } else {
        None
    };
    if is_heif {
        if let Some(grid) = tile_grid(root, heif_turn) {
            return Some(grid);
        }
    }
    let video: Vec<&Value> = streams
        .iter()
        .filter(|stream: &&Value| -> bool { text_of(stream, "codec_type") == Some("video") })
        .collect();
    // The primary picture of a HEIC file is the stream marked default; a plain file has one stream.
    let chosen: &Value = video
        .iter()
        .find(|stream: &&&Value| -> bool {
            stream
                .get("disposition")
                .and_then(|flags: &Value| -> Option<i64> { integer_of(flags, "default") })
                == Some(1)
        })
        .or_else(|| -> Option<&&Value> { video.first() })?;
    let width: i64 = integer_of(chosen, "width")?;
    let height: i64 = integer_of(chosen, "height")?;
    if width <= 0 || height <= 0 {
        return None;
    }
    let orientation: Orientation = if is_heif {
        heif_turn.unwrap_or_else(|| -> Orientation { display_matrix_orientation(chosen) })
    } else {
        orientation::read_from_file(path)
    };
    Some(Picture {
        stored: PixelSize { width, height },
        orientation,
        input: PictureInput::Stream(integer_of(chosen, "index")?),
    })
}

fn has_heif_brand(format: &Value) -> bool {
    let Some(tags) = format.get("tags") else {
        return false;
    };
    let major: &str = text_of(tags, "major_brand").unwrap_or("");
    let compatible: &str = text_of(tags, "compatible_brands").unwrap_or("");
    let listed = |brand: &&str| -> bool {
        major == *brand
            || compatible
                .as_bytes()
                .chunks(4)
                .any(|chunk: &[u8]| -> bool { chunk == brand.as_bytes() })
    };
    HEIF_BRANDS.iter().any(listed)
}

/// The tile grid of a HEIC file, when it has one. The grid's own size is the picture's size.
fn tile_grid(root: &Value, turn: Option<Orientation>) -> Option<Picture> {
    let groups: &Vec<Value> = root.get("stream_groups")?.as_array()?;
    let grids: Vec<&Value> = groups
        .iter()
        .filter(|group: &&Value| -> bool { text_of(group, "type") == Some("Tile Grid") })
        .collect();
    let chosen: &Value = grids
        .iter()
        .find(|group: &&&Value| -> bool {
            group
                .get("disposition")
                .and_then(|flags: &Value| -> Option<i64> { integer_of(flags, "default") })
                == Some(1)
        })
        .or_else(|| -> Option<&&Value> { grids.first() })?;
    let grid: &Value = chosen.get("components")?.as_array()?.first()?;
    let width: i64 = integer_of(grid, "width")?;
    let height: i64 = integer_of(grid, "height")?;
    if width <= 0 || height <= 0 {
        return None;
    }
    Some(Picture {
        stored: PixelSize { width, height },
        orientation: turn.unwrap_or_else(|| -> Orientation { display_matrix_orientation(grid) }),
        input: PictureInput::Group(integer_of(chosen, "index")?),
    })
}

/// The orientation a stream or tile grid carries as a display matrix, or upright.
fn display_matrix_orientation(holder: &Value) -> Orientation {
    let Some(list) = holder.get("side_data_list").and_then(Value::as_array) else {
        return Orientation::Upright;
    };
    for entry in list {
        if let Some(matrix) = text_of(entry, "displaymatrix") {
            return Orientation::from_display_matrix(matrix);
        }
    }
    Orientation::Upright
}

/// The size of a preview: the picture's size after its tag, scaled to fit within 2048 on its long
/// side and never enlarged (SPEC section 24.3).
pub fn preview_size(size: PixelSize) -> PixelSize {
    let long: i64 = size.width.max(size.height);
    if long <= PREVIEW_LIMIT {
        return size;
    }
    let scaled = |side: i64| -> i64 { ((side * PREVIEW_LIMIT * 2 + long) / (long * 2)).max(1) };
    PixelSize {
        width: scaled(size.width),
        height: scaled(size.height),
    }
}

/// FFmpeg's arguments for the preview: decode the picture, scale it, put it on black (so
/// transparent areas are black), turn it upright, and write one RGB PNG to standard output.
pub fn preview_arguments(path: &Path, picture: &Picture) -> Vec<OsString> {
    let target: PixelSize = preview_size(picture.size());
    // FFmpeg turns a tile grid upright by itself, whatever `-noautorotate` says, so its frames
    // arrive in the final orientation. A single stream is left alone and turned here. The picture
    // is scaled before it is turned, so the single stream's target has its sides swapped by a
    // quarter turn.
    let (width, height, stored, turn_filter): (i64, i64, PixelSize, Option<&'static str>) =
        match picture.input {
            PictureInput::Group(_) => (target.width, target.height, picture.size(), None),
            PictureInput::Stream(_) if picture.orientation.swaps_sides() => (
                target.height,
                target.width,
                picture.stored,
                picture.orientation.filter(),
            ),
            PictureInput::Stream(_) => (
                target.width,
                target.height,
                picture.stored,
                picture.orientation.filter(),
            ),
        };
    let source: String = match picture.input {
        PictureInput::Stream(index) => format!("[0:{index}]"),
        PictureInput::Group(index) => format!("[0:g:{index}]"),
    };
    let scale: String = if width == stored.width && height == stored.height {
        String::new()
    } else {
        format!("scale={width}:{height}:flags=area,")
    };
    let turn: String = turn_filter.map_or(String::new(), |filters: &str| -> String {
        format!(",{filters}")
    });
    let graph: String = format!(
        "color=c=black:s={width}x{height}:r=1:d=1,format=rgba[ground];\
         {source}{scale}format=rgba[picture];\
         [ground][picture]overlay=shortest=1:format=auto,format=rgb24{turn}[preview]"
    );
    let mut arguments: Vec<OsString> = Vec::new();
    for word in [
        "-hide_banner",
        "-v",
        "error",
        "-nostdin",
        "-noautorotate",
        "-i",
    ] {
        arguments.push(OsString::from(word));
    }
    arguments.push(path.as_os_str().to_os_string());
    for word in [
        "-filter_complex",
        graph.as_str(),
        "-map",
        "[preview]",
        "-frames:v",
        "1",
        "-c:v",
        "png",
        "-f",
        "image2pipe",
        "-",
    ] {
        arguments.push(OsString::from(word));
    }
    arguments
}

/// Makes the preview PNG. The bytes are checked to be a PNG of the size the command promised.
pub fn render_preview(
    tools: &Tools,
    path: &Path,
    picture: &Picture,
    cancel: &CancelToken,
) -> Result<Vec<u8>, PreviewFailure> {
    let arguments: Vec<OsString> = preview_arguments(path, picture);
    let limits: RunLimits = RunLimits {
        timeout: PREVIEW_TIMEOUT,
        max_stdout: PREVIEW_MAX_OUTPUT,
    };
    let run: ToolRun = match run_tool(&tools.ffmpeg, &arguments, limits, cancel) {
        Ok(run) => run,
        Err(RunError::Cancelled) => return Err(PreviewFailure::Cancelled),
        Err(RunError::CouldNotStart) => return Err(PreviewFailure::ToolUnavailable),
        Err(RunError::TimedOut | RunError::TooMuchOutput) => {
            return Err(PreviewFailure::Unreadable)
        }
    };
    let target: PixelSize = preview_size(picture.size());
    if run.exit_code != 0 || png_size(&run.stdout) != Some(target) {
        return Err(PreviewFailure::Unreadable);
    }
    Ok(run.stdout)
}

/// Why a preview could not be made.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PreviewFailure {
    ToolUnavailable,
    Cancelled,
    /// FFmpeg could not decode the picture.
    Unreadable,
}

/// The size a PNG's header gives, or None when the bytes are not a PNG.
pub fn png_size(bytes: &[u8]) -> Option<PixelSize> {
    const SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    if bytes.len() < 24 || bytes[..8] != SIGNATURE || &bytes[12..16] != b"IHDR" {
        return None;
    }
    let read = |at: usize| -> i64 {
        i64::from(u32::from_be_bytes([
            bytes[at],
            bytes[at + 1],
            bytes[at + 2],
            bytes[at + 3],
        ]))
    };
    Some(PixelSize {
        width: read(16),
        height: read(20),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn classify_json(value: &Value) -> Inspection {
        classify(value, Path::new("file"))
    }

    #[test]
    fn a_wav_length_is_counted_in_frames() {
        let root: Value = json!({
            "streams": [{"codec_type": "audio", "codec_name": "pcm_s16le", "sample_rate": "44100", "channels": 1,
                         "time_base": "1/44100", "duration_ts": 104517, "duration": "2.370000"}],
            "format": {"format_name": "wav", "duration": "2.370000"}
        });
        assert_eq!(
            classify_json(&root),
            Inspection::Audio(AudioStream {
                duration: 2.37,
                sample_rate: 44100,
                channels: 1,
                exact_in_container: true,
                time_base: (1, 44100),
                declared_frames: None,
            })
        );
    }

    #[test]
    fn a_stream_without_a_length_uses_the_container_length() {
        let root: Value = json!({
            "streams": [{"codec_type": "audio", "sample_rate": "48000", "channels": 2}],
            "format": {"format_name": "aac", "duration": "183.123000"}
        });
        assert_eq!(
            classify_json(&root),
            Inspection::Audio(AudioStream {
                duration: 183.123,
                sample_rate: 48000,
                channels: 2,
                time_base: (1, 48000),
                declared_frames: None,
                exact_in_container: false
            })
        );
    }

    #[test]
    fn packets_add_up_to_the_frames_less_the_padding() {
        let audio: AudioStream = AudioStream {
            duration: 2.438,
            sample_rate: 44100,
            channels: 1,
            time_base: (1, 44100),
            declared_frames: None,
            exact_in_container: false,
        };
        // 105 packets of 1024 frames, 2112 to skip at the start and 891 to drop at the end.
        let mut packets: Vec<Value> = (0..105)
            .map(|_i: i32| -> Value { json!({"duration": 1024}) })
            .collect();
        packets[0] = json!({"duration": 1024, "side_data_list": [{"side_data_type": "Skip Samples", "skip_samples": 2112, "discard_padding": 0}]});
        packets[104] = json!({"duration": 1024, "side_data_list": [{"side_data_type": "Skip Samples", "skip_samples": 0, "discard_padding": 891}]});
        assert_eq!(
            packet_length(&json!({"packets": packets}), &audio),
            Some(2.37)
        );
        assert_eq!(packet_length(&json!({"packets": []}), &audio), None);
        // A time base that is not one frame: seconds add up and the padding is taken off in frames.
        let mp3: AudioStream = AudioStream {
            time_base: (1, 14_112_000),
            ..audio
        };
        let seconds: f64 =
            packet_length(&json!({"packets": [{"duration": 14_112_000 * 2}]}), &mp3).unwrap();
        assert!((seconds - 2.0).abs() < 1e-9);
    }

    #[test]
    fn a_declared_frame_count_beats_the_packets_when_it_fits() {
        let root: Value = json!({"packets": [{"duration": 1024}, {"duration": 1024}]});
        let mut audio: AudioStream = AudioStream {
            duration: 0.0,
            sample_rate: 44100,
            channels: 2,
            time_base: (1, 44100),
            declared_frames: Some(2000),
            exact_in_container: false,
        };
        assert_eq!(packet_length(&root, &audio), Some(2000.0 / 44100.0));
        // A count larger than the packets can hold is not believed.
        audio.declared_frames = Some(9000);
        assert_eq!(packet_length(&root, &audio), Some(2048.0 / 44100.0));
        let format: Value =
            json!({"tags": {"iTunSMPB": " 00000000 00000840 0000037B 0000000000019845 00000000"}});
        assert_eq!(declared_frames(&format), Some(104_517));
        assert_eq!(declared_frames(&json!({"tags": {"title": "x"}})), None);
        assert_eq!(
            declared_frames(&json!({"tags": {"iTunSMPB": "garbage"}})),
            None
        );
    }

    #[test]
    fn an_empty_or_odd_song_is_neither() {
        let empty: Value = json!({
            "streams": [{"codec_type": "audio", "sample_rate": "44100", "channels": 2, "duration_ts": 0, "time_base": "1/44100"}],
            "format": {"format_name": "wav"}
        });
        assert_eq!(classify_json(&empty), Inspection::Neither);
        let no_rate: Value = json!({"streams": [{"codec_type": "audio", "sample_rate": "0", "channels": 2}], "format": {}});
        assert_eq!(classify_json(&no_rate), Inspection::Neither);
    }

    #[test]
    fn a_png_is_a_picture_and_a_video_is_not() {
        let png: Value = json!({
            "streams": [{"index": 0, "codec_type": "video", "width": 300, "height": 150}],
            "format": {"format_name": "png_pipe"}
        });
        assert_eq!(
            classify_json(&png),
            Inspection::Picture(Picture {
                stored: PixelSize {
                    width: 300,
                    height: 150
                },
                orientation: Orientation::Upright,
                input: PictureInput::Stream(0),
            })
        );
        let video: Value = json!({
            "streams": [{"index": 0, "codec_type": "video", "width": 300, "height": 150}],
            "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2", "tags": {"major_brand": "isom", "compatible_brands": "isomiso2avc1mp41"}}
        });
        assert_eq!(classify_json(&video), Inspection::Neither);
        let empty_picture: Value = json!({
            "streams": [{"index": 0, "codec_type": "video", "width": 0, "height": 0}],
            "format": {"format_name": "image2"}
        });
        assert_eq!(classify_json(&empty_picture), Inspection::Neither);
    }

    #[test]
    fn a_heic_tile_grid_gives_the_whole_picture_and_its_turn() {
        let heic: Value = json!({
            "streams": [{"index": 0, "codec_type": "video", "width": 512, "height": 512}],
            "stream_groups": [{"index": 0, "type": "Tile Grid", "disposition": {"default": 1},
                "components": [{"width": 3000, "height": 1500, "side_data_list": [
                    {"side_data_type": "EXIF metadata"},
                    {"side_data_type": "Display Matrix",
                     "displaymatrix": "\n00000000:            0       65536           0\n00000001:       -65536           0           0\n00000002:            0           0  1073741824\n"}]}]}],
            "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2", "tags": {"major_brand": "heic", "compatible_brands": "mif1MiPrmiafMiHBheic"}}
        });
        let Inspection::Picture(picture) = classify_json(&heic) else {
            panic!("expected a picture");
        };
        assert_eq!(picture.input, PictureInput::Group(0));
        assert_eq!(picture.orientation, Orientation::Rotate90Clockwise);
        assert_eq!(
            picture.size(),
            PixelSize {
                width: 1500,
                height: 3000
            }
        );
    }

    #[test]
    fn a_preview_fits_within_2048_and_is_never_enlarged() {
        let size =
            |width: i64, height: i64| -> PixelSize { preview_size(PixelSize { width, height }) };
        assert_eq!(
            size(1500, 3000),
            PixelSize {
                width: 1024,
                height: 2048
            }
        );
        assert_eq!(
            size(4032, 3024),
            PixelSize {
                width: 2048,
                height: 1536
            }
        );
        assert_eq!(
            size(60, 40),
            PixelSize {
                width: 60,
                height: 40
            }
        );
        assert_eq!(
            size(2048, 2048),
            PixelSize {
                width: 2048,
                height: 2048
            }
        );
        assert_eq!(
            size(3001, 2000),
            PixelSize {
                width: 2048,
                height: 1365
            }
        );
        assert_eq!(
            size(20000, 1),
            PixelSize {
                width: 2048,
                height: 1
            }
        );
    }

    fn graph_of(picture: &Picture) -> String {
        let arguments: Vec<String> = preview_arguments(Path::new("x"), picture)
            .iter()
            .map(|argument: &OsString| -> String { argument.to_string_lossy().into_owned() })
            .collect();
        let at: usize = arguments
            .iter()
            .position(|a: &String| -> bool { a == "-filter_complex" })
            .unwrap();
        arguments[at + 1].clone()
    }

    #[test]
    fn a_single_stream_is_scaled_then_turned_here() {
        let picture: Picture = Picture {
            stored: PixelSize {
                width: 3000,
                height: 1500,
            },
            orientation: Orientation::Rotate90Clockwise,
            input: PictureInput::Stream(0),
        };
        let graph: String = graph_of(&picture);
        assert!(graph.contains("s=2048x1024"));
        assert!(graph.contains("[0:0]scale=2048:1024:flags=area,format=rgba[picture]"));
        assert!(graph.ends_with(",format=rgb24,transpose=1[preview]"));
    }

    #[test]
    fn a_tile_grid_arrives_turned_so_it_is_only_scaled() {
        let picture: Picture = Picture {
            stored: PixelSize {
                width: 3000,
                height: 1500,
            },
            orientation: Orientation::Rotate90Clockwise,
            input: PictureInput::Group(2),
        };
        let graph: String = graph_of(&picture);
        assert!(graph.contains("s=1024x2048"));
        assert!(graph.contains("[0:g:2]scale=1024:2048:flags=area,format=rgba[picture]"));
        assert!(graph.ends_with(",format=rgb24[preview]"));
    }

    #[test]
    fn a_small_upright_picture_is_not_scaled() {
        let picture: Picture = Picture {
            stored: PixelSize {
                width: 60,
                height: 40,
            },
            orientation: Orientation::Upright,
            input: PictureInput::Stream(0),
        };
        let graph: String = graph_of(&picture);
        assert!(graph.contains("[0:0]format=rgba[picture]"));
        assert!(!graph.contains("scale="));
    }
}
