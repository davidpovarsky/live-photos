import Photos
import PhotosUI
import SwiftUI

struct LivePhotoCase: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let photoResource: String
    let photoExtension: String
    let videoResource: String
}

private let cases: [LivePhotoCase] = [
    LivePhotoCase(
        id: "control",
        title: "Control Native",
        subtitle: "Original iPhone Live Photo. This should save and remain wallpaper-capable.",
        photoResource: "Control",
        photoExtension: "HEIC",
        videoResource: "Control"
    ),
    LivePhotoCase(
        id: "basic",
        title: "Basic Custom",
        subtitle: "Custom video with only basic Live Photo metadata.",
        photoResource: "BasicCustom",
        photoExtension: "jpg",
        videoResource: "BasicCustom"
    ),
    LivePhotoCase(
        id: "template",
        title: "Template Custom",
        subtitle: "Custom video with static-template mebx tracks.",
        photoResource: "TemplateCustom",
        photoExtension: "jpg",
        videoResource: "TemplateCustom"
    )
]

struct ContentView: View {
    @State private var selectedCase = cases[0]
    @State private var selectedCaseID = cases[0].id
    @State private var status = "Choose a case, preview it, then save to Photos."
    @State private var livePhoto: PHLivePhoto?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Case", selection: $selectedCaseID) {
                    ForEach(cases) { item in
                        Text(item.title).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCaseID) { _, newValue in
                    selectedCase = cases.first { $0.id == newValue } ?? cases[0]
                    livePhoto = nil
                    status = selectedCase.subtitle
                }

                LivePhotoPreview(livePhoto: livePhoto)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .background(Color.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedCase.title)
                        .font(.headline)
                    Text(selectedCase.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button {
                        Task { await loadPreview() }
                    } label: {
                        Label("Preview", systemImage: "livephoto")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Button {
                        Task { await saveSelectedCase() }
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Live Photo Spike")
            .task {
                status = selectedCase.subtitle
            }
        }
    }

    private func loadPreview() async {
        await runBusy("Loading preview...") {
            let urls = try selectedCase.resourceURLs()
            let livePhoto = try await LivePhotoService.requestLivePhoto(photoURL: urls.photo, videoURL: urls.video)
            await MainActor.run {
                self.livePhoto = livePhoto
                self.status = "Preview loaded. Long-press the preview to play it."
            }
        }
    }

    private func saveSelectedCase() async {
        await runBusy("Requesting Photos permission...") {
            let urls = try selectedCase.resourceURLs()
            try await LivePhotoService.saveToPhotos(photoURL: urls.photo, videoURL: urls.video)
            await MainActor.run {
                self.status = "Saved. Open Photos, find the new Live Photo, then try setting it as Lock Screen wallpaper."
            }
        }
    }

    private func runBusy(_ initialStatus: String, operation: @escaping () async throws -> Void) async {
        await MainActor.run {
            isBusy = true
            status = initialStatus
        }

        do {
            try await operation()
        } catch {
            await MainActor.run {
                status = "Error: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            isBusy = false
        }
    }
}

struct LivePhotoPreview: UIViewRepresentable {
    let livePhoto: PHLivePhoto?

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        if livePhoto != nil {
            uiView.startPlayback(with: .hint)
        }
    }
}

private extension LivePhotoCase {
    func resourceURLs() throws -> (photo: URL, video: URL) {
        guard let photoURL = Bundle.main.url(forResource: photoResource, withExtension: photoExtension) else {
            throw SpikeError.missingResource("\(photoResource).\(photoExtension)")
        }
        guard let videoURL = Bundle.main.url(forResource: videoResource, withExtension: "mov") else {
            throw SpikeError.missingResource("\(videoResource).mov")
        }
        return (photoURL, videoURL)
    }
}

enum SpikeError: LocalizedError {
    case missingResource(String)
    case photosDenied
    case livePhotoRequestFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled resource: \(name)"
        case .photosDenied:
            return "Photos permission was denied."
        case .livePhotoRequestFailed:
            return "PHLivePhoto preview request failed."
        case .saveFailed(let message):
            return "Saving failed: \(message)"
        }
    }
}
