import Foundation
import Testing

@testable import UttrflowCore

@Suite("Uttrflow build identities")
struct UttrflowBuildIdentityTests {
    private func isHeldElsewhere(_ outcome: SingleInstanceLock.Outcome) -> Bool {
        if case .heldElsewhere = outcome { return true }
        return false
    }

    @Test("A build is recognised by identifier prefix, or by executable outside the prefix")
    func recognisesBuildsByIdentifierOrExecutable() {
        #expect(UttrflowBuildIdentity.isUttrflow("com.uttrflow.Uttrflow"))
        #expect(UttrflowBuildIdentity.isUttrflow("com.uttrflow.Uttrflow.dev"))
        #expect(!UttrflowBuildIdentity.isUttrflow("com.apple.finder"))
        #expect(UttrflowBuildIdentity.isUttrflow("com.example.fork", executableName: "Uttrflow"))
        #expect(UttrflowBuildIdentity.isUttrflow(nil, executableName: "Uttrflow"))
        #expect(!UttrflowBuildIdentity.isUttrflow("com.example.other", executableName: "Other"))
    }

    @Test("Only a suffixed Uttrflow identifier identifies an isolated development build")
    func recognizesDevelopmentVariants() {
        #expect(UttrflowBuildIdentity.isDevelopmentBuild("com.uttrflow.Uttrflow.dev"))
        #expect(!UttrflowBuildIdentity.isDevelopmentBuild("com.uttrflow.Uttrflow"))
        #expect(!UttrflowBuildIdentity.isDevelopmentBuild("com.uttrflow.Uttrflow."))
        #expect(!UttrflowBuildIdentity.isDevelopmentBuild("com.example.Uttrflow.dev"))
    }

    @Test("Unknown identifiers are reported as sharing the production data folder")
    func recognizesProductionFolderFallback() {
        #expect(UttrflowBuildIdentity.usesProductionFolder("com.example.Uttrflow.dev"))
        #expect(UttrflowBuildIdentity.usesProductionFolder(nil))
        #expect(!UttrflowBuildIdentity.usesProductionFolder("com.uttrflow.Uttrflow.dev"))
    }

    @Test("Variants have separate store locks and one shared startup coordination lock")
    func separatesStoreLocksFromCoordinationLock() {
        let directory = URL(filePath: "/tmp/uttrflow-locks", directoryHint: .isDirectory)
        let productionStoreLock = LocalStore.file(
            "instance.lock", in: directory, for: "com.uttrflow.Uttrflow")
        let developmentStoreLock = LocalStore.file(
            "instance.lock", in: directory, for: "com.uttrflow.Uttrflow.dev")
        #expect(productionStoreLock != developmentStoreLock)
        #expect(
            SingleInstanceLock.coordinationFile(in: directory).path(percentEncoded: false)
                == "/tmp/uttrflow-locks/Uttrflow/instance-coordination.lock"
        )
    }

    @Test("The shared guard arbitrates before independent data-store locks")
    func coordinatesIndependentStoreLocks() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "uttrflow-build-locks-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinationFile = SingleInstanceLock.coordinationFile(in: directory)
        guard case .acquired(let coordinationLock) = SingleInstanceLock.acquire(at: coordinationFile) else {
            Issue.record("the first build did not take the shared coordination lock")
            return
        }
        let productionStore = SingleInstanceLock.acquire(
            at: LocalStore.file("instance.lock", in: directory, for: LocalStore.productionIdentifier))
        guard case .acquired(let productionLock) = productionStore
        else {
            Issue.record("the coordination winner did not take its store lock")
            return
        }

        #expect(isHeldElsewhere(SingleInstanceLock.acquire(at: coordinationFile)))
        // A current-protocol loser is stopped by coordination before claiming its own store lock.
        guard
            case .acquired(let developmentLock) = SingleInstanceLock.acquire(
                at: LocalStore.file("instance.lock", in: directory, for: "com.uttrflow.Uttrflow.dev"))
        else {
            Issue.record("the startup loser should not yet hold its independent store lock")
            return
        }
        withExtendedLifetime((productionLock, developmentLock, coordinationLock)) {}
    }

    @Test("A pre-coordination build remains visible through its per-store lock")
    func findsOlderBuildHoldingItsStoreLock() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "uttrflow-legacy-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard
            case .acquired(let legacyStoreLock) = SingleInstanceLock.acquire(
                at: SingleInstanceLock.defaultFile(in: directory, for: "com.uttrflow.Uttrflow.dev"))
        else {
            Issue.record("the older build did not take its store lock")
            return
        }
        guard
            case .acquired(let coordinationLock) = SingleInstanceLock.acquire(
                at: SingleInstanceLock.coordinationFile(in: directory))
        else {
            Issue.record("the new build did not take the shared coordination lock")
            return
        }
        #expect(
            isHeldElsewhere(
                SingleInstanceLock.acquire(
                    at: SingleInstanceLock.defaultFile(in: directory, for: "com.uttrflow.Uttrflow.dev"))))
        withExtendedLifetime((legacyStoreLock, coordinationLock)) {}
    }
}
