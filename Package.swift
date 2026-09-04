// swift-tools-version: 6.3
import PackageDescription

// Shared settings applied to every target so quality rules cannot drift between modules.
let sharedSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MLX's macros expand to code written before ExistentialAny, so the one target that
// uses them cannot enforce it. Every other rule still applies there.
let mlxSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "Uttrflow",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "UttrflowCore", targets: ["UttrflowCore"]),
        .library(name: "UttrflowAudio", targets: ["UttrflowAudio"]),
        .library(name: "UttrflowPermissions", targets: ["UttrflowPermissions"]),
        .library(name: "UttrflowSpeech", targets: ["UttrflowSpeech"]),
        .library(name: "UttrflowAI", targets: ["UttrflowAI"]),
        .library(name: "UttrflowInput", targets: ["UttrflowInput"]),
        .library(name: "UttrflowPipeline", targets: ["UttrflowPipeline"]),
        .library(name: "UttrflowSettings", targets: ["UttrflowSettings"]),
        .library(name: "UttrflowUX", targets: ["UttrflowUX"]),
        .library(name: "UttrflowHistory", targets: ["UttrflowHistory"]),
        .library(name: "UttrflowDictionary", targets: ["UttrflowDictionary"]),
        .library(name: "UttrflowClipboard", targets: ["UttrflowClipboard"]),
        .library(name: "UttrflowAccount", targets: ["UttrflowAccount"]),
        .library(name: "UttrflowContext", targets: ["UttrflowContext"]),
        .library(name: "UttrflowPredict", targets: ["UttrflowPredict"]),
        .library(name: "UttrflowPredictStore", targets: ["UttrflowPredictStore"]),
        .library(name: "UttrflowPredictCapture", targets: ["UttrflowPredictCapture"]),
        // UttrflowEval is deliberately NOT a library product.
        //
        // It knows how to reach a private bucket holding real people's recordings, and
        // nothing a user installs may. A library product is an open door: one `import`
        // in a UX module — reached for the day a diagnostics pane wants a word error
        // rate — and the harness is in the shipped binary. Keeping it a target means
        // only this package's own executables can name it, which is a wall rather than
        // a test. The tests and bundle.sh check it too; this stops it being possible.
        .library(name: "UttrflowLocalModel", targets: ["UttrflowLocalModel"]),
        .executable(name: "Uttrflow", targets: ["Uttrflow"]),
        .executable(name: "uttrflow-dev", targets: ["uttrflow-dev"]),
        .executable(name: "uttrflow-bakeoff", targets: ["uttrflow-bakeoff"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.1.0"),
        // Updating the app in place. A dependency rather than something written here
        // because the hard part is not fetching a file — it is replacing a *running*
        // bundle without breaking its signature, its permissions or its menu bar item.
        // See Docs/releasing.md ("Updating").
        //
        // Pinned exactly, not `from:`. This one ships as a remote binary target — an
        // XCFramework downloaded from a release, checksummed in Sparkle's own manifest —
        // so a floating version means the bytes linked into a signed build can change
        // without anything in this repository changing.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.7.2"),
    ],
    targets: [
        // Platform-free domain layer: protocols, models, errors. Imports nothing but the stdlib.
        .target(name: "UttrflowCore", swiftSettings: sharedSwiftSettings),

        // Microphone capture. Everything that can be reasoned about without hardware —
        // resampling, accumulation, encoding — lives outside the AVAudioEngine boundary.
        .target(
            name: "UttrflowAudio",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Speech to text. One engine drives any recogniser that fits the backend
        // boundary; the recogniser-specific files behind it are kept trivially small.
        .target(
            name: "UttrflowSpeech",
            dependencies: [
                "UttrflowDictionary", "UttrflowCore", .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // Turning a raw transcript into the words the speaker meant. One transformer
        // serves every language model; the floor beneath them cannot invent anything.
        .target(
            name: "UttrflowAI",
            dependencies: ["UttrflowCore", "UttrflowDictionary"],
            swiftSettings: sharedSwiftSettings
        ),

        // An open-weight model on the Mac's GPU, for the languages Apple's does not
        // cover. Quarantined here because MLX needs Metal shaders that SwiftPM's
        // command line cannot build — nothing else in the package depends on it.
        .target(
            name: "UttrflowLocalModel",
            dependencies: [
                "UttrflowAI", "UttrflowCore", "UttrflowPredict",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            swiftSettings: mlxSwiftSettings
        ),

        // Getting finished text into whatever the user is typing in, and taking the keys
        // that accept a suggestion before the application beneath sees them.
        .target(
            name: "UttrflowInput",
            dependencies: ["UttrflowCore", "UttrflowPredict"],
            swiftSettings: sharedSwiftSettings
        ),

        // The whole product, expressed once, over protocols only.
        .target(
            name: "UttrflowPipeline",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // What the user has chosen, kept between launches.
        .target(
            name: "UttrflowSettings",
            dependencies: ["UttrflowCore", "UttrflowPredict"],
            swiftSettings: sharedSwiftSettings
        ),

        // What was dictated, kept between launches.
        //
        // Its own module rather than part of UttrflowSettings: a setting is something the
        // user chose and is tiny, whereas this grows without bound, ages out on a clock,
        // and is the one store whose contents are the user's own words.
        .target(
            name: "UttrflowHistory",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Everything the user has copied, and what it turns out to be.
        //
        // Its own module because the clipboard is a second product sharing one app: the
        // panel is opened dozens of times a day by people who never dictate, and nothing
        // in here should have to know that speech exists.
        .target(
            name: "UttrflowClipboard",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Words this user says that a general model does not know, and the index that
        // finds them by sound.
        //
        // Its own module because it is the one store queried during a dictation, on the
        // hot path, and because the rule that keeps it scalable — the prompt never grows
        // with the dictionary — is only enforceable if the lookup lives somewhere it can
        // be tested in isolation.
        .target(
            name: "UttrflowDictionary",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Who the user is, and what their subscription entitles them to.
        //
        // Knows nothing about networking: the backend is behind a protocol so the whole
        // of sign-in, session expiry and entitlement can be tested without a server.
        .target(
            name: "UttrflowAccount",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // What every window and menu should say, decided without drawing anything.
        //
        // The app target cannot be tested — its types own windows, menu bar items and
        // SwiftUI views, none of which exist without a running app. So the deciding
        // lives here, in a module that imports nothing but Core, and the views become
        // thin enough to read at a glance and to exclude from coverage honestly.
        .target(
            name: "UttrflowUX",
            dependencies: [
                "UttrflowAccount", "UttrflowClipboard", "UttrflowCore", "UttrflowDictionary",
                "UttrflowHistory", "UttrflowPredict",
                "UttrflowSettings",
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // What the user is looking at, so terms can be got right.
        .target(
            name: "UttrflowContext",
            dependencies: ["UttrflowCore", "UttrflowPredict"],
            swiftSettings: sharedSwiftSettings
        ),

        // What the user is about to type. Pure decisions; the store and the model are elsewhere.
        .target(
            name: "UttrflowPredict",
            swiftSettings: sharedSwiftSettings
        ),

        // The corpus on disk. The app's only SQL, over the system's own libsqlite3.
        .target(
            name: "UttrflowPredictStore",
            dependencies: ["UttrflowCore", "UttrflowPredict"],
            swiftSettings: sharedSwiftSettings
        ),

        // Noticing what the user finished entering and recording it, through the refusals
        // that keep secrets and other people's text out. Depends on UttrflowClipboard for the
        // one thing it must not reimplement: the rules that recognise a credential.
        .target(
            name: "UttrflowPredictCapture",
            dependencies: [
                "UttrflowClipboard", "UttrflowCore", "UttrflowPredict", "UttrflowPredictStore",
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // Measuring how well a transformer did. Pure scoring, no model anywhere near it.
        .target(
            name: "UttrflowEval",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Reading and requesting the permissions macOS gates the pipeline behind.
        .target(
            name: "UttrflowPermissions",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Fakes and builders shared by every test target. Never linked into the shipping app.
        .target(
            name: "UttrflowTestSupport",
            dependencies: ["UttrflowCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // Grows one command per phase, so every phase ends in something runnable.
        // Later becomes the evaluation harness.
        .executableTarget(
            name: "uttrflow-dev",
            dependencies: [
                "UttrflowAccount",
                "UttrflowCore", "UttrflowAI", "UttrflowAudio", "UttrflowContext", "UttrflowEval",
                "UttrflowInput", "UttrflowPermissions",
                "UttrflowSpeech",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // Phase 8's harness. Separate from uttrflow-dev because it records real speech
        // and writes a corpus, which is a different job from poking at one stage.
        .executableTarget(
            name: "uttrflow-eval",
            dependencies: [
                "UttrflowAI", "UttrflowAudio", "UttrflowCore", "UttrflowEval", "UttrflowSpeech",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // The app itself. Owns nothing but the wiring: everything worth testing lives
        // in a module a test can reach without a screen.
        .executableTarget(
            name: "Uttrflow",
            dependencies: [
                "UttrflowAI", "UttrflowAudio", "UttrflowContext", "UttrflowCore", "UttrflowInput",
                "UttrflowAccount", "UttrflowClipboard", "UttrflowDictionary",
                "UttrflowHistory", "UttrflowLocalModel", "UttrflowPermissions", "UttrflowPipeline",
                "UttrflowPredict", "UttrflowPredictCapture", "UttrflowPredictStore",
                "UttrflowSettings", "UttrflowSpeech", "UttrflowUX",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // The mark, for the panel and the menu bar slot. The bare monogram rather
            // than the app icon: that one is the mark on its ink tile, which on a dark
            // panel is a tile inside a tile. `Scripts/bundle.sh` seals every generated
            // resource bundle into Contents/Resources, so these reach the packaged app
            // without being named anywhere.
            resources: [.process("Resources")],
            swiftSettings: sharedSwiftSettings
        ),

        // Separate from uttrflow-dev because it links MLX, which needs a build that
        // SwiftPM's command line cannot do. Keeps the everyday tool light.
        .executableTarget(
            name: "uttrflow-bakeoff",
            dependencies: [
                "UttrflowAI", "UttrflowAudio", "UttrflowCore", "UttrflowEval", "UttrflowLocalModel",
                "UttrflowSpeech",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: mlxSwiftSettings
        ),

        .testTarget(
            name: "UttrflowCoreTests",
            dependencies: ["UttrflowCore", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowAudioTests",
            dependencies: ["UttrflowAudio", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowSpeechTests",
            dependencies: ["UttrflowSpeech", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowAITests",
            dependencies: ["UttrflowAI", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowLocalModelTests",
            dependencies: ["UttrflowLocalModel"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowTests",
            dependencies: ["Uttrflow"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowSettingsTests",
            dependencies: ["UttrflowPredict", "UttrflowSettings", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowClipboardTests",
            dependencies: ["UttrflowClipboard", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowDictionaryTests",
            dependencies: ["UttrflowDictionary", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowAccountTests",
            dependencies: ["UttrflowAccount", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowHistoryTests",
            dependencies: ["UttrflowHistory", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowUXTests",
            dependencies: ["UttrflowPredict", "UttrflowUX", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowPipelineTests",
            dependencies: ["UttrflowPipeline", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowInputTests",
            dependencies: ["UttrflowInput", "UttrflowPredict", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowContextTests",
            dependencies: ["UttrflowContext", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowPredictTests",
            dependencies: ["UttrflowPredict"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowPredictStoreTests",
            dependencies: ["UttrflowPredictStore"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowPredictCaptureTests",
            dependencies: [
                "UttrflowContext", "UttrflowPredict", "UttrflowPredictCapture", "UttrflowPredictStore",
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowEvalTests",
            dependencies: ["UttrflowAI", "UttrflowEval", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "UttrflowPermissionsTests",
            dependencies: ["UttrflowPermissions", "UttrflowTestSupport"],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
