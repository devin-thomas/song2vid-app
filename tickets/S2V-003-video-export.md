# S2V-003 - Video export

Status: resolved
Blocked by: S2V-002

## Goal

Given an audio file, an image and a placement, write a correct MP4 with progress and cancel.

## Scope

- Read the audio and image (SPEC §7). Render the still frame. Write H.264 at 30 fps plus AAC audio (SPEC §6.3).
- Report progress. Support cancel. Delete the partial file on cancel or failure. Return plain error messages.

## Acceptance Criteria

- Integration tests (SPEC §11) pass: correct pixel size for each Frame Shape, length within ±0.1 s, both tracks present, and the file removed after cancel.
- Unreadable audio or image gives the SPEC §7 message.

## Dependencies

S2V-002.

## Comments

Implemented in Song2VidCore (`VideoExporter`, `ExportRequest`, `ExportOutcome`, `ExportError`, `AudioInfo`, `ImageInfo`) with 22 integration tests in `Song2VidIntegrationTests`. Implementation commit: 38b9e86.

How the window uses it (S2V-004, S2V-005): `AudioInfo.read(from:)` and `ImageInfo.read(from:)` check a chosen file (SPEC §7) and give the length and the oriented pixel size. `await VideoExporter.export(request, progress:)` returns `.completed(url)`, `.cancelled` or `.failed(error)`; cancel it by cancelling the task running it. `error.message` is the text to show. Progress comes from a background queue, so hop to the main actor before touching the UI.

Decisions on points the SPEC leaves open:
- SPEC §6.5 and §7 both name an audio read failure. A file that can't be read when it is first opened (or has no audio track) gives the §7 message; a read that breaks partway through gives "Couldn't read the audio file". The §6.5 messages are used as written, without a full stop.
- The video is the same still frame throughout, so it is encoded once for a ten-second group of frames and that group is repeated with new timestamps. This keeps a 4-minute song at 2160p to seconds and does not depend on how busy the hardware encoder is. The output is still 30 fps with a key frame every 10 seconds.
- The length is counted from the decoded audio, not read from the file header, because an MP3 header can estimate its length. The video has `ceil(length × 30)` frames and ends at the audio's end.
- Audio is decoded with AVAudioFile, not AVAssetReader, because the reader's decode path stalled for 90 seconds on this Mac.
- AAC keeps the source sample rate and its mono or stereo layout. Rates above 96 kHz or below 8 kHz are brought to the nearest rate the AAC encoder accepts, and more than two channels are mixed down to stereo.
- The file is written under a hidden name beside the destination and moved into place when complete, so a cancelled or failed export never damages a file the person agreed to replace.
- Placement edges are rounded to whole pixels when drawing, as S2V-002 left to this ticket.
