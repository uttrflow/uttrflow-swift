// Tests the cue spec, the shaping arithmetic, the system sound lookup and the fallback chain, in silence.
import AVFoundation
import Foundation
import Synchronization
import Testing

@testable import UttrflowAudio

@Suite("CueSound")
struct CueSoundTests {
    @Test("the start cue is Pop, three semitones down, low-passed at 3 kHz, at 0.7")
    func startSpec() {
        #expect(CueSound.start.sound == SystemSound("Pop"))
        #expect(CueSound.start.semitones == -3)
        #expect(CueSound.start.lowPassHz == 3000)
        #expect(CueSound.start.volume == 0.7)
    }

    @Test("the stop cue is Tink, nine semitones down, low-passed at 2.2 kHz, at 0.7")
    func stopSpec() {
        #expect(CueSound.stop.sound == SystemSound("Tink"))
        #expect(CueSound.stop.semitones == -9)
        #expect(CueSound.stop.lowPassHz == 2200)
        #expect(CueSound.stop.volume == 0.7)
    }

    @Test("the warning cue is Glass and differs from the start and stop cues")
    func warningSpec() {
        #expect(CueSound.warning.sound == SystemSound("Glass"))
        #expect(CueSound.warning.semitones == -3)
        #expect(CueSound.warning.lowPassHz == 3000)
        #expect(CueSound.warning.volume == 0.7)
        #expect(CueSound.warning != CueSound.start)
        #expect(CueSound.warning != CueSound.stop)
    }

    @Test("the discarded cue is Bottle, softer than the stop cue")
    func discardedSpec() {
        #expect(CueSound.discarded.sound == SystemSound("Bottle"))
        #expect(CueSound.discarded.semitones == -7)
        #expect(CueSound.discarded.lowPassHz == 1800)
        #expect(CueSound.discarded.volume < CueSound.stop.volume)
    }

    @Test("the four cues are told apart")
    func cuesDiffer() {
        #expect(CueSound.start != CueSound.stop)
        #expect(Set([CueSound.start, CueSound.stop, CueSound.warning, CueSound.discarded]).count == 4)
    }

    @Test(
        "a semitone shift reads the source at 2^(n/12) speed",
        arguments: [
            (0.0, 1.0), (12, 2), (-12, 0.5), (-24, 0.25), (7, 1.498_307), (-3, 0.840_896), (-9, 0.594_604),
        ]
    )
    func playbackRate(semitones: Double, rate: Double) {
        let cue = CueSound("Pop", semitones: semitones, lowPassHz: 1000, volume: 1)
        #expect(abs(cue.playbackRate - rate) < 1e-6)
    }
}

@Suite("CueShaping")
struct CueShapingTests {
    @Test("reading at half speed doubles the length and interpolates between samples")
    func halfSpeed() {
        #expect(CueShaping.resample([0, 1, 2, 3], step: 0.5) == [0, 0.5, 1, 1.5, 2, 2.5, 3])
    }

    @Test("reading at double speed halves the length")
    func doubleSpeed() {
        #expect(CueShaping.resample([0, 1, 2, 3, 4], step: 2) == [0, 2, 4])
    }

    @Test("reading at the source speed changes nothing")
    func unitSpeed() {
        #expect(CueShaping.resample([0.25, -0.5, 1], step: 1) == [0.25, -0.5, 1])
    }

    @Test("nothing to read, or no speed to read it at, gives nothing", arguments: [0.0, -1, .infinity, .nan])
    func degenerateStep(step: Double) {
        #expect(CueShaping.resample([1, 2, 3], step: step).isEmpty)
        #expect(CueShaping.resample([], step: 1).isEmpty)
    }

    @Test("a single sample survives any speed")
    func singleSample() {
        #expect(CueShaping.resample([0.5], step: 0.25) == [0.5])
    }

    @Test("the low-pass matches the browser formula, with Q read in decibels")
    func lowPassCoefficients() {
        let biquad = CueShaping.lowPass(cutoff: 12_000, sampleRate: 48_000)
        let alpha = 1 / (2 * pow(10, 0.5 / 20))
        let a0 = 1 + alpha
        #expect(abs(biquad.b0 - 0.5 / a0) < 1e-12)
        #expect(abs(biquad.b1 - 1 / a0) < 1e-12)
        #expect(abs(biquad.b2 - 0.5 / a0) < 1e-12)
        #expect(abs(biquad.a1) < 1e-12)
        #expect(abs(biquad.a2 - (1 - alpha) / a0) < 1e-12)
    }

