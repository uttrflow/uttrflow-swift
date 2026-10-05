// Runs the Whisper Core ML models over a job file to test whether a decoder prefix cache transfers between clips.
// See Docs/speech-vocabulary-prompt.md. Usage: swift prefix_cache_probe.swift <model-dir> <job.json> <out.json>
import CoreML
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: prefix_cache_probe <model-dir> <job.json> <out.json>\n".utf8))
    exit(2)
}
let modelDir = URL(fileURLWithPath: arguments[1])
let job = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))) as? [String: Any] ?? [:]
let clips = job["clips"] as? [String] ?? []
let prompts = job["prompts"] as? [String: [Int]] ?? [:]
let tail = job["tail"] as? [Int] ?? []
let endToken = job["end"] as? Int ?? 0
let maxNewTokens = job["max_new_tokens"] as? Int ?? 96

/// Loads one model on the compute units the app uses for it (WhisperKitBackend).
func load(_ name: String, _ units: MLComputeUnits = .cpuAndNeuralEngine) throws -> MLModel {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = units
    return try MLModel(contentsOf: modelDir.appendingPathComponent("\(name).mlmodelc"), configuration: configuration)
}
let melModel = try load("MelSpectrogram", .cpuAndGPU)
let encoderModel = try load("AudioEncoder")
let decoderModel = try load("TextDecoder")
let contextPrefillModel = try load("TextDecoderContextPrefill")

let channels = 5120
let layerWidth = 1280
let context = 224

/// A self-attention cache laid out as the decoder takes it: channel-major, one column per position.
struct Cache {
    var keys = [Float](repeating: 0, count: channels * context)
    var values = [Float](repeating: 0, count: channels * context)
    var length = 0
}

/// An array with contiguous strides, so a flat write lands where its index says; Core ML pads the last axis otherwise.
func array(_ shape: [Int], _ type: MLMultiArrayDataType = .float16) throws -> MLMultiArray {
    let count = shape.reduce(1, *)
    let strides = shape.indices.map { shape[($0 + 1)...].reduce(1, *) }
    let memory = UnsafeMutableRawPointer.allocate(byteCount: count * 4, alignment: 64)
    memory.initializeMemory(as: UInt8.self, repeating: 0, count: count * 4)
    return try MLMultiArray(
        dataPointer: memory, shape: shape.map { NSNumber(value: $0) }, dataType: type,
        strides: strides.map { NSNumber(value: $0) }, deallocator: { $0.deallocate() })
}

/// Reads an output whose only non-unit axis is the last, the shape of the logits.
func floats(_ value: MLMultiArray) -> [Float] {
    value.withUnsafeBufferPointer(ofType: Float16.self) { buffer in (0..<value.count).map { Float(buffer[$0]) } }
}

func fill(_ target: MLMultiArray, _ source: [Float]) {
    target.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
        for index in source.indices { buffer[index] = Float16(source[index]) }
    }
}

func readWave(_ path: String) throws -> [Float] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var samples = [Float]()
    var offset = 12
    while offset + 8 <= data.count {
        let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = data[offset + 4..<offset + 8].withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self)) }
        if id == "data" {
            let body = data[offset + 8..<min(data.count, offset + 8 + size)]
            body.withUnsafeBytes { raw in
                for index in 0..<(body.count / 2) {
                    samples.append(Float(raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)) / 32768)
                }
            }
            break
        }
        offset += 8 + size
    }
    return samples
}

func encode(_ path: String) throws -> MLMultiArray {
    var samples = try readWave(path)
    samples = Array(samples.prefix(480_000)) + [Float](repeating: 0, count: max(0, 480_000 - samples.count))
    let audio = try array([480_000])
    fill(audio, samples)
    let mel = try melModel.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": audio]))
    let encoded = try encoderModel.prediction(from: mel)
    guard let embeds = encoded.featureValue(for: "encoder_output_embeds")?.multiArrayValue else {
        throw NSError(domain: "probe", code: 1)
    }
    // The encoder pads its last axis; the decoder is handed a contiguous copy.
    let rowStride = embeds.strides[1].intValue
    let copy = try array([1, 1280, 1, 1500])
    embeds.withUnsafeBufferPointer(ofType: Float16.self) { source in
        copy.withUnsafeMutableBufferPointer(ofType: Float16.self) { target, _ in
            for row in 0..<1280 {
                for column in 0..<1500 { target[row * 1500 + column] = source[row * rowStride + column] }
            }
        }
    }
    return copy
}

/// Feeds one token at the cache's next position over `encoder`, appends its keys and values, and returns its logits.
func step(_ token: Int, _ cache: inout Cache, _ encoder: MLMultiArray) throws -> [Float] {
    let position = cache.length
    let ids = try array([1], .int32)
    ids[0] = NSNumber(value: token)
    let length = try array([1], .int32)
    length[0] = NSNumber(value: position)
    let keys = try array([1, channels, 1, context])
    fill(keys, cache.keys)
    let values = try array([1, channels, 1, context])
    fill(values, cache.values)
    let update = try array([1, context])
    fill(update, (0..<context).map { $0 == position ? 1 : 0 })
    let padding = try array([1, context])
    fill(padding, (0..<context).map { $0 <= position ? 0 : -10_000 })
    let output = try decoderModel.prediction(from: MLDictionaryFeatureProvider(dictionary: [
        "input_ids": ids, "cache_length": length, "key_cache": keys, "value_cache": values,
        "kv_cache_update_mask": update, "encoder_output_embeds": encoder, "decoder_key_padding_mask": padding,
    ]))
    guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
        let keyUpdates = output.featureValue(for: "key_cache_updates")?.multiArrayValue,
        let valueUpdates = output.featureValue(for: "value_cache_updates")?.multiArrayValue
    else { throw NSError(domain: "probe", code: 2) }
    for channel in 0..<channels {
        cache.keys[channel * context + position] = keyUpdates[[0, channel, 0, 0] as [NSNumber]].floatValue
        cache.values[channel * context + position] = valueUpdates[[0, channel, 0, 0] as [NSNumber]].floatValue
    }
    cache.length += 1
    return floats(logits)
}

