# Experiment Log

日期：2026-05-09

公开说明：本文是历史实验记录，可能提到本地私有样本、第三方样本或未随仓库发布的路径。开源仓库只提供生成方法、代码和调试工具；用户需要自行提供有权使用的模板资产。

目标：验证 AI/自定义视频是否可以导出为真正 iOS Live Photo，并进一步验证是否可以作为 iPhone 锁屏动态壁纸。

## 1. Basic Live Photo Packager

实现：

- Swift Package CLI：`livephoto-packager`
- 写入 photo `MakerApple[17]`
- 写入 MOV `com.apple.quicktime.content.identifier`
- 写入 `com.apple.quicktime.still-image-time`

输出：

```text
output/live-photo.jpg
output/live-photo.mov
```

结果：

- macOS Photos 导入后可以合并为 Live Photo。
- iPhone Photos 可识别实况。
- 锁屏动态壁纸失败，提示动态效果不可用。

结论：

基础 Live Photo metadata 不足以通过锁屏动态壁纸校验。

## 2. iPhone Native Sample Analysis

样本：

```text
IMG_0130 (1).HEIC
IMG_0130 (1).mov
```

原生 MOV 结构：

```text
video: HEVC / hvc1, 1920x1440, 1.303333s, 38 frames
audio: PCM
track 3: video-orientation, 1 sample
track 4: live-photo-info, 38 samples, 144 bytes each
track 5: still-image-time + still-image-transform
```

实验：

- 原始 HEIC + 原始 MOV：可锁屏
- 新 UUID + 原始 HEIC metadata + 原始 MOV metadata tracks：可锁屏
- 原始视频重编码 + 原始 metadata tracks：可锁屏
- 自定义视频 + 原始 metadata tracks：不可锁屏

结论：

iPhone 原生 `live-photo-info` 与真实视频/相机运动有关，不能直接迁移到完全不同的视频上。

## 3. Static White Desktop Sample

样本：

```text
IMG_0135.HEIC
IMG_0135.mov
```

结构：

```text
video: HEVC / hvc1, 1920x1440, 3.003333s, 88 frames
audio: PCM
track 3: video-orientation, 1 sample
track 4: live-photo-info, 88 samples, 144 bytes each
track 5: still-image-time + transform, start=1.468333s
```

实验：

```text
output-static-template-migration/live-photo.jpg
output-static-template-migration/live-photo.mov
```

做法：

- 生成 3s / 88 frames 自定义视频
- 使用白桌面完整 photo metadata
- 复制白桌面 `mebx` tracks

结果：

- iOS Photos 能显示实况。
- 锁屏动态壁纸失败。

结论：

即使是静止/低运动 iPhone 原生样本，其 `live-photo-info` 仍不能作为通用模板。

## 4. Third-Party `.livp` Sample

样本：

```text
<private third-party sample>.livp
```

拆包：

```text
vendor-livp/IMB_ZyUbrU.HEIC.heic
vendor-livp/IMB_ZyUbrU.HEIC.mov
```

`.livp` 本质：

```text
ZIP archive
```

third-party MOV 结构：

```text
video: HEVC / hvc1, 1080x1920, 1.0s, 60fps, 60 frames
audio: AAC stereo
track 2: live-photo-info, time_base=1/60000, start=0.05s, duration=0.95s, 57 samples
track 3: still-image-time + still-image-transform, start=0.5s
```

third-party HEIC metadata：

```text
MakerApple {
  17 = "B315BEEB-AA1A-4D1C-B308-6BE144D1D9B0";
}
```

关键发现：

```text
vendor live-photo-info:
  57 samples
  each sample = 144 bytes
  all sample payloads are identical
```

这说明该样本使用的是固定中性 metadata，而不是从每个视频真实估计相机运动。

## 5. Vendor Template Migration

目标：

验证第三方样本中的中性 `mebx` 是否能迁移到我们自己的视频。

生成输入：

```text
Samples/vendor-template-custom.mov
  1080x1920
  1s
  60fps
  HEVC hvc1
  AAC silent audio
```

输出：

```text
output-vendor-template-migration/live-photo.jpg
output-vendor-template-migration/live-photo.mov
```

做法：

- 从自定义视频 0.5s 抽封面
- photo 侧使用 third-party HEIC metadata template，仅替换 `MakerApple[17]`
- MOV 主视频使用自定义视频
- MOV metadata tracks 复制 third-party `.livp` 的中性 `mebx`
- 写入全新 UUID：`9DF8D4D3-2C27-42F3-A514-D0A6277AE41B`

