import Foundation

struct LocalLivpGenerator {
    struct Event: Sendable {
        let text: String
    }

    enum GeneratorError: LocalizedError {
        case missingScript(URL)
        case processFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .missingScript(let url):
                return "找不到生成脚本：\(url.path)"
            case .processFailed(let code):
                return "生成脚本执行失败，退出码：\(code)"
            }
        }
    }

    private let repositoryRoot: URL

    init(repositoryRoot: URL = ProjectPaths.repositoryRoot) {
        self.repositoryRoot = repositoryRoot
    }

    func generate(
        inputVideoURL: URL,
        outputURL: URL,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws {
        let scriptURL = repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("make-livp.sh")

        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw GeneratorError.missingScript(scriptURL)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = scriptURL
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [inputVideoURL.path, outputURL.path]
        process.environment = mergedEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                onEvent(Event(text: text))
            }
        }

        try process.run()
        process.waitUntilExit()
        handle.readabilityHandler = nil

        let remainingData = handle.readDataToEndOfFile()
        if !remainingData.isEmpty, let text = String(data: remainingData, encoding: .utf8) {
            onEvent(Event(text: text))
        }

        if process.terminationStatus != 0 {
            throw GeneratorError.processFailed(process.terminationStatus)
        }
    }

    private func mergedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            existingPath
        ].joined(separator: ":")
        return environment
    }
}

private enum ProjectPaths {
    static let repositoryRoot: URL = {
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()
}
