import SwiftUI
import Photos
import UniformTypeIdentifiers

@main
struct LivePhotoImporterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@MainActor
final class ImportViewModel: ObservableObject {
    enum ImportState: Equatable {
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
            return "בחר יחד את קובץ ה־HEIC ואת קובץ ה־MOV שנוצרו מתוך ה־LIVP."
        case .preparing:
            return "מעתיק את הקבצים למיקום זמני בטוח."
        case .importing:
            return "יוצר asset אחד עם photo + pairedVideo."
        case .success:
            return "פתח את Photos. אמור להופיע שם פריט אחד עם סימון LIVE."
        case .failed(let message):
            return message
        }
    }

    func importFiles(_ urls: [URL]) async {
        state = .preparing

        do {
            let pair = try Self.findPair(in: urls)
            let localPair = try Self.copyToTemporaryDirectory(photo: pair.photo, video: pair.video)
            defer {
                try? FileManager.default.removeItem(at: localPair.directory)
            }

            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                throw ImportError.photoPermissionDenied
            }

            state = .importing
            try await Self.saveLivePhoto(photoURL: localPair.photo, videoURL: localPair.video)
            state = .success
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct Pair {
        let photo: URL
        let video: URL
    }

    private struct LocalPair {
        let directory: URL
        let photo: URL
        let video: URL
    }

    private enum ImportError: LocalizedError {
        case needExactlyOnePhotoAndOneVideo
        case couldNotAccessFile(String)
        case photoPermissionDenied
        case photosDidNotSave

        var errorDescription: String? {
            switch self {
            case .needExactlyOnePhotoAndOneVideo:
                return "בחר בדיוק שני קבצים יחד: HEIC/JPEG אחד ו־MOV אחד."
            case .couldNotAccessFile(let name):
                return "לא הצלחתי לגשת לקובץ: \(name)"
            case .photoPermissionDenied:
                return "אין הרשאה להוסיף תמונות ל־Photos. אפשר לאשר אותה ב־Settings."
            case .photosDidNotSave:
                return "Photos לא אישר את יצירת ה־Live Photo."
            }
        }
    }

    private static func findPair(in urls: [URL]) throws -> Pair {
        guard urls.count == 2 else {
            throw ImportError.needExactlyOnePhotoAndOneVideo
        }

        let photoExtensions = Set(["heic", "heif", "jpg", "jpeg"])
        let videoExtensions = Set(["mov"])

        let photo = urls.first {
            photoExtensions.contains($0.pathExtension.lowercased())
        }
        let video = urls.first {
            videoExtensions.contains($0.pathExtension.lowercased())
        }

        guard let photo, let video, photo != video else {
            throw ImportError.needExactlyOnePhotoAndOneVideo
        }

        return Pair(photo: photo, video: video)
    }

    private static func copyToTemporaryDirectory(photo: URL, video: URL) throws -> LocalPair {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePhotoImport-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let localPhoto = directory.appendingPathComponent(photo.lastPathComponent)
        let localVideo = directory.appendingPathComponent(video.lastPathComponent)

        try copySecurityScopedFile(from: photo, to: localPhoto)
        try copySecurityScopedFile(from: video, to: localVideo)

        return LocalPair(directory: directory, photo: localPhoto, video: localVideo)
    }

    private static func copySecurityScopedFile(from source: URL, to destination: URL) throws {
        let didStart = source.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.couldNotAccessFile(source.lastPathComponent)
        }
    }

    private static func saveLivePhoto(photoURL: URL, videoURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()

                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.shouldMoveFile = false
                request.addResource(
                    with: .photo,
                    fileURL: photoURL,
                    options: photoOptions
                )

                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.shouldMoveFile = false
                request.addResource(
                    with: .pairedVideo,
                    fileURL: videoURL,
                    options: videoOptions
                )
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ImportError.photosDidNotSave)
                }
            }
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

                VStack(spacing: 8) {
                    Text(model.statusTitle)
                        .font(.title2.bold())

                    Text(model.statusDetail)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                }

                Button {
                    model.showFilePicker = true
                } label: {
                    Label("בחר HEIC + MOV", systemImage: "doc.on.doc")
                        .frame(maxWidth: 320)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
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
            .fileImporter(
                isPresented: $model.showFilePicker,
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await model.importFiles(urls)
                    }
                case .failure(let error):
                    model.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private var isBusy: Bool {
        model.state == .preparing || model.state == .importing
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
