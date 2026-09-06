import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Whether an engine finishes with the network off; an exhaustive switch, so a new kind must decide.
private func runsWithoutNetwork(_ kind: TransformerKind) -> Bool {
    switch kind {
    case .foundationModels: true  // Apple's model, already on this Mac.
    case .localModel: true  // Open weights, already on disk.
    case .rules: true  // String arithmetic; it cannot reach anything.
    case .cloud: false  // The one engine that is a network call.
    }
}

/// An endpoint on an RFC 2606 reserved host, so a test that wrongly reaches it fails to resolve.
private let refusedEndpoint = "https://cloud.invalid/tidy"

/// The assembly of engines refuses a network engine even when offered one. See Docs/offline.md.
@Suite("Offline guarantee")
struct OfflineGuaranteeTests {
    /// A build without `UTTRFLOW_CLOUD` must ignore a supplied endpoint, or the flag guards the type only.
    @Test("a supplied endpoint cannot smuggle a network engine into a build without one")
    func endpointIsIgnoredWithoutCloudSupport() throws {
        let endpoint = try #require(URL(string: refusedEndpoint))
        let offered = TextTransformers.all(cloudEndpoint: endpoint).map(\.kind)

        #if UTTRFLOW_CLOUD
            #expect(offered.contains(.cloud), "a cloud build given an endpoint should use it")
        #else
            #expect(
                offered == TextTransformers.all().map(\.kind),
                "an endpoint changed which engines exist in a build compiled without cloud support"
            )
        #endif
    }

    /// Whatever the build assembles must run on this Mac alone, even after an engine is added.
    @Test("every engine the shipping build assembles runs without the network")
    func assembledEnginesAreAllLocal() throws {
        #if !UTTRFLOW_CLOUD
            let endpoint = try #require(URL(string: refusedEndpoint))
            for kind in TextTransformers.all(cloudEndpoint: endpoint).map(\.kind) {
                #expect(runsWithoutNetwork(kind), "\(kind.rawValue) needs the network to work")
            }
        #endif
    }

    /// `route` is what the pipeline tries, so a preference reaching a network engine is caught here.
    @Test("the route the pipeline will take reaches no network engine")
    func shippingRouteIsLocal() throws {
        #if !UTTRFLOW_CLOUD
            let endpoint = try #require(URL(string: refusedEndpoint))
            let route = TextTransformers.router(configuration: .default, cloudEndpoint: endpoint).route

            #expect(!route.isEmpty, "a route with nothing in it would dead-end every dictation")
            for kind in route {
                #expect(runsWithoutNetwork(kind), "the default route reaches \(kind.rawValue)")
            }
        #endif
    }

    /// A stored preference, from a cloud build or by hand, can name an engine this binary lacks.
    @Test("a stored preference asking for the cloud is dropped, not honoured")
    func storedCloudPreferenceIsDropped() {
        #if !UTTRFLOW_CLOUD
            let stored = EngineConfiguration(
                speech: .whisperKit, transformerPreference: [.cloud, .foundationModels, .rules]
            )

            #expect(!stored.resolvedTransformerPreference.contains(.cloud))
            for kind in stored.resolvedTransformerPreference {
                #expect(runsWithoutNetwork(kind), "a stored preference resolved to \(kind.rawValue)")
            }
        #endif
    }

    /// A kind selectable in a build without cloud support must not need a connection.
    @Test("every kind this build lets the user select works offline")
    func selectableKindsAreLocal() {
        #if !UTTRFLOW_CLOUD
            for kind in TransformerKind.selectable {
                #expect(runsWithoutNetwork(kind), "\(kind.rawValue) is selectable but needs the network")
            }
        #endif
    }
}
