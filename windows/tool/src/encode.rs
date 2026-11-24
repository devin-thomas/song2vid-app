//! Making the video with FFmpeg (SPEC sections 6.3, 26.2 and 26.3).
//!
//! The picture never changes, so the video is not encoded frame by frame. Like the Mac's
//! `StillEncoder` it is made in three runs of FFmpeg:
//!
//! 1. **Still.** The picture is placed in the frame (orientation turned, transparency made black,
//!    scaled to the Output Frame's placement, bars or crop) and written once as a PNG.
//! 2. **Group.** The still is encoded as one group of at most 300 frames (10 seconds): a key
//!    frame, then frames that repeat it. The Encoder is the one the command chose.
//! 3. **Mux.** The group is repeated for the length of the song without being encoded again, and
//!    the song is encoded as AAC beside it. FFmpeg's progress output gives the percent.
//!
//! So encoding costs the same for a 30-second song and a four-minute one, and does not depend on
//! how busy the hardware encoder is.

use std::ffi::OsString;
use std::path::Path;
use std::time::Duration;

use crate::audio_target::AudioTarget;
use crate::cancel::CancelToken;
use crate::encoder::{Encoder, GROUP_LENGTH};
use crate::frame::OutputFrame;
use crate::make_options::Codec;
use crate::media::{AudioStream, Picture, PictureInput};
use crate::process::{run_tool_streaming, RunError, RunLimits, ToolRun, Tools};

/// The video frame rate (SPEC section 6.3).
pub const FRAMES_PER_SECOND: i64 = 30;

/// A run that does not finish in this long is stopped; these only catch a hung program.
const STILL_TIMEOUT: Duration = Duration::from_secs(600);
const GROUP_TIMEOUT: Duration = Duration::from_secs(1800);
const MUX_TIMEOUT: Duration = Duration::from_secs(3 * 3600);
/// FFmpeg's progress lines are short; this only bounds what is kept of them.
const PROGRESS_KEEP: usize = 64 * 1024;

/// Everything the three runs need to know.
pub struct Job<'a> {
    pub tools: &'a Tools,
    /// The picture, as a path FFmpeg opens.
    pub picture_path: &'a Path,
    pub picture: &'a Picture,
    /// The song, as a path FFmpeg opens.
    pub audio_path: &'a Path,
    pub audio: &'a AudioStream,
    pub frame: &'a OutputFrame,
    pub codec: Codec,
    pub encoder: Encoder,
}

/// Where the runs write. All three are beside the final name and are removed by their owners.
pub struct Files<'a> {
    pub still: &'a Path,
    pub group: &'a Path,
    pub output: &'a Path,
}

/// Why the video was not made.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Failure {
    Cancelled,
    ToolsMissing,
    DiskFull,
    /// FFmpeg could not make it.
    Failed,
}

/// The frames the video has: one per 1/30 second, enough to cover the whole song.
pub fn frame_count(audio: &AudioStream) -> i64 {
    ((audio.duration * FRAMES_PER_SECOND as f64).ceil() as i64).max(1)
}

fn words(list: &[&str]) -> Vec<OsString> {
    list.iter()
        .map(|word: &&str| -> OsString { OsString::from(*word) })
        .collect()
}

/// The filter graph that places the picture in the frame: black underneath (the bars, and what
/// transparent areas become), the picture turned upright and scaled to its placement, and drawn
/// at whole-pixel edges as the Mac does.
pub fn still_graph(picture: &Picture, frame: &OutputFrame) -> String {
    let placement = frame.image_placement;
    let left: i64 = placement.x.round() as i64;
    let right: i64 = (placement.x + placement.width).round() as i64;
    let top: i64 = placement.y.round() as i64;
    let bottom: i64 = (placement.y + placement.height).round() as i64;
    let width: i64 = (right - left).max(1);
    let height: i64 = (bottom - top).max(1);
    let source: String = match picture.input {
        PictureInput::Stream(index) => format!("[0:{index}]"),
        PictureInput::Group(index) => format!("[0:g:{index}]"),
    };
    // FFmpeg turns a tile grid upright by itself, whatever `-noautorotate` says; a single stream
    // is left alone and turned here.
    let turn: String = match (picture.input, picture.orientation.filter()) {
        (PictureInput::Stream(_), Some(filters)) => format!("{filters},"),
        _ => String::new(),
    };
    format!(
        "color=c=black:s={frame_width}x{frame_height}:r=1:d=1,format=rgba[ground];\
         {source}{turn}scale={width}:{height}:flags=lanczos,format=rgba[picture];\
         [ground][picture]overlay=x={left}:y={top}:shortest=1:format=auto,format=rgb24[still]",
        frame_width = frame.size.width,
        frame_height = frame.size.height,
    )
}

