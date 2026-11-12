// Tests which input channel reaches the converter and the channel map that selects it.
import AVFoundation
import Testing

@testable import UttrflowAudio

@Suite("ChannelSelector")
struct ChannelSelectorTests {
    @Test("builds one single-entry channel map per input channel")
    func buildsOneMapPerChannel() {
        let selector = ChannelSelector(channelCount: 4)

        #expect(selector.maps.map { $0.map(\.intValue) } == [[0], [1], [2], [3]])
        #expect(selector.selected == 0)
    }

    @Test("hands over the loudest channel's prebuilt map, not a new array")
    func switchesToPrebuiltMap() throws {
        let selector = ChannelSelector(channelCount: 4)
        let block = try Self.block(loudest: 2, of: 4)

        let map = try #require(selector.mapIfChanged(for: block))

        #expect(map.map(\.intValue) == [2])
        #expect(selector.selected == 2)
        #expect(Self.storage(of: map) == Self.storage(of: selector.maps[2]))
        #expect((map as NSArray) === (selector.maps[2] as NSArray))
    }

    @Test("installs nothing while the selected channel stays loudest")
    func keepsMapWhileChannelHolds() throws {
        let selector = ChannelSelector(channelCount: 4)
        let first = try Self.block(loudest: 0, of: 4)
        let louder = try Self.block(loudest: 3, of: 4)

        #expect(selector.mapIfChanged(for: first) == nil)
        #expect(selector.mapIfChanged(for: louder)?.map(\.intValue) == [3])
        #expect(selector.mapIfChanged(for: louder) == nil)
        #expect(selector.selected == 3)
    }

    @Test("returns to channel 0's prebuilt map when channel 0 is loudest again")
    func switchesBackToFirstChannel() throws {
        let selector = ChannelSelector(channelCount: 2)
        _ = selector.mapIfChanged(for: try Self.block(loudest: 1, of: 2))

        let map = try #require(selector.mapIfChanged(for: try Self.block(loudest: 0, of: 2)))

        #expect(map.map(\.intValue) == [0])
        #expect(Self.storage(of: map) == Self.storage(of: selector.maps[0]))
        #expect(selector.selected == 0)
    }

    @Test("reads the loudest channel out of an interleaved block")
    func selectsInterleavedChannel() throws {
        let format = try #require(
            SyntheticAudio.format(sampleRate: 48_000, channels: 2, interleaved: true))
        let block = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_048))
        block.frameLength = 2_048
        let buffers = UnsafeMutableAudioBufferListPointer(block.mutableAudioBufferList)
        let samples = try #require(buffers.first?.mData).assumingMemoryBound(to: Float.self)
        for frame in 0..<Int(block.frameLength) {
            samples[frame * 2] = 0.1
            samples[frame * 2 + 1] = 0.4
        }
        let selector = ChannelSelector(channelCount: 2)

        #expect(selector.mapIfChanged(for: block)?.map(\.intValue) == [1])
    }

    @Test("a mono input has one map and never switches")
    func monoNeverSwitches() throws {
        let selector = ChannelSelector(channelCount: 1)
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let block = try #require(SyntheticAudio.constant(0.5, frames: 2_048, format: format))

        #expect(selector.maps.map { $0.map(\.intValue) } == [[0]])
        #expect(selector.mapIfChanged(for: block) == nil)
    }

    /// A 2048-frame deinterleaved block whose `loudest` channel carries the most energy.
    private static func block(loudest: Int, of channels: AVAudioChannelCount) throws -> AVAudioPCMBuffer {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: channels))
        var amplitudes = Array(repeating: Float(0.1), count: Int(channels))
        amplitudes[loudest] = 0.5
        return try #require(
            SyntheticAudio.tone(
                frequency: 440, frames: 2_048, format: format, channelAmplitudes: amplitudes))
    }

    /// The address of an array's element storage, equal for two arrays only when they share it.
    private static func storage(of map: [NSNumber]) -> UnsafeRawPointer? {
        map.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }
}
