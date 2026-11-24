# song2vid.exe

The Windows command (SPEC sections 14, 24 and 26, ADR-024, ADR-029). A Rust program that reads the
shared command line, answers everything that does not encode (`check`, `preview`, `-h -v -S -R -u`),
and runs the bundled FFmpeg and FFprobe as child processes. `make` and `encoders` are S2V-026 and
S2V-027: their options are read and checked here, and until then they answer with exit status 5.

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
| `src/check.rs`, `report.rs`, `preview.rs` | The commands |
| `src/media.rs`, `orientation.rs` | FFprobe and FFmpeg use: what a file is, its size after its tag, the preview graph |
| `src/process.rs`, `process/job.rs` | Children in a kill-on-close job object (SPEC 26.3) |
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

Dependencies: `serde_json` (FFprobe's JSON and the fixture file) and `windows-sys` (the calls above).
