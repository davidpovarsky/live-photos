# Live Photo / `.livp` Generator

中文技术调查版见 [README.zh.md](README.zh.md)。

一个用于研究和生成 iOS Live Photo / `.livp` 的开源实验项目。

这个仓库的目标不是做一个播放器，而是整理一条可复用的生成链路：

```text
input video
  -> 1080x1920 / 1s / 60fps / HEVC hvc1
  -> 0.5s cover frame
  -> still image MakerApple[17]
  -> MOV content.identifier
  -> neutral mebx metadata tracks
  -> HEIC + MOV
  -> compatible .livp ZIP package
```

## Current Status

已验证的锁屏可用路径是固定规格 `.livp`：

- `1080x1920`
- `1.0s`
- `60fps`
- HEVC `hvc1` MOV
- silent AAC audio
- cover frame at `0.5s`
- HEIC/JPEG still image with `MakerApple[17]`
- MOV with matching `content.identifier`
- neutral `mebx` metadata tracks
- `.livp` package with compatible internal file names and ZIP comment

Important: the repository does not include neutral template media files. To produce lock-screen capable `.livp` files, provide template assets you have the right to use. See [docs/template-assets.md](docs/template-assets.md).

## Requirements

- macOS 13 or newer
- Xcode / Command Line Tools with Swift 5.9+
- `ffmpeg` with VideoToolbox support
- Node.js 18+
- `zip`

On a typical macOS machine:

```bash
xcode-select --install
brew install ffmpeg node
```

## Quick Start

Build the Swift packager:

```bash
swift build
```

Generate a basic Live Photo resource pair:

```bash
swift run livephoto-packager \
  --photo Samples/sample.jpg \
  --video Samples/sample.mov \
  --out .tmp/basic
```

This basic pair is useful for understanding the metadata shape, but it may not pass iPhone lock-screen wallpaper checks.

Generate a template-backed `.livp`:

```bash
mkdir -p vendor-livp

# Put your own legal template assets here:
# vendor-livp/IMB_ZyUbrU.HEIC.heic
# vendor-livp/IMB_ZyUbrU.HEIC.mov

./scripts/make-livp.sh Samples/vendor-template-custom.mov .tmp/output.livp
```

Or keep templates outside the repository:

```bash
LIVEPHOTO_TEMPLATE_PHOTO=/absolute/path/template.heic \
LIVEPHOTO_TEMPLATE_VIDEO=/absolute/path/template.mov \
./scripts/make-livp.sh Samples/vendor-template-custom.mov .tmp/output.livp
```

## How It Works

Core implementation:

- [Sources/LivePhotoPackager/main.swift](Sources/LivePhotoPackager/main.swift): Swift CLI that writes image and MOV metadata.
- [scripts/make-livp.sh](scripts/make-livp.sh): full pipeline from input video to `.livp`.
- [tools/set-livp-zip-comment.js](tools/set-livp-zip-comment.js): writes the `.livp` ZIP comment used by compatible import flows.

Reference docs:

- [docs/live-photo-generation.md](docs/live-photo-generation.md): technical implementation guide.
- [docs/template-assets.md](docs/template-assets.md): how to provide and inspect template assets.
- [docs/experiments.md](docs/experiments.md): historical experiment log.
- [docs/production-architecture.md](docs/production-architecture.md): production architecture notes.
- [docs/mac-local-app.md](docs/mac-local-app.md): local macOS app concept.

## Useful Commands

Verify generated resource metadata:

```bash
./scripts/verify-metadata.sh .tmp/basic/live-photo.jpg .tmp/basic/live-photo.mov
```

Inspect MOV boxes:

```bash
./tools/dump-mov-boxes.js /path/to/file.mov
```

Dump `mebx` metadata samples:

```bash
./tools/dump-mebx-samples.js /path/to/file.mov
```

Export likely `live-photo-info` samples:

```bash
./tools/export-live-photo-info-csv.js /path/to/file.mov .tmp/live-photo-info.csv
```

## iOS Validation

The iOS spike project can preview and save resource pairs:

```text
iOSSpike/LivePhotoSpike.xcodeproj
```

Useful code:

- `PHLivePhoto.request(...)` preview path in [iOSSpike/LivePhotoSpike/LivePhotoService.swift](iOSSpike/LivePhotoSpike/LivePhotoService.swift)
- `PHAssetCreationRequest.addResource(.photo/.pairedVideo)` save path in the same file

Final compatibility must be tested on real devices. Photos preview support does not guarantee lock-screen dynamic wallpaper support.

## Open-Source Notes

- Do not publish private `.livp`, `.heic`, or `.mov` template assets unless redistribution is allowed.
- The current lock-screen compatible path is verified for a fixed 1 second / 60 fps vertical output.
- Longer durations, different frame rates, and different aspect ratios need separate testing.
- This repository is a technical reference and experiment. It is not legal advice and does not grant rights to third-party media or metadata templates.

## License

MIT. See [LICENSE](LICENSE).
