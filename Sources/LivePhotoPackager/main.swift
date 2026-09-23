import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PackagerError: LocalizedError {
    case missingArgument(String)
    case invalidArguments
    case cannotReadImage(URL)
    case cannotCreateImageDestination(URL)
    case cannotCreateMetadataDescription
    case cannotAddReaderOutput(String)
    case cannotAddWriterInput(String)
    case readerFailed(String)
    case writerFailed(String)
    case noVideoTrack(URL)
    case unsupportedPhotoFormat(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Missing argument: \(name)"
        case .invalidArguments:
            return "Usage: livephoto-packager --photo photo.jpg --video video.mov --out output-dir [--id uuid]"
        case .cannotReadImage(let url):
            return "Cannot read image at \(url.path)"
        case .cannotCreateImageDestination(let url):
            return "Cannot create image destination at \(url.path)"
        case .cannotCreateMetadataDescription:
            return "Cannot create QuickTime metadata description"
        case .cannotAddReaderOutput(let mediaType):
            return "Cannot add reader output for \(mediaType)"
        case .cannotAddWriterInput(let mediaType):
            return "Cannot add writer input for \(mediaType)"
        case .readerFailed(let message):
            return "Asset reader failed: \(message)"
        case .writerFailed(let message):
            return "Asset writer failed: \(message)"
        case .noVideoTrack(let url):
            return "No video track found at \(url.path)"
        case .unsupportedPhotoFormat(let format):
            return "Unsupported photo format: \(format). Use jpeg or heic."
        }
    }
}

enum PhotoFormat: String {
    case jpeg
    case heic

    var fileName: String {
        switch self {
        case .jpeg:
            return "live-photo.jpg"
        case .heic:
            return "live-photo.heic"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .jpeg:
            return UTType.jpeg.identifier as CFString
        case .heic:
            return UTType.heic.identifier as CFString
        }
    }
}

struct Arguments {
    let photoURL: URL
    let templatePhotoMetadataURL: URL?
    let videoURL: URL
    let templateVideoURL: URL?
    let outputDirectory: URL
    let photoFormat: PhotoFormat
    let assetIdentifier: String
    let stillImageTime: Double
    let preserveInputMetadataTracks: Bool
}

@main
struct LivePhotoPackager {
    static func main() async {
        do {
            let arguments = try parseArguments()
            try FileManager.default.createDirectory(
                at: arguments.outputDirectory,
                withIntermediateDirectories: true
            )

            let photoOutputURL = arguments.outputDirectory.appendingPathComponent(arguments.photoFormat.fileName)
            let videoOutputURL = arguments.outputDirectory.appendingPathComponent("live-photo.mov")

            try writePhoto(
                inputURL: arguments.photoURL,
                metadataTemplateURL: arguments.templatePhotoMetadataURL,
                outputURL: photoOutputURL,
                outputFormat: arguments.photoFormat,
                assetIdentifier: arguments.assetIdentifier
            )

            try await writeVideo(
                inputURL: arguments.videoURL,
                outputURL: videoOutputURL,
                assetIdentifier: arguments.assetIdentifier,
                stillImageTime: arguments.stillImageTime,
                preserveInputMetadataTracks: arguments.preserveInputMetadataTracks,
                templateVideoURL: arguments.templateVideoURL
            )

            print("Created Live Photo resource pair")
            print("Asset identifier: \(arguments.assetIdentifier)")
            print("Photo: \(photoOutputURL.path)")
            print("Video: \(videoOutputURL.path)")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parseArguments() throws -> Arguments {
        var photo: String?
        var templatePhotoMetadata: String?
        var video: String?
        var templateVideo: String?
        var output: String?
        var photoFormat = PhotoFormat.jpeg
        var identifier: String?
        var stillImageTime: Double = 0.5
        var preserveInputMetadataTracks = false

        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--photo":
                photo = iterator.next()
            case "--template-photo-metadata":
                templatePhotoMetadata = iterator.next()
            case "--video":
                video = iterator.next()
            case "--template-video":
                templateVideo = iterator.next()
            case "--out":
                output = iterator.next()
            case "--photo-format":
                let value = iterator.next()
                guard let value, let parsed = PhotoFormat(rawValue: value.lowercased()) else {
                    throw PackagerError.unsupportedPhotoFormat(value ?? "")
                }
                photoFormat = parsed
            case "--id":
                identifier = iterator.next()
            case "--still-image-time":
                guard let value = iterator.next(), let parsed = Double(value) else {
                    throw PackagerError.invalidArguments
                }
                stillImageTime = parsed
            case "--preserve-input-metadata-tracks":
                preserveInputMetadataTracks = true
            case "--help", "-h":
                throw PackagerError.invalidArguments
            default:
                throw PackagerError.invalidArguments
            }
        }

        guard let photo else { throw PackagerError.missingArgument("--photo") }
        guard let video else { throw PackagerError.missingArgument("--video") }
        guard let output else { throw PackagerError.missingArgument("--out") }

        return Arguments(
            photoURL: URL(fileURLWithPath: photo),
            templatePhotoMetadataURL: templatePhotoMetadata.map { URL(fileURLWithPath: $0) },
            videoURL: URL(fileURLWithPath: video),
            templateVideoURL: templateVideo.map { URL(fileURLWithPath: $0) },
            outputDirectory: URL(fileURLWithPath: output, isDirectory: true),
            photoFormat: photoFormat,
            assetIdentifier: identifier ?? UUID().uuidString,
            stillImageTime: stillImageTime,
            preserveInputMetadataTracks: preserveInputMetadataTracks
        )
    }

