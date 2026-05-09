import Foundation

enum GenerationStatus: String {
    case idle = "待开始"
    case ready = "已选择视频"
    case running = "生成中"
    case succeeded = "已完成"
    case failed = "失败"
}

struct GenerationJob {
    var inputVideoURL: URL?
    var outputURL: URL?
    var status: GenerationStatus = .idle
    var log: String = ""
}

