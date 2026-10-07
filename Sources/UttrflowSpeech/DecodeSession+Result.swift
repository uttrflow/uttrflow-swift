// What a decode session filters with, reports while it runs, and returns once a window is done.
import CoreML
import Foundation
import Synchronization
import WhisperKit

/// A caller's progress callback, run off the decoding path, whose `false` past the prefill ends the window.
final class EarlyStop: Sendable {
    private let callback: TranscriptionCallback
    private let requested = Mutex(false)

    init(callback: @escaping TranscriptionCallback) {
        self.callback = callback
    }

    var isRequested: Bool { requested.withLock { $0 } }

    func report(_ progress: TranscriptionProgress, isPrefill: Bool) {
        Task.detached(priority: .low) { [self] in
            if callback(progress) == false, !isPrefill { requested.withLock { $0 = true } }
        }
    }
}

extension DecodeSession {
    /// The decoder's own filters, then the suppression and timestamp rules the options ask for, in WhisperKit's order.
    func logitsFilters(promptCount: Int) -> [any LogitsFiltering] {
        var filters = decoder.logitsFilters ?? []
        if options.suppressBlank {
            filters.append(
                SuppressBlankFilter(specialTokens: tokenizer.specialTokens, sampleBegin: promptCount))
        }
        let suppressed = options.suppressTokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        if !options.suppressTokens.isEmpty {
            filters.append(SuppressTokensFilter(suppressTokens: suppressed))
        }
        if !options.withoutTimestamps {
            filters.append(
                TimestampRulesFilter(
                    specialTokens: tokenizer.specialTokens, sampleBegin: promptCount,
                    maxInitialTimestampIndex: options.maxInitialTimestamp.map {
                        Int($0 / WhisperKit.secondsPerTimeToken)
                    },
                    isModelMultilingual: decoder.isModelMultilingual))
        }
        return filters
    }

    /// The transcript so far, as WhisperKit hands it to a progress callback.
    func transcriptionProgress(of progress: Progress) -> TranscriptionProgress {
        let words = progress.tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return TranscriptionProgress(
            timings: progress.timings,
            text: tokenizer.decode(tokens: options.skipSpecialTokens ? words : progress.tokens),
            tokens: progress.tokens,
            avgLogprob: progress.logProbs.reduce(0, +) / Float(progress.logProbs.count),
            compressionRatio: TextUtilities.compressionRatio(of: progress.tokens))
    }

    /// The window's result, cut from start of transcript to end of text, as WhisperKit cuts it.
    func result(of progress: Progress, sampler: any TokenSampling) -> DecodingResult {
        let final = sampler.finalize(tokens: progress.tokens, logProbs: progress.logProbs)
        let special = tokenizer.specialTokens
        let start = final.tokens.firstIndex(of: special.startOfTranscriptToken) ?? 0
        let end = final.tokens.firstIndex(of: special.endToken) ?? final.tokens.count
        let tokens = Array(final.tokens[start...end])
        let logProbs = Array(final.logProbs[start...end])
        let tokenLogProbs = zip(tokens, logProbs).map { [$0: $1] }
        let avgLogProb = logProbs.reduce(0, +) / Float(logProbs.count)
        let compressionRatio = TextUtilities.compressionRatio(
            of: tokens.filter { $0 < special.specialTokenBegin })
        let (language, languageProbs) = language(of: tokens, tokenLogProbs: tokenLogProbs)
        // WhisperKit has no no-speech probability yet and writes zero; parity keeps its zero.
        let noSpeechProb: Float = 0
        return DecodingResult(
            language: language, languageProbs: languageProbs, tokens: tokens, tokenLogProbs: tokenLogProbs,
            text: tokenizer.decode(tokens: tokens), avgLogProb: avgLogProb, noSpeechProb: noSpeechProb,
            temperature: Self.temperature(of: sampler, options: options), compressionRatio: compressionRatio,
            cache: DecodingCache(
                keyCache: inputs.keyCache, valueCache: inputs.valueCache,
                alignmentWeights: progress.hasAlignment ? inputs.alignmentWeights : nil),
            timings: progress.timings,
            fallback: DecodingFallback(
                options: options, isFirstTokenLogProbTooLow: progress.isFirstTokenLogProbTooLow,
                noSpeechProb: noSpeechProb, compressionRatio: compressionRatio, avgLogProb: avgLogProb))
    }

    /// A greedy sampler's temperature to three places, else the options'.
    static func temperature(of sampler: any TokenSampling, options: DecodingOptions) -> Float {
        guard let greedy = sampler as? GreedyTokenSampler else { return options.temperature }
        return (Float(greedy.temperature) * 1000).rounded() / 1000
    }

    /// The language asked for, or the first language token decoded with its log-probability.
    private func language(
        of tokens: [Int], tokenLogProbs: [[Int: Float]]
    ) -> (String, [String: Float]) {
        let asked = options.language ?? Constants.defaultLanguageCode
        guard options.language == nil else { return (asked, [asked: 0]) }
        guard let index = tokens.firstIndex(where: tokenizer.allLanguageTokens.contains) else {
            return (asked, [asked: 0])
        }
        let language = tokenizer.decode(tokens: [tokens[index]]).trimmingSpecialTokenCharacters()
        return (language, [language: tokenLogProbs[index][tokens[index]] ?? 0])
    }
}
