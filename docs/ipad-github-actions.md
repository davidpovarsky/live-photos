# iPad-only GitHub Action

This fork adds a cloud workflow that converts a video into a template-backed
`.livp` using a GitHub-hosted macOS runner. No local Mac is required.

## One-time setup

The full intoLive HEIC/MOV pair is **not** stored in this public repository.
Only its compact neutral `mebx` metadata template is needed at runtime.

Create this Actions secret:

`LIVEPHOTO_NEUTRAL_TEMPLATE_GZ_B64`

The value is a gzip-compressed, Base64-encoded compact MOV containing only the
neutral metadata tracks. The source media itself is not placed in Git.

Path in GitHub:

**Settings -> Secrets and variables -> Actions -> New repository secret**

## Create a Live Photo from iPad/iPhone

1. Upload the source video to Google Drive or Dropbox.
2. Create a share link that the GitHub runner can download.
3. Open **Actions -> Create iPhone Live Photo -> Run workflow**.
4. Paste the link into **video_url**.
5. Optionally choose an output name.
6. Run the workflow.
7. When it finishes, download the artifact.
8. Unzip the artifact ZIP; inside is the generated `.livp`.

Ordinary direct HTTPS video links are also accepted.

## Current lock-screen profile

The first version intentionally follows the project's verified fixed profile:

- 1080x1920
- 1.0 second
- 60 fps
- HEVC / `hvc1`
- silent AAC
- cover at 0.5 seconds
- neutral `mebx` metadata tracks

The source video is looped if shorter than one second and center-cropped to
fill the vertical frame.

## Regenerating the compact secret

If the neutral template is ever replaced, run:

`python3 tools/compact-live-photo-template.py TEMPLATE.mov compact-template.mov`

Then gzip and Base64 encode `compact-template.mov` and store the result in
`LIVEPHOTO_NEUTRAL_TEMPLATE_GZ_B64`.
