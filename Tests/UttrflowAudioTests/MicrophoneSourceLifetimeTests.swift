// Tests that the real microphone source lets go of its session, without opening the microphone.
import Testing

@testable import UttrflowAudio

@Suite("AVAudioEngineMicrophoneSource lifetime")
struct MicrophoneSourceLifetimeTests {
    @Test("a released source takes its session with it")
    func releasedSourceReleasesSession() {
        weak var session: InputDeviceSession?
        do {
            let source = AVAudioEngineMicrophoneSource()
            session = source.session
            #expect(session != nil)
        }
        #expect(session == nil)
    }

    @Test("a stopped and released source takes its session with it")
    func stoppedSourceReleasesSession() async {
        weak var session: InputDeviceSession?
        weak var released: AVAudioEngineMicrophoneSource?
        do {
            let source = AVAudioEngineMicrophoneSource()
            released = source
            session = source.session
            await source.stop(draining: false)
        }
        #expect(released == nil)
        #expect(session == nil)
    }
}