/// Run 1: the picture placed in the frame, written as one PNG.
pub fn still_arguments(job: &Job, still: &Path) -> Vec<OsString> {
    let mut arguments: Vec<OsString> = words(&["-hide_banner", "-v", "error", "-nostdin", "-y"]);
    arguments.extend(words(&["-noautorotate", "-i"]));
    arguments.push(job.picture_path.as_os_str().to_os_string());
    arguments.extend(words(&["-filter_complex"]));
    arguments.push(OsString::from(still_graph(job.picture, job.frame)));
    arguments.extend(words(&[
        "-map",
        "[still]",
        "-frames:v",
        "1",
        "-c:v",
        "png",
        "-f",
        "image2",
        "-update",
        "1",
    ]));
    arguments.push(still.as_os_str().to_os_string());
    arguments
}

/// The conversion from the picture's RGB to the video's colours: limited range, BT.709 matrix,
/// primaries and transfer, written into the frames so the stream and the file carry the tags.
const COLOUR_FILTER: &str = "scale=in_range=full:out_range=tv:out_color_matrix=bt709:\
out_primaries=bt709:out_transfer=bt709:flags=accurate_rnd+full_chroma_int,format=yuv420p";

/// Run 2: the still, repeated for one group of frames and encoded by the chosen Encoder. None
/// when that Encoder can't make the Codec.
pub fn group_arguments(job: &Job, still: &Path, group: &Path) -> Option<Vec<OsString>> {
    let video: Vec<OsString> = job.encoder.video_arguments(job.codec)?;
    let frames: i64 = frame_count(job.audio).min(GROUP_LENGTH);
    let mut arguments: Vec<OsString> = words(&["-hide_banner", "-v", "error", "-nostdin", "-y"]);
    // The picture is one file, never a numbered sequence, whatever its folder is called.
    arguments.extend(words(&[
        "-f",
        "image2",
        "-pattern_type",
        "none",
        "-loop",
        "1",
        "-framerate",
    ]));
    arguments.push(OsString::from(FRAMES_PER_SECOND.to_string()));
    arguments.push(OsString::from("-i"));
    arguments.push(still.as_os_str().to_os_string());
    arguments.extend(words(&["-vf", COLOUR_FILTER, "-frames:v"]));
    arguments.push(OsString::from(frames.to_string()));
    arguments.extend(video);
    arguments.extend(words(&["-f", "mp4"]));
    arguments.push(group.as_os_str().to_os_string());
    Some(arguments)
}

/// Run 3: the group repeated for the length of the song, and the song as AAC.
pub fn mux_arguments(job: &Job, group: &Path, output: &Path) -> Vec<OsString> {
    let target: AudioTarget = AudioTarget::for_song(job.audio);
    let mut arguments: Vec<OsString> = words(&[
        "-hide_banner",
        "-v",
        "error",
        "-nostdin",
        "-y",
        "-progress",
        "pipe:1",
        "-nostats",
        "-stream_loop",
        "-1",
        "-i",
    ]);
    arguments.push(group.as_os_str().to_os_string());
    arguments.push(OsString::from("-i"));
    arguments.push(job.audio_path.as_os_str().to_os_string());
    // Nothing the song's tags say (a title, an artist, a cover picture) goes into the video.
    arguments.extend(words(&[
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-map_metadata",
        "-1",
        "-map_chapters",
        "-1",
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-b:a",
    ]));
    arguments.push(OsString::from(target.bit_rate.to_string()));
    arguments.push(OsString::from("-ar"));
    arguments.push(OsString::from(target.sample_rate.to_string()));
    arguments.push(OsString::from("-ac"));
    arguments.push(OsString::from(target.channels.to_string()));
    // The video is as long as the song.
    arguments.push(OsString::from("-t"));
    arguments.push(OsString::from(format!("{:.6}", job.audio.duration)));
    arguments.extend(words(&["-movflags", "+faststart", "-f", "mp4"]));
    arguments.push(output.as_os_str().to_os_string());
    arguments
}