    private static func writePhoto(
        inputURL: URL,
        metadataTemplateURL: URL?,
        outputURL: URL,
        outputFormat: PhotoFormat,
        assetIdentifier: String
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw PackagerError.cannotReadImage(inputURL)
        }

        let metadataSource = try metadataTemplateURL.map { url -> CGImageSource in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw PackagerError.cannotReadImage(url)
            }
            return source
        } ?? imageSource

        let metadata = (CGImageSourceCopyPropertiesAtIndex(metadataSource, 0, nil) as? [String: Any]) ?? [:]
        let mutableMetadata = NSMutableDictionary(dictionary: metadata)
        let makerApple = NSMutableDictionary(
            dictionary: metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
        )

        // Apple uses MakerApple key 17 to associate the still image with the paired video.
        makerApple.setObject(assetIdentifier, forKey: "17" as NSString)
        mutableMetadata.setObject(makerApple, forKey: kCGImagePropertyMakerAppleDictionary as NSString)

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            outputFormat.typeIdentifier,
            1,
            nil
        ) else {
            throw PackagerError.cannotCreateImageDestination(outputURL)
        }

        CGImageDestinationAddImage(destination, image, mutableMetadata)
        if !CGImageDestinationFinalize(destination) {
            throw PackagerError.cannotCreateImageDestination(outputURL)
        }
    }

    private struct MetadataCopyPair {
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
    }

    private static func writeVideo(
        inputURL: URL,
        outputURL: URL,
        assetIdentifier: String,
        stillImageTime: Double,
        preserveInputMetadataTracks: Bool,
        templateVideoURL: URL?
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let videoAsset = AVURLAsset(url: inputURL)
        let metadataAsset = AVURLAsset(url: templateVideoURL ?? inputURL)
        let videoReader = try AVAssetReader(asset: videoAsset)
        let metadataReader = templateVideoURL == nil ? videoReader : try AVAssetReader(asset: metadataAsset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let targetDurationTime = try await videoAsset.load(.duration)
        let targetDurationSeconds = CMTimeGetSeconds(targetDurationTime)

        writer.metadata = videoMetadataItems(assetIdentifier: assetIdentifier)

        var copyPairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = []
        var templateMetadataPairs: [MetadataCopyPair] = []
        let videoAudioTypes: [AVMediaType] = [.video, .audio]

        for mediaType in videoAudioTypes {
            for track in videoAsset.tracks(withMediaType: mediaType) {
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                output.alwaysCopiesSampleData = false

                guard videoReader.canAdd(output) else {
                    throw PackagerError.cannotAddReaderOutput(mediaType.rawValue)
                }
                videoReader.add(output)

                let input = AVAssetWriterInput(mediaType: mediaType, outputSettings: nil)
                input.expectsMediaDataInRealTime = false

                guard writer.canAdd(input) else {
                    throw PackagerError.cannotAddWriterInput(mediaType.rawValue)
                }
                writer.add(input)
                copyPairs.append((output, input))
            }
        }

        if videoAsset.tracks(withMediaType: .video).isEmpty {
            throw PackagerError.noVideoTrack(inputURL)
        }

        if preserveInputMetadataTracks {
            for track in metadataAsset.tracks(withMediaType: .metadata) {
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                output.alwaysCopiesSampleData = false

                guard metadataReader.canAdd(output) else {
                    throw PackagerError.cannotAddReaderOutput(AVMediaType.metadata.rawValue)
                }
                metadataReader.add(output)

                let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil)
                input.expectsMediaDataInRealTime = false

                guard writer.canAdd(input) else {
                    throw PackagerError.cannotAddWriterInput(AVMediaType.metadata.rawValue)
                }
                writer.add(input)

                if templateVideoURL != nil {
                    templateMetadataPairs.append(MetadataCopyPair(output: output, input: input))
                } else {
                    copyPairs.append((output, input))
                }
            }
        }

        let metadataInput: AVAssetWriterInputMetadataAdaptor?
        if preserveInputMetadataTracks {
            metadataInput = nil
        } else {
            let input = try stillImageTimeMetadataInput()
            guard writer.canAdd(input.assetWriterInput) else {
                throw PackagerError.cannotAddWriterInput(AVMediaType.metadata.rawValue)
            }
            writer.add(input.assetWriterInput)
            metadataInput = input
        }

        var templateMetadataSamples: [([CMSampleBuffer], AVAssetWriterInput)] = []

        if templateVideoURL != nil {
            guard metadataReader.startReading() else {
                throw PackagerError.readerFailed(metadataReader.error?.localizedDescription ?? "unknown")
            }

            for pair in templateMetadataPairs {
                var samples: [CMSampleBuffer] = []
                while let sample = pair.output.copyNextSampleBuffer() {
                    samples.append(sample)
                }
                templateMetadataSamples.append((samples, pair.input))
            }

            if metadataReader.status == .failed {
                throw PackagerError.readerFailed(metadataReader.error?.localizedDescription ?? "unknown")
            }
        }

        guard writer.startWriting() else {
            throw PackagerError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        guard videoReader.startReading() else {
            throw PackagerError.readerFailed(videoReader.error?.localizedDescription ?? "unknown")
        }

        writer.startSession(atSourceTime: .zero)
        if let metadataInput {
            appendStillImageTime(using: metadataInput, at: stillImageTime)
        }

        async let mediaCopy: Void = copySamples(copyPairs)
        async let metadataCopy: Void = copyAdaptedTemplateMetadata(
            templateMetadataSamples,
            targetDurationSeconds: targetDurationSeconds,
            stillImageTime: stillImageTime
        )

        try await mediaCopy
        try await metadataCopy

        if videoReader.status == .failed {
            throw PackagerError.readerFailed(videoReader.error?.localizedDescription ?? "unknown")
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw PackagerError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    private static func copyAdaptedTemplateMetadata(
        _ tracks: [([CMSampleBuffer], AVAssetWriterInput)],
        targetDurationSeconds: Double,
        stillImageTime: Double
    ) async throws {
        guard !tracks.isEmpty else {
            return
        }

        var prepared: [([CMSampleBuffer], AVAssetWriterInput)] = []
        prepared.reserveCapacity(tracks.count)

        for (samples, input) in tracks {
            guard let first = samples.first else {
                input.markAsFinished()
                continue
            }

            if samples.count == 1 {
                let originalDuration = CMSampleBufferGetDuration(first)
                let duration = originalDuration.isValid && originalDuration.value > 0
                    ? originalDuration
                    : CMTime(value: 1, timescale: 600)

                let timescale = max(CMSampleBufferGetPresentationTimeStamp(first).timescale, 600)
                let presentationTime = CMTime(
                    seconds: stillImageTime,
                    preferredTimescale: timescale
                )

                let retimed = try copySampleBuffer(
                    first,
                    presentationTime: presentationTime,
                    duration: duration
                )
                prepared.append(([retimed], input))
                continue
            }

            let firstTime = CMSampleBufferGetPresentationTimeStamp(first)
            var sampleDuration = CMSampleBufferGetDuration(first)

            if !sampleDuration.isValid || sampleDuration.value <= 0 {
                if samples.count > 1 {
                    let secondTime = CMSampleBufferGetPresentationTimeStamp(samples[1])
                    sampleDuration = CMTimeSubtract(secondTime, firstTime)
                }
            }

            let sampleDurationSeconds = CMTimeGetSeconds(sampleDuration)
            let firstTimeSeconds = CMTimeGetSeconds(firstTime)

            guard sampleDurationSeconds.isFinite,
                  sampleDurationSeconds > 0,
                  firstTimeSeconds.isFinite,
                  targetDurationSeconds.isFinite,
                  targetDurationSeconds > firstTimeSeconds else {
                prepared.append((samples, input))
                continue
            }

            // The neutral live-photo-info payload is intentionally identical
            // for every sample. Extend or trim it to end exactly with the
            // requested video duration while keeping the original 0.05s start.
            let exactCount = (targetDurationSeconds - firstTimeSeconds) / sampleDurationSeconds
            let targetCount = max(1, Int(floor(exactCount + 0.000001)))

            var retimedSamples: [CMSampleBuffer] = []
            retimedSamples.reserveCapacity(targetCount)

            for index in 0..<targetCount {
                let offset = CMTimeMultiply(sampleDuration, multiplier: Int32(index))
                let presentationTime = CMTimeAdd(firstTime, offset)
                let retimed = try copySampleBuffer(
                    first,
                    presentationTime: presentationTime,
                    duration: sampleDuration
                )
                retimedSamples.append(retimed)
            }

            prepared.append((retimedSamples, input))
        }

        try await appendPreparedSamples(prepared)
    }

    private static func copySampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        presentationTime: CMTime,
        duration: CMTime
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var output: CMSampleBuffer?

        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &output
        )

        guard status == noErr, let output else {
            throw PackagerError.writerFailed("Could not retime metadata sample (OSStatus \\(status))")
        }

        return output
    }

    private static func appendPreparedSamples(
        _ tracks: [([CMSampleBuffer], AVAssetWriterInput)]
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let group = DispatchGroup()
            let queue = DispatchQueue(
                label: "live-photo-packager.metadata-copy",
                attributes: .concurrent
            )

            for (samples, input) in tracks {
                group.enter()
                var index = 0
                var didFinish = false

                input.requestMediaDataWhenReady(on: queue) {
                    guard !didFinish else { return }

                    while input.isReadyForMoreMediaData {
                        if index < samples.count {
                            if !input.append(samples[index]) {
                                input.markAsFinished()
                                didFinish = true
                                group.leave()
                                return
                            }
                            index += 1
                        } else {
                            input.markAsFinished()
                            didFinish = true
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: queue) {
                continuation.resume()
            }
        }
    }

    private static func videoMetadataItems(assetIdentifier: String) -> [AVMetadataItem] {
        [
            metadataItem(
                key: AVMetadataKey.quickTimeMetadataKeyContentIdentifier.rawValue,
                value: assetIdentifier,
                dataType: "com.apple.metadata.datatype.UTF-8"
            ),
            metadataItem(
                key: "com.apple.quicktime.live-photo.auto",
                value: "1",
                dataType: "com.apple.metadata.datatype.UTF-8"
            ),
            metadataItem(
                key: "com.apple.quicktime.full-frame-rate-playback-intent",
                value: "0",
                dataType: "com.apple.metadata.datatype.UTF-8"
            ),
            metadataItem(
                key: "com.apple.quicktime.live-photo.vitality-score",
                value: "1.000000",
                dataType: "com.apple.metadata.datatype.UTF-8"
            ),
            metadataItem(
                key: "com.apple.quicktime.live-photo.vitality-scoring-version",
                value: "0",
                dataType: "com.apple.metadata.datatype.UTF-8"
            )
        ]
    }

    private static func metadataItem(key: String, value: String, dataType: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = key as NSString
        item.value = value as NSString
        item.dataType = dataType
        return item.copy() as! AVMetadataItem
    }

    private static func stillImageTimeMetadataInput() throws -> AVAssetWriterInputMetadataAdaptor {
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                "com.apple.metadata.datatype.int8"
        ]

        var formatDescription: CMMetadataFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDescription else {
            throw PackagerError.cannotCreateMetadataDescription
        }

        let input = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }

    private static func appendStillImageTime(
        using adaptor: AVAssetWriterInputMetadataAdaptor,
        at seconds: Double
    ) {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = "com.apple.quicktime.still-image-time" as NSString
        item.value = 0 as NSNumber
        item.dataType = "com.apple.metadata.datatype.int8"

        let group = AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(
                start: CMTime(seconds: seconds, preferredTimescale: 600),
                duration: CMTime(value: 1, timescale: 600)
            )
        )
        adaptor.append(group)
        adaptor.assetWriterInput.markAsFinished()
    }

    private static func copySamples(
        _ pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "live-photo-packager.copy", attributes: .concurrent)

            for (output, input) in pairs {
                group.enter()
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        if let sampleBuffer = output.copyNextSampleBuffer() {
                            if !input.append(sampleBuffer) {
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                        } else {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: queue) {
                continuation.resume()
            }
        }
    }
}
