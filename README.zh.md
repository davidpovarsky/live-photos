# Live Photo / `.livp` 生成技术调查

本文是一份围绕 iOS Live Photo 与 `.livp` 文件生成的技术调查报告。它记录了当前仓库已经验证过的工程路径、关键元数据、失败路径、可复现步骤和仍需继续验证的问题。

如果你只想快速跑命令，可以先看根目录 [README.md](README.md)。如果你想理解为什么这个方案能工作，以及哪些部分不能随便改，建议读完本文。

## 1. 调查目标

这次调查的目标不是做一个“看起来像 Live Photo 的播放器”，而是回答一个更具体的问题：

```text
能不能从普通视频生成 iOS 能识别、能导入相册、并且有机会作为锁屏动态壁纸使用的 Live Photo / .livp 文件？
```

这里有三个层级：

1. macOS Photos 或 iOS Photos 能把一张图和一个 MOV 识别为 Live Photo。
2. iOS Photos 能预览实况，并能保存到相册。
3. iPhone 锁屏墙纸设置页允许启用动态效果。

调查过程中发现，第 1、2 层相对容易，第 3 层明显更严格。只写最基础的 Live Photo 元数据可以让 Photos 显示“实况”，但不一定能通过锁屏动态壁纸校验。

## 2. 当前结论

当前仓库验证过的稳定路径是：

```text
输入视频
  -> 转成固定规格：1080x1920 / 1s / 60fps / HEVC hvc1
  -> 添加静音 AAC 音频
  -> 在 0.5s 抽取封面帧
  -> 写入图片 MakerApple[17]
  -> 写入 MOV com.apple.quicktime.content.identifier
  -> 迁移 compatible neutral mebx 元数据轨道
  -> 输出 HEIC + MOV
  -> 使用兼容命名和 ZIP comment 打包为 .livp
```

也就是说，当前真正有价值的技术点不是“只写一个 UUID”，而是以下几件事组合在一起：

- 图片和视频必须通过同一个 asset identifier 关联。
- MOV 需要写 QuickTime metadata。
- 只写 `still-image-time` 不够，锁屏动态壁纸路径还依赖更完整的 `mebx` metadata。
- `.livp` 不是普通 ZIP 改后缀，还需要兼容的内部文件名和 ZIP comment。
- 当前已验证路径依赖 neutral template assets。仓库不会发布模板媒体文件，用户需要自己提供有权使用的模板。

## 3. 术语说明

### Live Photo resource pair

Live Photo 的底层资源通常是一张静态图片和一个短 MOV：

```text
still image: HEIC 或 JPEG
paired video: MOV
```

二者通过相同的 asset identifier 关联。

### `.livp`

`.livp` 可以理解为一种交付容器。本仓库观察到的 `.livp` 本质是 ZIP，但它不是任意 ZIP：

- 里面通常有一张 HEIC/JPEG 和一个 MOV。
- 内部文件名需要符合某些导入路径的预期。
- ZIP comment 中包含图片和视频 local entry 的偏移与大小。

### `mebx`

`mebx` 是 QuickTime/MOV 中的 metadata sample entry。Live Photo 相关的信息可能以 metadata track 的形式存在，例如：

```text
com.apple.quicktime.live-photo-info
com.apple.quicktime.still-image-time
com.apple.quicktime.live-photo-still-image-transform
```

调查发现，普通 Photos 识别和锁屏动态壁纸校验对这些 metadata 的要求并不完全一样。

## 4. 为什么基础元数据不够

最基础的 Live Photo 生成方式是：

```text
图片:
  MakerApple[17] = UUID

MOV:
  com.apple.quicktime.content.identifier = UUID
  com.apple.quicktime.still-image-time
```

仓库中的 Swift CLI 已经能做到这件事：

```bash
swift run livephoto-packager \
  --photo Samples/sample.jpg \
  --video Samples/sample.mov \
  --out .tmp/basic
```

这个资源对可以用于理解 Live Photo 的基本结构，也可以被 Photos 识别为 Live Photo。但是实验记录显示，只写这些基础元数据时，iPhone 锁屏动态壁纸可能提示动态效果不可用。

