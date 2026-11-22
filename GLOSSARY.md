# Glossary

**Frame Shape**: The proportions of the output video: 16:9, 9:16, 1:1, 4:3, or Original.
_Avoid_: aspect, ratio, format, layout

**Original**: The Frame Shape that uses the image's own exact pixel dimensions.
_Avoid_: native, source size

**Resolution**: The size tier of the output video, named by the pixel count of the frame's short side: 480p, 1080p, or 2160p.
_Avoid_: quality, size

**Fit with bars**: Placing the whole image inside the frame, scaled to fit, with black bars filling the uncovered area. Used by 16:9 and 9:16.
_Avoid_: letterbox, pillarbox, pad

**Crop**: Filling the frame with the image and discarding the parts outside it. Used by 1:1 and 4:3. The person chooses which part is kept.
_Avoid_: trim, cut

**Agent Guide**: The public Markdown instructions at `song2vid.pages.dev/agent.md` that tell an agent how to install and use the `song2vid` command. The same text is the repo's agent skill.
_Avoid_: agent docs, llms file

**Agent Handoff**: The control on the download page that gives a short prompt, pointing at the Agent Guide, to copy into a named agent.
_Avoid_: agent button, prompt widget

**Headed**: A run of the `song2vid` command whose error output is an interactive terminal, so it can draw a live progress bar.
_Avoid_: interactive mode, TTY mode

**Headless**: A run of the `song2vid` command whose output goes to a program, an agent or a file rather than a terminal.
_Avoid_: batch mode, non-interactive
