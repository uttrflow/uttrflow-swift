import AppKit
import SwiftUI
import UttrflowContext
import UttrflowPredict
import UttrflowUX

/// A window that never becomes the active one, so the caret stays in the field under it.
final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the surface was last asked to draw, so a display setting can change under it.
private struct SuggestionRequest: Equatable {
    var suggestion: Suggestion = .silent
    /// What is already in the field, so the surface offers only what the suggestion adds.
    var typed: String = ""
    var placement: SuggestionPlacement = .inlineGhost
    var direction: WritingDirection = .leftToRight
    var caret: CGRect?
    var window: CGRect?
    /// The field's own rectangle, whose right edge a long ghost is cut at.
    var field: CGRect?
    var fieldPointSize: CGFloat?
    /// Where the arrow keys have put the highlight, and whether they have moved it at all.
    var selection: SuggestionSelection = .untouched
    /// The key that accepts in this field, so the hint drawn after the ghost is the key that works.
    var acceptKey: AcceptKey = .tab
    /// The field's own font family, so the ghost is set in the face the line is.
    var fontFamily: String?
    var isBold = false
    var isItalic = false
    /// The field's own text colour, so the ghost reads against the field and not against Uttrflow's appearance.
    var textColor: TextColor?

    /// How far apart two reads of one caret may be and still be the same place, since a field can report it a point off.
    static let caretTolerance: CGFloat = 1

    /// Whether this asks for exactly what `other` drew, the caret allowed its read-to-read wobble.
    func draws(sameAs other: Self) -> Bool {
        var aligned = self
        aligned.caret = other.caret
        return aligned == other && Self.sameCaret(caret, other.caret)
    }

    /// Whether two caret reads are one place.
    private static func sameCaret(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.minX - rhs.minX) <= caretTolerance && abs(lhs.maxX - rhs.maxX) <= caretTolerance
            && abs(lhs.minY - rhs.minY) <= caretTolerance && abs(lhs.maxY - rhs.maxY) <= caretTolerance
    }
}

/// Owns the panel the suggestion is drawn in, one for the whole process so no two ghosts are ever on screen.
@MainActor
final class SuggestionPanelController {
    /// The one panel every suggestion loop draws in, so a loop rebuilt by a settings change cannot leave a second one behind.
    static let shared = SuggestionPanelController()

    private let panel: SuggestionPanel
    private let hostingView: NSHostingView<SuggestionView>
    /// Lays out the ghost line alone at its full width, which is how a ghost too long for its room is caught.
    private var measurer: NSHostingView<SuggestionGhostLine>?
    /// Lays out one complete open-list row at its full width before the list can claim keys.
    private var listRowMeasurer: NSHostingView<SuggestionListRow>?
    private var request = SuggestionRequest()
    private var panelSize = CGSize(width: 1, height: 1)
    private var geometryDirection: WritingDirection {
        request.direction == .rightToLeft ? .rightToLeft : .leftToRight
    }
    private var appearanceObserver: (any NSObjectProtocol)?
    private var screenParametersObserver: (any NSObjectProtocol)?
    private var announcer = SuggestionAnnouncer()
    var announcementCoalescer = SuggestionAnnouncementCoalescer()
    private var announcementTask: Task<Void, Never>?
    private let announcementClock = ContinuousClock()
    private let announcementStartedAt = ContinuousClock().now
    var announcementNow: (@MainActor () -> Duration)?
    /// Explains why the model cannot offer candidates under current Mac conditions.
    var statusMessage: String?
    var announcementSleep: @MainActor (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }
    /// Reads an announcement aloud to VoiceOver; a test swaps it to hear what would be said.
    var announce: @MainActor (String) -> Void = SuggestionPanelController.post
    private var isActuallyShowing = false
    /// Called when the panel takes a drawn ghost off screen without being asked, so its keys are let go.
    var onWithdrawnUnasked: (@MainActor () -> Void)?

