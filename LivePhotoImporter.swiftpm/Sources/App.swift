import SwiftUI
@preconcurrency import Photos
import UniformTypeIdentifiers

@main
struct LivePhotoImporterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class ImportViewModel: ObservableObject, @unchecked Sendable {

    enum ImportState: Equatable, Sendable {
        case idle
        case preparing
        case importing
        case success
        case failed(String)
    }

    @Published var state: ImportState = .idle
    @Published var showFilePicker = false

    var statusTitle: String {
        switch state {
        case .idle:
            return "בחר את שני הקבצים"
        case .preparing:
            return "מכין את הקבצים…"
        case .importing:
            return "מוסיף ל־Photos…"
        case .success:
            return "נשמר כ־Live Photo"
        case .failed:
            return "הייבוא נכשל"
        }
    }

    var statusDetail: String {
        switch state {
        case .idle:
            return "בחר יחד את קובץ ה־HEIC ואת קובץ ה־MOV שחילצת מה־LIVP."
        case .preparing:
            return "מעתיק את הקבצים למיקום זמני."
        case .importing:
            return "יוצר פריט אחד עם photo + pairedVideo."
        case .success:
            return "פתח את Photos. אמור להופיע פריט אחד עם סימון LIVE."
        case .failed(let message):
            return message
        }
    }

    func importFiles(_ urls: [URL]) {
        setState(.preparing)

        let pair: Pair
        let localPair: LocalPair

        do {
            pair = try Self.findPair(in: urls)
            localPair = try Self.copyToTemporaryDirectory(
                photo: pair.photo,
                video: pair.video
            )
        } catch {
            setState(.failed(error.localizedDescription))
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else {
                try? FileManager.default.removeItem(at: localPair.directory)
                return
            }

            guard status == .authorized || status == .limited else {
                try? FileManager.default.removeItem(at: localPair.directory)
                self.setState(.failed(ImportError.photoPermissionDenied.localizedDescription))
                return
            }

            self.setState(.importing)

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()

                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.shouldMoveFile = false
                request.addResource(
                    with: .photo,
                    fileURL: localPair.photo,
                    options: photoOptions
                )

                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.shouldMoveFile = false
                request.addResource(
                    with: .pairedVideo,
                    fileURL: localPair.video,
                    options: videoOptions
                )
            }) { [weak self] success, error in
                try? FileManager.default.removeItem(at: localPair.directory)

                guard let self else { return }

                if let error {
                    self.setState(.failed(
                        ImportError.photosDidNotSave(error.localizedDescription)
                            .localizedDescription
                    ))
                } else if success {
                    self.setState(.success)
                } else {
                    self.setState(.failed(
                        ImportError.photosDidNotSave("Unknown PhotoKit error")
                            .localizedDescription
                    ))
                }
            }
        }
    }

    private func setState(_ newState: ImportState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = newState
            }
        }
    }

    private struct Pair: Sendable {
        let photo: URL
        let video: URL
    }

    private struct LocalPair: Sendable {
        let directory: URL
        let photo: URL
        let video: URL
    }

    private enum ImportError: LocalizedError {
        case needExactlyOnePhotoAndOneVideo
        case couldNotAccessFile(String)
        case photoPermissionDenied
        case photosDidNotSave(String)

        var errorDescription: String? {
            switch self {
            case .needExactlyOnePhotoAndOneVideo:
                return "בחר בדיוק שני קבצים יחד: HEIC/JPEG אחד ו־MOV אחד."
            case .couldNotAccessFile(let name):
                return "לא הצלחתי לגשת לקובץ: \(name)"
            case .photoPermissionDenied:
                return "אין הרשאה להוסיף ל־Photos. אשר הרשאה ב־Settings."
            case .photosDidNotSave(let message):
                return "Photos לא הצליח ליצור Live Photo: \(message)"
            }
        }
    }

    private static func findPair(in urls: [URL]) throws -> Pair {
        guard urls.count == 2 else {
            throw ImportError.needExactlyOnePhotoAndOneVideo
        }

        let photoExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg"]
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

        guard let photo = urls.first(where: {
            photoExtensions.contains($0.pathExtension.lowercased())
        }) else {
            throw ImportError.needExactlyOnePhotoAndOneVideo
        }

        guard let video = urls.first(where: {
            videoExtensions.contains($0.pathExtension.lowercased())
        }) else {
            throw ImportError.needExactlyOnePhotoAndOneVideo
        }

        guard photo != video else {
            throw ImportError.needExactlyOnePhotoAndOneVideo
        }

        return Pair(photo: photo, video: video)
    }

    private static func copyToTemporaryDirectory(
        photo: URL,
        video: URL
    ) throws -> LocalPair {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LivePhotoImport-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let localPhoto = directory.appendingPathComponent(photo.lastPathComponent)
        let localVideo = directory.appendingPathComponent(video.lastPathComponent)

        do {
            try copySecurityScopedFile(from: photo, to: localPhoto)
            try copySecurityScopedFile(from: video, to: localVideo)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        return LocalPair(
            directory: directory,
            photo: localPhoto,
            video: localVideo
        )
    }

    private static func copySecurityScopedFile(
        from source: URL,
        to destination: URL
    ) throws {
        let didStart = source.startAccessingSecurityScopedResource()

        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(
                at: source,
                to: destination
            )
        } catch {
            throw ImportError.couldNotAccessFile(source.lastPathComponent)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ImportViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 72, weight: .regular))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    Text(model.statusTitle)
                        .font(.title2.bold())

                    Text(model.statusDetail)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 500)
                }

                Button {
                    model.showFilePicker = true
                } label: {
                    Label("בחר HEIC + MOV", systemImage: "doc.on.doc")
                        .frame(maxWidth: 320)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)

                if case .failed = model.state {
                    Button("נסה שוב") {
                        model.state = .idle
                        model.showFilePicker = true
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(32)
            .navigationTitle("Live Photo Importer")
        }
        .fileImporter(
            isPresented: $model.showFilePicker,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(urls)
            case .failure(let error):
                model.state = .failed(error.localizedDescription)
            }
        }
    }

    private var isBusy: Bool {
        switch model.state {
        case .preparing, .importing:
            return true
        default:
            return false
        }
    }

    private var iconName: String {
        switch model.state {
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .preparing, .importing:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return "livephoto"
        }
    }
}