func argmax(_ values: [Float]) -> Int {
    values.indices.max { values[$0] < values[$1] } ?? 0
}

/// Copies the first `count` positions of `source` into a fresh cache.
func prefix(_ source: Cache, _ count: Int) -> Cache {
    var cache = Cache()
    for channel in 0..<channels {
        for position in 0..<count {
            cache.keys[channel * context + position] = source.keys[channel * context + position]
            cache.values[channel * context + position] = source.values[channel * context + position]
        }
    }
    cache.length = count
    return cache
}

/// Finishes the forced run from the cache's length on `encoder`, then decodes greedily.
func finish(_ forced: [Int], _ start: Cache, _ encoder: MLMultiArray) throws -> (first: [Float], tokens: [Int]) {
    var cache = start
    var logits = [Float]()
    for token in forced[cache.length...] { logits = try step(token, &cache, encoder) }
    let first = logits
    var tokens = [Int]()
    while tokens.count < maxNewTokens, cache.length < context {
        let next = argmax(logits)
        if next == endToken { break }
        tokens.append(next)
        logits = try step(next, &cache, encoder)
    }
    return (first, tokens)
}

/// The largest absolute key and value difference per decoder layer over the first `count` positions.
func layerDifferences(_ a: Cache, _ b: Cache, _ count: Int) -> [Float] {
    (0..<(channels / layerWidth)).map { layer in
        var largest: Float = 0
        for channel in (layer * layerWidth)..<((layer + 1) * layerWidth) {
            for position in 0..<count {
                let index = channel * context + position
                largest = max(largest, abs(a.keys[index] - b.keys[index]), abs(a.values[index] - b.values[index]))
            }
        }
        return largest
    }
}

/// The three-position cache the library's context-prefill model looks up without seeing any audio.
func libraryPrefill(language: Int, task: Int) throws -> Cache {
    let languageInput = try array([1], .int32)
    languageInput[0] = NSNumber(value: language)
    let taskInput = try array([1], .int32)
    taskInput[0] = NSNumber(value: task)
    let prefill = try contextPrefillModel.prediction(
        from: MLDictionaryFeatureProvider(dictionary: ["task": taskInput, "language": languageInput]))
    guard let keys = prefill.featureValue(for: "key_cache_prefill")?.multiArrayValue,
        let values = prefill.featureValue(for: "value_cache_prefill")?.multiArrayValue
    else { throw NSError(domain: "probe", code: 3) }
    var cache = Cache()
    for channel in 0..<channels {
        for position in 0..<3 {
            let index = [0, channel, 0, position] as [NSNumber]
            cache.keys[channel * context + position] = keys[index].floatValue
            cache.values[channel * context + position] = values[index].floatValue
        }
    }
    cache.length = 3
    return cache
}

func compare(_ reference: (first: [Float], tokens: [Int]), _ other: (first: [Float], tokens: [Int])) -> [String: Any] {
    let difference = zip(reference.first, other.first).map { abs($0 - $1) }.max() ?? 0
    return [
        "max_logit_diff": difference,
        "top1_same": argmax(reference.first) == argmax(other.first),
        "tokens": other.tokens,
        "transcript_same": reference.tokens == other.tokens,
    ]
}

let start = Date()
let encoders = try clips.map(encode)
FileHandle.standardError.write(Data("encoded \(encoders.count) clips\n".utf8))
var results = [String: Any]()
for (name, prompt) in prompts.sorted(by: { $0.key < $1.key }) {
    let forced = prompt + tail
    let prefixLength = forced.count - 1
    let promptLength = prompt.count
    var own = [Cache]()
    for encoder in encoders {
        var cache = Cache()
        for token in forced[..<prefixLength] { _ = try step(token, &cache, encoder) }
        own.append(cache)
    }
    var rows = [[String: Any]]()
    for index in clips.indices {
        let donor = (index + 1) % clips.count
        let reference = try finish(forced, own[index], encoders[index])
        let repeated = try finish(forced, own[index], encoders[index])
        var row: [String: Any] = [
            "clip": clips[index], "reference": reference.tokens,
            "repeat": compare(reference, repeated),
            "whole_prefix": compare(reference, try finish(forced, prefix(own[donor], prefixLength), encoders[index])),
            "layer_diff": layerDifferences(own[index], own[donor], prefixLength),
        ]
        if promptLength > 0 {
            row["prompt_only"] = compare(
                reference, try finish(forced, prefix(own[donor], promptLength), encoders[index]))
        } else {
            // The library's lookup table is indexed by language token and a 0 or 1 task; the right task reproduces layer 0 exactly.
            let library = try [0, 1].map { try libraryPrefill(language: tail[1], task: $0) }
                .min { layerDifferences(own[index], $0, 3)[0] < layerDifferences(own[index], $1, 3)[0] } ?? Cache()
            row["library_prefill"] = compare(reference, try finish(forced, library, encoders[index]))
            row["library_layer_diff"] = layerDifferences(own[index], library, 3)
        }
        rows.append(row)
        FileHandle.standardError.write(Data("\(name) clip \(index + 1)/\(clips.count)\n".utf8))
    }
    results[name] = rows
}
results["seconds"] = Date().timeIntervalSince(start)
try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]).write(to: URL(fileURLWithPath: arguments[3]))
