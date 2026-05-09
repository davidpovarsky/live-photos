import AppKit
import Foundation

@MainActor
final class GeneratorViewModel: ObservableObject {
    @Published private(set) var job = GenerationJob()
    @Published private(set) var isRunning = false

    private let generator = LocalLivpGenerator()

    var canGenerate: Bool {
        job.inputVideoURL != nil && !isRunning
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "选择一个视频"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        job.inputVideoURL = url
        job.status = .ready
        appendLog("已选择视频：\(url.path)\n")
    }

    func generate() {
        guard let inputURL = job.inputVideoURL else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "导出 .livp"
        savePanel.nameFieldStringValue = defaultOutputFileName()
        savePanel.allowedContentTypes = [.data]
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let outputURL = normalizedLivpURL(savePanel.url) else {
            return
        }

        job.outputURL = outputURL
        job.status = .running
        isRunning = true
        appendLog("开始生成：\(outputURL.path)\n")

        Task {
            do {
                try await generator.generate(inputVideoURL: inputURL, outputURL: outputURL) { [weak self] event in
                    Task { @MainActor in
                        self?.appendLog(event.text)
                    }
                }

                job.status = .succeeded
                appendLog("\n生成完成：\(outputURL.path)\n")
            } catch {
                job.status = .failed
                appendLog("\n错误：\(error.localizedDescription)\n")
            }

            isRunning = false
        }
    }

    func revealOutput() {
        guard let outputURL = job.outputURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    private func appendLog(_ text: String) {
        job.log += text
    }

    private func defaultOutputFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "live-wallpaper-\(formatter.string(from: Date())).livp"
    }

    private func normalizedLivpURL(_ url: URL?) -> URL? {
        guard let url else {
            return nil
        }
        if url.pathExtension.lowercased() == "livp" {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension("livp")
    }
}