    @Test("a cutoff at or past Nyquist passes the signal untouched")
    func cutoffPastNyquist() {
        #expect(
            CueShaping.lowPass(cutoff: 24_000, sampleRate: 48_000) == .init(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
        )
        #expect(
            CueShaping.filter([0.5, -0.25, 1], CueShaping.lowPass(cutoff: 30_000, sampleRate: 48_000)) == [
                0.5, -0.25, 1,
            ])
    }

    @Test("a cutoff at or under zero mutes the signal")
    func cutoffAtZero() {
        #expect(
            CueShaping.filter([0.5, -0.25, 1], CueShaping.lowPass(cutoff: 0, sampleRate: 48_000)) == [
                0, 0, 0,
            ])
    }

    @Test("the low-pass passes a steady level at unity")
    func unityAtDirectCurrent() {
        let output = CueShaping.filter(
            Array(repeating: 0.5, count: 4800), CueShaping.lowPass(cutoff: 2200, sampleRate: 48_000))
        #expect(abs((output.last ?? 0) - 0.5) < 1e-4)
    }

    @Test("the low-pass keeps a tone under its cutoff and strips one far above it")
    func attenuatesAboveCutoff() {
        let lowPass = CueShaping.lowPass(cutoff: 2200, sampleRate: 48_000)
        let below = peak(CueShaping.filter(tone(hertz: 200), lowPass).suffix(2400))
        let above = peak(CueShaping.filter(tone(hertz: 12_000), lowPass).suffix(2400))
        #expect(below > 0.95)
        #expect(above < 0.05)
    }

    @Test("shaping lengthens a sound as it lowers it, and scales it by the cue's volume")
    func shapeChain() {
        let cue = CueSound("Pop", semitones: -12, lowPassHz: 24_000, volume: 0.5)
        let shaped = CueShaping.shape([1, 1, 1, 1, 1], sourceRate: 48_000, cue: cue, outputRate: 48_000)
        #expect(shaped == Array(repeating: 0.5, count: 9))
    }

    @Test("shaping converts the source rate as it pitches")
    func shapeConvertsRate() {
        let cue = CueSound("Pop", semitones: 0, lowPassHz: 48_000, volume: 1)
        let shaped = CueShaping.shape(
            Array(repeating: 1, count: 441), sourceRate: 44_100, cue: cue, outputRate: 48_000)
        #expect(shaped.count == 479)
    }

    private func tone(hertz: Double) -> [Float] {
        (0..<4800).map { Float(sin(2 * .pi * hertz * Double($0) / 48_000)) }
    }

    private func peak(_ samples: ArraySlice<Float>) -> Float {
        samples.map(abs).max() ?? 0
    }
}

@Suite("SystemSoundFile")
struct SystemSoundFileTests {
    @Test("finds the stop cue's sound where macOS keeps it")
    func findsSystemSound() throws {
        let url = try #require(SystemSoundFile.url(for: CueSound.stop.sound))
        #expect(url.deletingPathExtension().lastPathComponent == "Tink")
    }

    @Test("finds nothing for a name the system has no sound for")
    func missingName() {
        #expect(SystemSoundFile.url(for: SystemSound("NoSuchSound-\(UUID())")) == nil)
        #expect(SystemSoundFile.load(SystemSound("NoSuchSound-\(UUID())")) == nil)
    }

    @Test("decodes both cues' sounds into one channel of audio")
    func decodesCues() throws {
        for cue in [CueSound.start, CueSound.stop, CueSound.warning, CueSound.discarded] {
            let file = try #require(SystemSoundFile.load(cue.sound))
            #expect(file.sampleRate > 0)
            #expect(file.samples.contains { $0 != 0 })
        }
    }

    @Test("a sound in an earlier directory wins over the system's own")
    func earlierDirectoryWins() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cue-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try #require(SystemSoundFile.url(for: SystemSound("Tink")))
        let replacement = directory.appending(path: "Tink.aiff")
        try FileManager.default.copyItem(at: original, to: replacement)

