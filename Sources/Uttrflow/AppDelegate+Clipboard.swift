import Accessibility
import AppKit
import OSLog
import UniformTypeIdentifiers
import UttrflowAI
import UttrflowAccount
import UttrflowAudio
import UttrflowClipboard
import UttrflowContext
import UttrflowCore
import UttrflowDiagnostics
import UttrflowDictionary
import UttrflowHistory
import UttrflowInput
import UttrflowLocalModel
import UttrflowPermissions
import UttrflowPipeline
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX

extension AppDelegate {
    /// How long unkept clips live, read on every use because both the window and now move.
    private var retention: ClipRetention {
        ClipRetention(
            days: settings.clipboardRetentionDays, now: Date(),
            // One control, both copies: the clipboard's copy of a transcript ages by the same setting.
            dictationDays: settings.transcriptRetentionDays)
    }

    func startWatchingTheClipboard() {
        quickPanel.onKey = { [weak self] key, behind in
            self?.panelAnswered(key, behind: behind)
        }
        quickPanel.onIntent = { [weak self] intent, behind in self?.carryOut(intent, behind: behind) }

        followTheClipboardSwitch()
        startWatchingForClaimedShortcuts()
    }

    /// Records copies while the Clipboard switch is on, and stops recording the moment it is off.
    func followTheClipboardSwitch() {
        settingsPage.setClipboardCapturePaused(isClipboardPaused)
        settingsPage.setConfirmsMultilinePaste(clipboardPreferences.confirmsMultilinePaste)
        if isClipboardPaused { startClipboardPauseTimerIfNeeded() }
        guard surfaces.watchesTheClipboard, !isClipboardPaused else {
            clipboardWatchTask?.cancel()
            clipboardWatchTask = nil
            return
        }
        guard clipboardWatchTask == nil else { return }
        // Built out here: a `[weak self]` closure nested in another captures the outer binding.
        let arrived: @Sendable (NoticedClip) async -> Void = { [weak self] noticed in
            await self?.clipArrived(noticed)
        }
        // Read now, so a copy made after the switch went on is recorded even if the task starts late.
        let baseline = clipboardWatcher.changeCount
        let excludedApplications = clipboardPreferences.excludedBundleIdentifiers
        // Utility, because a poll nobody is waiting on should not run as the main thread's work.
        clipboardWatchTask = Task(priority: .utility) { [clipboardWatcher] in
            // Whatever was copied while the switch was off stays unrecorded.
            await clipboardWatcher.passOver(upTo: baseline)
            await clipboardWatcher.setExcludedApplications(excludedApplications)
            await clipboardWatcher.run(
                handing: arrived,
                whenCaptureDegrades: { [weak self] in await self?.reportClipboardCaptureDegraded() })
        }
    }

    var isClipboardPaused: Bool {
        guard !clipboardPreferencesUnreadable else { return true }
        return clipboardPause.isActive
    }

    /// Stops capture immediately and resumes from a fresh baseline after one hour.
    func setClipboardPaused(_ isPaused: Bool) {
        guard !clipboardPreferencesUnreadable else { return }
        clipboardPreferences.pausedUntil = clipboardPause.set(isPaused)
        settingsPage.setClipboardCapturePaused(isPaused)
        saveClipboardPreferences()
        if isPaused {
            clipboardWatchTask?.cancel()
            clipboardWatchTask = nil
            let baseline = clipboardWatcher.changeCount
            Task { [clipboardWatcher] in await clipboardWatcher.passOver(upTo: baseline) }
            startClipboardPauseTimerIfNeeded()
        } else {
            followTheClipboardSwitch()
        }
    }

    private func startClipboardPauseTimerIfNeeded() {
        clipboardPause.startTimerIfNeeded { [weak self] in
            self?.clipboardPreferences.pausedUntil = nil
            self?.saveClipboardPreferences()
            self?.followTheClipboardSwitch()
        }
    }

