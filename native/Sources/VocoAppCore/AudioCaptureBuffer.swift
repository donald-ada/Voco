import Foundation

public struct AudioCaptureBuffer: Sendable {
    private let targetSampleRate: Double
    private var resampler: Float32LinearResampler
    private var pcm16Samples: [Int16]
    private var peakAmplitude: Double

    public init(targetSampleRate: Double = 16_000) {
        precondition(targetSampleRate > 0)
        self.targetSampleRate = targetSampleRate
        self.resampler = Float32LinearResampler()
        self.pcm16Samples = []
        self.peakAmplitude = 0
    }

    public mutating func reset() {
        resampler.reset()
        pcm16Samples.removeAll(keepingCapacity: true)
        peakAmplitude = 0
    }

    @discardableResult
    public mutating func appendNonInterleavedFloat32(_ channels: [[Float]], sourceSampleRate: Double) -> [Int16] {
        guard sourceSampleRate > 0, let firstChannel = channels.first, !firstChannel.isEmpty else {
            return []
        }

        let frameCount = firstChannel.count
        var mono = Array(repeating: Float(0), count: frameCount)
        let usableChannels = channels.filter { $0.count >= frameCount }
        guard !usableChannels.isEmpty else {
            return []
        }

        for channel in usableChannels {
            for index in 0..<frameCount {
                mono[index] += channel[index]
            }
        }

        let divisor = Float(usableChannels.count)
        return appendMonoFloat32(mono.map { $0 / divisor }, sourceSampleRate: sourceSampleRate)
    }

    @discardableResult
    public mutating func appendMonoFloat32(_ samples: [Float], sourceSampleRate: Double) -> [Int16] {
        guard sourceSampleRate > 0, !samples.isEmpty else {
            return []
        }

        let resampled = resampler.resample(
            samples,
            sourceSampleRate: sourceSampleRate,
            targetSampleRate: targetSampleRate
        )
        var appended: [Int16] = []
        appended.reserveCapacity(resampled.count)
        for sample in resampled {
            let clipped = Self.clipped(sample)
            let pcm = Self.floatToInt16(clipped)
            pcm16Samples.append(pcm)
            appended.append(pcm)
            peakAmplitude = max(peakAmplitude, Double(abs(clipped)))
        }
        return appended
    }

    public func snapshot() -> CapturedAudioSnapshot {
        CapturedAudioSnapshot(
            durationSeconds: Double(pcm16Samples.count) / targetSampleRate,
            sampleRate: targetSampleRate,
            peakAmplitude: peakAmplitude,
            pcm16Samples: pcm16Samples
        )
    }

    private static func clipped(_ sample: Float) -> Float {
        sample.isFinite ? min(max(sample, -1), 1) : 0
    }

    private static func floatToInt16(_ sample: Float) -> Int16 {
        Int16(clipped(sample) * Float(Int16.max))
    }
}

private struct Float32LinearResampler: Sendable {
    private var pending: [Float] = []
    private var nextSourcePosition: Double = 0

    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        nextSourcePosition = 0
    }

    mutating func resample(_ samples: [Float], sourceSampleRate: Double, targetSampleRate: Double) -> [Float] {
        guard sourceSampleRate > 0, targetSampleRate > 0, !samples.isEmpty else {
            return []
        }

        pending.append(contentsOf: samples.map { sample in
            sample.isFinite ? min(max(sample, -1), 1) : 0
        })

        let step = sourceSampleRate / targetSampleRate
        var output: [Float] = []
        output.reserveCapacity(Int((Double(samples.count) / step).rounded(.up)) + 1)

        while true {
            let index = Int(nextSourcePosition.rounded(.down))
            guard index < pending.count else {
                break
            }

            let fraction = nextSourcePosition - Double(index)
            if fraction <= Double.ulpOfOne {
                output.append(pending[index])
            } else if index + 1 < pending.count {
                output.append(pending[index] + ((pending[index + 1] - pending[index]) * Float(fraction)))
            } else {
                break
            }

            nextSourcePosition += step
        }

        let drainCount = min(Int(nextSourcePosition.rounded(.down)), pending.count)
        if drainCount > 0 {
            pending.removeFirst(drainCount)
            nextSourcePosition -= Double(drainCount)
        }

        return output
    }
}
