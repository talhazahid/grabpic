import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Records one display (or part of it) to a web-ready MP4: H.264 High profile video, AAC audio,
/// and the movie header at the front of the file ("fast start") so browsers can begin playback
/// before the whole file has downloaded.
///
/// Everything that touches the writer runs on one serial queue. ScreenCaptureKit and the
/// microphone both deliver samples on the host clock, so they share one timeline.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {

    struct Options {
        var displayID: CGDirectDisplayID
        var screenFrame: CGRect          // AppKit global points
        var area: CGRect?                // AppKit global points, inside screenFrame
        var backingScale: CGFloat
        var framesPerSecond: Int         // 30 or 60
        var limitTo1080p: Bool
        var systemAudio: Bool
        var microphone: Bool
        var showsCursor: Bool
        var outputURL: URL
    }

    enum RecorderError: LocalizedError {
        case noDisplay
        case noFrames
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "The display to record is no longer available."
            case .noFrames: return "Nothing was recorded. Try again."
            case .writer(let message): return message
            }
        }
    }

    /// Called on the main thread when the stream stops on its own (display unplugged, permission
    /// revoked, disk full). The owner should call `stop()` to keep what was recorded.
    var onUnexpectedStop: ((Error?) -> Void)?

    private(set) var pixelSize: CGSize = .zero
    private(set) var microphoneActive = false

    private let queue = DispatchQueue(label: "com.owl.grabpic.recorder", qos: .userInitiated)
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    /// One AAC track carrying system sound and the microphone, mixed.
    private var audioInput: AVAssetWriterInput?
    private let mixer = AudioMixer()
    private var wantsMicrophone = false
    private var microphoneSession: AVCaptureSession?
    private var sessionStarted = false
    private var startTime = CMTime.invalid
    private var lastVideoBuffer: CMSampleBuffer?
    private var lastVideoTime = CMTime.invalid
    private var stopping = false
    private var outputURL: URL?

    // MARK: - Start

    func start(_ options: Options) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if CaptureService.isPermissionError(error) { throw CaptureService.CaptureError.permission }
            throw CaptureService.CaptureError.failed(error.localizedDescription)
        }
        guard let display = content.displays.first(where: { $0.displayID == options.displayID }) else {
            throw RecorderError.noDisplay
        }

        // Exclude the whole app, so overlays and windows opened later are never recorded. The main
        // window is already hidden at this point, and an app without on-screen windows is missing
        // from the on-screen list, so look it up in the full list.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var ownApps = content.applications.filter { $0.processID == ownPID }
        if ownApps.isEmpty,
           let all = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
            ownApps = all.applications.filter { $0.processID == ownPID }
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        // Source rectangle in the display's own points, top-left origin.
        let pointRect: CGRect
        if let area = options.area?.intersection(options.screenFrame), !area.isNull, area.width >= 2, area.height >= 2 {
            pointRect = CGRect(
                x: area.minX - options.screenFrame.minX,
                y: options.screenFrame.maxY - area.maxY,
                width: area.width,
                height: area.height
            ).integral
        } else {
            pointRect = CGRect(origin: .zero, size: options.screenFrame.size)
        }

        let size = Self.outputSize(
            for: pointRect.size,
            scale: options.backingScale,
            limitTo1080p: options.limitTo1080p
        )
        pixelSize = size

        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        if options.area != nil {
            configuration.sourceRect = pointRect
        }
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.framesPerSecond))
        configuration.queueDepth = 6
        configuration.showsCursor = options.showsCursor
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.backgroundColor = .black
        configuration.capturesAudio = options.systemAudio
        if options.systemAudio {
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        try setUpWriter(options: options, size: size)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        self.stream = stream

        if options.microphone {
            startMicrophone()
        }

        do {
            try await stream.startCapture()
        } catch {
            microphoneSession?.stopRunning()
            writer?.cancelWriting()
            removePartialFile()
            if CaptureService.isPermissionError(error) { throw CaptureService.CaptureError.permission }
            throw error
        }
    }

    /// Even dimensions (H.264 4:2:0 needs them), capped at 4K-class sizes that every hardware
    /// encoder and browser handles, or at 1080p when the smaller web size is chosen.
    static func outputSize(for points: CGSize, scale: CGFloat, limitTo1080p: Bool) -> CGSize {
        var width = points.width * max(1, scale)
        var height = points.height * max(1, scale)
        let maxLong: CGFloat = limitTo1080p ? 1920 : 3840
        let maxShort: CGFloat = limitTo1080p ? 1080 : 2400
        let long = max(width, height)
        let short = min(width, height)
        let factor = min(1, maxLong / max(long, 1), maxShort / max(short, 1))
        width *= factor
        height *= factor
        let evenWidth = max(2, Int(width.rounded(.down)) & ~1)
        let evenHeight = max(2, Int(height.rounded(.down)) & ~1)
        return CGSize(width: evenWidth, height: evenHeight)
    }

    private func setUpWriter(options: Options, size: CGSize) throws {
        try? FileManager.default.removeItem(at: options.outputURL)
        let writer = try AVAssetWriter(outputURL: options.outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        outputURL = options.outputURL

        let fps = Double(options.framesPerSecond)
        let pixels = Double(size.width * size.height)
        // About 0.08 bits per pixel per frame keeps text sharp without bloating the file.
        let bitRate = Int(min(40_000_000, max(2_000_000, pixels * fps * 0.08)))

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoExpectedSourceFrameRateKey: options.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: options.framesPerSecond * 2,
                AVVideoAllowFrameReorderingKey: true
            ]
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecorderError.writer("The video encoder is not available.") }
        writer.add(video)
        videoInput = video

        wantsMicrophone = options.microphone
        if options.systemAudio || options.microphone {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: AudioMixer.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
        }

        guard writer.startWriting() else {
            throw RecorderError.writer(writer.error?.localizedDescription ?? "The recording file could not be created.")
        }
        self.writer = writer
    }

    // MARK: - Microphone

    private func startMicrophone() {
        guard wantsMicrophone, audioInput != nil,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        session.startRunning()
        microphoneSession = session
        microphoneActive = session.isRunning
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        append(audio: sampleBuffer, from: .microphone)
    }

    // MARK: - Samples

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            append(video: sampleBuffer)
        case .audio:
            append(audio: sampleBuffer, from: .system)
        default:
            break
        }
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete && CMSampleBufferGetImageBuffer(sampleBuffer) != nil
    }

    private func append(video sampleBuffer: CMSampleBuffer) {
        guard !stopping, let writer, writer.status == .writing, let videoInput else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            startTime = time
            mixer.start(at: time)
            sessionStarted = true
        }
        if lastVideoTime.isValid, time <= lastVideoTime { return }
        guard videoInput.isReadyForMoreMediaData else { return } // drop a frame rather than stall
        if videoInput.append(sampleBuffer) {
            lastVideoBuffer = sampleBuffer
            lastVideoTime = time
        } else {
            reportWriterFailure()
        }
    }

    private func append(audio sampleBuffer: CMSampleBuffer, from source: AudioMixer.Source) {
        guard !stopping, sessionStarted, audioInput != nil, let writer, writer.status == .writing else { return }
        writeMixed(mixer.add(sampleBuffer, from: source))
    }

    private func writeMixed(_ buffers: [CMSampleBuffer]) {
        guard let audioInput, let writer, writer.status == .writing else { return }
        for buffer in buffers {
            guard audioInput.isReadyForMoreMediaData else { continue } // drop rather than stall
            if !audioInput.append(buffer) {
                reportWriterFailure()
                return
            }
        }
    }

    private func reportWriterFailure() {
        guard let writer, writer.status == .failed else { return }
        let error = writer.error
        DispatchQueue.main.async { [weak self] in self?.onUnexpectedStop?(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onUnexpectedStop?(error) }
    }

    // MARK: - Stop

    /// Stops capture and finishes the file. Returns the finished MP4.
    func stop() async throws -> URL {
        let endTime = CMClockGetTime(CMClockGetHostTimeClock())
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        microphoneSession?.stopRunning()
        microphoneSession = nil

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                stopping = true
                guard let writer, let outputURL else {
                    continuation.resume(throwing: RecorderError.noFrames)
                    return
                }
                guard sessionStarted, writer.status == .writing else {
                    let error = writer.error
                    writer.cancelWriting()
                    removePartialFile()
                    continuation.resume(throwing: error.map { RecorderError.writer($0.localizedDescription) } ?? RecorderError.noFrames)
                    return
                }

                // ScreenCaptureKit only sends frames when the screen changes. Repeat the last frame
                // at the stop time so a still screen still plays for the full length.
                var end = endTime
                if end <= lastVideoTime { end = CMTimeAdd(lastVideoTime, CMTime(value: 1, timescale: 60)) }
                if let last = lastVideoBuffer, let videoInput, videoInput.isReadyForMoreMediaData {
                    var timing = CMSampleTimingInfo(
                        duration: .invalid,
                        presentationTimeStamp: end,
                        decodeTimeStamp: .invalid
                    )
                    var copy: CMSampleBuffer?
                    if CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: last,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: &timing,
                        sampleBufferOut: &copy
                    ) == noErr, let copy {
                        videoInput.append(copy)
                    }
                }
                lastVideoBuffer = nil

                if audioInput != nil {
                    writeMixed(mixer.drain())
                }
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                writer.endSession(atSourceTime: end)
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: outputURL)
                    } else {
                        let message = writer.error?.localizedDescription ?? "The recording could not be finished."
                        continuation.resume(throwing: RecorderError.writer(message))
                    }
                }
            }
        }
    }

    private func removePartialFile() {
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}
