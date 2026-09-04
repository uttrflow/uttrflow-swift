import UttrflowPredict

extension FixtureCatalogue {
    /// An address bar with the person's recent URLs, and three kinds of search field with their recent queries.
    static let url: [Scenario] = [
        Scenario(
            category: "url", name: "address",
            situation: GenerationSituation(
                application: "Chrome", field: "Address and search bar", windowTitle: "New Tab",
                recentLines: [
                    "github.com/brightleaf/api/pulls", "localhost:3000/dashboard", "linear.app/brightleaf/team",
                    "developer.apple.com/documentation/swift", "github.com/brightleaf/web/issues",
                    "stackoverflow.com/questions",
                ]),
            cuts: .address, determinacy: .address, band: 1...60,
            known: ["github.com/brightleaf/web", "localhost:8000/docs", "docs.python.org/3"],
            lines: [
                "github.com/brightleaf/api/pulls", "github.com/brightleaf/web/issues",
                "developer.apple.com/documentation/swift", "stackoverflow.com/questions", "docs.python.org/3/library",
                "localhost:3000/dashboard", "localhost:8000/docs", "linear.app/brightleaf/team",
                "en.wikipedia.org/wiki/Autocomplete", "news.ycombinator.com", "npmjs.com/package/zod",
                "developer.mozilla.org/en-US/docs/Web", "swiftpackageindex.com", "figma.com/files",
            ]),
        Scenario(
            category: "url", name: "web-search",
            situation: GenerationSituation(
                application: "Safari", field: "Search or enter website name", windowTitle: "Start Page",
                recentLines: [
                    "swift actors tutorial", "docker compose restart one service", "weather tomorrow",
                    "python list comprehension", "flights to goa december",
                ]),
            cuts: .prose, determinacy: .any, band: 1...50,
            lines: [
                "swift concurrency actors", "docker compose restart single service", "best coffee grinder under 100",
                "weather tomorrow", "how to renew a passport", Line("python list comprehension", determinacy: .word),
                "flights to goa in december", "bookcase 80cm wide", "swiftui list performance",
                Line("kubectl rollout restart", determinacy: .word),
            ]),
        Scenario(
            category: "url", name: "finder",
            situation: GenerationSituation(
                application: "Finder", field: "Search", windowTitle: "Documents",
                recentLines: ["invoice august", "tax 2025", "invoice july", "lease", "passport scan"]),
            cuts: .clause, determinacy: .word, band: 1...30,
            known: ["invoice june", "tax return 2024", "receipts 2025"],
            lines: [
                "invoice september", "tax return 2025", "passport scan", "lease agreement", "receipts 2026",
                "resume 2026", "screenshot september",
            ]),
        Scenario(
            category: "url", name: "settings",
            situation: GenerationSituation(
                application: "System Settings", field: "Search", windowTitle: "System Settings",
                recentLines: ["keyboard shortcuts", "bluetooth", "display", "trackpad"]),
            cuts: .clause, determinacy: .word, band: 1...30,
            known: ["keyboard", "display brightness", "default browser", "screen saver"],
            lines: [
                "keyboard shortcuts", "night shift", "trackpad speed", "wifi password", "screen time",
                "default web browser", "bluetooth devices",
            ]),
    ]
}
