// The main window's chrome: sidebar, page header and page switch.

import UttrflowUX
import SwiftUI

/// The main window: a sidebar, a toolbar, and whichever page is selected; the chrome lives here only.
struct MainWindowView: View {
    @Bindable var model: MainWindowModel
    var onIntent: (MainIntent) -> Void = { _ in }
    var onSearch: (String) -> Void = { _ in }
    var onScope: (String) -> Void = { _ in }
    var onDraft: () -> Void = {}
    var onToggleSidebar: () -> Void = {}

    /// The question a button is asking before it acts, drawn over the whole window.
    @State private var confirmations = MainConfirmationCenter()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                presentation: model.content.sidebar,
                account: model.content.home.account,
                picture: model.content.account.identity?.picture,
                isExpanded: model.isSidebarExpanded,
                // The page on screen, so the highlight moves with it rather than with the next redraw.
                selection: model.showsSettings
                    ? .settings(model.settings?.session.tab ?? .general) : .page(model.page),
                onSelect: { destination in
                    switch destination {
                    case .page(let page):
                        // Through the app, so the sidebar's highlight and badge are rebuilt with the page.
                        onIntent(.show(page))
                    case .settings(let tab):
                        // Through the app too, which refreshes what the Settings page shows.
                        onIntent(.go(.settings(tab)))
                    }
                },
                onAccount: { onIntent(model.content.home.account.open.intent) },
                onToggle: onToggleSidebar)
            pane
        }
        // The one animation in the window: the sidebar's width moves the page beside it.
        .animation(MotionBudget.current().allowing(.snappy(duration: 0.22)), value: model.isSidebarExpanded)
        .background(Color.redesignWindow)
        .foregroundStyle(Color.mainText, Color.mainMuted, Color.mainDim)
        // One tint at the root, so a control added later cannot arrive in the stock blue.
        .tint(Color.dockAccent)
        .confirmationSheet(confirmations, onIntent: onIntent)
        // SwiftUI still reserves a safe area for the transparent title bar; the island keeps its own inset.
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Pane

    /// The shown pane with the notice floating in its corner, over Settings as well as the pages.
    private var pane: some View {
        shownPane
            .overlay(alignment: .topTrailing) {
                if let notice = model.content.notice {
                    MainNoticeBar(notice: notice, onIntent: onIntent)
                        // Below every page's title and search row, so the notice covers content, never the header.
                        .padding(.top, Self.noticeTopInset)
                        .padding(.trailing, 20)
                        // Fades in place under Reduce Motion rather than sliding from the top.
                        .transition(
                            MotionBudget.current().reducesMotion
                                ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.content.notice)
    }

    /// Clears the tallest header, Home's greeting beside its search field, which ends 90 points down.
    private static let noticeTopInset: CGFloat = 98

    /// Settings when it is showing, which draws its own title and search, or the selected page.
    @ViewBuilder private var shownPane: some View {
        if model.showsSettings, let settings = model.settings {
            SettingsPageView(
                model: settings, diagnostics: model.content.diagnostics,
                searchFocusRequest: model.searchFocusRequest, onIntent: onIntent)
        } else {
            pagePane
        }
    }

    private var pagePane: some View {
        VStack(spacing: 0) {
            // The band under the title bar, which the traffic lights and the window's drag own; some pages draw their own.
            if !drawsOwnHeader {
                Color.clear.frame(height: MainMetrics.toolbarHeight)
                if isRedesigned {
                    PageTitleBar(
                        chrome: model.chrome, query: $model.searchQuery,
                        searchFocusRequest: model.searchFocusRequest, onIntent: onIntent,
                        onSearch: onSearch)
                } else {
                    OrbitPageHeader(
                        chrome: model.chrome, query: $model.searchQuery,
                        searchFocusRequest: model.searchFocusRequest, onIntent: onIntent,
                        onSearch: onSearch, onScope: onScope)
                }
            }
            page
                // A page with its own header sets its own margins; a redesigned page is set wider than the rest.
                .padding(.horizontal, horizontalMargin)
                .padding(.top, drawsOwnHeader ? 0 : (isRedesigned ? 16 : 18))
                .padding(.bottom, drawsOwnHeader ? 0 : 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.dictationKeycaps, model.content.shortcutKeycaps)
        // The field holds what is being typed, so it is only put back in step when the page changes.
        .onChange(of: model.page) { _, _ in
            model.searchQuery = model.chrome.search?.query ?? ""
        }
    }

    /// Whether the page draws its own title, and so its own margins.
    private var drawsOwnHeader: Bool { [.home, .history, .insights, .account].contains(model.page) }

    /// Whether the page draws the redesign's title bar and margins.
    private var isRedesigned: Bool { [.dictionary, .snippets].contains(model.page) }

    /// A page with its own header sets its own margins; a redesigned page is set wider than the others.
    private var horizontalMargin: CGFloat {
        if drawsOwnHeader { return 0 }
        return isRedesigned ? PageMetrics.margin : MainMetrics.contentPadding
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .home:
            HomePageView(presentation: model.content.home, onIntent: onIntent)
        case .history:
            HistoryPageView(
                presentation: model.content.history, chrome: model.chrome, query: $model.searchQuery,
                searchFocusRequest: model.searchFocusRequest, onIntent: onIntent, onSearch: onSearch)
        case .dictionary:
            DictionaryPageView(
                presentation: model.content.dictionary, draft: reporting($model.wordDraft),
                onIntent: onIntent, onFilter: onScope)
        case .corrections:
            CorrectionsPageView(presentation: model.content.corrections, onIntent: onIntent)
        case .insights:
            InsightsPageView(
                presentation: model.content.insights, onIntent: onIntent, onScope: onScope)
        case .snippets:
            SnippetsPageView(
                presentation: model.content.snippets, draft: reporting($model.snippetDraft),
                onIntent: onIntent)
        case .account:
            AccountPageView(presentation: model.content.account, onIntent: onIntent)
        }
    }

    /// Wraps an editor's binding so typing into it also asks the app to re-present the page.
    private func reporting<Draft>(_ binding: Binding<Draft>) -> Binding<Draft> {
        Binding(
            get: { binding.wrappedValue },
            set: {
                binding.wrappedValue = $0; onDraft()
            })
    }
}

/// The band each page opens with: a mono kicker, the title, the caption, and the page's own control.
struct OrbitPageHeader: View {
    let chrome: MainPageChrome
    @Binding var query: String
    /// Rises when Find is chosen; handed on to the search field, which is what takes the focus.
    var searchFocusRequest = 0
    var onIntent: (MainIntent) -> Void
    var onSearch: (String) -> Void
    var onScope: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(chrome.title.uppercased())
                    .font(.system(size: MainMetrics.footnoteSize, weight: .medium))
                    .tracking(1.6)
                    .foregroundStyle(Color.accentInk)
                Text(chrome.title)
                    .font(.system(size: 29, weight: .bold))
                if let caption = chrome.caption {
                    Text(caption)
                        .font(.system(size: MainMetrics.bodySize))
                        .foregroundStyle(Color.mainMuted)
                }
            }
            // One element, so a screen reader hears the page's name once.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([chrome.title, chrome.caption].compactMap(\.self).joined(separator: ". "))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 10)
            if let scope = chrome.scope {
                MainScopeControl(scope: scope, onScope: onScope)
            }
            if let search = chrome.search {
                MainSearchControl(
                    field: search, query: $query, focusRequest: searchFocusRequest,
                    onSearch: onSearch)
            }
            if let add = chrome.addAction {
                MainActionButton(action: add, onIntent: onIntent)
            }
        }
        .padding(.horizontal, MainMetrics.contentPadding)
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(Color.mainCard)
        .overlay(alignment: .bottom) { MainDivider() }
    }
}

