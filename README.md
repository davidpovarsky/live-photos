# Live Photo / `.livp` 可行性验证

本仓库记录一次围绕 **AI 生成 iOS Live Photo 锁屏动态壁纸** 的技术可行性验证。

目标不是做一个“看起来像 Live Photo 的播放器”，而是验证能否产出：

- macOS Photos / iOS Photos 可识别的 Live Photo
- iPhone 锁屏可启用“动态效果”的实况壁纸
- 适合后续 Web + AI 视频生成平台商业化的交付格式

## 最终结论

**可行。**

已验证成功的商业化路线不是复刻 iPhone 原生 Live Photo，而是复刻小红书商家交付的 `.livp` 方案：

```text
AI/自定义视频
  -> 转成 1080x1920、1 秒、60fps、HEVC hvc1
  -> 在 0.5 秒处抽取封面
  -> 写入图片 MakerApple 键 17
  -> 写入 MOV content.identifier
  -> 注入商家风格的中性 mebx 轨道
  -> 将 HEIC/JPG + MOV 打包成 .livp
```

最终本地验证：

- 购买的小红书 `.livp` 可以设置为 iPhone 锁屏动态壁纸。
- 拆包后迁移其“中性 `live-photo-info` / `mebx` 轨道”到我们自己的自定义视频。
- 生成的 `output-vendor-template-migration/live-photo.jpg + live-photo.mov` 成功设置为锁屏动态壁纸。
- Web 生成的新格式 `.livp` 上传百度网盘后，iPhone 下载到相册并成功设置为锁屏动态壁纸。

因此，MVP 可以先固定产出 **1 秒 60fps 竖屏 `.livp`**，再逐步扩展规格。

## 推荐 MVP 规格

第一版建议严格固定规格，避免锁屏兼容性漂移：

```text
容器：.livp，本质是 ZIP
图片：HEIC 或 JPG，写入 MakerApple 键 17
视频：MOV / HEVC hvc1
分辨率：1080x1920
时长：1.0 秒
帧率：60fps
封面时间：0.5 秒
音频：静音 AAC 可以接受
元数据：商家风格的中性 mebx 轨道
ZIP 结构：商家风格文件名 + ZIP 注释
```

不要在 MVP 阶段开放任意时长、任意比例、任意帧率。

## 关键发现

### `.livp` 是 ZIP 容器

购买样本：

```text
299 动态实况【苹果用户下载】.livp
```

解包结果：

```text
vendor-livp/IMB_ZyUbrU.HEIC.heic
vendor-livp/IMB_ZyUbrU.HEIC.mov
```

### 基础 Live Photo 元数据不够

只写这些基础元数据：

- 图片 `MakerApple[17] = UUID`
- MOV `com.apple.quicktime.content.identifier = UUID`
- MOV `com.apple.quicktime.still-image-time`

结果：

- macOS Photos 可以合并为 Live Photo
- iOS Photos 也能显示实况
- 但 iPhone 锁屏提示“动态效果不可用”

### iPhone 原生 `mebx` 不能当通用模板

iPhone 原生 Live Photo 中的 `live-photo-info` 轨道是逐帧元数据，和真实拍摄视频/相机运动强绑定。

验证结果：

- 原始 iPhone Live Photo：可锁屏
- 原始 iPhone Live Photo 换新 UUID：可锁屏
- 原始视频重编码后保留原始 `mebx`：可锁屏
- 把原始 iPhone `mebx` 迁移到完全不同的自定义视频：不可锁屏
- 白桌面静止 Live Photo 的 `mebx` 迁移到自定义视频：不可锁屏

### 商家 `.livp` 使用中性轨道

小红书商家 `.livp` 的结构更简单：

- 图片侧只有 `MakerApple[17]`
- MOV 只有两条 `mebx` 元数据轨道
- `live-photo-info` 有 57 个样本
- 57 个样本的载荷完全相同
- 静态图时间在 `0.5s`
- 视频是 `1080x1920 / 1s / 60fps / HEVC hvc1`

这套中性 `mebx` 成功迁移到自定义视频，并可设置锁屏动态壁纸。

### `.livp` 的 ZIP 结构很重要

普通 ZIP 改后缀为 `.livp` 不够。百度网盘下载/保存时会识别失败，iOS 侧提示无法保存该格式。

商家 `.livp` 还有两个关键结构：

```text
内部文件名：
  IMB_xxxxxxxx.HEIC.heic
  IMB_xxxxxxxx.HEIC.mov

ZIP 注释：
  0002 + HEIC 数据偏移量 + HEIC 文件大小
  0003 + MOV 数据偏移量 + MOV 文件大小
  313030304C495650  # 1000LIVP 的 ASCII 十六进制表示
```

