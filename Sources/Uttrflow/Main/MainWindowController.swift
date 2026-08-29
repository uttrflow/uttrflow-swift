import AppKit
import UttrflowUX
import SwiftUI

/// Every page of the window, as it currently stands.
///
/// One value rather than nine separate updates: the sidebar shows all of them at once,
/// so a window holding a fresh Dictation beside a stale Diagnostics would be showing the
/// user two different moments and calling them the same one.
struct MainContent: Sendable, Equatable {
    var home: HomePresentation
    var sidebar: SidebarPresentation
    var dictation: DictationPresentation
    var history: HistoryPresentation
    var dictionary: DictionaryPresentation
    var corrections: CorrectionsPresentation
    var insights: InsightsPresentation
    var snippets: SnippetsPresentation
    var style: StylePagePresentation
    var diagnostics: DiagnosticsPresentation
    var account: AccountPagePresentation
}

/// What the window is showing, in one place the view can watch.
@MainActor
@Observable
final class MainWindowModel {
    var page: MainTab
    var content: MainContent
    /// What the user has typed into the current page's search field.
    ///
    /// Held here rather than in the view because the filtering itself is a decision, and
    /// decisions belong in the presenters: the field reports what was typed, the app
    /// rebuilds the page from it, and the view draws whatever comes back.
    var searchQuery = ""
    /// Which of a page's scopes is selected, reported the same way and for the same
    /// reason. A raw identifier because the app maps it back to the page's own scope
    /// type — the view never learns what the strings mean.
    var scope = ""
    /// What is being typed into the snippet editor.
    ///
    /// The one piece of half-finished input the window holds. It lives here rather than
    /// inside the row so that redrawing the page under an open editor — which happens on
    /// every refresh — does not take the user's half-typed trigger away.
    var snippetDraft = SnippetDraft()
    /// What is being typed into the word editor, held here for the same reason.
    var wordDraft = DictionaryDraft()
    /// Whether the sidebar is showing its names.
    ///
    /// Chrome rather than a decision, so it is held here and not built by a presenter:
    /// nothing about the page changes with it, and a presenter that took a width would
    /// be a presenter that had to be handed one on every rebuild.
    var isSidebarExpanded: Bool

    init(page: MainTab = .home, content: MainContent, isSidebarExpanded: Bool = false) {
        self.page = page
        self.content = content
        self.isSidebarExpanded = isSidebarExpanded
    }
}

/// Owns the main window.
///
/// The window is built the first time it is asked for and kept afterwards, so reopening
/// from the menu bar returns the user to the page they left rather than to a new window
/// with nothing in it.
@MainActor
final class MainWindowController {
    /// Everything the pages can ask for. Carried out by the app, which is the only part
    /// that knows how to reach System Settings, the pasteboard or another window.
    var onIntent: ((MainIntent) -> Void)?
    /// A search field was typed in. The app re-presents the page.
    var onSearch: ((String) -> Void)?
    /// A scope was picked. Same contract as ``onSearch``.
    var onScope: ((String) -> Void)?
    /// An inline editor was typed in. Same contract again, and needed for the same
    /// reason: whether a draft may be saved is a decision, decisions live in the
    /// presenters, and a presenter that is never told about a keystroke answers about
    /// the draft as it was when the editor opened.
    var onDraft: (() -> Void)?

    private let model: MainWindowModel
    private var window: NSWindow?
    private let defaults: UserDefaults

    /// The page currently on screen, so the app can re-present the right one.
    var page: MainTab { model.page }
    /// Whether the sidebar is showing its names, so the menu item can say which way
    /// choosing it will go.
    var isSidebarExpanded: Bool { model.isSidebarExpanded }
    /// What is in the snippet editor, so a save intent can be carried out against it.
    var snippetDraft: SnippetDraft { model.snippetDraft }
    /// The same, for the word editor.
    var wordDraft: DictionaryDraft { model.wordDraft }

    /// Where the sidebar's width is remembered between launches.
    ///
    /// `UserDefaults` directly rather than the settings store: this is not a setting.
    /// Nothing in Settings offers it, it is not carried to another Mac with the user's
    /// account, and it is the same kind of thing as where the quick panel was last
    /// dragged to — this window's own memory of how it was left.
    private static let sidebarExpandedKey = "com.uttrflow.window.sidebarExpanded"

    init(content: MainContent, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent means collapsed, which is also what `bool(forKey:)` answers for a key
        // never written — so the default needs no special case, and the window opens the
        // way it opens for somebody who has never touched it.
        model = MainWindowModel(
            content: content,
            isSidebarExpanded: defaults.bool(forKey: Self.sidebarExpandedKey))
    }

    /// Shows or hides the sidebar's names, and remembers which.
    func toggleSidebar() {
        model.isSidebarExpanded.toggle()
        defaults.set(model.isSidebarExpanded, forKey: Self.sidebarExpandedKey)
    }

    /// Replaces what the pages show. Cheap enough to call whenever anything changes.
    func update(_ content: MainContent) {
        model.content = content
    }

    /// Puts the opening values into the inline snippet editor.
    ///
    /// Only the opening values. What the editor holds after that is the window's, and is
    /// read back through ``snippetDraft`` — the app is told *that* an editor is open and
    /// asks the window *what is in it*, so there is one copy of the text and not two.
    func editSnippet(_ draft: SnippetDraft?) {
        model.snippetDraft = draft ?? SnippetDraft()
    }

    /// The same, for the word editor.
    func editWord(_ draft: DictionaryDraft?) {
        model.wordDraft = draft ?? DictionaryDraft()
    }

    /// Brings the window up on a given page, building it if this is the first time.
    ///
    /// The one entry point: the menu bar, a recovery action and onboarding all arrive
    /// here, so there is no second way for a window to appear on the wrong page.
    func show(_ page: MainTab) {
        model.page = page
        let window = window ?? makeWindow()
        self.window = window
        // Asked for explicitly rather than left to macOS. The app is opened from its own
        // menu-bar item and from the Dock as often as from the Finder, and in the first
        // two cases nothing else brings it forward — the window would open behind
        // whatever the user was dictating into.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Gets out of the way without forgetting where the user was.
    ///
    /// What `minimisesWhileDictating` asks for: the point of dictating is to watch the
    /// words land in the other app, which cannot happen from behind this window.
    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MainMetrics.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = MainPresenter.windowTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentMinSize = MainMetrics.minimumWindowSize
        // Kept rather than released so that closing and reopening returns the user to the
        // page they left instead of to a fresh window with nothing in it.
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: MainWindowView(
                model: model,
                onIntent: { [weak self] in self?.onIntent?($0) },
                onSearch: { [weak self] in self?.onSearch?($0) },
                onScope: { [weak self] in self?.onScope?($0) },
                onDraft: { [weak self] in self?.onDraft?() },
                onToggleSidebar: { [weak self] in self?.toggleSidebar() }))
        // The window is a window, not a poster. `NSHostingView` reports SwiftUI's ideal
        // size as its `intrinsicContentSize` by default, and AppKit resizes the window to
        // match — so the window grew and shrank as the user moved between pages. Measured
        // before this: 1084 points tall on Home, 4458 on Account and 5461 on Insights,
        // because a long empty state or a tall card wants the room. On Account the effect
        // read as a bug in the page rather than the window: the content sat at the top of
        // a window four times the height of the screen and everything below it was blank.
        //
        // The pages already scroll. Nothing here needs the hosting view to have an
        // opinion about how big the window should be.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        return window
    }
}