/// Reads FFmpeg's `-progress` output as it arrives and says how far along the song it is.
#[derive(Debug)]
pub struct ProgressReader {
    pending: Vec<u8>,
    seconds: f64,
    length: f64,
}

impl ProgressReader {
    pub fn new(length: f64) -> ProgressReader {
        ProgressReader {
            pending: Vec::new(),
            seconds: 0.0,
            length,
        }
    }

    /// Takes the next bytes. Returns the fraction done (0 to 1) whenever a block of progress
    /// lines ends, which FFmpeg marks with a `progress=` line.
    pub fn feed(&mut self, bytes: &[u8]) -> Option<f64> {
        self.pending.extend_from_slice(bytes);
        let mut report: Option<f64> = None;
        while let Some(end) = self
            .pending
            .iter()
            .position(|byte: &u8| -> bool { *byte == b'\n' })
        {
            let line: Vec<u8> = self.pending.drain(..=end).collect();
            let text: String = String::from_utf8_lossy(&line).trim().to_string();
            if let Some(value) = text.strip_prefix("out_time_us=") {
                if let Ok(microseconds) = value.parse::<i64>() {
                    self.seconds = (microseconds.max(0) as f64) / 1_000_000.0;
                }
            } else if text.starts_with("progress=") && self.length > 0.0 {
                report = Some((self.seconds / self.length).clamp(0.0, 1.0));
            }
        }
        // A line that never ends can't grow without limit.
        if self.pending.len() > PROGRESS_KEEP {
            self.pending.clear();
        }
        report
    }
}

/// Makes the video. `on_fraction` is called with the song's progress (0 to 1) during the last
/// run. Everything FFmpeg wrote is thrown away except what tells a full disk from another failure.
pub fn make(
    job: &Job,
    files: &Files,
    cancel: &CancelToken,
    on_fraction: &mut dyn FnMut(f64),
) -> Result<(), Failure> {
    let limits = |timeout: Duration| -> RunLimits {
        RunLimits {
            timeout,
            max_stdout: PROGRESS_KEEP,
        }
    };

    let still: Vec<OsString> = still_arguments(job, files.still);
    check(
        run_tool_streaming(
            &job.tools.ffmpeg,
            &still,
            limits(STILL_TIMEOUT),
            cancel,
            None,
        ),
        cancel,
    )?;

    let group: Vec<OsString> =
        group_arguments(job, files.still, files.group).ok_or(Failure::Failed)?;
    check(
        run_tool_streaming(
            &job.tools.ffmpeg,
            &group,
            limits(GROUP_TIMEOUT),
            cancel,
            None,
        ),
        cancel,
    )?;

    let mux: Vec<OsString> = mux_arguments(job, files.group, files.output);
    let mut reader: ProgressReader = ProgressReader::new(job.audio.duration);
    let mut sink = |bytes: &[u8]| -> () {
        if let Some(fraction) = reader.feed(bytes) {
            on_fraction(fraction);
        }
    };
    check(
        run_tool_streaming(
            &job.tools.ffmpeg,
            &mux,
            limits(MUX_TIMEOUT),
            cancel,
            Some(&mut sink),
        ),
        cancel,
    )?;

    // FFmpeg said it succeeded; a file that is not there or is empty is a failure all the same.
    match std::fs::metadata(files.output) {
        Ok(found) if found.len() > 0 => Ok(()),
        _ => Err(Failure::Failed),
    }
}

/// Turns what a run of FFmpeg left into success or the reason it failed.
fn check(run: Result<ToolRun, RunError>, cancel: &CancelToken) -> Result<(), Failure> {
    match run {
        Err(RunError::Cancelled) => Err(Failure::Cancelled),
        Err(RunError::CouldNotStart) => Err(Failure::ToolsMissing),
        Err(RunError::TimedOut | RunError::TooMuchOutput) => Err(Failure::Failed),
        Ok(finished) if finished.exit_code == 0 => {
            if cancel.is_requested() {
                Err(Failure::Cancelled)
            } else {
                Ok(())
            }
        }
        Ok(finished) => {
            if cancel.is_requested() {
                Err(Failure::Cancelled)
            } else if says_disk_full(&finished.stderr_tail) {
                Err(Failure::DiskFull)
            } else {
                Err(Failure::Failed)
            }
        }
    }
}

