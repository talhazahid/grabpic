import AVFoundation
import CoreMedia

/// Mixes system sound and the microphone into one 48 kHz stereo track, placed on the recording's
/// timeline by each buffer's host-clock timestamp. One mixed track plays everywhere: browsers,
/// QuickTime, phones, and chat apps all play only the first audio track of an MP4.
///
/// Not thread-safe: the recorder calls it from its single serial queue.
final class AudioMixer {
    enum Source: Int, CaseIterable { case system = 0, microphone = 1 }

    static let sampleRate: Double = 48_000
    /// How far behind the newest audio the mixer waits for a slower source before writing.
    private let latencyFrames: Int64 = 9_600   // 0.2 s
    /// Small timestamp jitter is absorbed so consecutive buffers join without clicks.
    private let jitterFrames: Int64 = 1_200    // 25 ms

    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioMixer.sampleRate,
        channels: 2,
        interleaved: false
    )!

    var gains: [Source: Float] = [.system: 1.0, .microphone: 1.0]

    private var startTime = CMTime.invalid
    private var baseFrame: Int64 = 0              // timeline frame of left[0]
    private var left: [Float] = []
    private var right: [Float] = []
    private var writtenUpTo: [Source: Int64] = [:]
    private var expectedNext: [Source: Int64] = [:]
    private var converters: [Source: (AVAudioConverter, AVAudioFormat)] = [:]

    func start(at time: CMTime) {
        startTime = time
        baseFrame = 0
        left.removeAll(keepingCapacity: true)
        right.removeAll(keepingCapacity: true)
    }

    /// Adds one captured buffer. Returns mixed buffers that are ready to be written.
    func add(_ sampleBuffer: CMSampleBuffer, from source: Source) -> [CMSampleBuffer] {
        guard startTime.isValid, let pcm = convert(sampleBuffer, source: source), pcm.frameLength > 0 else {
            return []
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var frame = Int64(((pts - startTime).seconds * AudioMixer.sampleRate).rounded())
        if let expected = expectedNext[source], abs(frame - expected) <= jitterFrames {
            frame = expected
        }
        let count = Int64(pcm.frameLength)
        expectedNext[source] = frame + count

        // Skip whatever lands before the session start or before what has already been written.
        var skip: Int64 = 0
        if frame < baseFrame { skip = baseFrame - frame }
        if skip < count, let channels = pcm.floatChannelData {
            let start = Int(frame + skip - baseFrame)
            let length = Int(count - skip)
            ensureCapacity(start + length)
            let gain = gains[source] ?? 1
            let l = channels[0]
            let r = pcm.format.channelCount > 1 ? channels[1] : channels[0]
            for i in 0..<length {
                left[start + i] += l[Int(skip) + i] * gain
                right[start + i] += r[Int(skip) + i] * gain
            }
        }
        writtenUpTo[source] = max(writtenUpTo[source] ?? 0, frame + count)
        return flush(final: false)
    }

    /// Everything still buffered, at the end of a recording.
    func drain() -> [CMSampleBuffer] {
        flush(final: true)
    }

    // MARK: - Mixing

    private func ensureCapacity(_ needed: Int) {
        if left.count < needed {
            left.append(contentsOf: repeatElement(0, count: needed - left.count))
            right.append(contentsOf: repeatElement(0, count: needed - right.count))
        }
    }

    private func flush(final: Bool) -> [CMSampleBuffer] {
        let newest = writtenUpTo.values.max() ?? baseFrame
        var ready: Int64
        if final {
            ready = newest
        } else {
            // Wait for every active source, but never more than the latency window.
            let slowest = writtenUpTo.values.min() ?? baseFrame
            ready = max(slowest, newest - latencyFrames)
        }
        ready = min(ready, baseFrame + Int64(left.count))
        let count = Int(ready - baseFrame)
        guard count > 0 else { return [] }

        var output: [CMSampleBuffer] = []
        var offset = 0
        let chunk = 4_800
        while offset < count {
            let length = min(chunk, count - offset)
            if let buffer = makeBuffer(offset: offset, length: length) {
                output.append(buffer)
            }
            offset += length
        }
        left.removeFirst(count)
        right.removeFirst(count)
        baseFrame += Int64(count)
        return output
    }

    private func makeBuffer(offset: Int, length: Int) -> CMSampleBuffer? {
        guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(length)),
              let channels = pcm.floatChannelData else { return nil }
        pcm.frameLength = AVAudioFrameCount(length)
        for i in 0..<length {
            channels[0][i] = max(-1, min(1, left[offset + i]))
            channels[1][i] = max(-1, min(1, right[offset + i]))
        }
        let frame = baseFrame + Int64(offset)
        let pts = CMTimeAdd(startTime, CMTime(value: frame, timescale: CMTimeScale(AudioMixer.sampleRate)))
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(AudioMixer.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: outputFormat.formatDescription,
            sampleCount: CMItemCount(length),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcm.audioBufferList
        ) == noErr else { return nil }
        return sampleBuffer
    }

    // MARK: - Conversion

    /// Any input (mono or multi-channel microphones, 44.1/48/96 kHz, integer or float) becomes
    /// 48 kHz float, one or two channels.
    private func convert(_ sampleBuffer: CMSampleBuffer, source: Source) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames) else { return nil }
        input.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: input.mutableAudioBufferList
        ) == noErr else { return nil }

        let outChannels = AVAudioChannelCount(min(2, max(1, Int(inputFormat.channelCount))))
        var entry = converters[source]
        if entry == nil || entry!.0.inputFormat != inputFormat {
            guard let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioMixer.sampleRate,
                channels: outChannels,
                interleaved: false
            ), let converter = AVAudioConverter(from: inputFormat, to: target) else { return nil }
            converter.downmix = inputFormat.channelCount > 2
            entry = (converter, target)
            converters[source] = entry
        }
        guard let (converter, target) = entry else { return nil }

        let capacity = AVAudioFrameCount(Double(frames) * AudioMixer.sampleRate / inputFormat.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error else { return nil }
        return output
    }
}
