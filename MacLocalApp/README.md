# Live Wallpaper Studio

Mac 本机可安装版开发目录。

当前阶段目标：

```text
选择本地视频
  -> 调用仓库内已验证的 scripts/make-livp.sh
  -> 生成 compatible .livp
  -> 导出到用户选择的位置
```

## 运行

1. 打开 `LiveWallpaperStudio.xcodeproj`。
2. 选择 `LiveWallpaperStudio` scheme。
3. 直接运行 macOS App。
4. 选择一个本地视频，点击生成。

## 当前依赖

- macOS 13+
- Xcode / Command Line Tools
- Swift CLI
- FFmpeg
- neutral template assets，见 `docs/template-assets.md`

内部测试阶段先复用仓库脚本。后续再把 `LivePhotoPackager`、`.livp` ZIP comment 写入和校验逻辑抽成 App 内部模块。