这说明：

```text
Photos 能识别 Live Photo
不等于
锁屏墙纸能启用动态效果
```

锁屏路径会检查更多条件，例如视频规格、metadata track、still image time、transform 信息、导入容器结构等。

## 5. 关键实验路径

### 5.1 原生 iPhone Live Photo

原生 iPhone Live Photo 的 MOV 中包含多条轨道：

```text
video track
audio track
metadata track: video-orientation
metadata track: live-photo-info
metadata track: still-image-time + transform
```

实验结论：

- 原始 iPhone Live Photo 可以作为锁屏动态壁纸。
- 只替换 UUID 后仍然可以。
- 原始视频重编码后，如果保留原始 metadata tracks，有机会仍然可用。
- 把原生 iPhone 的 `live-photo-info` 直接迁移到完全不同的自定义视频上，会失败。

这说明原生 iPhone 的 `live-photo-info` 很可能和真实视频内容、拍摄过程或相机运动有关，不适合作为任意视频的通用模板。

### 5.2 静态或低运动样本

调查也尝试过使用静态或低运动的 iPhone Live Photo 作为模板。结果仍然不能稳定迁移到任意自定义视频。

这进一步说明：

```text
“看起来很静止”的原生 Live Photo metadata
不等于
可通用迁移的 neutral metadata
```

### 5.3 Neutral template 路径

后续发现一种更适合作为工程路径的方案：使用与固定输出规格匹配的 neutral `mebx` metadata tracks。

当前验证过的 template 形态大致是：

```text
video: 1080x1920
duration: 1.0s
fps: 60
codec: HEVC hvc1
audio: AAC
live-photo-info: 多个 metadata samples
still-image-time: 0.5s
```

这些 metadata tracks 被迁移到自定义视频后，配合固定视频规格和 `.livp` 包装，可以通过真实 iPhone 的锁屏动态效果验证。

## 6. 生成链路详解

完整入口是：

```bash
./scripts/make-livp.sh input.mp4 output.livp
```

这个脚本做了四大步。

### 6.1 视频归一化

脚本使用 FFmpeg 把输入视频归一化：

```bash
ffmpeg -y \
  -stream_loop -1 -i "$input_video" \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -t 1 \
  -map 0:v:0 -map 1:a:0 \
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=60,setsar=1,format=yuv420p" \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -c:a aac \
  -b:a 2k \
  -shortest \
  -movflags +faststart \
  "$normalized_mov"
```

关键点：

- 固定输出 `1080x1920`，避免比例漂移。
- 固定 `1s`，匹配当前 neutral template 的时长。
- 固定 `60fps`，匹配当前验证路径。
- 使用 `hevc_videotoolbox` 和 `hvc1` tag。
- 添加静音 AAC 音频，避免没有音轨带来的兼容性差异。

### 6.2 抽取封面

脚本在 `0.5s` 抽一帧作为静态图片输入：

```bash
ffmpeg -y \
  -ss 0.5 \
  -i "$normalized_mov" \
  -frames:v 1 \
  "$cover_jpg"
```

`0.5s` 也对应当前验证路径里的 still-image-time。

### 6.3 写 Live Photo 元数据

脚本调用 Swift CLI：

```bash
swift run livephoto-packager \
  --photo "$cover_jpg" \
  --template-photo-metadata "$template_photo" \
  --video "$normalized_mov" \
  --template-video "$template_video" \
  --out "$pair_dir" \
  --photo-format heic \
  --preserve-input-metadata-tracks
```

这里最重要的是两个参数：

```text
--template-photo-metadata
--template-video
```

它们告诉 packager：

- 图片侧可以复制模板图片 metadata，然后替换 `MakerApple[17]`。
- MOV 侧可以复制模板 MOV 的 metadata tracks。

`--preserve-input-metadata-tracks` 表示不要只写一个基础 still-image-time，而是保留模板 MOV 中的 metadata tracks。

### 6.4 打包 `.livp`

脚本最后把 HEIC 和 MOV 放进 ZIP：