        let found = SystemSoundFile.url(
            for: SystemSound("Tink"), in: [directory, original.deletingLastPathComponent()])
        #expect(found?.standardizedFileURL == replacement.standardizedFileURL)
    }

    @Test("a file that is not audio decodes to nothing")
    func notAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cue-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not audio".utf8).write(to: directory.appending(path: "Broken.aiff"))

        #expect(SystemSoundFile.load(SystemSound("Broken"), in: [directory]) == nil)
    }

    @Test("the search follows NSSound's order, ending in the system's sounds")
    func searchOrder() {
        let paths = SystemSoundFile.searchDirectories.map(\.path)
        #expect(paths.suffix(2) == ["/Library/Sounds", "/System/Library/Sounds"])
        #expect(paths.first?.hasSuffix("/Library/Sounds") == true)
    }
}

/// A player that remembers every cue and answers with a fixed result.
private final class ScriptedPlayer: SoundPlayer {
    private let heard: Bool
    private let log = Mutex<(played: [CueSound], prewarmed: [CueSound])>(([], []))

    init(heard: Bool) {
        self.heard = heard
    }

    func play(_ sound: CueSound) -> Bool {
        log.withLock { $0.played.append(sound) }
        return heard
    }

    func prewarm(_ sounds: [CueSound]) {
        log.withLock { $0.prewarmed.append(contentsOf: sounds) }
    }

    var played: [CueSound] { log.withLock { $0.played } }
    var prewarmed: [CueSound] { log.withLock { $0.prewarmed } }
}

@Suite("FallbackSoundPlayer")
struct FallbackSoundPlayerTests {
    @Test("plays the shaped cue and never touches the fallback when it is heard")
    func primaryHeard() {
        let shaped = ScriptedPlayer(heard: true)
        let plain = ScriptedPlayer(heard: true)

        #expect(FallbackSoundPlayer([shaped, plain]).play(.start))
        #expect(shaped.played == [.start])
        #expect(plain.played.isEmpty)
    }

    @Test("hands the same cue to the plain player when the shaped one fails")
    func fallsBack() {
        let shaped = ScriptedPlayer(heard: false)
        let plain = ScriptedPlayer(heard: true)

        #expect(FallbackSoundPlayer([shaped, plain]).play(.stop))
        #expect(shaped.played == [.stop])
        #expect(plain.played == [.stop])
    }

    @Test("ends in silence, reporting nothing heard, when every player fails")
    func silentWhenAllFail() {
        let shaped = ScriptedPlayer(heard: false)
        let plain = ScriptedPlayer(heard: false)

        #expect(!FallbackSoundPlayer([shaped, plain]).play(.start))
        #expect(plain.played == [.start])
        #expect(!FallbackSoundPlayer([]).play(.start))
    }

    @Test("warms every player it holds")
    func prewarmsAll() {
        let shaped = ScriptedPlayer(heard: true)
        let plain = ScriptedPlayer(heard: true)

        FallbackSoundPlayer([shaped, plain]).prewarm([.start, .stop])

        #expect(shaped.prewarmed == [.start, .stop])
        #expect(plain.prewarmed == [.start, .stop])
    }

    @Test("an unheard shaped start still sounds, so the recording cue owes its stop")
    func recordingCueArmsThroughFallback() {
        let shaped = ScriptedPlayer(heard: false)
        let plain = ScriptedPlayer(heard: true)
        let cue = SoundPlayingRecordingCue(player: FallbackSoundPlayer([shaped, plain]))

        cue.playStart()
        cue.playStop()

        #expect(plain.played == [.start, .stop])
    }
}

@Suite("CueEngineWiring")
struct CueEngineWiringTests {
    @Test("feeds a cue's player node into the engine's main mixer")
    func wiresIntoMixer() throws {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))

        CueEngineWiring.wire(node, into: engine, format: format)

        #expect(engine.attachedNodes.contains(node))
        #expect(engine.outputConnectionPoints(for: node, outputBus: 0).map(\.node) == [engine.mainMixerNode])
        #expect(node.outputFormat(forBus: 0) == format)
    }
}
