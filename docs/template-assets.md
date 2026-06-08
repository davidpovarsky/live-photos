# Template Assets

The lock-screen capable `.livp` path needs a neutral Live Photo metadata template:

- one still image template, used only as an ImageIO metadata source
- one MOV template, used as the source of metadata tracks

This repository intentionally does not publish template media files. Use assets you own, created yourself, or are explicitly licensed to redistribute.

## Expected Default Paths

By default, `scripts/make-livp.sh` looks for:

```text
vendor-livp/IMB_ZyUbrU.HEIC.heic
vendor-livp/IMB_ZyUbrU.HEIC.mov
```

The names are defaults for local compatibility with the existing script. They are not special to the algorithm.

You can also pass template paths with environment variables:

```bash
LIVEPHOTO_TEMPLATE_PHOTO=/absolute/path/template.heic \
LIVEPHOTO_TEMPLATE_VIDEO=/absolute/path/template.mov \
./scripts/make-livp.sh input.mp4 output.livp
```

## What The Template Must Provide

Still image template:

- A readable HEIC/JPEG image.
- Image metadata that can be copied by ImageIO.
- The packager will replace `MakerApple[17]` with a fresh asset identifier.

MOV template:

- A QuickTime/MOV file with metadata tracks compatible with the output format.
- For the currently verified path, the useful template shape is:
  - vertical `1080x1920`
  - `1.0s`
  - `60fps`
  - HEVC `hvc1`
  - neutral `mebx` metadata tracks
  - still-image time around `0.5s`

The packager copies metadata tracks when `--preserve-input-metadata-tracks` is set.

## Inspecting A Candidate Template

Use these tools before using a template:

```bash
./tools/dump-mov-boxes.js /path/to/template.mov
./tools/dump-mebx-samples.js /path/to/template.mov
```

Look for metadata tracks with `mebx` sample entries and Live Photo related strings such as:

```text
com.apple.quicktime.live-photo-info
com.apple.quicktime.still-image-time
```

You can also export likely `live-photo-info` samples:

```bash
./tools/export-live-photo-info-csv.js /path/to/template.mov .tmp/live-photo-info.csv
```

## Publishing Guidance

For an open-source repository:

- Commit this README.
- Do not commit private `.livp`, `.heic`, `.mov`, or extracted vendor media unless redistribution is allowed.
- Document how users can provide their own templates.
- Keep generated `.livp` outputs out of git.

The repository `.gitignore` ignores `vendor-livp/*` while allowing `vendor-livp/README.md`.
