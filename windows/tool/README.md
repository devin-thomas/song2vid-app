# song2vid.exe

The Windows command (SPEC sections 14, 24 and 26, ADR-024, ADR-029). A Rust program that reads the
shared command line, answers `check`, `preview` and `-h -v -S -R -u`, makes videos with `make`, and
runs the bundled FFmpeg and FFprobe as child processes. `make` encodes with Microsoft's software
H.264 encoder (S2V-026); the hardware encoders, the fallback and `encoders` are S2V-027, and until
then `encoders` answers with exit status 5.

Built for `x86_64-pc-windows-msvc` with a static C runtime (`.cargo/config.toml`). `build.rs`
embeds `song2vid.manifest` (UTF-8 active code page, long paths). Toolchain: Rust 1.97.1
(`windows/scripts/check.ps1` pins it with `cargo +1.97.1`); `rust-version` in `Cargo.toml` is the
oldest it is meant to build with.

```powershell
# On Windows, from this folder:
cargo +1.97.1 build --release --target x86_64-pc-windows-msvc
# Everything, with the Mac comparison (see parity/):
..\scripts\check.ps1 -Staging <folder with ffmpeg.exe and ffprobe.exe> -Bundle <parity bundle>
```

The pure logic (option table, frame math, report text, orientation, JSON) also builds and tests on
the Mac (`cargo test`), where the process tests run against a host FFmpeg named by
`SONG2VID_TEST_FFMPEG_DIR`. The Mac build is only a way to try the logic; nothing but the Windows
build ships.

## Layout

| Path | What it holds |
| --- | --- |
| `src/options.rs`, `make_options.rs` | The option table and parser; the `make` rules (SPEC 14.2, 24.1, 24.4) |
| `src/frame.rs` | Port of `OutputFrame`; proven against `fixtures/frame-math.json` in `tests/frame_math.rs` |
| `src/check.rs`, `report.rs`, `preview.rs` | `check` and `preview` |
| `src/make.rs`, `make_report.rs` | `make`: the checks in the Mac command's order, then the video, then one-step publication |
| `src/encode.rs`, `encoder.rs`, `audio_target.rs` | The three FFmpeg runs of `make`; which Encoder makes the Codec (the seam for S2V-027); the AAC rate, channel and bit rate rules (the Mac's table) |
| `src/progress.rs`, `console.rs` | Headed, plain and JSON progress with the S2V-013 timings; standard output and error, and virtual terminal sequences |
| `src/media.rs`, `orientation.rs` | FFprobe and FFmpeg use: what a file is, its size after its tag, the preview graph |
| `src/process.rs`, `process/job.rs` | Children in a kill-on-close job object (SPEC 26.3), with their standard output handed on while they run |
| `src/destination.rs` | Temporary file, one-step publish, `output_exists`, `output_in_use` |
| `src/help/*.txt` | The Mac command's help, byte for byte |
| `parity/` | Media and the Mac command's recorded answers, for `check.ps1` |

## Where `unsafe` is used (RS025, RS026)

Application logic is safe Rust: the crate denies `unsafe_code`, and four modules allow it for one
reason each, with a `SAFETY` note on every block.

| Module | Why |
| --- | --- |
| `process/job.rs` | `CreateProcessW` with a handle list, a job object with kill-on-close, `CREATE_SUSPENDED`. `std::process` cannot hand back the suspended thread, and SPEC 26.3 requires the child to enter the job before it runs |
| `destination.rs` (Windows part) | `MoveFileExW` without the replace flag (SPEC 26.3), a directory open that tests write access without creating a file, file identity, the system random generator |
| `http.rs` (Windows part) | WinHTTP for `--update`, which keeps the program to Windows' own DLLs |
| `cancel.rs` (Windows part) | `SetConsoleCtrlHandler` for Ctrl-C and Ctrl-Break |
| `console.rs` (Windows part) | `SetConsoleMode` to turn virtual terminal sequences on for the live line (and back off at the end), and the console width |

Dependencies: `serde_json` (FFprobe's JSON and the fixture file) and `windows-sys` (the calls above).

## How `make` makes a video (SPEC 6.3, 26.3)

The picture never changes, so the video is not encoded frame by frame. Like the Mac's `StillEncoder`
it takes three runs of FFmpeg, each in its own job object:

1. **Still**: the picture is turned upright, scaled to the Output Frame's placement (whole-pixel
   edges, as the Mac draws it) and laid on black, so bars and transparent areas are black. One PNG.
2. **Group**: the still is encoded as at most 300 frames (10 seconds): one key frame, then frames
   that only repeat it, by the chosen Encoder (`encoder.rs`). RGB becomes limited-range BT.709 in
   the `scale` filter, which also puts the BT.709 primaries and transfer on the frames, so the
   stream and the MP4 carry the tags.
3. **Mux**: the group is repeated for the song's length with `-stream_loop -1 -c:v copy`, and the
   song is encoded as AAC beside it (`audio_target.rs`). FFmpeg's `-progress` output gives the
   percent. The tool's own tags (title, artist, a cover picture) are not copied.

The three files (still, group, output) are hidden `.song2vid-<32 hex>...tmp` files beside the final
name, removed on every way out (success, failure, cancel). A run killed from outside cannot clean up:
its FFmpeg child dies with it, but those files stay.

Environment variables the command reads: `SONG2VID_UPDATE_URL` (`--update`, tests), `SONG2VID_TEST_ENCODER`
(`nvenc`, `media_foundation` or `software`: forces one Encoder, tests only), `NO_COLOR` and `TERM=dumb`
(the live line's colour and line clearing). Nothing else in the environment is looked at.