/// True when the end of FFmpeg's standard error says the disk is full.
fn says_disk_full(tail: &[u8]) -> bool {
    String::from_utf8_lossy(tail)
        .to_lowercase()
        .contains("no space left on device")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{CropPosition, FrameShape, PixelSize, Resolution};
    use crate::orientation::Orientation;
    use std::path::PathBuf;

    fn picture(width: i64, height: i64, orientation: Orientation, input: PictureInput) -> Picture {
        Picture {
            stored: PixelSize { width, height },
            orientation,
            input,
        }
    }

    fn frame_for(picture: &Picture, shape: FrameShape, resolution: Resolution) -> OutputFrame {
        OutputFrame::new(picture.size(), shape, resolution, CropPosition::CENTER).unwrap()
    }

    fn song(duration: f64, sample_rate: i64, channels: i64) -> AudioStream {
        AudioStream {
            duration,
            sample_rate,
            channels,
            time_base: (1, sample_rate),
            declared_frames: None,
            exact_in_container: true,
        }
    }

    fn texts(arguments: &[OsString]) -> Vec<String> {
        arguments
            .iter()
            .map(|argument: &OsString| -> String { argument.to_string_lossy().into_owned() })
            .collect()
    }

    #[test]
    fn the_frame_count_covers_the_song() {
        assert_eq!(frame_count(&song(144.0, 44_100, 2)), 4320);
        assert_eq!(frame_count(&song(1.01, 44_100, 2)), 31);
        assert_eq!(frame_count(&song(0.0, 44_100, 2)), 1);
    }

    #[test]
    fn fit_with_bars_draws_the_picture_at_whole_pixel_edges_inside_the_frame() {
        let source: Picture = picture(1000, 800, Orientation::Upright, PictureInput::Stream(0));
        let frame: OutputFrame = frame_for(&source, FrameShape::SixteenByNine, Resolution::P1080);
        let graph: String = still_graph(&source, &frame);
        assert!(graph.starts_with("color=c=black:s=1920x1080:r=1:d=1,format=rgba[ground];"));
        assert!(graph.contains("[0:0]scale=1350:1080:flags=lanczos,format=rgba[picture]"));
        assert!(graph.contains("overlay=x=285:y=0:shortest=1:format=auto,format=rgb24[still]"));
    }

    #[test]
    fn crop_draws_a_larger_picture_from_a_negative_corner() {
        let source: Picture = picture(1000, 800, Orientation::Upright, PictureInput::Stream(0));
        let frame: OutputFrame = frame_for(&source, FrameShape::OneByOne, Resolution::P480);
        let graph: String = still_graph(&source, &frame);
        assert!(graph.contains("scale=600:480"), "{graph}");
        assert!(graph.contains("overlay=x=-60:y=0"), "{graph}");
    }

    #[test]
    fn a_turned_picture_is_turned_before_it_is_scaled() {
        let source: Picture = picture(
            800,
            1000,
            Orientation::Rotate90Clockwise,
            PictureInput::Stream(2),
        );
        let frame: OutputFrame = frame_for(&source, FrameShape::SixteenByNine, Resolution::P480);
        let graph: String = still_graph(&source, &frame);
        assert!(graph.contains("[0:2]transpose=1,scale="), "{graph}");
    }

    #[test]
    fn a_tile_grid_is_not_turned_again() {
        let source: Picture = picture(
            800,
            1000,
            Orientation::Rotate90Clockwise,
            PictureInput::Group(0),
        );
        let frame: OutputFrame = frame_for(&source, FrameShape::SixteenByNine, Resolution::P480);
        let graph: String = still_graph(&source, &frame);
        assert!(graph.contains("[0:g:0]scale="), "{graph}");
        assert!(!graph.contains("transpose"));
    }

    fn job_parts() -> (Tools, Picture, AudioStream, OutputFrame) {
        let source: Picture = picture(1000, 800, Orientation::Upright, PictureInput::Stream(0));
        let frame: OutputFrame = frame_for(&source, FrameShape::SixteenByNine, Resolution::P1080);
        (
            Tools {
                ffmpeg: PathBuf::from("ffmpeg"),
                ffprobe: PathBuf::from("ffprobe"),
            },
            source,
            song(144.0, 48_000, 2),
            frame,
        )
    }

    #[test]
    fn the_group_is_300_frames_of_the_still_with_the_colour_tags() {
        let (tools, source, audio, frame) = job_parts();
        let job: Job = Job {
            tools: &tools,
            picture_path: Path::new("picture.png"),
            picture: &source,
            audio_path: Path::new("song.wav"),
            audio: &audio,
            frame: &frame,
            codec: Codec::H264,
            encoder: Encoder::Software,
        };
        let words: Vec<String> =
            texts(&group_arguments(&job, Path::new("still.png"), Path::new("group.mp4")).unwrap());
        let joined: String = words.join(" ");
        assert!(
            joined.contains("-loop 1 -framerate 30 -i still.png"),
            "{joined}"
        );
        assert!(joined.contains("-frames:v 300 "));
        assert!(joined.contains("out_color_matrix=bt709"));
        assert!(joined.contains("out_primaries=bt709"));
        assert!(joined.contains("out_transfer=bt709"));
        assert!(joined.contains("out_range=tv"));
        assert!(joined.contains("-c:v h264_mf -profile:v 100 -g 300 -bf 0"));
        assert!(joined.ends_with("-f mp4 group.mp4"));

        // A song under ten seconds needs fewer frames than a group.
        let short: AudioStream = song(2.0, 44_100, 2);
        let short_job: Job = Job {
            audio: &short,
            ..job
        };
        let words: Vec<String> = texts(
            &group_arguments(&short_job, Path::new("still.png"), Path::new("group.mp4")).unwrap(),
        );
        assert!(words.join(" ").contains("-frames:v 60 "));
    }

    #[test]
    fn a_codec_the_encoder_cannot_make_has_no_group() {
        let (tools, source, audio, frame) = job_parts();
        let job: Job = Job {
            tools: &tools,
            picture_path: Path::new("picture.png"),
            picture: &source,
            audio_path: Path::new("song.wav"),
            audio: &audio,
            frame: &frame,
            codec: Codec::Hevc,
            encoder: Encoder::Software,
        };
        assert!(group_arguments(&job, Path::new("a"), Path::new("b")).is_none());
    }

    #[test]
    fn the_mux_repeats_the_group_for_the_length_of_the_song_and_writes_aac() {
        let (tools, source, _audio, frame) = job_parts();
        let audio: AudioStream = song(37.5, 37_800, 6);
        let job: Job = Job {
            tools: &tools,
            picture_path: Path::new("picture.png"),
            picture: &source,
            audio_path: Path::new("song.flac"),
            audio: &audio,
            frame: &frame,
            codec: Codec::H264,
            encoder: Encoder::Software,
        };
        let joined: String = texts(&mux_arguments(
            &job,
            Path::new("group.mp4"),
            Path::new("out.tmp"),
        ))
        .join(" ");
        assert!(
            joined.contains("-stream_loop -1 -i group.mp4 -i song.flac"),
            "{joined}"
        );
        assert!(
            joined.contains("-c:v copy -c:a aac -b:a 256000 -ar 44100 -ac 2"),
            "{joined}"
        );
        assert!(joined.contains("-t 37.500000"));
        assert!(joined.contains("-map_metadata -1"));
        assert!(joined.ends_with("-movflags +faststart -f mp4 out.tmp"));
    }

    #[test]
    fn progress_is_read_from_blocks_that_end_with_a_progress_line() {
        let mut reader: ProgressReader = ProgressReader::new(10.0);
        assert_eq!(reader.feed(b"frame=10\nout_time_us=2500000\nout_ti"), None);
        assert_eq!(reader.feed(b"me=00:00:02\nprogress=continue\n"), Some(0.25));
        assert_eq!(
            reader.feed(b"out_time_us=10500000\nprogress=end\n"),
            Some(1.0)
        );
        // Windows line ends and a negative start (FFmpeg writes N/A or a small negative first).
        let mut crlf: ProgressReader = ProgressReader::new(4.0);
        assert_eq!(
            crlf.feed(b"out_time_us=-1000\r\nprogress=continue\r\n"),
            Some(0.0)
        );
        assert_eq!(
            crlf.feed(b"out_time_us=N/A\r\nprogress=continue\r\n"),
            Some(0.0)
        );
    }

    #[test]
    fn a_full_disk_is_told_from_another_failure() {
        assert!(says_disk_full(
            b"av_interleaved_write_frame(): No space left on device\n"
        ));
        assert!(!says_disk_full(b"Invalid argument\n"));
    }
}