结果：

- macOS Photos 合并为 Live Photo。
- iPhone Photos 显示实况。
- iPhone 锁屏动态壁纸可用。

结论：

compatible neutral `live-photo-info` 可以迁移到自定义视频。商业路线可行。

## 6. iOS App Spike

已创建：

```text
iOSSpike/LivePhotoSpike.xcodeproj
```

目的：

验证 `PHLivePhoto.request` + `PHAssetCreationRequest` 保存路径是否会改变或修复锁屏兼容性。

状态：

- 工程已生成。
- 当前机器已安装 Xcode 26.4.1。
- 该 App Spike 尚未真机运行；CLI 和 Web API 已跑通。

测试项：

- `Control Native`
- `Basic Custom`
- `Template Custom`

判断：

- 如果 custom case 经 App 保存后可锁屏，App 路线可以作为后端打包的替代/补充。
- 如果仍不可锁屏，则 App 不会自动生成所需 `live-photo-info`。

## 7. Historical Web MVP and Baidu Netdisk Import

公开说明：本节记录的是历史 Web MVP；当前开源仓库不包含 `web/server.mjs`，可运行入口以根目录 `README.md` 为准。

已实现：

```text
scripts/make-livp.sh
web/server.mjs
web/static/*
```

验证：

```bash
swift build
./scripts/make-livp.sh Samples/vendor-template-custom.mov test-output.livp
curl -F 'video=@Samples/vendor-template-custom.mov' http://localhost:3000/api/generate
```

第一版坑：

```text
普通 ZIP + .livp 后缀
  -> 本地可拆包
  -> 但百度网盘/iOS 保存提示无法保存该格式
```

对比 third-party `.livp` 发现：

```text
sample ZIP comment:
  00020000003200013DBD000300013E20000564FF313030304C495650

含义:
  0002
  HEIC data offset
  HEIC compressed size
  0003
  MOV data offset
  MOV compressed size
  313030304C495650  # 1000LIVP
```

sample internal file names:

```text
IMB_ZyUbrU.HEIC.heic
IMB_ZyUbrU.HEIC.mov
```

修复：

- 新增 `tools/set-livp-zip-comment.js`
- `scripts/make-livp.sh` 改为：
  - `zip -0 -X`
  - 内部文件名使用 `IMB_xxxxxxxx.HEIC.heic/mov`
  - 写入 ZIP comment

修复后生成：

```text
test-output-v2.livp
```

验证结果：

```text
Web 生成 .livp
  -> 上传百度网盘
  -> iPhone 下载到相册
  -> 相册识别实况
  -> 可设置锁屏墙纸
  -> 锁屏动态效果正常播放
```

结论：

`.livp` 的 ZIP comment 和内部命名影响第三方 App/网盘识别。商业交付必须生成 compatible `.livp`，不能只是普通 ZIP 改后缀。

## Open Questions

- `.livp` 通过不同渠道下载/导入后是否都能保持锁屏能力？
- 1 秒 60fps 是否是硬性规格，还是只是当前 neutral template 限制？
- 是否可以生成 2 秒或 3 秒的中性 `mebx`？
- 是否可以把 neutral payload 参数化，而不是依赖第三方样本？
- 不同 iOS 版本是否对 `.livp`/Live Photo wallpaper 校验不同？
- 目标 AI 视频模型输出是否能稳定压缩到 1 秒 60fps 且观感可接受？
- `.livp` 文件命名和 ZIP 内文件名是否影响导入体验？
- ZIP comment 是否还有其他版本/字段含义，当前仅按第三方样本复刻。
- 是否需要输出 HEIC，还是 JPG 足够？

## Next Implementation Step

封装：

```bash
make-livp input.mp4 output.livp
```

职责：

1. 转码到 `1080x1920 / 1s / 60fps / HEVC hvc1`
2. 生成静音 AAC 音轨
3. 抽取 `0.5s` 封面
4. 生成 UUID
5. 写 photo `MakerApple[17]`
6. 写 MOV `content.identifier`
7. 注入 neutral `mebx`
8. 打包 `.livp`

第一版只支持固定规格。

当前已实现：

```bash
./scripts/make-livp.sh input.mp4 output.livp
```

说明：

- `scripts/make-livp.sh` 会转码、抽帧、写 metadata、注入 neutral `mebx`、打包 `.livp`。
- 当前开源仓库保留 CLI 路径；历史 Web MVP 未随仓库发布。
- 当前已在 Xcode 26.4.1 下跑通 CLI。
