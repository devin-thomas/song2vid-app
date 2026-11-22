# Phase 3 proof: a new agent uses the installed command (S2V-018)

The check that an agent which has never seen this project can use `song2vid` from the release and report real values. The owner runs it; the coordinator checks the answer against the command's own output.

## Setup (once, outside this repo)

1. Download Song2Vid 1.1.0 from https://song2vid.pages.dev, move it to Applications and approve it with **Open Anyway** (System Settings → Privacy & Security).
2. Link the command and make two small test files in a scratch folder:

```bash
mkdir -p ~/.local/bin
ln -sf /Applications/Song2Vid.app/Contents/Helpers/song2vid ~/.local/bin/song2vid
mkdir -p ~/song2vid-proof && cd ~/song2vid-proof
ffmpeg -v error -y -f lavfi -i "sine=frequency=330:duration=12" -ar 44100 -ac 2 tone.wav
ffmpeg -v error -y -f lavfi -i testsrc2=size=800x600:rate=1 -frames:v 1 cover.png
song2vid --version
```

3. Open a new Claude Code session in `~/song2vid-proof`, not in this repo.

## The prompt

```text
Use Song2Vid to make a video from my song and image. Instructions: https://song2vid.pages.dev/agent.md

Files: tone.wav and cover.png in this folder. Please:
1. Run a check on the two files and tell me the song's length and the image's size.
2. Make a square (1:1) 480p video named square.mp4.
3. Then run the same make command once more with an image called missing.png (output failing.mp4), and tell me exactly what happened.
Report only what the command printed.
```

## What the answer must contain

| Step | Real values |
| --- | --- |
| check | song 12.0 seconds, 44100 Hz, 2 channels; image 800×600 |
| make | exit 0; `square.mp4`, 480×480, 12.0 seconds, `placement` crop, `enlarged` false, a byte count that matches `ls -l square.mp4` |
| failing make | exit status **1**, error code **`image_not_found`**, message "The image file was not found." |

The coordinator then runs `song2vid check tone.wav cover.png --json` and `ffprobe square.mp4` itself and compares. The agent must not invent a value, and `failing.mp4` must not exist.

## Recording the result

When the owner confirms, the Starter Pack progress record's `agent-cli` step gets the short verification object (what was run, the agent's reported values, and that they matched).
