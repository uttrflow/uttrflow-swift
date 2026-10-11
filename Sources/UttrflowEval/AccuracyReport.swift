// The public accuracy report a release carries, rendered from the committed baseline.
public import Foundation

/// One release's accuracy, slice by slice, against the release before it. See Docs/measuring-accuracy.md.
public struct AccuracyReport: Sendable, Equatable {
    /// Fewer reference words than this in a slice and its rate is printed as too small to judge.
    public static let minimumReferenceWords = 100

    public let version: String
    public let baseline: AccuracyBaseline
    /// The latest earlier release in the history, if there is one.
    public let previous: AccuracyHistory.Release?
    /// The fallback rungs' accuracy on the user's own words, as `DegradedPathMatrix.rungSection` reads it.
    public let rungSection: String?

    public init(
        version: String, baseline: AccuracyBaseline, history: AccuracyHistory, rungSection: String? = nil
    ) {
        self.version = version
        self.baseline = baseline
        self.previous = history.releases.last { $0.version != version }
        self.rungSection = rungSection
    }

    /// The digest of every case and the exact recording scored, so two reports name the same corpus or not.
    public var corpusDigest: String {
        let lines = baseline.entries.map { "\($0.caseID) \($0.recordingIdentity ?? "-")\n" }.joined()
        return RecordingIdentity.digest(of: Data(lines.utf8))
    }

    public var markdown: String {
        var lines = ["# Accuracy report, version \(version)", ""]
        lines += measured + [""] + caveats + [""]
        lines += ["## Word error rate", ""]
        lines += rateTable("Language", languageSlices)
        lines += rateTable("Stressor", stressSlices)
        lines += rateTable("Cohort", cohortSlices)
        lines += againstPrevious
        let report = lines.joined(separator: "\n") + "\n"
        return rungSection.map { report + "\n" + $0 } ?? report
    }

    /// The rung section of the generated degraded-path page at `url`; an error when it is unreadable or has none.
    public static func rungSection(from url: URL) throws(EvaluationStoreError) -> String {
        let page: String
        do { page = try String(contentsOf: url, encoding: .utf8) } catch {
            throw .couldNotRead(path: url.lastPathComponent, reason: "\(error)")
        }
        guard let section = DegradedPathMatrix.rungSection(in: page) else {
            throw .couldNotRead(
                path: url.lastPathComponent, reason: "no '\(DegradedPathMatrix.rungHeading)' section")
        }
        return section
    }

    // MARK: Sections

    private var measured: [String] {
        let date = ISO8601DateFormatter.string(
            from: baseline.recordedAt, timeZone: TimeZone(identifier: "UTC") ?? .current,
            formatOptions: [.withFullDate])
        return [
            "- Measured: \(baseline.label)",
            "- Recogniser: \(baseline.recogniser ?? "not recorded in this baseline")",
            "- Clean-up engine: none; these are the recogniser's words before clean-up, "
                + "which changes words on purpose and is measured separately",
            "- Recorded: \(date)",
            "- Normalisation: \(baseline.normalisation.map(\.rawValue).joined(separator: ", "))",
            "- Corpus digest: `\(corpusDigest)`",
        ]
    }

    private var caveats: [String] {
        let unscorable = baseline.entries.count { $0.isUnscorable }
        let cohorts = Set(baseline.entries.map(\.cohortLabel)).sorted()
        return [
            "Read these numbers with their limits:",
            "",
            "- \(baseline.entries.count) cases, \(unscorable) of them with nothing to score. "
                + "0 cases are held out: every case in the baseline is scored here.",
            "- Each cohort is one voice: \(cohorts.joined(separator: ", ")).",
            "- Rates are never pooled across slices. A slice under \(Self.minimumReferenceWords) reference words, "
                + "or of a single case, is too small to judge.",
            "- These figures are not comparable with figures published for other tools, "
                + "which use other passages, voices and normalisation.",
        ]
    }

    private var againstPrevious: [String] {
        guard let previous else {
            return ["## Against the previous release", "", "No earlier release is in the history."]
        }
        let comparison = previous.baseline.compare(with: baseline)
        var lines = ["## Against \(previous.version)", ""]
        if let reason = comparison.reason {
            return lines + ["Not compared: \(reason)."]
        }
        lines += [
            "Over the \(counted(comparison.overall.referenceWordCount, "reference word")) both releases scored."
        ]
        if !comparison.added.isEmpty {
            lines += ["New cases, not compared: \(comparison.added.joined(separator: ", "))."]
        }
        if !comparison.removed.isEmpty {
            lines += ["Cases since removed: \(comparison.removed.joined(separator: ", "))."]
        }
        lines += [""]
        lines += changeTable("Language", comparison.byLanguage)
        lines += changeTable("Stressor", comparison.byStress)
        lines += changeTable("Cohort", comparison.byCohort)
        return Array(lines.dropLast())
    }