    /// Adds or removes bundle identifiers through private preferences and a running-app picker.
    func manageClipboardExclusions() {
        guard !clipboardPreferencesUnreadable else { return }
        let identifiers = clipboardPreferences.excludedBundleIdentifiers.sorted()
        let alert = NSAlert()
        alert.messageText = "Clipboard exclusions"
        alert.informativeText =
            identifiers.isEmpty
            ? "No apps are excluded. The frontmost app at copy detection time is used; macOS does not identify the pasteboard writer."
            : "Excluded: " + identifiers.joined(separator: ", ")
        alert.addButton(withTitle: "Add Running App…")
        alert.addButton(withTitle: "Remove…")
        alert.addButton(withTitle: "Done")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            ApplicationPicker.chooseClipboardApplication { [weak self] identifier in
                guard let self else { return }
                clipboardPreferences.exclude(identifier)
                saveClipboardPreferences()
            }
        case .alertSecondButtonReturn:
            guard !identifiers.isEmpty else { return }
            let removal = NSAlert()
            removal.messageText = "Remove an excluded app"
            let menu = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
            menu.setAccessibilityLabel(removal.messageText)
            menu.addItems(withTitles: identifiers)
            removal.accessoryView = menu
            removal.addButton(withTitle: "Remove")
            removal.addButton(withTitle: "Cancel")
            if removal.runModal() == .alertFirstButtonReturn {
                clipboardPreferences.include(identifiers[max(0, menu.indexOfSelectedItem)])
                saveClipboardPreferences()
            }
        default: break
        }
    }

    private func saveClipboardPreferences() {
        guard !clipboardPreferencesUnreadable else { return }
        do {
            try clipboardPreferencesFile.save(clipboardPreferences)
            let excludedApplications = clipboardPreferences.excludedBundleIdentifiers
            Task { [clipboardWatcher] in
                await clipboardWatcher.setExcludedApplications(excludedApplications)
                await clipboardWatcher.passOver(upTo: clipboardWatcher.changeCount)
            }
        } catch { report(error) }
    }

    static func clipboardPreferencesUnreadableNotice(canRestore: Bool) -> MainNotice {
        MainNotice(
            message:
                "Your exclusion list could not be read. Clipboard capture is off until you restore it.",
            symbolName: "exclamationmark.triangle", tone: .critical,
            action: canRestore
                ? MainAction(title: "Restore exclusions", intent: .restoreClipboardPreferences)
                : nil)
    }

    func restoreClipboardPreferences() {
        guard let clipboardPreferencesSetAside else { return }
        do {
            clipboardPreferences = try clipboardPreferencesFile.restore(from: clipboardPreferencesSetAside)
            self.clipboardPreferencesSetAside = nil
            clipboardPreferencesUnreadable = false
            clipboardPause.load(clipboardPreferences.pausedUntil)
            actionNotice = nil
            followTheClipboardSwitch()
            refreshMainWindow()
        } catch {
            actionNotice = Self.clipboardPreferencesUnreadableNotice(canRestore: true)
            refreshMainWindow()
        }
    }

    /// Keeps a clip the user has just copied, and shows it if they are looking.
    func clipArrived(_ noticed: NoticedClip) async {
        clipboardArrivals += 1
        let arrival = clipboardArrivals
        let clips = await keep(noticed)
        guard arrival == clipboardArrivals else { return }
        await reportUnreadableClipboardIndexes()
        await refreshPanelIfOpen(using: clips)
        await readMenuClips(using: clips)
    }

    /// Rereads the popover's clips in the background and redraws once they are in.
    func refreshMenuClips() {
        Task { [weak self] in await self?.readMenuClips() }
    }

    /// The newest few clips for the popover, or none while the clipboard is switched off.
    func readMenuClips(using recordedClips: [Clip]? = nil) async {
        let clips: [Clip]
        if settings.clipboardEnabled {
            let history: [Clip]
            if let recordedClips {
                history = recordedClips
            } else {
                history = await clipboard.clips(keeping: retention)
                await reportUnreadableClipboardIndexes()
            }
            clips = Array(history.prefix(MenuBarPresenter.clipCount))
        } else {
            clips = []
        }
        guard clips != menuClips else { return }
        menuClips = clips
        refreshMenuBar()
    }

    /// Reports an incompatible format or tells the user where a damaged index was preserved.
    private func reportUnreadableClipboardIndexes() async {
        let unsupportedVersions = await clipboard.takeUnsupportedFormatVersions()
        if !unsupportedVersions.isEmpty {
            let versions = unsupportedVersions.map(String.init).joined(separator: ", ")
            let message =
                "Clipboard history uses unsupported version \(versions) and is read-only. Update Uttrflow before changing clipboard history."
            let notice = MainNotice(message: message, symbolName: "externaldrive", tone: .warning)
            actionNotice = notice
            panel?.notice = PanelNotice(symbolName: notice.symbolName, message: message)
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            announce(message, urgently: false)
            refreshMainWindow()
            return
        }
        let unreadableRecords = await clipboard.takeUnreadableRecordCount()
        let unpreservedRecords = await clipboard.takeUnpreservedRecordCount()
        let copies = await clipboard.takeUnreadableIndexSetAsides()
        guard unreadableRecords > 0 || !copies.isEmpty else { return }
        let locations = copies.map(\.path).joined(separator: ", ")
        var details: [String] = []
        if unreadableRecords > 0 {
            details.append(
                "\(unreadableRecords) clipboard clip\(unreadableRecords == 1 ? "" : "s") could not be read.")
        }
        if !locations.isEmpty {
            details.append("Damaged clipboard data was preserved at \(locations).")
        }
        if unpreservedRecords > 0 {
            details.append(
                "The damaged clipboard data could not be preserved, so that index will not be overwritten.")
        }
        let message = details.joined(separator: " ")
        let notice = MainNotice(
            message: message, symbolName: "externaldrive", tone: .warning)
        actionNotice = notice
        panel?.notice = PanelNotice(symbolName: notice.symbolName, message: message)
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        announce(message, urgently: false)
        refreshMainWindow()
    }

    /// Tells the user once when a clipboard writer takes longer than the read limit.
    private func reportClipboardCaptureDegraded() {
        let message = "A clipboard copy took too long to read. Capture will retry automatically."
        let notice = MainNotice(message: message, symbolName: "doc.on.clipboard", tone: .warning)
        actionNotice = notice
        panel?.notice = PanelNotice(symbolName: notice.symbolName, message: message)
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        announce(message, urgently: false)
        refreshMainWindow()
    }

    /// Records one noticed clip; a refused write loses that clip, and giving up would lose all the rest.
    private func keep(_ noticed: NoticedClip) async -> [Clip] {
        do {
            let clips = try await clipboard.record(noticed, keeping: retention)
            clearClipboardWriteFailure()
            return clips
        } catch {
            reportClipboardWriteFailure(error)
            return await clipboard.clips(keeping: retention)
        }
    }

    private func reportClipboardWriteFailure(_ failure: ClipboardStoreError) {
        guard failure != .aliasAlreadyInUse else { return }
        guard clipboardWriteFailure == nil else { return }
        clipboardWriteFailure = failure
        panel?.notice = pendingClipboardPanelNotice
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        refreshMenuBar()
        if let clipboardFailureAnnouncer {
            clipboardFailureAnnouncer(failure.userMessage)
        } else {
            announce(failure.userMessage, urgently: false)
        }
    }

    private func clearClipboardWriteFailure() {
        guard let failure = clipboardWriteFailure else { return }
        clipboardWriteFailure = nil
        if let notice = panel?.notice, notice.message == failure.userMessage {
            panel?.notice = nil
        }
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        refreshMenuBar()
    }

    func confirmQuittingWithUnsavedClipboard(_ failure: ClipboardStoreError) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clipboard history could not be saved"
        alert.informativeText = [
            failure.userMessage,
            "Recent copies that have not been saved will be lost if you quit.",
        ].joined(separator: " ")
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// One registration per claimed shortcut; a refusal is logged rather than shown as a dictation failure.
    func startWatchingForClaimedShortcuts() {
        for task in claimedTasks.values { task.cancel() }
        claimedTasks.removeAll()
        for monitor in claimedHotkeys.values { monitor.stop() }
        claimedHotkeys.removeAll()

        var refused: [ShortcutAction: HotkeyError] = [:]
        // Signed out, no key is claimed, so each one still reaches the app in front.
        for action in surfaces.claimedShortcuts {
            guard let binding = settings.shortcuts.first(for: action) else { continue }
            let monitor = CarbonHotkeyMonitor()
            do {
                try monitor.start(binding: binding)
            } catch {
                Self.log.error(
                    "\(action.rawValue, privacy: .public) shortcut refused: \(error.userMessage, privacy: .public)"
                )
                refused[action] = error
                continue
            }
            claimedHotkeys[action] = monitor
            claimedTasks[action] = Task { [weak self] in
                for await event in monitor.events {
                    // Releases ignored: acting on key-up would punish a slow hand.
                    guard event == .pressed else { continue }
                    await self?.perform(action)
                }
            }
        }
        unarmedShortcuts = refused
    }

    /// Does what one claimed shortcut is for; internal so a test can press one.
    func perform(_ action: ShortcutAction) async {
        guard isSignedIn else { return }
        switch action {
        case .clipboard:
            await toggleQuickPanel()
        case .pasteLastTranscript:
            await pasteLastTranscript()
        case .copyLastTranscript:
            await copyLastTranscript()
        // Watched through the tap rather than registered, so they never arrive here.
        case .dictate, .editCommand:
            break
        }
    }

    /// Puts the last dictation back at the caret by the route a dictation takes, never the clipboard.
    private func pasteLastTranscript() async {
        guard let text = await keptLastTranscript() else {
            sayNoLastTranscript(to: "paste")
            return
        }
        do {
            _ = try await lastTranscriptInserter.insert(text)
        } catch {
            render(.failed(DictationFailure(error)))
        }
    }

    /// A dictation's text classified with the shape rules and the snippets marked secret.
    func dictationText(_ text: String) -> DictationTextPresentation {
        DictationTextPresentation(text, secretPhrases: knownSnippets.secretPhrases)
    }

    /// Shown and spoken, so a shortcut with nothing to act on never looks broken.
    private func sayNoLastTranscript(to verb: String) {
        Self.log.notice("\(verb, privacy: .public) last dictation: nothing dictated yet")
        let message = "There is no dictation to \(verb) yet."
        actionNotice = MainNotice(message: message, symbolName: "info.circle", tone: .neutral)
        announce(message, urgently: false)
    }

    /// Writes the clipboard on purpose, which is the one shortcut whose whole job that is.
    private func copyLastTranscript() async {
        guard let text = await keptLastTranscript() else {
            sayNoLastTranscript(to: "copy")
            return
        }
        // Read now: the shortcut can fire before any page has read the snippets.
        knownSnippets = await snippets.snippets()
        let result: PasteboardWriteResult
        if dictationText(text).isSecret {
            result = announcingPasteboard.writeConcealedText(text)
            if result.didWrite { scheduleSecretClear(writtenAt: result.changeCount) }
        } else {
            result = announcingPasteboard.writeTransientText(text, richText: nil)
        }
        guard result.didWrite else {
            showClipboardCopyFailure()
            return
        }
        sayCopiedForMainWindow(secret: dictationText(text).isSecret)
    }

    /// The shortcut is a toggle, so the same key puts the panel away again.
    func toggleQuickPanel() async {
        guard isSignedIn else { return }
        guard !quickPanel.isVisible else {
            closeQuickPanel()
            return
        }
        // Fresh, and shown before anything is awaited, so the keys after the shortcut reach the search (#860).
        let opening = PanelSnapshot.opening(now: Date(), resuming: resume)
        panel = opening
        quickPanel.show(PanelPresenter.present(opening))
        panelTarget = quickPanel.insertionDestination
        updates.refresh()
        let opened = quickPanel.opens
        // A copy since the last poll is taken now, started not awaited, so no read holds the panel shut (#895).
        if surfaces.watchesTheClipboard && !isClipboardPaused {
            let arrived: @Sendable (NoticedClip) async -> Void = { [weak self] noticed in
                await self?.clipArrived(noticed)
            }
            Task { [clipboardWatcher] in await clipboardWatcher.catchUp(handing: arrived) }
        }
        let placement = await placement()
        let dictation = await voice()
        // K4, B8 — asked once on the way in, so the presenter stays a function of its input.
        let folder = await clipboard.imagesFolder
        // Nothing is written into a panel this open no longer owns; a later one asks these again itself.
        guard quickPanel.opens == opened, panel != nil else { return }
        panel?.insertion = placement
        panel?.dictation = dictation
        panel?.imagesFolder = folder
        // A4 — said on the way in, not after Return, when there is nowhere left to say it.
        if case .clipboardOnly(let obstacle) = placement, obstacle == .accessibilityNotGranted {
            panel?.notice = obstacle.notice
        }
        if let pendingClipboardPanelNotice { panel?.notice = pendingClipboardPanelNotice }
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        // The list comes by the one path a copy arriving also takes, so neither can undo the other.
        await refreshPanelIfOpen()
    }

    /// B3–B5 — whether Return will place a clip or only copy it, asked while there is still somewhere to say so.
    private func placement() async -> PanelInsertion {
        // The two questions only the machine can answer; the rule is `PanelInsertion.decided`.
        await PanelInsertion.decided(
            isAccessibilityGranted: accessibility.status() == .granted,
            isSelfFrontmost: focus.isSelfFrontmost())
    }

    /// I6, I7 — whether dictation can start and why not, so a dimmed button carries its reason.
    private func voice() async -> PanelDictation {
        guard await microphone.status() == .granted else {
            return .unavailable(.microphoneNotGranted)
        }
        // The same question the menu bar asks: loaded, not merely on disk.
        switch speechReadiness {
        case .ready: return .ready
        case .loading: return .unavailable(.modelLoading)
        case .downloading, .loadFailed, .loadFailedAgain, .incomplete, .notInstalled:
            return .unavailable(.modelNotReady(percent: nil))
        }
    }

    /// A8 — answers a key or click in the panel, which only copies when the application the caret belonged to has quit.
    private func panelAnswered(_ key: PanelKey, behind: NSRunningApplication? = nil) {
        guard let snapshot = panel else { return }
        // Any key means the panel is in use; a notice below starts the wait again.
        noticeLinger.interrupt()
        let response = snapshot.applying(key, caretOwnerHasQuit: behind?.isTerminated == true)
        panel = response.state
        perform(response.outcome.effect)
    }

    /// Carries out what an answered keystroke or row button asks, against the panel as it now stands.
    private func perform(_ effect: PanelEffect) {
        switch effect {
        case .redraw:
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        case .close:
            closeQuickPanel()
        case .closeAndInsertImage(let clip):
            let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
            closeQuickPanel()
            insertImage(clip, targeting: destination)
        case .say(let notice):
            // Stays open, or the sentence describes a clip the user cannot see.
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .closeAndInsertFormatted(let text, let richText, let used):
            insertFromPanel(text, richText: richText, concealed: false, used: used)
        case .closeAndInsert(let text, let used):
            insertFromPanel(text, concealed: false, used: used)
        case .closeAndInsertConcealed(let text, let used):
            insertFromPanel(text, concealed: true, used: used)
        case .closeAndInsertConfirmed(let text, let used):
            insertFromPanel(text, concealed: false, used: used, agreed: true)
        case .closeAndInsertConfirmedConcealed(let text, let used):
            insertFromPanel(text, concealed: true, used: used, agreed: true)
        case .copyAndSay(let text, let notice, let used):
            // Stays open: the panel is the only surface left to say this on.
            let copied = putOnClipboard(text, used: used)
            panel?.notice = copied ? notice : Self.clipboardCopyFailedNotice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            if copied { closeAfterReading() }
        case .copyConcealedAndSay(let text, let notice, let used):
            let copied = putOnClipboard(text, concealed: true, used: used)
            panel?.notice = copied ? notice : Self.clipboardCopyFailedNotice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            if copied { closeAfterReading() }
        case .copyImageAndSay(let clip, let notice):
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            Task { [weak self] in
                guard let self else { return }
                let outcome = await putImageOnClipboard(clip)
                guard owner.isSameOpen(panel, opens: quickPanel.opens) else { return }
                // A picture that went between the draw and the keypress is said, never claimed as copied.
                switch outcome {
                case .copied:
                    panel?.notice = notice
                    closeAfterReading()
                case .missingPicture:
                    panel?.notice = Self.pictureMissingNotice(clip)
                    closeAfterReading()
                case .writeRefused:
                    panel?.notice = Self.clipboardCopyFailedNotice
                }
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            }
        case .closeAndCopy(let text, let richText, let used):
            // Onto the clipboard and no further: the user will paste it somewhere else.
            if putOnClipboard(text, richText: richText, used: used) {
                closeQuickPanel()
                reportPanelPaste(.copied(.text))
            } else {
                panel?.notice = Self.clipboardCopyFailedNotice
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            }
        case .closeAndCopyConcealed(let text, let used):
            if putOnClipboard(text, concealed: true, used: used) {
                closeQuickPanel()
                reportPanelPaste(.copied(.hiddenText))
            } else {
                panel?.notice = Self.clipboardCopyFailedNotice
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            }
        case .closeAndCopyImage(let clip):
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            Task { [weak self] in
                guard let self else { return }
                let outcome = await putImageOnClipboard(clip)
                guard owner.isSameOpen(panel, opens: quickPanel.opens), outcome == .copied else {
                    if owner.isSameOpen(panel, opens: quickPanel.opens) {
                        panel?.notice =
                            outcome == .missingPicture
                            ? Self.pictureMissingNotice(clip) : Self.clipboardCopyFailedNotice
                        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
                        if outcome == .missingPicture { closeAfterReading() }
                    }
                    return
                }
                closeQuickPanel()
                reportPanelPaste(.copied(.picture))
            }
        case .applyAndRedraw(let change):
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            apply(change)
        case .placeFiles(let clip, let placement):
            placeFiles(clip, placement)
        }
    }

    /// Resolved before the panel closes, so a missing file is said where the user is looking.
    private func placeFiles(_ clip: Clip, _ placement: PanelFilePlacement) {
        let resolution = PanelFilePaste.resolve(clip)
        if case .refused(let notice) = resolution { return perform(.say(notice)) }
        guard case .files(let urls) = resolution else { return }
        let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
        if case .paste = placement { closeQuickPanel() }
        markUsed(clip.id)
        let engine = PasteboardFileInsertionEngine(
            focus: focus, pasteboard: announcingPasteboard, keystrokes: CGEventKeystrokeSender())
        var failure: TextInsertionError?
        do {
            if case .paste = placement {
                try engine.insert(urls, targeting: destination)
            } else {
                try engine.copy(urls)
            }
        } catch { failure = error }
        let landing = PanelFilePaste.landing(
            placement, failure: failure, copyFailed: Self.clipboardCopyFailedNotice)
        if let effect = landing.effect { perform(effect) }
        if let report = landing.report { reportPanelPaste(report) }
    }

    /// The notice for a picture whose file has gone, worded as Return words it.
    private static func pictureMissingNotice(_ clip: Clip) -> PanelNotice? {
        guard case .say(let notice) = PanelOutcome.pictureMissing(clip).effect else { return nil }
        return notice
    }

    /// Carries out a panel change and redraws from the state returned by the store.
    func apply(_ change: PanelChange) {
        let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
        Task {
            do {
                try await carryOut(change, owner: owner)
            } catch let failure as ClipboardStoreError {
                // F10 — stays open holding the failure, which must look different from a success.
                Self.log.error(
                    "clipboard write refused: \(failure.userMessage, privacy: .public)")
                reportClipboardWriteFailure(failure)
                guard owner.isSameOpen(panel, opens: quickPanel.opens) else { return }
                panel?.notice = .writeFailed(failure.userMessage)
            }
            await refreshPanelIfOpen()
            await readMenuClips()
        }
    }

    /// The write itself, with every refusal allowed to reach the caller.
    private func carryOut(
        _ change: PanelChange, owner: PanelLateRequest
    ) async throws(ClipboardStoreError) {
        switch change {
        case .setAlias(let id, let alias):
            _ = try await clipboard.setAlias(alias, of: id, keeping: retention)
        case .setLabels(let id, let alias, let tags):
            _ = try await clipboard.setLabels(alias: alias, tags: tags, of: id, keeping: retention)
        case .setCategory(let id, let category):
            _ = try await clipboard.setCategory(category, of: id, keeping: retention)
        case .setPinned(let id, let isPinned):
            _ = try await clipboard.setPinned(isPinned, of: id, keeping: retention)
        case .setSecret(let id, let isSecret):
            _ = try await clipboard.setSecret(isSecret, of: id, keeping: retention)
        case .delete(let id):
            // F7, F9 — kept in hand, because the store forgets it the moment this returns.
            let held = panel?.clips.first { $0.id == id }.map { [$0] } ?? []
            let ticket = undoOffer.offer(held)
            // The earlier delete's timer must not expire this one's offer before its own starts.
            undoTask?.cancel()
            panel?.canUndoDelete = !held.isEmpty
            panel?.undoAnnouncementID = UUID()
            Self.log.info(
                "delete: undoable=\(!held.isEmpty, privacy: .public) flag=\(self.panel?.canUndoDelete == true, privacy: .public)"
            )
            let deletion = Task { [clipboard, retention] () -> Result<Void, ClipboardStoreError> in
                await clipboard.forgetHeldPictures()
                do throws(ClipboardStoreError) {
                    _ = try await clipboard.delete(
                        id, keeping: retention, holdingPicture: !held.isEmpty)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
            undoOffer.trackDelete(deletion, ticket: ticket)
            // Only the latest delete can be undone, so an earlier one's picture is let go first.
            switch await deletion.value {
            case .success:
                break
            case .failure(let error):
                throw error
            }
            // A later delete owns the offer and its timer, so a superseded one leaves both alone.
            guard undoOffer.isLatest(ticket) else { return }
            await startForgettingTheUndo()
        case .create(let text):
            // Detected here, off the main actor: the panel knows what was typed, not what a string is.
            let classified = await ClipKindDetector.classify(text)
            let clip = Clip(
                text: text, kind: classified.kind, copiedAt: Date(), source: nil,
                // Typed into the panel and kept, so it belongs with what the app made.
                origin: .uttrflow,
                language: classified.language)
            _ = try await clipboard.record(clip, keeping: retention)
        case .rewriteText(let id, let tidied):
            _ = try await clipboard.setText(tidied, of: id, keeping: retention)
        case .editText(let id, let text):
            let previous = panel?.clips.first { $0.id == id }?.text
            _ = try await clipboard.setText(text, of: id, keeping: retention)
            // Awaited before the redraw that follows, so the edited clip is drawn at the top.
            _ = await clipboard.markUsed(id, at: Date(), keeping: retention)
            guard let previous else { break }
            undoOffer.offerEdit(of: id, previousText: previous)
            panel?.canUndoDelete = true
            panel?.undoAnnouncementID = UUID()
            await clipboard.forgetHeldPictures()
            await startForgettingTheUndo()
        case .setRichText(let id, let note):
            _ = try await clipboard.setRichText(note, of: id, keeping: retention)
        case .renameCategory(let from, let to):
            // Every clip under the old name moves; no alias is touched, because a collection is a shelf.
            _ = try await clipboard.moveCategory(from, to: to, keeping: retention)
        case .deleteCategory(let name, let destination):
            _ = try await clipboard.moveCategory(name, to: destination, keeping: retention)
        case .deleteCategoryAndClips(let name):
            let ticket = undoOffer.offer([])
            undoTask?.cancel()
            panel?.canUndoDelete = false
            let deletion = Task { [clipboard, retention] () -> Result<[Clip], ClipboardStoreError> in
                await clipboard.forgetHeldPictures()
                do throws(ClipboardStoreError) {
                    let deleted = try await clipboard.deleteCategoryForUndo(
                        name, keeping: retention)
                    return .success(deleted)
                } catch {
                    return .failure(error)
                }
            }
            let deleteGate = Task { () -> Result<Void, ClipboardStoreError> in
                switch await deletion.value {
                case .success: return .success(())
                case .failure(let error): return .failure(error)
                }
            }
            undoOffer.trackDelete(deleteGate, ticket: ticket)
            switch await deletion.value {
            case .success(let held):
                guard undoOffer.complete(ticket, with: held) else { return }
                panel?.canUndoDelete = !held.isEmpty
                panel?.undoAnnouncementID = UUID()
                await startForgettingTheUndo()
            case .failure(let error):
                if undoOffer.isLatest(ticket) {
                    undoOffer.withdraw()
                    await clipboard.forgetHeldPictures()
                }
                throw error
            }
        }
        clearClipboardWriteFailure()
    }

    /// Expires the undo offer, so an old delete cannot be reversed by a keystroke meant for something else.
    private func startForgettingTheUndo() async {
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.undoWindow)
            guard let self, !Task.isCancelled else { return }
            await PanelUndoExpiry.expire(
                withdraw: {
                    self.undoOffer.withdraw()
                    self.panel?.canUndoDelete = false
                },
                releasingPictures: { await self.clipboard.forgetHeldPictures() })
            await self.refreshPanelIfOpen()
        }
    }

    /// The row's own buttons, for the ones the panel cannot answer alone.
    private func carryOut(_ intent: PanelIntent, behind: NSRunningApplication? = nil) {
        // Any row button means the panel is in use; a notice below starts the wait again.
        noticeLinger.interrupt()
        // Insert and reveal go the path Return goes, quit check included, so a click and a key mean one clip.
        if let key = intent.key {
            panelAnswered(key, behind: behind)
            return
        }
        if let change = intent.immediateChange {
            apply(change)
            return
        }

        switch intent {
        case .pin, .unpin, .markNotSecret, .markSecret:
            // These are routed through `immediateChange` above.
            break
        case .copy(let id):
            // Through the panel, so a picture is copied as a picture and a missing one is said.
            guard let response = panel?.copying(id) else { return }
            panel = response.state
            perform(response.outcome.effect)
        case .keepQuery(let text):
            apply(.create(text))
        case .dictate:
            // Closed first, then the ordinary dictation, so one place describes it.
            closeQuickPanel()
            toggleDictation()
        case .openAccessibilitySettings:
            closeQuickPanel()
            Task { await openSettingsPane(.accessibility) }
        case .undoDelete:
            Self.log.info("undo requested: have=\(self.undoOffer.clip != nil, privacy: .public)")
            guard let claim = undoOffer.claimForRestore() else { return }
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            undoTask?.cancel()
            panel?.canUndoDelete = false
            intentWork = Task { [weak self] in
                guard let self else { return }
                do throws(ClipboardStoreError) {
                    let notice = try await PanelUndoRestorer.restore(
                        claim, to: self.clipboard, keeping: self.retention)
                    if owner.isSameOpen(self.panel, opens: self.quickPanel.opens) {
                        self.panel?.notice = notice
                    }
                } catch {
                    if owner.isSameOpen(self.panel, opens: self.quickPanel.opens) {
                        self.panel?.notice = .writeFailed(error.userMessage)
                    }
                }
                await self.refreshPanelIfOpen()
            }
        case .format(let id):
            runFormatter(on: id)
        case .openSettings:
            // Closed first: Settings activates the app, and the panel would belong to nothing.
            closeQuickPanel()
            show(.settings(.general))
        case .insert, .insertCleaned, .reveal, .alias, .move, .edit, .delete, .renameCategory,
            .deleteCategory, .reindent, .makeNote, .scope:
            // Answered above, by `intent.key`.
            break
        }
    }

    /// D5–D7 — runs the formatter through the panel's guarded formatting owner.
    private func runFormatter(on id: Clip.ID) {
        guard let clip = panel?.clips.first(where: { $0.id == id }), let language = clip.language
        else { return }
        formatterRuns += 1
        let request = PanelFormatRequest(
            owner: PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet),
            clip: id, text: clip.text, run: formatterRuns)
        Task { [formatter] in
            await PanelFormattingCoordinator(formatter: formatter, log: Self.log).run(
                text: clip.text, language: language,
                actions: .init(
                    isCurrent: { [self] in
                        request.accepts(into: panel, opens: quickPanel.opens, latestRun: formatterRuns)
                    },
                    finish: { [self] ending in
                        panel?.notice = ending.notice
                        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
                    },
                    present: { [self] prepared, produced in
                        panel?.remember(prepared)
                        panel?.sheet = .formatting(id, formatted: produced)
                        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
                    }))
        }
    }

    /// Pastes a panel clip, or asks first in the panel when the shared decision holds it back.
    private func insertFromPanel(
        _ text: String, richText: String? = nil, concealed: Bool, used: Clip.ID, agreed: Bool = false
    ) {
        let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
        let situation = PasteQuestion.Situation(
            isConcealed: concealed, field: .secure, bundleIdentifier: destination.bundleIdentifier,
            text: text,
            confirmsHiddenClips: settings.confirmsHiddenClipPaste,
            confirmsMultiline: clipboardPreferences.confirmsMultilinePaste, isAgreed: agreed)
        let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
        Task { [weak self, focus, pasteGate] in
            let decision = await pasteGate.decide(situation, focus: focus)
            guard let self, owner.stillOwns(panel, opens: quickPanel.opens) else { return }
            switch decision {
            case .pasteNow:
                // Closed first: insertion declines outright while Uttrflow is frontmost.
                closeQuickPanel()
                insert(
                    text, richText: richText, concealed: concealed, targeting: destination, used: used,
                    forPanel: true)
            case .ask(let reason):
                let original = panel?.clips.first { $0.id == used }?.text
                panel = panel?.askingBeforePaste(of: used, cleaned: original != text, reason: reason)
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            case .refuse(let refusal):
                panel?.notice = PanelNotice(symbolName: "eye.slash", message: refusal.message)
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
                closeAfterReading()
            }
        }
    }

    /// Notes a clip was reached for, from the three methods that place one so no path can forget.
    private func markUsed(_ id: Clip.ID?) {
        guard let id else { return }
        let window = retention
        Task { [clipboard] in
            await clipboard.markUsed(id, at: Date(), keeping: window)
        }
    }

    enum ImageCopyOutcome: Equatable { case copied, missingPicture, writeRefused }

    /// Puts a picture's PNG on the clipboard through the one pasteboard.
    func putImageOnClipboard(_ clip: Clip) async -> ImageCopyOutcome {
        guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
            Self.log.error("picture missing at copy: \(clip.id, privacy: .public)")
            return .missingPicture
        }
        guard announcingPasteboard.setImage(data).didWrite else { return .writeRefused }
        markUsed(clip.id)
        return .copied
    }

    /// K4 — pastes a picture, on its own path because the Accessibility route writes only strings.
    func insertImage(_ clip: Clip, targeting destination: InsertionDestination? = nil) {
        markUsed(clip.id)
        Task { [weak self, clipboard, pasteboard = announcingPasteboard, focus] in
            guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
                // B8 from the other side: the file went between the draw and the keypress.
                Self.log.error("picture missing at paste: \(clip.id, privacy: .public)")
                self?.reportPanelPaste(.pictureMissing)
                return
            }
            do {
                // Named by its bytes, so a copy landing in the same tick is not claimed by this write.
                try PasteboardImageInsertionEngine(
                    focus: focus, pasteboard: pasteboard, keystrokes: CGEventKeystrokeSender()
                ).insert(data, targeting: destination)
            } catch let failure as TextInsertionError {
                // The image may already be on the clipboard if focus changes during the write.
                Self.log.error(
                    "picture paste refused: \(failure.userMessage, privacy: .public)")
                self?.reportPanelPaste(.pictureRefused)
            }
        }
    }

    /// Removes Uttrflow's own clipboard copies of a forgotten dictation, found by its identifier.
    func forgetClips(of dictation: DictationRecord.ID, saying spoken: String?) async throws {
        let retention = ClipRetention(
            days: settings.clipboardRetentionDays, now: Date(),
            dictationDays: settings.transcriptRetentionDays)
        try await clipboard.deleteCopies(ofDictation: dictation, saying: spoken, keeping: retention)
        clearClipboardWriteFailure()
        await refreshPanelIfOpen()
    }

    /// Adds a chosen dictation to clipboard history while the Clipboard switch is on.
    @discardableResult
    func recordAsClip(_ text: String, of dictation: DictationRecord.ID) -> Task<Void, Never>? {
        guard surfaces.watchesTheClipboard else { return nil }
        let retention = self.retention
        return Task { [weak self, clipboard, retention] in
            guard let self else { return }
            let classified = await ClipKindDetector.classify(text)
            let clip = Clip(
                text: text, kind: classified.kind, copiedAt: Date(), source: ClipOrigin.dictationSource,
                // Which keeps it out of History, where it would be the newest thing every time.
                origin: .uttrflow, dictations: [dictation],
                language: classified.language)
            do {
                _ = try await clipboard.record(clip, keeping: retention)
                self.clearClipboardWriteFailure()
            } catch let failure as ClipboardStoreError {
                self.reportClipboardWriteFailure(failure)
            } catch {
                self.reportClipboardWriteFailure(.couldNotWrite)
            }
            await self.refreshPanelIfOpen()
        }
    }

    /// Stores the terminal paste choice with the other clipboard choices and redraws its row.
    func setConfirmsMultilinePaste(_ isOn: Bool) {
        guard !clipboardPreferencesUnreadable else { return }
        clipboardPreferences.confirmsMultilinePaste = isOn
        settingsPage.setConfirmsMultilinePaste(isOn)
        saveClipboardPreferences()
    }

    /// Puts text where the caret is, through the coordinator whose last strategy cannot fail.
    func insert(
        _ text: String, richText: String? = nil, concealed: Bool = false,
        targeting destination: InsertionDestination? = nil, used: Clip.ID?, forPanel: Bool = false
    ) {
        markUsed(used)
        let clipInserter: any TextInserting =
            switch (forPanel, concealed) {
            case (true, true): panelSecretInserter
            case (true, false): panelClipInserter
            case (false, true): secretInserter
            case (false, false): self.clipInserter
            }
        Task { [weak self, clipInserter] in
            do {
                let attempt: InsertionAttempt
                if let destination {
                    attempt = try await clipInserter.insert(text, richText: richText, targeting: destination)
                } else {
                    attempt = try await clipInserter.insert(text, richText: richText)
                }
                let arrival = forPanel ? "" : " arrival=\(attempt.arrival.rawValue)"
                Self.log.info(
                    "clip inserted by \(attempt.method.rawValue, privacy: .public)\(arrival, privacy: .public)"
                )
                if forPanel { self?.reportPanelPaste(.text(attempt)) }
            } catch {
                // Every strategy refused, including the one that cannot.
                let why = (error as? any UttrflowFailure)?.userMessage ?? SuggestionLog.failure(error)
                Self.log.error("clip insertion failed: \(why, privacy: .public)")
                self?.reportPanelPaste(forPanel ? .textCouldNotPaste : .textRefused)
            }
        }
    }

    /// Says on the floating button, and aloud, what a panel action left on the clipboard.
    func reportPanelPaste(_ result: PanelPasteResult) {
        guard let report = PanelPasteReport.after(result) else { return }
        var spoken = AttributedString(report.spoken)
        spoken.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(spoken).post()
        // A dictation under way owns the button, and its own outcome is the newer news.
        guard case .idle = lastDictationState else { return }
        pasteReport = DictationPresenter.dock(
            notice: report.symbolName, primaryLine: report.primaryLine,
            secondaryLine: report.secondaryLine, accessibilityLabel: report.spoken)
        dock.update(with: dockPresentation(for: lastDictationState))
        pasteReportTask?.cancel()
        pasteReportTask = Task { [weak self] in
            try? await Task.sleep(for: Self.failureLingers)
            guard !Task.isCancelled, let self else { return }
            self.pasteReport = nil
            self.dock.update(with: self.dockPresentation(for: self.lastDictationState))
        }
    }

    /// Adds a copy made while the panel is open, without moving a selection held by identity.
    private func refreshPanelIfOpen(using recordedClips: [Clip]? = nil) async {
        guard panel != nil, quickPanel.isVisible else { return }
        await panelRefresh.refresh(
            using: recordedClips,
            readers: .init(
                clips: { [self] in await clipboard.clips(keeping: retention) },
                reportUnreadable: { [self] in await reportUnreadableClipboardIndexes() },
                facts: { [self] clips in
                    await PanelListFacts.about(clips, clipboard: clipboard, formatter: formatter)
                }),
            publish: { [self] clips, facts in
                panel?.install(
                    clips, missingImages: facts.missingPictures, missingFiles: facts.missingFiles,
                    formattableLanguages: facts.formattable, now: Date())
                guard let snapshot = panel else { return }
                quickPanel.update(PanelPresenter.present(snapshot))
            })
    }

    /// Through the one pasteboard, so the write is announced and stays on this Mac. See `Docs/insertion.md`.
    @discardableResult
    func putOnClipboard(
        _ text: String, richText: String? = nil, concealed: Bool = false, used: Clip.ID?
    ) -> Bool {
        // A secret goes up marked, so no other clipboard history records it in plain text.
        let result: PasteboardWriteResult
        guard !concealed else {
            result = announcingPasteboard.writeConcealedText(text)
            if result.didWrite {
                markUsed(used)
                scheduleSecretClear(writtenAt: result.changeCount)
            }
            return result.didWrite
        }
        // E2, E3 — both flavours, so the receiving application takes the one it understands.
        result = announcingPasteboard.setText(text, richText: richText)
        if result.didWrite { markUsed(used) }
        return result.didWrite
    }

    /// Takes a copied secret off the clipboard after the chosen delay, unless something newer was copied.
    private func scheduleSecretClear(writtenAt changeCount: Int?) {
        ConcealedClipboardClear().schedule(
            on: announcingPasteboard, writtenAt: changeCount,
            afterSeconds: settings.secretClipboardClearSeconds)
    }

    /// Tells the user, on screen and through VoiceOver, that the words are on the clipboard, where the panel would have said so.
    func sayCopiedForMainWindow(secret: Bool = false) {
        let seconds = settings.secretClipboardClearSeconds
        let cleared = secret && seconds > 0 ? ". It leaves the clipboard in \(seconds) seconds" : ""
        let notice = MainNotice(
            message: "Copied — click where you want it, then press ⌘V" + cleared,
            symbolName: "doc.on.clipboard", tone: .neutral)
        actionNotice = notice
        announce(notice.message, urgently: false)
        refreshMainWindow()
    }

    private static var clipboardCopyFailedNotice: PanelNotice {
        PanelNotice.writeFailed(MainNotice.clipboardCopyFailed.message)
    }

    func showClipboardCopyFailure() {
        actionNotice = .clipboardCopyFailed
        announce(MainNotice.clipboardCopyFailed.message, urgently: false)
        refreshMainWindow()
    }

    private func closeAfterReading() {
        noticeLinger.start { [weak self] in
            // A sheet opened meanwhile is work in progress, never closed under the person.
            guard self?.panel?.sheet == nil else { return }
            self?.closeQuickPanel()
        }
    }

    func closeQuickPanel() {
        // A3, A7 — remembered before it goes, so an accidental dismissal costs nothing.
        resume = panel.map {
            PanelResume(
                scope: $0.scope, category: $0.category, selection: $0.selection,
                sheet: $0.sheet, closedAt: Date())
        }
        noticeLinger.interrupt()
        quickPanel.hide()
        panel = nil
        panelTarget = nil
        pasteGate.forget()
        // The quiet minute an update waits for starts here, not at the next window event.
        updates.refresh()
    }
}