```bash
zip -0 -X output.livp IMB_xxxxxxxx.HEIC.heic IMB_xxxxxxxx.HEIC.mov
```

然后调用：

```bash
node tools/set-livp-zip-comment.js output.livp
```

该工具会解析 ZIP local entries，找到 HEIC 和 MOV 的 data offset / size，并写入 ZIP comment：

```text
0002 + HEIC data offset + HEIC size
0003 + MOV data offset + MOV size
313030304C495650
```

这个 comment 对某些导入路径很关键。实验中，普通 ZIP 改后缀在部分渠道会被拒绝，而补齐内部命名和 ZIP comment 后可以导入。

## 7. Swift CLI 实现点

核心代码在：

```text
Sources/LivePhotoPackager/main.swift
```

主要方法：

### `writePhoto(...)`

职责：

- 读取输入图片。
- 可选读取模板图片 metadata。
- 设置 `MakerApple[17] = assetIdentifier`。
- 输出 JPEG 或 HEIC。

关键点：

```swift
makerApple.setObject(assetIdentifier, forKey: "17" as NSString)
mutableMetadata.setObject(makerApple, forKey: kCGImagePropertyMakerAppleDictionary as NSString)
```

### `writeVideo(...)`

职责：

- 读取输入 MOV 的 video/audio tracks。
- 写入 QuickTime metadata。
- 可选从 template MOV 复制 metadata tracks。
- 输出新的 MOV。

关键点：

```swift
writer.metadata = videoMetadataItems(assetIdentifier: assetIdentifier)
```

以及：

```swift
for track in metadataAsset.tracks(withMediaType: .metadata) {
  ...
  copyPairs.append((output, input))
}
```

这就是迁移 `mebx` metadata tracks 的核心。

### `videoMetadataItems(...)`

写入 MOV format-level tags：

```text
com.apple.quicktime.content.identifier
com.apple.quicktime.live-photo.auto
com.apple.quicktime.full-frame-rate-playback-intent
com.apple.quicktime.live-photo.vitality-score
com.apple.quicktime.live-photo.vitality-scoring-version
```

其中 `content.identifier` 必须和图片 `MakerApple[17]` 对应。

### `stillImageTimeMetadataInput(...)` / `appendStillImageTime(...)`

这两个方法用于基础路径：在没有 template metadata tracks 时写入 `com.apple.quicktime.still-image-time`。

这个基础路径适合理解结构，但不保证通过锁屏动态壁纸校验。

## 8. 模板资产

当前开源仓库不发布 neutral template media files。

默认路径是：

```text
vendor-livp/IMB_ZyUbrU.HEIC.heic
vendor-livp/IMB_ZyUbrU.HEIC.mov
```

你也可以通过环境变量指定：

```bash
LIVEPHOTO_TEMPLATE_PHOTO=/absolute/path/template.heic \
LIVEPHOTO_TEMPLATE_VIDEO=/absolute/path/template.mov \
./scripts/make-livp.sh input.mp4 output.livp
```

模板资产应该满足：

- 你有权使用和分发。
- MOV 中包含与目标输出规格匹配的 neutral metadata tracks。
- still-image-time 与输出封面时间一致或兼容。
- 最好经过真实 iPhone 导入和锁屏验证。

更多说明见：

```text
docs/template-assets.md
```

## 9. 调试工具

### 检查图片和 MOV 元数据

```bash
./scripts/verify-metadata.sh .tmp/basic/live-photo.jpg .tmp/basic/live-photo.mov
```

它会输出：

- 图片 `{MakerApple}` metadata。
- MOV format tags。
- MOV data streams。

### 查看 MOV box

```bash
./tools/dump-mov-boxes.js /path/to/file.mov
```

可以用来观察：

- `moov`
- `trak`
- `mdia`
- `stbl`
- `stsd`
- `mebx`
- metadata handler

### dump `mebx` samples

```bash
./tools/dump-mebx-samples.js /path/to/file.mov
```

可以用来观察 metadata track 中的 sample 数量、时间戳、payload size 和可打印字符串。

### 导出 `live-photo-info` CSV

