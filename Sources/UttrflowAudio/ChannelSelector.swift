// Chooses the loudest input channel of each block and the converter channel map that selects it.
import AVFoundation

/// Picks the strongest input channel per block; every map and total is built at init. See Docs/audio-capture.md.
final class ChannelSelector {
    /// One single-entry channel map per input channel, so a switch on the tap installs one and builds none.
    let maps: [[NSNumber]]
    /// The channel whose map is installed; a converter starts on channel 0.
    private(set) var selected = 0
    private var energy: [Double]

    init(channelCount: AVAudioChannelCount) {
        let count = max(Int(channelCount), 1)
        maps = (0..<count).map { [NSNumber(value: $0)] }
        energy = Array(repeating: 0, count: count)
    }

    /// The map to install when `block`'s strongest channel differs from the selected one, else `nil`.
    func mapIfChanged(for block: AVAudioPCMBuffer) -> [NSNumber]? {
        let channel = strongestChannel(in: block)
        guard channel != selected else { return nil }
        selected = channel
        return maps[channel]
    }

    /// Selects the channel with the most energy so inactive channels and phase cancellation do not erase speech.
    private func strongestChannel(in input: AVAudioPCMBuffer) -> Int {
        let channelCount = Int(input.format.channelCount)
        guard channelCount > 1, input.frameLength > 0, energy.count == channelCount else { return 0 }
        for channel in energy.indices { energy[channel] = 0 }

        switch input.format.commonFormat {
        case .pcmFormatFloat32:
            Self.accumulateEnergy(in: input, into: &energy) { (sample: Float) in Double(sample) }
        case .pcmFormatFloat64:
            Self.accumulateEnergy(in: input, into: &energy) { (sample: Double) in sample }
        case .pcmFormatInt16:
            Self.accumulateEnergy(in: input, into: &energy) { (sample: Int16) in Double(sample) }
        case .pcmFormatInt32:
            Self.accumulateEnergy(in: input, into: &energy) { (sample: Int32) in Double(sample) }
        default:
            return 0
        }

        var strongest = 0
        for channel in 1..<channelCount where energy[channel] > energy[strongest] {
            strongest = channel
        }
        return strongest
    }

    private static func accumulateEnergy<Sample>(
        in input: AVAudioPCMBuffer, into energy: inout [Double], convert: (Sample) -> Double
    ) {
        let channelCount = Int(input.format.channelCount)
        let frames = Int(input.frameLength)
        let buffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        if input.format.isInterleaved {
            guard buffers.count == 1, let memory = buffers[0].mData else { return }
            let samples = memory.assumingMemoryBound(to: Sample.self)
            for frame in 0..<frames {
                for channel in 0..<channelCount {
                    let sample = convert(samples[frame * channelCount + channel])
                    energy[channel] += sample * sample
                }
            }
        } else {
            guard buffers.count == channelCount else { return }
            for channel in 0..<channelCount {
                guard let memory = buffers[channel].mData else { return }
                let samples = memory.assumingMemoryBound(to: Sample.self)
                for frame in 0..<frames {
                    let sample = convert(samples[frame])
                    energy[channel] += sample * sample
                }
            }
        }
    }
}
