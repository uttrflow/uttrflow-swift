import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Whether a clean-up engine can finish its work with the network switched off.
///
/// Written as an exhaustive switch rather than a list of allowed kinds so that adding
/// a ``TransformerKind`` fails to compile until somebody has decided which side of the
/// offline promise it falls on. A list would quietly admit a new engine as safe, which
/// is exactly the regression these tests exist to catch.
private func runsWithoutNetwork(_ kind: TransformerKind) -> Bool {
    switch kind {
    case .foundationModels: true  // Apple's model, already on this Mac.
    case .localModel: true  // Open weights, already on disk.
    case .rules: true  // String arithmetic; it cannot reach anything.
    case .cloud: false  // The one engine that is a network call.
    }
}

/// An endpoint no build should ever honour. Reserved by RFC 2606, so a test that
/// wrongly reached it would fail to resolve rather than hitting somebody's server.
private let refusedEndpoint = "https://cloud.invalid/tidy"

/// The dictation path must never touch the network once the speech model is present.
///
/// The static half of that promise is audited by `Scripts/offline_audit.sh`, which
/// reads the sources and the linked binary; the dynamic half is recorded in
/// `Docs/offline.md`. These tests cover what neither can: that the *assembly* of
/// engines refuses a network one even when a caller offers it one. Every test here is
/// pure — none of them needs the network, or its absence, to pass.
@Suite("Offline guarantee")
struct OfflineGuaranteeTests {
    /// A hosted endpoint is an argument, not a compile-time switch, so nothing stops a
    /// caller passing one. In a build without `UTTRFLOW_CLOUD` it must be ignored
    /// rather than honoured — otherwise the flag would guard the type but not the door.
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

    /// The check that has to keep holding after somebody adds an engine: whatever the
    /// build assembles, all of it must run on this Mac alone.
    @Test("every engine the shipping build assembles runs without the network")
    func assembledEnginesAreAllLocal() throws {
        #if !UTTRFLOW_CLOUD
            let endpoint = try #require(URL(string: refusedEndpoint))
            for kind in TextTransformers.all(cloudEndpoint: endpoint).map(\.kind) {
                #expect(runsWithoutNetwork(kind), "\(kind.rawValue) needs the network to work")
            }
        #endif
    }

    /// `route` is what the pipeline will actually try, in order. Asserting on it rather
    /// than on the engine list catches a preference that reaches a network engine even
    /// when the engine list itself looks innocent.
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

    /// Settings are decoded from disk, so a preference written by a cloud-enabled build
    /// — or by hand — can name an engine this binary does not contain. It must be
    /// dropped before it reaches the router, not after.
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

    /// The compile-time gate and the offline classification have to agree. If a kind is
    /// selectable in a build without cloud support, it is by definition one the user
    /// can be routed to with no connection, so it had better not need one.
    @Test("every kind this build lets the user select works offline")
    func selectableKindsAreLocal() {
        #if !UTTRFLOW_CLOUD
            for kind in TransformerKind.selectable {
                #expect(runsWithoutNetwork(kind), "\(kind.rawValue) is selectable but needs the network")
            }
        #endif
    }
}
