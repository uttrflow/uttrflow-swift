import ArgumentParser
import Foundation
import UttrflowSpeech

/// Installs, lists and removes speech models.
struct Models: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage installed speech models.",
        subcommands: [List.self, Install.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show what is available and installed.")

        func run() async throws {
            let store = FileSystemSpeechModelStore.whisperKit()
            print("Models in \(store.root.path)\n")
            for model in SpeechModel.catalogue {
                let installed = store.isInstalled(model)
                let size = store.bytesOnDisk(model).map { " \(megabytes($0)) on disk" } ?? ""
                let marker = installed ? "✓" : " "
                let isDefault = model == .default ? "  (default)" : ""
                print("  \(marker) \(model.variant)")
                print("      \(megabytes(model.downloadBytes)) download\(size)\(isDefault)")
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download a speech model.")

        @Option(name: .shortAndLong, help: "Model variant. Defaults to the shipping model.")
        var model: String?

        func run() async throws {
            let model = try resolve(model)
            let store = FileSystemSpeechModelStore.whisperKit()
            if store.isInstalled(model) {
                print("\(model.variant) is already installed.")
                return
            }

            print("Installing \(model.variant) — \(megabytes(model.downloadBytes))\n")
            let url = try await store.install(model) { fraction in
                let width = 30
                let filled = Int((fraction * Double(width)).rounded())
                let bar =
                    String(repeating: "▇", count: filled)
                    + String(repeating: " ", count: width - filled)
                FileHandle.standardError.write(
                    Data("\r  [\(bar)] \(Int((fraction * 100).rounded()))% ".utf8)
                )
            }
            FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
            print("Installed to \(url.path)")
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a downloaded model.")

        @Option(name: .shortAndLong) var model: String?

        func run() async throws {
            let model = try resolve(model)
            let store = FileSystemSpeechModelStore.whisperKit()
            guard store.isInstalled(model) else {
                print("\(model.variant) is not installed.")
                return
            }
            try store.remove(model)
            print("Removed \(model.variant).")
        }
    }
}

/// Resolves a variant name, defaulting to the shipping model.
func resolve(_ variant: String?) throws -> SpeechModel {
    guard let variant else { return .default }
    guard let model = SpeechModel.named(variant) else {
        throw ValidationError(
            "Unknown model '\(variant)'. Known: "
                + SpeechModel.catalogue.map(\.variant).joined(separator: ", ")
        )
    }
    return model
}

func megabytes(_ bytes: Int64) -> String {
    String(format: "%.0f MB", Double(bytes) / 1_000_000)
}
