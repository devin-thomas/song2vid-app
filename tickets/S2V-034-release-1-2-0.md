# S2V-034 - Release 1.2.0 and the proofs

Status: open
Blocked by: S2V-033

## Goal

Song2Vid 1.2.0 is public for Mac and Windows and proven by a clean install and fresh agents (SPEC §31, §32).

## Scope

- Mac zip (universal, ad hoc signed) and Windows zip with SHA-256 sums; release notes with the unverified list.
- Merge, tag, publish the release, deploy the site from this repo.
- Release check on the DeskMini under a Windows user that never had Song2Vid, with the foreground sampler; the Mac release check of section 18.
- Windows agent proof on Titan; the separate-agent site proof with the new fact.

## Acceptance Criteria

- The live page's Windows download installs and makes a video on the clean DeskMini user, and the command works from PATH.
- The Mac download passes the section 18 release check at 1.2.0.
- The Windows agent proof reports real values, exit status 1 and `image_not_found` for the failing run; the owner confirms.
- The site proof answers 1.2.0 with both requirements and cites `/`.
- `--update` on a 1.1.0 Mac command reports 1.2.0 available.

## Dependencies

S2V-033.

## Comments