    init() {
        hostingView = NSHostingView(rootView: SuggestionView(presentation: .init(.silent)))
        panel = SuggestionPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        configurePanel()
        hostingView.rootView = SuggestionView(
            presentation: SuggestionPresentation(.silent),
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        observeAppearance()
        observeScreenParameters()
    }

    isolated deinit {
        if let appearanceObserver { NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver) }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    /// Says what to draw and what to draw it against, answering whether the offer is on screen whole; `.silent` takes the surface away.
    @discardableResult
    func show(
        _ suggestion: Suggestion,
        typed: String = "",
        placement: SuggestionPlacement,
        direction: WritingDirection = .leftToRight,
        caret: CGRect? = nil,
        window: CGRect? = nil,
        field: CGRect? = nil,
        fieldPointSize: CGFloat? = nil,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab,
        fontFamily: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        textColor: TextColor? = nil
    ) -> Bool {
        let next = SuggestionRequest(
            suggestion: suggestion, typed: typed, placement: placement, direction: direction, caret: caret,
            window: window, field: field, fieldPointSize: fieldPointSize, selection: selection,
            acceptKey: acceptKey, fontFamily: fontFamily, isBold: isBold, isItalic: isItalic,
            textColor: textColor)
        // The same offer at the same caret is already on screen, so nothing is laid out, placed or fronted again.
        if isActuallyShowing, next.draws(sameAs: request) { return true }
        request = next
        return render()
    }

    /// Draws another offer, highlight or dot at the caret the panel already follows, answering whether it is on screen whole.
    @discardableResult
    func redraw(_ suggestion: Suggestion, typed: String, selection: SuggestionSelection) -> Bool {
        var next = request
        next.suggestion = suggestion
        next.typed = typed
        next.selection = selection
        if isActuallyShowing, next.draws(sameAs: request), statusMessage != nil {
            request = next
            return render()
        }
        if isActuallyShowing, next.draws(sameAs: request) { return true }
        request = next
        return render()
    }

    /// Follows a key that typed the ghost's next characters: the rest stays where it is drawn, and nothing is hidden.
    @discardableResult
    func advance(to typed: String, showing suggestion: Suggestion) -> Bool {
        guard isActuallyShowing, let caret = request.caret, let before = drawn.inline else { return false }
        let drawnWidth = width(of: before, in: drawn)
        var next = request
        next.typed = typed
        next.suggestion = suggestion
        let after = SuggestionPresentation(
            suggestion, typed: typed, selection: next.selection, fieldPointSize: next.fieldPointSize,
            appearance: Self.appearance(), acceptKey: next.acceptKey, fontFamily: next.fontFamily,
            isBold: next.isBold, isItalic: next.isItalic,
            fieldTextColor: next.textColor,
            direction: next.direction == .rightToLeft ? .rightToLeft : .leftToRight)
        guard let remaining = after.inline else { return false }
        // Keep the rest of the ghost where it was as the caret advances in its writing direction.
        let advancedWidth = drawnWidth - width(of: remaining, in: after)
        let direction: CGFloat = next.direction == .rightToLeft ? -1 : 1
        next.caret = caret.offsetBy(dx: direction * advancedWidth, dy: 0)
        request = next
        return render()
    }

    func hide() {
        // Already hidden and already drawn hidden: redrawing would change nothing and costs a screen lookup per key.
        if request.suggestion == .silent, !panel.isVisible, drawn.style == .hidden { return }
        request.suggestion = .silent
        render()
    }

    /// Whether a suggestion is on screen, which is what a scroll or a typed-through key acts on.
    var isShowing: Bool { isActuallyShowing }

    /// Exposed so a probe or a test can read back what was actually configured.
    var window: NSPanel { panel }

    /// What the panel is drawing right now, which a test reads back.
    var drawn: SuggestionPresentation { hostingView.rootView.presentation }

    /// How many times the view has been replaced, so a test can see that a redundant hide changes nothing.
    private(set) var renders = 0

    /// How many times the panel has been placed, so a test can see that one redraw moves it once.
    private(set) var placements = 0

    /// How many times the panel has been taken off screen, so a test can see a typed-through ghost never blinks.
    private(set) var withdrawals = 0

    /// The ghost line's full width in this presentation's face, as the view would draw it with no room limit.
    private func width(of row: SuggestionPresentation.Row, in presentation: SuggestionPresentation) -> CGFloat
    {
        let line = SuggestionGhostLine(presentation: presentation, row: row)
        guard let measurer else {
            let made = NSHostingView(rootView: line)
            measurer = made
            return made.fittingSize.width
        }
        measurer.rootView = line
        return measurer.fittingSize.width
    }

    /// The width of one list row with its marker and exact presentation font and weight.
    private func listRowWidth(
        of row: SuggestionPresentation.Row, in presentation: SuggestionPresentation
    )
        -> CGFloat
    {
        let line = SuggestionListRow(presentation: presentation, row: row)
        guard let listRowMeasurer else {
            let made = NSHostingView(rootView: line)
            self.listRowMeasurer = made
            return made.fittingSize.width
        }
        listRowMeasurer.rootView = line
        return listRowMeasurer.fittingSize.width
    }

    /// Takes the panel off screen, and says so to VoiceOver.
    private func withdraw() {
        announcer.surfaceWithdrawn()
        announcementTask?.cancel()
        announcementTask = nil
        announcementCoalescer.reset()
        isActuallyShowing = false
        withdrawals += 1
        panel.orderOut(nil)
    }

    /// Redraws from the last request, measuring the new content before the panel is placed so old and new are never on screen together.
    @discardableResult
    private func render() -> Bool {
        // Nothing to place means no screen to look up.
        let room =
            request.suggestion == .silent
            ? nil
            : request.caret.flatMap {
                SuggestionGeometry.availableWidth(
                    caret: $0, field: request.field, window: request.window, screen: screenFrame,
                    direction: geometryDirection)
            }
        var presentation = SuggestionPresentation(
            request.suggestion, typed: request.typed, selection: request.selection,
            fieldPointSize: request.fieldPointSize, appearance: Self.appearance(),
            acceptKey: request.acceptKey, fontFamily: request.fontFamily,
            isBold: request.isBold, isItalic: request.isItalic,
            fieldTextColor: request.textColor, statusMessage: statusMessage,
            maximumWidth: room,
            direction: request.direction == .rightToLeft ? .rightToLeft : .leftToRight)
        // A ghost cut short would hide words Tab inserts, so one that does not fit its room is not drawn at all.
        if let inline = presentation.inline, let room = presentation.maximumWidth,
            !SuggestionGeometry.fits(width(of: inline, in: presentation), in: room)
        {
            presentation = SuggestionPresentation(.silent)
        }
        // The open list claims navigation keys, so every row must fit before any of its candidates can be accepted.
        if presentation.isExpanded,
            let room = presentation.maximumWidth,
            presentation.list.contains(where: {
                !SuggestionGeometry.fits(listRowWidth(of: $0, in: presentation), in: room)
            })
        {
            presentation = SuggestionPresentation(.silent)
        }
        hostingView.rootView = SuggestionView(
            presentation: presentation,
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        renders += 1
        guard presentation.style != .hidden else {
            withdraw()
            return false
        }
        let measured = hostingView.fittingSize
        if measured.width > 0, measured.height > 0 {
            panelSize = CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
        }
        guard reposition() else {
            withdraw()
            return false
        }
        // `orderFrontRegardless`, never `makeKeyAndOrderFront`: no keyboard is taken; a panel already up is not fronted again.
        if !isActuallyShowing || !panel.isVisible { panel.orderFrontRegardless() }
        isActuallyShowing = true
        // The panel is out of VoiceOver's reach, so the offer and its accept key are spoken once as it appears.
        scheduleAnnouncement(announcer.announcement(for: presentation))
        return true
    }

    /// Coalesces changing offers while keeping a quiet offer prompt and a changing stream bounded.
    private func scheduleAnnouncement(_ text: String?) {
        guard let text else { return }
        let instant = announcementNow?() ?? announcementStartedAt.duration(to: announcementClock.now)
        if let ready = announcementCoalescer.offer(text, at: instant) { announce(ready); return }
        guard announcementTask == nil else { return }
        scheduleAnnouncementFlush(after: SuggestionAnnouncer.coalescingInterval)
    }

    /// Waits for quiet, then flushes the latest pending label.
    private func scheduleAnnouncementFlush(after interval: Duration) {
        announcementTask = Task { @MainActor [weak self] in
            await self?.announcementSleep(interval)
            guard let self, !Task.isCancelled else { return }
            let now =
                self.announcementNow?() ?? self.announcementStartedAt.duration(to: self.announcementClock.now)
            if let ready = self.announcementCoalescer.flushIfReady(at: now) {
                self.announce(ready)
            } else {
                let remaining = self.announcementCoalescer.remainingQuietInterval(at: now) ?? .zero
                self.scheduleAnnouncementFlush(after: remaining)
                return
            }
            self.announcementTask = nil
        }
    }

    /// Asks VoiceOver to speak at low priority, so the echo of the user's own typing is not cut off.
    private static func post(_ text: String) {
        NSAccessibility.post(
            element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.low.rawValue,
            ])
    }

    /// What Increase Contrast and Reduce Transparency are set to right now.
    private static func appearance() -> SuggestionAppearance {
        let workspace = NSWorkspace.shared
        return SuggestionAppearance(
            increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
    }

    /// Redraws when the user changes a display setting while the surface is on screen.
    private func observeAppearance() {
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.render() }
        }
    }

