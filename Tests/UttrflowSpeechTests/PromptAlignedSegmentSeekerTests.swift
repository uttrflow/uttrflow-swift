// Holds that a prompted decode's word timings are read from the transcript's alignment rows, not the prompt's.
import CoreML
import Testing
import WhisperKit

@testable import UttrflowSpeech

/// The segment seeker a prompted decode is given, and the alignment rows it reads.
@Suite("The prompt-aligned segment seeker")
struct PromptAlignedSegmentSeekerTests {
    /// Start-of-previous and three prompt words, which is where a three-word prompt puts the transcript.
    static let transcriptStart = 4

    /// One window's transcript: the four opening tokens, five words, and the closing timestamp.
    static let segmentTokens = [51, 52, 53, 58, 10, 11, 12, 13, 14, 59]

    /// Rows the fixture's decoder cache holds, more than the prompt and transcript together.
    static let rowCount = 24

    /// Columns of audio frames, each 20 ms.
    static let columnCount = 150

    // MARK: Where the transcript starts

    @Test("puts the transcript after the start-of-previous token and the prompt")
    func transcriptStartsAfterThePrompt() {
        let prefill = DecoderPrefill(promptTokens: [10, 11, 12], specialTokenBegin: 50, isMultilingual: true)

        #expect(prefill.transcriptStart == Self.transcriptStart)
    }

