import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GeneratorViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                workspace
                    .frame(minWidth: 460)

                Divider()

                outputPanel
                    .frame(width: 360)
            }
            .navigationTitle("Live Wallpaper Studio")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("本机生成")
                    .font(.headline)
                Text("选择视频，生成 iPhone 可识别的 `.livp`。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Label("固定规格：1080x1920 / 1s / 60fps", systemImage: "iphone")
                .font(.callout)
                .foregroundStyle(.secondary)

            Label("使用已验证的中性 mebx 模板", systemImage: "checkmark.seal")
                .font(.callout)
                .foregroundStyle(.secondary)

            Label("导出后传到 iPhone 相册验证", systemImage: "square.and.arrow.up")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("生成工作台")
                    .font(.title2.weight(.semibold))
                Text("第一版先复用当前仓库里已经通过真机验证的 `make-livp.sh` 链路。")
                    .foregroundStyle(.secondary)
            }

            selectedVideoCard

            HStack(spacing: 12) {
                Button {
                    viewModel.chooseVideo()
                } label: {
                    Label("选择视频", systemImage: "video")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.generate()
                } label: {
                    Label("生成 .livp", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGenerate)
            }

            if viewModel.isRunning {
                ProgressView("正在生成，请保持应用打开")
                    .controlSize(.small)
            }

            Text("导入建议：生成后可以通过 AirDrop、iCloud Photos、百度网盘或文件 App 传到 iPhone，再保存到相册并设置锁屏。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(28)
    }

    private var selectedVideoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输入视频")
                .font(.headline)

            if let inputURL = viewModel.job.inputVideoURL {
                HStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(inputURL.lastPathComponent)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(inputURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Text("还没有选择视频。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("输出")
                    .font(.title3.weight(.semibold))
                Text(viewModel.job.status.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            if let outputURL = viewModel.job.outputURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text(outputURL.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(outputURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Button {
                    viewModel.revealOutput()
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.job.status != .succeeded)
            }

            Divider()

            Text("日志")
                .font(.headline)

            ScrollView {
                Text(viewModel.job.log.isEmpty ? "等待开始..." : viewModel.job.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }

    private var statusColor: Color {
        switch viewModel.job.status {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .running:
            return .blue
        case .idle, .ready:
            return .secondary
        }
    }
}

#Preview {
    ContentView()
}

