# S2V-032 - Windows: package, install and the installed check

Status: open
Blocked by: S2V-027, S2V-031

## Goal

Song2Vid for Windows is packaged, installs per user, and is checked as installed on both PCs (SPEC §29).

## Scope

- `pnpm package:win` on Titan with the real tool, FFmpeg, `SKILL.md` and `THIRD-PARTY-NOTICES.txt` staged; `pnpm fuses:check win32-x64`.
- `Install Song2Vid.cmd`, `Uninstall Song2Vid.cmd`, `README.txt` and the zip `Song2Vid-1.2.0-windows-x64.zip`.
- Installed check on the DeskMini through `scripts\run-as-user.ps1` with the foreground sampler running throughout: `list`, `helpers`, `launch` (no-activate, empty PATH), `memory`, `collect`, `quit`, `uninstall`.
- On Titan with the owner's go-ahead: install, make one video per Codec in the window with NVENC, uninstall.

## Acceptance Criteria

- The fuse wire and every probe pass on Windows.
- The installed check passes on the DeskMini with 0 second launches, helpers started with PATH empty, and the sampler recording no Song2Vid window in front.
- After the PATH line of SPEC §29, a new terminal runs `song2vid --version`, `encoders` and one `make` from a folder with a space and non-Latin text in its name.
- Uninstall removes the app and shortcut and leaves the data folder and videos.

## Dependencies

S2V-027, S2V-031.

## Comments