/// The search field, which reports what was typed and decides nothing.
struct MainSearchControl: View {
    let field: MainSearchField
    @Binding var query: String
    /// Rises when Find is chosen, which is the one thing that moves the caret here without a click.
    var focusRequest = 0
    var onSearch: (String) -> Void

    /// Whether the caret is in the field; SwiftUI owns it, so Find asks through ``focusRequest``.
    @FocusState private var isFocused: Bool
    /// What is selected in the field, held so Find can select the whole query rather than only reach it.
    @State private var selection: TextSelection?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(field.placeholder, text: $query, selection: $selection)
                .textFieldStyle(.plain)
                .font(.system(size: MainMetrics.calloutSize))
                .focused($isFocused)
                .onChange(of: query) { _, new in onSearch(new) }
        }
        .padding(.horizontal, 9)
        .frame(width: 200, height: 24)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 7))
        // Selected as well as focused, so the next keystroke replaces the old query rather than extending it.
        .onChange(of: focusRequest) { _, _ in
            isFocused = true
            selection = TextSelection(range: query.startIndex..<query.endIndex)
        }
        // Escape empties a field with something in it, and is left alone when there is nothing to clear.
        .onKeyPress(.escape) {
            guard !query.isEmpty else { return .ignored }
            query = ""
            onSearch("")
            return .handled
        }
    }
}

/// The pop-up that names what the page is showing and, where there is a choice, offers the others.
struct MainScopeControl: View {
    let scope: MainScope
    var onScope: (String) -> Void

    var body: some View {
        if scope.isSelectable {
            Picker(scope.title, selection: selection) {
                ForEach(scope.options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        } else {
            // No menu behind it, because there is nothing else it could be showing.
            Text(scope.title)
                .font(.system(size: MainMetrics.calloutSize))
                .foregroundStyle(.secondary)
        }
    }

    /// Reads the selection from the presentation and writes changes straight back to the app.
    private var selection: Binding<String> {
        Binding(
            get: { scope.options.first(where: \.isSelected)?.id ?? "" },
            set: { onScope($0) })
    }
}
