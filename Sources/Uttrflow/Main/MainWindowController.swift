// The main window's model and the controller that owns the window.

import AppKit
import UttrflowUX
import SwiftUI

/// Every page of the window as one value, so the sidebar never shows two different moments at once.
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
    /// What the user has typed into the current page's search field; filtering is the presenters' decision.
    var searchQuery = ""
    /// Which of a page's scopes is selected, as a raw identifier the app maps back to the page's own type.
    var scope = ""
    /// What is being typed into the snippet editor, held here so a refresh never takes the draft away.
    var snippetDraft = SnippetDraft()
    /// What is being typed into the word editor, held here for the same reason.
    var wordDraft = DictionaryDraft()
    /// Whether the sidebar is showing its names; chrome, not a decision, so no presenter builds it.
    var isSidebarExpanded: Bool

    init(page: MainTab = .home, content: MainContent, isSidebarExpanded: Bool = false) {
        self.page = page
        self.content = content
        self.isSidebarExpanded = isSidebarExpanded
    }
}

/// Owns the main window, built once and kept so reopening returns to the page the user left.
@MainActor
final class MainWindowController {
    /// Everything the pages can ask for, carried out by the app, which owns every window and the pasteboard.
    var onIntent: ((MainIntent) -> Void)?
    /// A search field was typed in. The app re-presents the page.
    var onSearch: ((String) -> Void)?
    /// A scope was picked. Same contract as ``onSearch``.
    var onScope: ((String) -> Void)?
    /// An inline editor was typed in; the presenter needs each keystroke to say whether Save is allowed.
    var onDraft: (() -> Void)?

    private let model: MainWindowModel
    private var window: NSWindow?
    private let defaults: UserDefaults

    /// The page currently on screen, so the app can re-present the right one.
    var page: MainTab { model.page }
    /// Whether the sidebar is showing its names, so the menu item can say which way choosing it will go.
    var isSidebarExpanded: Bool { model.isSidebarExpanded }
    /// What is in the snippet editor, so a save intent can be carried out against it.
    var snippetDraft: SnippetDraft { model.snippetDraft }
    /// The same, for the word editor.
    var wordDraft: DictionaryDraft { model.wordDraft }

    /// Where the sidebar's width is remembered; not a setting, so `UserDefaults` and not the settings store.
    private static let sidebarExpandedKey = "com.uttrflow.window.sidebarExpanded"

    init(content: MainContent, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent means collapsed, which is what `bool(forKey:)` answers for a key never written.
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

    /// Puts the opening values into the snippet editor; the app reads what it holds back via `snippetDraft`.
    func editSnippet(_ draft: SnippetDraft?) {
        model.snippetDraft = draft ?? SnippetDraft()
    }

    /// The same, for the word editor.
    func editWord(_ draft: DictionaryDraft?) {
        model.wordDraft = draft ?? DictionaryDraft()
    }

    /// Brings the window up on `page`, building it the first time; the one entry point for every caller.
    func show(_ page: MainTab) {
        model.page = page
        let window = window ?? makeWindow()
        self.window = window
        // Asked for explicitly: opened from the menu bar or the Dock, nothing else brings the app forward.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Gets out of the way without forgetting where the user was, for `minimisesWhileDictating`.
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
        // Kept rather than released, so reopening returns the user to the page they left.
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: MainWindowView(
                model: model,
                onIntent: { [weak self] in self?.onIntent?($0) },
                onSearch: { [weak self] in self?.onSearch?($0) },
                onScope: { [weak self] in self?.onScope?($0) },
                onDraft: { [weak self] in self?.onDraft?() },
                onToggleSidebar: { [weak self] in self?.toggleSidebar() }))
        // No intrinsic size from SwiftUI, or the window grows to the tallest page; Docs/app-main-window.md.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        return window
    }
}
