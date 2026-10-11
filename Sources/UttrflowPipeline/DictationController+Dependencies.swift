public import UttrflowCore

extension DictationController {
    /// The pipeline, gesture sources and recording sounds a controller owns for its lifetime.
    public struct Dependencies: Sendable {
        let pipeline: DictationPipeline
        let monitor: any HotkeyMonitoring
        let commandMonitor: (any HotkeyMonitoring)?
        let cue: any RecordingCueing

        /// Connects the dictation route and its gesture sources, with silent recording cues unless supplied.
        public init(
            pipeline: DictationPipeline, monitor: any HotkeyMonitoring,
            commandMonitor: (any HotkeyMonitoring)? = nil, cue: any RecordingCueing = SilentCue()
        ) {
            self.pipeline = pipeline
            self.monitor = monitor
            self.commandMonitor = commandMonitor
            self.cue = cue
        }
    }
}