    @Test("puts the transcript at the first row when there is no prompt")
    func transcriptStartsAtZeroWithoutAPrompt() {
        #expect(
            DecoderPrefill(promptTokens: nil, specialTokenBegin: 50, isMultilingual: true).transcriptStart
                == 0)
        #expect(
            DecoderPrefill(promptTokens: [50, 57], specialTokenBegin: 50, isMultilingual: true)
                .transcriptStart == 0)
    }

    @Test("counts only the prompt tokens left after trimming")
    func transcriptStartFollowsTrimming() {
        let prefill = DecoderPrefill(
            promptTokens: Array(repeating: 10, count: VocabularyPrompt.maximumTokens + 40),
            specialTokenBegin: 50, isMultilingual: false)

        #expect(prefill.transcriptStart == VocabularyPrompt.maximumTokens + 1)
    }

    @Test("gives a prompted decode a seeker offset by the prompt, and an unprompted one WhisperKit's own")
    func seekerFollowsThePrompt() {
        let prompted = DecoderPrefill(
            promptTokens: [10, 11, 12], specialTokenBegin: 50, isMultilingual: true)
        let unprompted = DecoderPrefill(promptTokens: nil, specialTokenBegin: 50, isMultilingual: true)

        #expect(
            (prompted.segmentSeeker() as? PromptAlignedSegmentSeeker)?.transcriptStart == Self.transcriptStart
        )
        #expect(unprompted.segmentSeeker() is SegmentSeeker)
    }

    // MARK: The rows it reads

    @Test("drops the leading rows, keeps the shape, and zeroes the rows it runs out of")
    func shiftsRows() throws {
        let weights = try Self.weights(transcriptAt: 0)
        let shifted = try PromptAlignedSegmentSeeker.rows(of: weights, from: 3)

        #expect(shifted.shape == weights.shape)
        #expect(Self.peak(of: shifted, row: 0) == Self.peak(of: weights, row: 3))
        #expect(Self.value(in: shifted, row: Self.rowCount - 1, column: 0) == 0)
    }

    @Test("returns the weights untouched when the transcript already starts at the first row")
    func leavesUnshiftedWeightsAlone() throws {
        let weights = try Self.weights(transcriptAt: 0)

        #expect(try PromptAlignedSegmentSeeker.rows(of: weights, from: 0) === weights)
    }

    // MARK: Padded rows

    /// A width WhisperKit's own buffers use, which an IOSurface pads to 1504 elements a row.
    static let paddedColumns = 1500

    /// A float16 buffer made the way WhisperKit makes its alignment weights, each row's first element its row number.
    private static func upstreamWeights(rows: Int, columns: Int) throws -> MLMultiArray {
        let weights = try MLMultiArray(
            shape: [NSNumber(value: rows), NSNumber(value: columns)], dataType: .float16,
            initialValue: FloatType(0))
        for row in 0..<rows {
            weights[[NSNumber(value: row), 0]] = NSNumber(value: row)
            weights[[NSNumber(value: row), NSNumber(value: columns - 1)]] = NSNumber(value: row + 1000)
        }
        return weights
    }

    @Test("reads a padded upstream buffer by its rows, keeping every retained row and zeroing the tail")
    func shiftsPaddedRows() throws {
        let rows = 224
        let first = 4
        let weights = try Self.upstreamWeights(rows: rows, columns: Self.paddedColumns)
        let shifted = try PromptAlignedSegmentSeeker.rows(of: weights, from: first)

        #expect(weights.strides[0].intValue > Self.paddedColumns, "the fixture must have padded rows")
        #expect(shifted.shape == weights.shape)
        for row in 0..<(rows - first) {
            #expect(shifted[[NSNumber(value: row), 0]].intValue == row + first)
            #expect(
                shifted[[NSNumber(value: row), NSNumber(value: Self.paddedColumns - 1)]].intValue
                    == row + first + 1000)
        }
        for row in (rows - first)..<rows {
            #expect(shifted[[NSNumber(value: row), 0]].intValue == 0)
            #expect(shifted[[NSNumber(value: row), NSNumber(value: Self.paddedColumns - 1)]].intValue == 0)
        }
    }

    @Test("reads a column-major buffer element by element")
    func shiftsAColumnMajorBuffer() throws {
        let rows = 5
        let columns = 3
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: rows * columns)
        for row in 0..<rows {
            for column in 0..<columns { storage[column * rows + row] = Float(row * 10 + column) }
        }
        let weights = try MLMultiArray(
            dataPointer: storage, shape: [NSNumber(value: rows), NSNumber(value: columns)],
            dataType: .float32, strides: [1, NSNumber(value: rows)],
            deallocator: { $0.deallocate() })
        let shifted = try PromptAlignedSegmentSeeker.rows(of: weights, from: 2)

        for row in 0..<3 {
            for column in 0..<columns {
                #expect(
                    shifted[[NSNumber(value: row), NSNumber(value: column)]].floatValue
                        == Float((row + 2) * 10 + column))
            }
        }
        #expect(shifted[[4, 2]].floatValue == 0)
    }

    @Test(
        "sizes an element from its data type",
        arguments: [
            (MLMultiArrayDataType.float16, 2), (.float32, 4), (.double, 8), (.int32, 4),
        ])
    func elementSizes(dataType: MLMultiArrayDataType, bytes: Int) {
        #expect(PromptAlignedSegmentSeeker.elementBytes(of: dataType) == bytes)
    }

    // MARK: What the user gets

    /// WhisperKit reads row zero as the transcript's first token, which behind a prompt is the start-of-previous token.
    @Test("times a prompted transcript's words as if no prompt had been there")
    func timesWordsPastThePrompt() throws {
        let unprompted = try Self.words(
            seeker: SegmentSeeker(), weights: Self.weights(transcriptAt: 0))
        let prompted = try Self.words(
            seeker: PromptAlignedSegmentSeeker(transcriptStart: Self.transcriptStart),
            weights: Self.weights(transcriptAt: Self.transcriptStart))

        #expect(!unprompted.isEmpty)
        #expect(prompted == unprompted)
    }

    /// The same timings when the prompted weights come in WhisperKit's own padded buffer, as they do in the app.
    @Test("times a prompted transcript's words the same from a padded upstream buffer")
    func timesWordsFromAPaddedBuffer() throws {
        let unprompted = try Self.words(
            seeker: SegmentSeeker(),
            weights: Self.weights(transcriptAt: 0, columns: Self.paddedColumns))
        let prompted = try Self.words(
            seeker: PromptAlignedSegmentSeeker(transcriptStart: Self.transcriptStart),
            weights: Self.weights(
                transcriptAt: Self.transcriptStart, columns: Self.paddedColumns, upstream: true))

        #expect(!unprompted.isEmpty)
        #expect(prompted == unprompted)
    }

    @Test("differs from WhisperKit's own seeker behind a prompt, which is the defect it exists for")
    func whisperKitsSeekerMisreadsAPrompt() throws {
        let unprompted = try Self.words(
            seeker: SegmentSeeker(), weights: Self.weights(transcriptAt: 0))
        let misread = try Self.words(
            seeker: SegmentSeeker(), weights: Self.weights(transcriptAt: Self.transcriptStart))

        #expect(misread != unprompted)
    }

    @Test("finds seek points and segments exactly as WhisperKit's own seeker does")
    func delegatesSeeking() {
        var result = DecodingResult.emptyResults
        result.tokens = [51, 52, 53, 58, 10, 11, 60, 60, 12, 13, 62, 50]
        result.tokenLogProbs = result.tokens.map { [$0: -0.1] }
        let arguments = (seek: 16_000, size: 480_000, rate: 16_000)

        let expected = SegmentSeeker().findSeekPointAndSegments(
            decodingResult: result, options: DecodingOptions(), allSegmentsCount: 0,
            currentSeek: arguments.seek,
            segmentSize: arguments.size, sampleRate: arguments.rate, timeToken: 58, specialToken: 50,
            tokenizer: WordPerToken())
        let actual = PromptAlignedSegmentSeeker(transcriptStart: Self.transcriptStart)
            .findSeekPointAndSegments(
                decodingResult: result, options: DecodingOptions(), allSegmentsCount: 0,
                currentSeek: arguments.seek,
                segmentSize: arguments.size, sampleRate: arguments.rate, timeToken: 58, specialToken: 50,
                tokenizer: WordPerToken())

        #expect(actual.0 == expected.0)
        #expect(actual.1?.map(\.text) == expected.1?.map(\.text))
    }

    /// The word timings a seeker gives the fixture's one segment.
    private static func words(seeker: any SegmentSeeking, weights: MLMultiArray) throws -> [WordTiming] {
        let segment = TranscriptionSegment(
            start: 0, end: 3, text: " w10 w11 w12 w13 w14", tokens: segmentTokens,
            tokenLogProbs: segmentTokens.map { [$0: -0.1] })
        let segments = try seeker.addWordTimestamps(
            segments: [segment], alignmentWeights: weights, tokenizer: WordPerToken(), seek: 0,
            segmentSize: 480_000, prependPunctuations: Constants.defaultPrependPunctuations,
            appendPunctuations: Constants.defaultAppendPunctuations, lastSpeechTimestamp: 0,
            options: DecodingOptions(), timings: TranscriptionTimings())
        return segments?.flatMap { $0.words ?? [] } ?? []
    }

    /// The fixture's weights in a buffer `columns` wide, written by logical index so a padded upstream buffer holds the same values.
    private static func weights(
        transcriptAt start: Int, columns: Int, upstream: Bool = false
    ) throws -> MLMultiArray {
        let shape = [NSNumber(value: rowCount), NSNumber(value: columns)]
        let weights =
            upstream
            ? try MLMultiArray(shape: shape, dataType: .float16, initialValue: FloatType(0))
            : try MLMultiArray(shape: shape, dataType: .float16)
        for row in 0..<rowCount {
            for column in 0..<columns { weights[[NSNumber(value: row), NSNumber(value: column)]] = 0 }
        }
        for row in 0..<start { weights[[NSNumber(value: row), NSNumber(value: columns - 1)]] = 1 }
        for token in 0..<segmentTokens.count {
            weights[[NSNumber(value: start + token), NSNumber(value: 12 * token)]] = 1
        }
        return weights
    }

    /// Alignment weights with the transcript's tokens marching across the audio from `start`, and a prompt looking at the end before it.
    private static func weights(transcriptAt start: Int) throws -> MLMultiArray {
        let weights = try MLMultiArray(
            shape: [NSNumber(value: rowCount), NSNumber(value: columnCount)], dataType: .float16)
        weights.withUnsafeMutableBufferPointer(ofType: FloatType.self) { buffer, _ in
            for index in 0..<buffer.count { buffer[index] = 0 }
            for row in 0..<start { buffer[row * columnCount + columnCount - 1] = 1 }
            for token in 0..<segmentTokens.count { buffer[(start + token) * columnCount + 12 * token] = 1 }
        }
        return weights
    }

    /// The column a row looks at hardest.
    private static func peak(of weights: MLMultiArray, row: Int) -> Int {
        (0..<columnCount).max {
            value(in: weights, row: row, column: $0) < value(in: weights, row: row, column: $1)
        } ?? 0
    }

    private static func value(in weights: MLMultiArray, row: Int, column: Int) -> FloatType {
        weights.withUnsafeBufferPointer(ofType: FloatType.self) { $0[row * columnCount + column] }
    }
}

/// A tokeniser that reads every token as a word of its own, so a word's timing is its token's.
private struct WordPerToken: WhisperTokenizer {
    let specialTokens = DecoderPrefillTests.specialTokens
    let allLanguageTokens: Set<Int> = [52]

    func encode(text: String) -> [Int] { [] }

    func decode(tokens: [Int]) -> String {
        tokens.map { $0 < specialTokens.specialTokenBegin ? " w\($0)" : "<|\($0)|>" }.joined()
    }

    func convertTokenToId(_ token: String) -> Int? { nil }

    func convertIdToToken(_ id: Int) -> String? { nil }

    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        (tokenIds.map { decode(tokens: [$0]) }, tokenIds.map { [$0] })
    }
}