```bash
./tools/export-live-photo-info-csv.js /path/to/file.mov .tmp/live-photo-info.csv
```

这个工具会尝试找到 144-byte sample 的 `live-photo-info` track，并把 sample payload 以 float 形式导出，方便做差异分析。

## 10. iOS 验证

仓库里有一个 iOS spike：

```text
iOSSpike/LivePhotoSpike.xcodeproj
```

核心代码在：

```text
iOSSpike/LivePhotoSpike/LivePhotoService.swift
```

它做两件事：

```swift
PHLivePhoto.request(...)
```

用于预览 Live Photo。

```swift
PHAssetCreationRequest.forAsset()
request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)
request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
```

用于保存到 Photos。

注意：能通过 `PHLivePhoto.request` 预览，不代表一定能作为锁屏动态壁纸。最终仍需真机验证。

## 11. 当前限制

当前可复现路径有明确限制：

- 固定 `1080x1920`。
- 固定 `1s`。
- 固定 `60fps`。
- 固定 `0.5s` 封面时间。
- 依赖 compatible neutral metadata template。
- 依赖 macOS / AVFoundation / ImageIO / VideoToolbox。
- Linux 版本需要重新验证 MOV 写入、HEIC 写入和 iOS 兼容性。

这些限制不是随便写的，而是为了减少兼容性变量。对于 iOS Live Photo 这种非公开完整规范的格式，先固定规格比一开始支持任意参数更可靠。

## 12. 仍需继续调查的问题

后续值得继续验证：

- `1s / 60fps` 是否是硬要求，还是只是当前 template 的限制。
- `30fps` 是否能通过锁屏动态壁纸校验。
- `1.5s / 2s / 3s` 是否可行。
- 是否能生成完全自有的 neutral `mebx` template。
- `.livp` ZIP comment 是否有更多字段或版本。
- AirDrop、Safari、文件 App、微信、网盘等导入路径是否行为一致。
- iOS 17、iOS 18、未来版本的兼容性是否一致。
- 不同机型对锁屏动态效果校验是否有差异。

## 13. 开源边界

这个仓库适合开源：

- Swift metadata packager。
- `.livp` packaging script。
- ZIP comment 写入工具。
- MOV box / mebx 分析工具。
- 技术调查文档。

不建议直接开源：

- 未确认授权的第三方 `.livp`。
- 从第三方样本中拆出的 HEIC / MOV。
- 私有 template assets。
- 生成结果中可能包含版权或肖像权风险的素材。

发布前建议看：

```text
docs/open-source-checklist.md
```

## 14. 文件索引

核心生成：

```text
scripts/make-livp.sh
Sources/LivePhotoPackager/main.swift
tools/set-livp-zip-comment.js
```

验证工具：

```text
scripts/verify-metadata.sh
tools/dump-mov-boxes.js
tools/dump-mebx-samples.js
tools/export-live-photo-info-csv.js
```

iOS 验证：

```text
iOSSpike/LivePhotoSpike/LivePhotoService.swift
iOSSpike/LivePhotoSpike/ContentView.swift
```

Mac app 包装：

```text
MacLocalApp/LiveWallpaperStudio/Services/LocalLivpGenerator.swift
MacLocalApp/LiveWallpaperStudio/ViewModels/GeneratorViewModel.swift
```

文档：

```text
docs/live-photo-generation.md
docs/template-assets.md
docs/experiments.md
docs/production-architecture.md
docs/mac-local-app.md
docs/open-source-checklist.md
```

## 15. 一句话总结

这次调查的核心结论是：

```text
Live Photo 的基础 UUID 关联可以让 Photos 识别资源对；
但想让 iPhone 锁屏动态效果可用，还需要匹配视频规格、mebx metadata、still-image-time、.livp 包装结构和真实导入路径。
```

因此，当前开源方案把问题收敛到一个固定可验证的 MVP：

```text
1080x1920 / 1s / 60fps / HEVC hvc1 / neutral mebx / compatible .livp
```

在这个固定点上继续做自动化校验、模板资产合法化和更多设备矩阵测试，会比一开始追求任意规格更稳。
