import UttrflowUX
import SwiftUI

/// The main window: a sidebar, a toolbar, and whichever page is selected.
///
/// The chrome is here and only here. Each page draws its own content and nothing else,
/// so nine pages cannot end up with nine subtly different headings — and everything they
/// draw arrives already decided, from ``UttrflowUX``.
struct MainWindowView: View {
    @Bindable var model: MainWindowModel
    var onIntent: (MainIntent) -> Void = { _ in }
    var onSearch: (String) -> Void = { _ in }
    var onScope: (String) -> Void = { _ in }
    var onDraft: () -> Void = {}
    var onToggleSidebar: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                presentation: model.content.sidebar,
                isExpanded: model.isSidebarExpanded
            ) { destination in
                switch destination {
                case .page(let page):
                    // Through the app, not straight into the model. Setting `model.page`
                    // alone swapped the pane and left the sidebar's highlight — and its
                    // "corrections today" badge — drawn from a presentation nothing had
                    // rebuilt, so the blue pill stayed on the page you had left until
                    // some unrelated event redrew the window.
                    onIntent(.show(page))
                case .settings(let tab):
                    // The one row that does not change the pane: Settings is a window of
                    // its own, and the app owns every window.
                    onIntent(.go(.settings(tab)))
                }
            }
            pane
        }
        // The one animation in the window. The sidebar's width moves the page beside it,
        // and a page that jumps sideways reads as a redraw rather than as a drawer.
        .animation(.snappy(duration: 0.22), value: model.isSidebarExpanded)
        .background(Color.mainBackground)
        .foregroundStyle(Color.mainText, Color.mainMuted, Color.mainDim)
        // Every system control in this window — the segmented pickers, the toggles, the
        // focus rings — is drawn in the accent colour, and the system's is the stock
        // macOS blue. One tint at the root rather than a modifier per control, so a
        // control added later cannot arrive blue.
        .tint(Color.dockAccent)
        // The title bar is transparent and the content is full-size, but SwiftUI still
        // reserves a safe area for it — which left a band of empty window above the
        // stage that no view owned. The rail keeps its own inset for the traffic lights,
        // which is the only thing that band was ever protecting.
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Pane

    private var pane: some View {
        VStack(spacing: 0) {
            MainWindowStrip(
                account: model.content.home.account,
                isSidebarExpanded: model.isSidebarExpanded,
                onToggleSidebar: onToggleSidebar,
                onIntent: onIntent)
            if model.page != .home {
                OrbitPageHeader(
                    chrome: chrome, query: $model.searchQuery, onIntent: onIntent,
                    onSearch: onSearch, onScope: onScope)
            }
            page
                // Home draws its own stage from edge to edge; every other page is a
                // document and wants a margin.
                .padding(.horizontal, model.page == .home ? 0 : MainMetrics.contentPadding)
                .padding(.top, model.page == .home ? 0 : 18)
                .padding(.bottom, model.page == .home ? 0 : 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // The field holds what is being typed, so it cannot be redrawn from the
        // presentation on every keystroke without fighting the cursor. It can be put
        // back in step when the page changes, which is the only moment the two can
        // legitimately differ: each page has its own query, and a field still showing
        // the last page's word would filter this one by it.
        .onChange(of: model.page) { _, _ in
            model.searchQuery = chrome.search?.query ?? ""
        }
    }

    /// The chrome of whichever page is showing.
    ///
    /// A `switch` rather than a protocol the presentations conform to: nine returns of
    /// one stored property is less machinery than an existential, and it fails to
    /// compile the day a tenth page is added, which is the point.
    private var chrome: MainPageChrome {
        let content = model.content
        return switch model.page {
        // Home draws its own greeting, so the toolbar above it stays empty rather than
        // repeating the page's name back at the reader.
        case .home: MainPageChrome(title: "")
        case .dictation: content.dictation.chrome
        case .history:
            MainPageChrome(
                title: SidebarPresenter.title(for: .history),
                caption: HistoryPresenter.caption,
                search: content.history.showsSearch
                    ? MainSearchField(
                        placeholder: HistoryPresenter.searchPlaceholder, query: model.searchQuery)
                    : nil)
        case .dictionary: content.dictionary.chrome
        case .corrections: content.corrections.chrome
        case .insights: content.insights.chrome
        case .snippets: content.snippets.chrome
        case .style: content.style.chrome
        case .diagnostics:
            MainPageChrome(
                title: SidebarPresenter.title(for: .diagnostics),
                caption: DiagnosticsPresenter.caption)
        case .account: content.account.chrome
        }
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .home:
            HomePageView(presentation: model.content.home, onIntent: onIntent)
        case .dictation:
            DictationPageView(presentation: model.content.dictation, onIntent: onIntent)
        case .history:
            ScrollView {
                HistoryPageView(presentation: model.content.history, onIntent: onIntent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .dictionary:
            DictionaryPageView(
                presentation: model.content.dictionary, draft: reporting($model.wordDraft),
                onIntent: onIntent)
        case .corrections:
            CorrectionsPageView(presentation: model.content.corrections, onIntent: onIntent)
        case .insights:
            InsightsPageView(presentation: model.content.insights, onIntent: onIntent)
        case .snippets:
            SnippetsPageView(
                presentation: model.content.snippets, draft: reporting($model.snippetDraft),
                onIntent: onIntent)
        case .style:
            StylePageView(presentation: model.content.style, onIntent: onIntent)
        case .diagnostics:
            ScrollView {
                DiagnosticsPageView(presentation: model.content.diagnostics, onIntent: onIntent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .account:
            AccountPageView(presentation: model.content.account, onIntent: onIntent)
        }
    }

    /// Wraps an editor's binding so that typing into it also asks the app to re-present
    /// the page.
    ///
    /// Without this the editor is drawn from the draft as it was when it opened: Save
    /// stays disabled however much is typed, because the presenter is still looking at
    /// an empty field and still has a reason to refuse it.
    private func reporting<Draft>(_ binding: Binding<Draft>) -> Binding<Draft> {
        Binding(
            get: { binding.wrappedValue },
            set: {
                binding.wrappedValue = $0; onDraft()
            })
    }
}

/// The strip across the top of the window: the traffic lights sit over the rail at one
/// end of it, and the account chip at the other.
///
/// Forty points of nothing in between, all but one control. It is the one band that is
/// the same on every page, so putting anything *page-specific* in it would make the
/// window's own chrome move about as you navigate — and the sidebar toggle is not page
/// specific. It is the window talking about itself, which is what this band is for.
struct MainWindowStrip: View {
    let account: HomeAccount
    var isSidebarExpanded: Bool = false
    var onToggleSidebar: () -> Void = {}
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebarToggle
            Spacer(minLength: 0)
            AccountChip(account: account, onIntent: onIntent)
        }
        .padding(.horizontal, 12)
        .frame(height: MainMetrics.toolbarHeight)
    }

    /// The one control in the band, and the only way to the sidebar's names with a mouse.
    ///
    /// Its symbol says which way it goes rather than what it is: the leading half of the
    /// square fills when the sidebar is showing, which is the same language every other
    /// Mac app uses for the same button.
    private var sidebarToggle: some View {
        Button(action: onToggleSidebar) {
            Image(systemName: isSidebarExpanded ? "sidebar.leading" : "sidebar.left")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.mainMuted)
                .frame(width: 26, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isSidebarExpanded ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityLabel(isSidebarExpanded ? "Hide Sidebar" : "Show Sidebar")
    }
}

/// The band each page opens with: what it is, what it is for, and its own one control.
///
/// The kicker above the title is the page's name in mono capitals — the same word, said
/// quietly, so the eye lands on the band before it reads it. It costs nothing to derive
/// and it is what makes nine pages read as one app rather than nine documents.
struct OrbitPageHeader: View {
    let chrome: MainPageChrome
    @Binding var query: String
    var onIntent: (MainIntent) -> Void
    var onSearch: (String) -> Void
    var onScope: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(chrome.title.uppercased())
                    .font(.system(size: MainMetrics.footnoteSize, weight: .medium))
                    .tracking(1.6)
                    .foregroundStyle(Color.dockSecondary)
                Text(chrome.title)
                    .font(.system(size: 29, weight: .bold))
                if let caption = chrome.caption {
                    Text(caption)
                        .font(.system(size: MainMetrics.bodySize))
                        .foregroundStyle(Color.mainMuted)
                }
            }
            // One element: a screen reader should hear the page's name once, not its
            // name, then its name again, then a sentence.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([chrome.title, chrome.caption].compactMap(\.self).joined(separator: ". "))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 10)
            if let scope = chrome.scope {
                MainScopeControl(scope: scope, onScope: onScope)
            }
            if let search = chrome.search {
                MainSearchControl(field: search, query: $query, onSearch: onSearch)
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
    var onSearch: (String) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(field.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: MainMetrics.calloutSize))
                .onChange(of: query) { _, new in onSearch(new) }
        }
        .padding(.horizontal, 9)
        .frame(width: 200, height: 24)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 7))
    }
}

/// The pop-up that names what the page is showing — and, where there is a choice,
/// offers the others.
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

    /// Reads the selection out of the presentation and writes changes straight back to
    /// the app, so the control never holds an opinion of its own about what is selected.
    private var selection: Binding<String> {
        Binding(
            get: { scope.options.first(where: \.isSelected)?.id ?? "" },
            set: { onScope($0) })
    }
}
