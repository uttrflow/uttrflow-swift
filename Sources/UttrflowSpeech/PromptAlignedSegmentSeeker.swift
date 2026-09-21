// Word timings for a prompted decode, read from the alignment rows the transcript actually occupies.
import CoreML
import WhisperKit

/// WhisperKit's segment seeker, handed alignment weights that start at the transcript rather than at the prompt. See `Docs/speech-engines.md`.
struct PromptAlignedSegmentSeeker: SegmentSeeking {
    /// The alignment row of the start-of-transcript token, which WhisperKit's seeker assumes is row zero.
    let transcriptStart: Int

    /// The seeker that does the work once the rows are lined up.
    let inner: any SegmentSeeking

    init(transcriptStart: Int, inner: any SegmentSeeking = SegmentSeeker()) {
        self.transcriptStart = transcriptStart
        self.inner = inner
    }

    func findSeekPointAndSegments(
        decodingResult: DecodingResult,
        options: DecodingOptions,
        allSegmentsCount: Int,
        currentSeek seek: Int,
        segmentSize: Int,
        sampleRate: Int,
        timeToken: Int,
        specialToken: Int,
        tokenizer: any WhisperTokenizer
    ) -> (Int, [TranscriptionSegment]?) {
        inner.findSeekPointAndSegments(
            decodingResult: decodingResult, options: options, allSegmentsCount: allSegmentsCount,
            currentSeek: seek, segmentSize: segmentSize, sampleRate: sampleRate, timeToken: timeToken,
            specialToken: specialToken, tokenizer: tokenizer)
    }

    func addWordTimestamps(
        segments: [TranscriptionSegment],
        alignmentWeights: MLMultiArray,
        tokenizer: any WhisperTokenizer,
        seek: Int,
        segmentSize: Int,
        prependPunctuations: String,
        appendPunctuations: String,
        lastSpeechTimestamp: Float,
        options: DecodingOptions,
        timings: TranscriptionTimings
    ) throws -> [TranscriptionSegment]? {
        try inner.addWordTimestamps(
            segments: segments,
            alignmentWeights: Self.rows(of: alignmentWeights, from: transcriptStart),
            tokenizer: tokenizer, seek: seek, segmentSize: segmentSize,
            prependPunctuations: prependPunctuations, appendPunctuations: appendPunctuations,
            lastSpeechTimestamp: lastSpeechTimestamp, options: options, timings: timings)
    }

    /// The weights with their first `first` rows removed and zero rows appended, so the shape is unchanged.
    static func rows(of weights: MLMultiArray, from first: Int) throws -> MLMultiArray {
        guard first > 0, weights.shape.count == 2 else { return weights }
        let rowCount = weights.shape[0].intValue
        let columnCount = weights.shape[1].intValue
        let shifted = try MLMultiArray(shape: weights.shape, dataType: weights.dataType)
        let kept = max(0, rowCount - first)
        let element = elementBytes(of: weights.dataType)
        // Read from the array's own strides, since an IOSurface-backed row is padded past its last column.
        let from = weights.strides.map(\.intValue)
        weights.withUnsafeBytes { source in
            shifted.withUnsafeMutableBytes { destination, strides in
                destination.initializeMemory(as: UInt8.self, repeating: 0)
                guard kept > 0, let read = source.baseAddress, let write = destination.baseAddress else {
                    return
                }
                for row in 0..<kept {
                    let sourceRow = read.advanced(by: (first + row) * from[0] * element)
                    let destinationRow = write.advanced(by: row * strides[0] * element)
                    if from[1] == 1, strides[1] == 1 {
                        destinationRow.copyMemory(from: sourceRow, byteCount: columnCount * element)
                        continue
                    }
                    for column in 0..<columnCount {
                        let value = sourceRow.advanced(by: column * from[1] * element)
                        destinationRow.advanced(by: column * strides[1] * element)
                            .copyMemory(from: value, byteCount: element)
                    }
                }
            }
        }
        return shifted
    }

    /// Bytes in one element, which the data type carries in its low byte as a count of bits.
    static func elementBytes(of dataType: MLMultiArrayDataType) -> Int {
        (dataType.rawValue & 0xFF) / 8
    }
}
