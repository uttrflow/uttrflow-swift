// The evaluation harness's root command.
import ArgumentParser

/// The evaluation harness: records a corpus once, then measures transcription against it.
@main
struct UttrflowEvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-eval",
        abstract: "Measure how well Uttrflow hears and how fast it answers.",
        subcommands: [
            RecordCorpus.self, PullCorpus.self, TranscribeCorpus.self, TailProbe.self, CueBleedProbe.self,
            AnnouncementBleedProbe.self,
            RetryParityProbe.self, SynthesiseCorpus.self, NonSpeechProbe.self, HomophoneConfidenceProbe.self,
            AccentProbe.self, AccentCalibrationProbe.self, NormaliseText.self, FitFromTable.self,
            FallbackSweepProbe.self, ClosedPhraseMarksProbe.self, HarvestConfusions.self,
            FinalPieceProbe.self, PronunciationKeyProbe.self, OmissionCoverageProbe.self, WordDoubtProbe.self,
            AccentGroupReport.self, RelistenProbe.self, HomophoneTable.self, LearningCurve.self,
            PathCoverageProbe.self, AccuracyReportCommand.self, ShortClipProbe.self, SilenceStopProbe.self,
            CommandRecallProbe.self, EnglishWords.self, CompareRuns.self, InputLevelProbe.self,
            ConfusablePairsProbe.self, CalibrateGate.self, GuidedReadProbe.self,
            DigitStringProbe.self, NameClassProbe.self, NoiseProbe.self,
        ]
    )
}
