# Live Photo Generation Guide

This document explains the reusable technical path in this repository.

The project generates two related outputs:

- A Live Photo resource pair: one still image plus one MOV.
- A `.livp` package: a ZIP-like container used by some iOS import flows.

The lock-screen capable path currently depends on a neutral metadata template. The repository does not publish template media files. See [template-assets.md](template-assets.md).

## Pipeline

```text
input video
  -> normalize to 1080x1920, 1 second, 60 fps, HEVC hvc1
  -> add silent AAC audio
  -> extract still frame at 0.5s
  -> write MakerApple[17] into the still image
  -> write QuickTime content.identifier into the MOV
  -> copy neutral mebx metadata tracks from a template MOV
  -> output HEIC + MOV
  -> package as .livp with compatible internal names and ZIP comment
```

The all-in-one command is:

```bash
./scripts/make-livp.sh input.mp4 output.livp
```

## Why Basic Metadata Is Not Enough

A minimal Live Photo pair only needs:

- Still image: `MakerApple[17] = UUID`
- MOV: `com.apple.quicktime.content.identifier = UUID`
- MOV: `com.apple.quicktime.still-image-time`

That pair can be previewed as a Live Photo in Photos, but the iPhone lock screen can reject it. The current successful path also includes neutral `mebx` metadata tracks compatible with a fixed 1 second / 60 fps vertical video.

## Swift Packager

The Swift executable is defined in [Sources/LivePhotoPackager/main.swift](../Sources/LivePhotoPackager/main.swift).

Useful functions:

- `writePhoto(...)`: reads the input still image, optionally copies metadata from a template image, and writes `MakerApple[17]`.
- `writeVideo(...)`: copies video/audio tracks, writes QuickTime metadata, and either creates a basic `still-image-time` track or copies metadata tracks from a template MOV.
- `videoMetadataItems(...)`: writes the content identifier and related QuickTime tags.
- `copySamples(...)`: streams samples from `AVAssetReader` to `AVAssetWriter`.

Basic resource pair:

```bash
swift run livephoto-packager \
  --photo Samples/sample.jpg \
  --video Samples/sample.mov \
  --out .tmp/basic
```

Template-backed resource pair:

```bash
swift run livephoto-packager \
  --photo cover.jpg \
  --template-photo-metadata vendor-livp/IMB_ZyUbrU.HEIC.heic \
  --video normalized.mov \
  --template-video vendor-livp/IMB_ZyUbrU.HEIC.mov \
  --out .tmp/pair \
  --photo-format heic \
  --preserve-input-metadata-tracks
```

## `.livp` Packaging

The `.livp` output is created by [scripts/make-livp.sh](../scripts/make-livp.sh).

Current fixed output:

- `1080x1920`
- `1.0s`
- `60fps`
- `HEVC hvc1` MOV
- silent AAC audio
- cover frame at `0.5s`
- HEIC still image

The package step uses:

```bash
zip -0 -X output.livp IMB_xxxxxxxx.HEIC.heic IMB_xxxxxxxx.HEIC.mov
node tools/set-livp-zip-comment.js output.livp
```

[tools/set-livp-zip-comment.js](../tools/set-livp-zip-comment.js) writes a ZIP comment containing the HEIC/MOV local-entry offsets and sizes:

```text
0002 + HEIC data offset + HEIC size
0003 + MOV data offset + MOV size
313030304C495650
```

## Validation

Check the generated resource pair:

```bash
./scripts/verify-metadata.sh .tmp/pair/live-photo.heic .tmp/pair/live-photo.mov
```

Inspect MOV metadata tracks:

```bash
./tools/dump-mov-boxes.js vendor-livp/IMB_ZyUbrU.HEIC.mov
./tools/dump-mebx-samples.js vendor-livp/IMB_ZyUbrU.HEIC.mov
./tools/export-live-photo-info-csv.js vendor-livp/IMB_ZyUbrU.HEIC.mov .tmp/live-photo-info.csv
```

Final compatibility still needs device testing. At minimum, test:

- iOS Photos preview.
- Save/import path that your users will use.
- Lock-screen wallpaper dynamic effect.
- More than one iPhone and iOS version when possible.

## Known Limits

- The lock-screen compatible path is verified only for the fixed 1 second / 60 fps vertical format.
- Arbitrary durations, frame rates, and aspect ratios need new validation.
- Template metadata should come from assets you have the right to use.
- The scripts use macOS media frameworks and VideoToolbox; Linux output would need separate validation.