    /// Takes the ghost off a display that has just changed, before its old frame is stranded.
    private func observeScreenParameters() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    /// The view measures itself and reports what it wants; the panel follows and stays on screen.
    private func resize(to size: CGSize) {
        let wanted = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted.width > 0, wanted.height > 0, wanted != panelSize else { return }
        panelSize = wanted
        guard drawn.style != .hidden else {
            isActuallyShowing = false
            return
        }
        guard reposition() else {
            withdraw()
            onWithdrawnUnasked?()
            return
        }
        if !isActuallyShowing || !panel.isVisible { panel.orderFrontRegardless() }
        isActuallyShowing = true
    }

    /// Places the panel at the caret, or reports that there is nowhere on the line to draw it.
    @discardableResult
    private func reposition() -> Bool {
        let font = baselineFont
        guard
            let anchor = SuggestionGeometry.anchor(
                for: request.placement, caret: request.caret, window: request.window,
                field: request.field, screen: screenFrame, size: panelSize, direction: geometryDirection,
                fontAscent: font.ascender, fontDescent: -font.descender)
        else { return false }
        guard anchor.frame != panel.frame else { return true }
        placements += 1
        panel.setFrame(anchor.frame, display: true)
        return true
    }

    /// The font metrics for the same face and size the ghost line uses.
    private var baselineFont: NSFont {
        let size = drawn.pointSize
        let fallback =
            drawn.prefersMonospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size)
        guard let family = request.fontFamily else { return fallback }
        return NSFont(name: family, size: size)
            ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? fallback
    }

    /// The screen the caret is on, so a field on another display is drawn there and not against the panel's last screen.
    private var screenHoldingCaret: NSScreen? {
        guard let caret = request.caret else { return nil }
        return NSScreen.screens.first { $0.frame.contains(CGPoint(x: caret.minX, y: caret.midY)) }
    }

    /// The screen's whole frame, Dock and menu bar bands included, since a full-screen window's own caret can sit in either.
    private var screenFrame: CGRect {
        // With no screen to place against, staying put beats moving somewhere arbitrary.
        (screenHoldingCaret ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.frame
            ?? panel.frame
    }

    private func configurePanel() {
        panel.styleMask = [.nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.level = .statusBar
        // A transient window hides while Mission Control shows window tiles.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Nothing here is clickable — Tab takes the suggestion — so clicks pass through to the field.
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        // `orderOut` waits out AppKit's fade on the main thread, which would stall every keystroke over a ghost.
        panel.animationBehavior = .none
        PrivateWindowSharing.apply(to: panel)
        panel.contentView = hostingView
    }
}