    // MARK: Slices

    private var scored: [BaselineEntry] { baseline.cleanEntries.filter { !$0.isUnscorable } }

    private var languageSlices: [(String, [BaselineEntry])] {
        TranscriptionCase.Language.allCases.compactMap { language in
            let matched = scored.filter { $0.language == language }
            return matched.isEmpty ? nil : (language.rawValue, matched)
        }
    }

    private var stressSlices: [(String, [BaselineEntry])] {
        Set(scored.flatMap(\.stresses)).sorted().map { stress in
            (stress, scored.filter { $0.stresses.contains(stress) })
        }
    }

    private var cohortSlices: [(String, [BaselineEntry])] {
        Set(scored.map(\.cohortLabel)).sorted().map { cohort in
            (cohort, scored.filter { $0.cohortLabel == cohort })
        }
    }

    private func rateTable(_ heading: String, _ slices: [(String, [BaselineEntry])]) -> [String] {
        var lines = [
            "| \(heading) | Cases | Reference words | Errors | Rate | 95% interval |",
            "|---|---:|---:|---:|---:|---|",
        ]
        for (label, entries) in slices {
            let words = entries.reduce(0) { $0 + $1.referenceWordCount }
            let errors = entries.reduce(0) { $0 + $1.errors }
            let interval = PairedBootstrap.standard.rateInterval(entries)
            let judged: String =
                if let interval, words >= Self.minimumReferenceWords {
                    "\(percent(Double(errors) / Double(words))) | \(percent(interval.lowerBound))–\(percent(interval.upperBound))"
                } else {
                    "too small to judge | –"
                }
            lines.append("| \(label) | \(entries.count) | \(words) | \(errors) | \(judged) |")
        }
        return lines + [""]
    }

    private func changeTable(_ heading: String, _ changes: [BaselineComparison.Change]) -> [String] {
        var lines = [
            "| \(heading) | Before | After | Change | 95% interval of change | Verdict |",
            "|---|---:|---:|---:|---|---|",
        ]
        for change in changes {
            let small = change.isUnderpowered || change.referenceWordCount < Self.minimumReferenceWords
            let interval =
                change.interval.map { "\(signed($0.lowerBound)) to \(signed($0.upperBound))" } ?? "–"
            lines.append(
                "| \(change.label) | \(change.before.map(percent) ?? "–") | \(change.after.map(percent) ?? "–") "
                    + "| \(change.delta.map(signed) ?? "–") | \(interval) "
                    + "| \(small ? "too small to judge" : change.verdict.rawValue) |")
        }
        return lines + [""]
    }

    private func percent(_ rate: Double) -> String { String(format: "%.1f%%", rate * 100) }

    private func signed(_ rate: Double) -> String { String(format: "%+.1f pts", rate * 100) }

    private func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// Every release's baseline, one release per line, so a report can compare with the one before it.
public struct AccuracyHistory: Sendable, Equatable {
    public struct Release: Sendable, Equatable, Codable {
        public let version: String
        public let baseline: AccuracyBaseline

        public init(version: String, baseline: AccuracyBaseline) {
            self.version = version
            self.baseline = baseline
        }
    }

    public private(set) var releases: [Release]

    public init(releases: [Release] = []) { self.releases = releases }

    /// Adds `release`, replacing an earlier line for the same version so a re-run never duplicates one.
    public mutating func record(_ release: Release) {
        releases.removeAll { $0.version == release.version }
        releases.append(release)
    }

    /// A JSON array with one release per line, so each release adds one line to the diff.
    public var fileContents: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let lines = releases.compactMap { release in
            (try? encoder.encode(release)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return lines.isEmpty ? "[]\n" : "[\n" + lines.joined(separator: ",\n") + "\n]\n"
    }

    /// The history at `url`, or an empty one when no release has been recorded yet.
    public static func read(from url: URL) throws(EvaluationStoreError) -> AccuracyHistory {
        guard FileManager.default.fileExists(atPath: url.path) else { return AccuracyHistory() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return AccuracyHistory(releases: try decoder.decode([Release].self, from: Data(contentsOf: url)))
        } catch {
            throw .couldNotRead(path: url.lastPathComponent, reason: "\(error)")
        }
    }

    public func write(to url: URL) throws(EvaluationStoreError) {
        do {
            try Data(fileContents.utf8).write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite(path: url.lastPathComponent, reason: "\(error)")
        }
    }
}