已实现：

```text
tools/set-livp-zip-comment.js
scripts/make-livp.sh
```

修复后验证：

```text
Web 生成 -> 百度网盘上传 -> iPhone 下载到相册 -> 可设置锁屏动态壁纸
```

## 当前资产

重要样本：

```text
IMG_0130 (1).HEIC / IMG_0130 (1).mov
  iPhone 原生 Live Photo，约 1.3 秒，38 帧。

IMG_0135.HEIC / IMG_0135.mov
  iPhone 白桌面 Live Photo，约 3 秒，88 帧。

299 动态实况【苹果用户下载】.livp
  小红书购买样本，可锁屏，是当前商业路线模板来源。
```

成功候选：

```text
output-vendor-template-migration/live-photo.jpg
output-vendor-template-migration/live-photo.mov
```

解析产物：

```text
vendor-livp/live-photo-info.csv
vendor-livp/mebx-samples-dump.txt
live-photo-info.csv
live-photo-info-0135.csv
mebx-samples-dump.txt
mebx-samples-0135-dump.txt
```

## 工具

从输入视频生成 `.livp`：

```bash
./scripts/make-livp.sh input.mp4 output.livp
```

启动本地 Web MVP：

```bash
npm run web
```

然后打开：

```text
http://localhost:3000
```

Swift 打包器：

```bash
swift run livephoto-packager \
  --photo input.jpg \
  --video input.mov \
  --template-video vendor-livp/IMB_ZyUbrU.HEIC.mov \
  --out output \
  --preserve-input-metadata-tracks
```

检查元数据：

```bash
./scripts/verify-metadata.sh output/live-photo.jpg output/live-photo.mov
```

解析 MOV box：

```bash
./tools/dump-mov-boxes.js vendor-livp/IMB_ZyUbrU.HEIC.mov
```

导出 `mebx` 样本：

```bash
./tools/dump-mebx-samples.js vendor-livp/IMB_ZyUbrU.HEIC.mov
```

导出 `live-photo-info` CSV：

```bash
./tools/export-live-photo-info-csv.js vendor-livp/IMB_ZyUbrU.HEIC.mov vendor-livp/live-photo-info.csv
```

## 产品架构建议

MVP：

```text
Web 应用
  -> 用户选择模板 / 输入提示词
  -> 后端调用图片和视频生成
  -> 后端将视频归一化到 MVP 规格
  -> 后端运行 make-livp
  -> 用户下载 .livp
```

后续增强：

```text
iOS 辅助应用
  -> 一键导入
  -> 本地预览
  -> 相册保存引导
  -> 更好的购买后体验
```

## 待办

- 为 `.livp` 结构增加一等回归测试，覆盖 ZIP 注释和内部文件名。
- 验证 iPhone 上不同导入路径的稳定性：
  - 文件 App
  - AirDrop
  - 微信
  - Safari 下载
  - 类小红书交付流程
- 用更多生成样本验证百度网盘，不只验证当前合成视频。
- 验证兼容性矩阵：
  - iOS 17
  - iOS 18
  - 当前测试环境的 iOS 26
  - iPhone 12 Pro Max
  - 更新机型
- 测试 1.5 秒 / 2 秒 / 3 秒是否也能作为锁屏动态壁纸。
- 测试 30fps 是否可用，或 60fps 是否必须固定。
- 用目标视频生成模型输出替换合成测试视频。
- 评估使用购买 `.livp` 作为逆向参考的法律和产品风险；必要时生成自有中性轨道。
- 增加自动化回归测试：
  - 校验图片和视频 UUID 一致
  - 校验视频规格
  - 校验 `mebx` 轨道数量和时间
  - 校验 `.livp` ZIP 注释的偏移量和大小
- 完成 iOS 应用验证项目：
  - 运行 `iOSSpike/LivePhotoSpike.xcodeproj`
  - 验证 `PHAssetCreationRequest` 是否会改变兼容性
  - 如有价值，将它保留为内部 QA / 导入应用

## 本地环境状态

Xcode 已安装并验证：

```text
Xcode 26.4.1
```

如果新机器再次出现许可协议提示：

```bash
sudo xcodebuild -license
```

已本地验证：

```bash
swift build
./scripts/make-livp.sh Samples/vendor-template-custom.mov test-output.livp
curl -F 'video=@Samples/vendor-template-custom.mov' http://localhost:3000/api/generate
```

## 详细实验日志

见 [docs/experiments.md](docs/experiments.md)。

## 生产架构设计

见 [docs/production-architecture.md](docs/production-architecture.md)。

## Mac 本机可安装版

见 [docs/mac-local-app.md](docs/mac-local-app.md)。
