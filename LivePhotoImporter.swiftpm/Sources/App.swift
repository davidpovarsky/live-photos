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
        state = .preparing

        guard let pair = Self.findPair(in: urls) else {
            state = .failed("בחר בדיוק שני קבצים יחד: HEIC/JPEG אחד ו־MOV אחד.")
            return
        }

        guard let localPair = Self.copyToTemporaryDirectory(
            photo: pair.photo,
            video: pair.video
        ) else {
            state = .failed("לא הצלחתי להעתיק את הקבצים שנבחרו.")
            return
        }

        PHPhotoLibrary.requestAuthorization(
            for: .addOnly,
            handler: { [weak self] status in

                guard status == .authorized || status == .limited else {
                    Self.cleanup(localPair.directory)

                    Task { @MainActor [weak self] in
                        self?.state = .failed(
                            "אין הרשאה להוסיף ל־Photos. אשר הרשאה ב־Settings."
                        )
                    }
                    return
                }

                Task { @MainActor [weak self] in
                    self?.state = .importing
                }

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
                }, completionHandler: { [weak self] success, error in

                    Self.cleanup(localPair.directory)

                    Task { @MainActor [weak self] in
                        if let error {
                            self?.state = .failed(
                                "Photos לא הצליח ליצור Live Photo: \(error.localizedDescription)"
                            )
                        } else if success {
                            self?.state = .success
                        } else {
                            self?.state = .failed(
                                "Photos לא הצליח ליצור Live Photo."
                            )
                        }
                    }
                })
            }
        )
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

    nonisolated private static func findPair(in urls: [URL]) -> Pair? {
        guard urls.count == 2 else {
            return nil
        }

        let photoExtensions: Set<String> = [
            "heic",
            "heif",
            "jpg",
            "jpeg"
        ]

        let videoExtensions: Set<String> = [
            "mov",
            "mp4",
            "m4v"
        ]

        guard let photo = urls.first(where: {
            photoExtensions.contains($0.pathExtension.lowercased())
        }) else {
            return nil
        }

        guard let video = urls.first(where: {
            videoExtensions.contains($0.pathExtension.lowercased())
        }) else {
            return nil
        }

        guard photo != video else {
            return nil
        }

        return Pair(photo: photo, video: video)
    }

    nonisolated private static func copyToTemporaryDirectory(
        photo: URL,
        video: URL
    ) -> LocalPair? {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LivePhotoImport-\(UUID().uuidString)",
                isDirectory: true
            )

        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else {
            return nil
        }

        let localPhoto = directory.appendingPathComponent(
            photo.lastPathComponent
        )

        let localVideo = directory.appendingPathComponent(
            video.lastPathComponent
        )

        guard copySecurityScopedFile(
            from: photo,
            to: localPhoto
        ) else {
            cleanup(directory)
            return nil
        }

        guard copySecurityScopedFile(
            from: video,
            to: localVideo
        ) else {
            cleanup(directory)
            return nil
        }

        return LocalPair(
            directory: directory,
            photo: localPhoto,
            video: localVideo
        )
    }

    nonisolated private static func copySecurityScopedFile(
        from source: URL,
        to destination: URL
    ) -> Bool {

        let didStart = source.startAccessingSecurityScopedResource()

        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try? FileManager.default.removeItem(at: destination)
        }

        return (try? FileManager.default.copyItem(
            at: source,
            to: destination
        )) != nil
    }

    nonisolated private static func cleanup(_ url: URL) {
        _ = try? FileManager.default.removeItem(at: url)
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
                    Label(
                        "בחר HEIC + MOV",
                        systemImage: "doc.on.doc"
                    )
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
