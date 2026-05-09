import Photos

enum LivePhotoService {
    static func requestLivePhoto(photoURL: URL, videoURL: URL) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(
                withResourceFileURLs: [photoURL, videoURL],
                placeholderImage: nil,
                targetSize: .zero,
                contentMode: .aspectFit
            ) { livePhoto, info in
                if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let livePhoto else {
                    continuation.resume(throwing: SpikeError.livePhotoRequestFailed)
                    return
                }
                continuation.resume(returning: livePhoto)
            }
        }
    }

    static func saveToPhotos(photoURL: URL, videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw SpikeError.photosDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)

                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.shouldMoveFile = false
                request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SpikeError.saveFailed(error?.localizedDescription ?? "unknown"))
                }
            }
        }
    }
}
