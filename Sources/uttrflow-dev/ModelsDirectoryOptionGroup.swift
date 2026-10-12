import ArgumentParser
import Foundation
import UttrflowSpeech

/// Selects the directory used by developer commands to find or install WhisperKit models.
struct ModelsDirectoryOptionGroup: ParsableArguments {
    @Option(name: .long, help: "Directory for downloaded speech models.")
    var modelsDir: String?

    func store(creatingDirectory: Bool = false) throws -> FileSystemSpeechModelStore {
        guard let modelsDir else { return FileSystemSpeechModelStore.whisperKit() }
        guard !modelsDir.isEmpty else { throw ValidationError("--models-dir must not be empty.") }

        let root = URL(fileURLWithPath: modelsDir).standardizedFileURL
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ValidationError("--models-dir must point to a directory: \(root.path)")
            }
        } else if creatingDirectory {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            } catch {
                print("Could not create models directory at \(root.path): \(error)")
                throw ExitCode.failure
            }
        } else {
            throw ValidationError("Models directory does not exist: \(root.path)")
        }

        return FileSystemSpeechModelStore.whisperKit(root: root)
    }
}
