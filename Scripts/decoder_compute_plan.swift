// Splits the text decoder's estimated cost into the cross-attention key and value projections and the rest.
//
// Usage: swift Scripts/decoder_compute_plan.swift <TextDecoder.mlmodelc> [steps]
// Prints the Core ML compute plan's share of estimated cost for operations that read only the encoder
// output, then times `steps` single-token predictions on zero inputs. Reads a local model; no network.

import CoreML
import Foundation

@main
struct DecoderComputePlan {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            print("usage: decoder_compute_plan.swift <TextDecoder.mlmodelc> [steps]")
            exit(2)
        }
        let url = URL(fileURLWithPath: arguments[1])
        let steps = arguments.count > 2 ? Int(arguments[2]) ?? 100 : 100
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let plan = try await MLComputePlan.load(contentsOf: url, configuration: configuration)
        guard case .program(let program) = plan.modelStructure, let main = program.functions["main"] else {
            print("not an ML program")
            exit(1)
        }
        // A value is encoder-only when it depends on the encoder output and on no other model input.
        var encoderOnly: Set<String> = ["encoder_output_embeds"]
        var perToken: Set<String> = Set(main.inputs.map(\.name)).subtracting(encoderOnly)
        var total = 0.0
        var projected = 0.0
        var devices: [String: Double] = [:]
        var projectionOps = 0
        for operation in main.block.operations {
            let weight = plan.estimatedCost(of: operation)?.weight ?? 0
            total += weight
            let names = operation.inputs.values.flatMap { $0.bindings }.compactMap { binding -> String? in
                if case .name(let name) = binding { return name }
                return nil
            }
            let outputs = operation.outputs.map(\.name)
            if names.contains(where: perToken.contains) {
                perToken.formUnion(outputs)
            } else if names.contains(where: encoderOnly.contains) {
                encoderOnly.formUnion(outputs)
                projected += weight
                projectionOps += 1
            }
            if let usage = plan.deviceUsage(for: operation) {
                devices[describe(usage.preferred), default: 0] += weight
            }
        }
        let share = total > 0 ? projected / total : 0
        print(String(format: "encoder-only operations: %d, estimated cost share %.3f", projectionOps, share))
        for (device, weight) in devices.sorted(by: { $0.value > $1.value }) {
            print(String(format: "preferred device %@: cost share %.3f", device, weight / max(total, 1e-12)))
        }
        try time(url: url, configuration: configuration, steps: steps)
    }

    static func describe(_ device: MLComputeDevice) -> String {
        switch device {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .neuralEngine: "Neural Engine"
        @unknown default: "other"
        }
    }

    /// Median and p95 milliseconds per single-token step over zero-filled inputs, after five warm-up steps.
    static func time(url: URL, configuration: MLModelConfiguration, steps: Int) throws {
        let model = try MLModel(contentsOf: url, configuration: configuration)
        var features: [String: MLFeatureValue] = [:]
        for (name, description) in model.modelDescription.inputDescriptionsByName {
            guard let constraint = description.multiArrayConstraint else { continue }
            let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
            features[name] = MLFeatureValue(multiArray: array)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: features)
        var samples: [Double] = []
        for step in 0..<(steps + 5) {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try model.prediction(from: provider)
            if step >= 5 { samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6) }
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
        print(String(format: "steps %d: median %.2f ms, p95 %.2f ms, %.1f steps/s", steps, median, p95, 1000 / median))
    }
}
