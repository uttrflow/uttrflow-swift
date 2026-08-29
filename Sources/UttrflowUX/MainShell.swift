/// The furniture every page in the main window is built out of.
///
/// Nine pages share one toolbar, one caption, one callout and one footnote, and the
/// only interesting difference between them is what sits in the middle. Factoring the
/// chrome here is what stops the ninth page inventing a tenth way to draw a heading —
/// and it is why the view that draws one page draws all of them.

/// How loudly something is drawn.
///
/// A closed set rather than a colour, because a page must not be able to choose a
/// colour: the palette belongs to the design and a page belongs to the decision.
public enum MainTone: Sendable, Equatable, CaseIterable {
    case neutral
    case accent
    /// Something the user should look at, but which is not yet wrong.
    case warning
    case good
    /// Something that has gone wrong and is costing them.
    case critical
}

/// A short label on a tinted background.
public struct MainPill: Sendable, Equatable {
    public let text: String
    public let tone: MainTone

    public init(text: String, tone: MainTone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// A tinted paragraph saying what a page is for, or what it promises.
///
/// Context, never an instruction: a callout the user has to act on is a row that has
/// been drawn in the wrong place.
public struct MainCallout: Sendable, Equatable {
    public let symbolName: String
    public let tone: MainTone
    public let message: String

    public init(symbolName: String, tone: MainTone = .accent, message: String) {
        self.symbolName = symbolName
        self.tone = tone
        self.message = message
    }
}

/// One bar in a figure, and the thing it is being compared with.
///
/// A figure with no comparison is a figure nobody can read: 97.2% is only good or bad
/// against the number it used to be. Where there is no honest second number, there is
/// no second meter rather than an invented one.
public struct MainMeter: Sendable, Equatable, Identifiable {
    public let label: String
    /// Between zero and one. Clamped on the way in, so a view can draw it without
    /// checking and a bad measurement cannot draw outside its track.
    public let fraction: Double
    /// Whether this is the figure being compared against rather than the current one.
    /// Drawn quietly, so the eye lands on the one that changed.
    public let isBaseline: Bool

    public var id: String { label }

    public init(label: String, fraction: Double, isBaseline: Bool = false) {
        self.label = label
        self.fraction = min(max(fraction, 0), 1)
        self.isBaseline = isBaseline
    }
}

/// How far off a page is from having something worth drawing.
///
/// Only ever shown when the answer is "wait": a page that is empty because the user has
/// not done anything gets a sentence, not a progress bar.
public struct MainProgress: Sendable, Equatable {
    public let fraction: Double
    /// What has happened so far — "2 of 7 days".
    public let leading: String
    /// What happens when it finishes — "Charts appear on Tuesday".
    public let trailing: String

    public init(fraction: Double, leading: String, trailing: String) {
        self.fraction = min(max(fraction, 0), 1)
        self.leading = leading
        self.trailing = trailing
    }
}

/// The search field in a page's toolbar.
///
/// Carries what is currently typed as well as the placeholder, so the page is drawn
/// from one value and the field cannot hold a query the list has not been filtered by.
public struct MainSearchField: Sendable, Equatable {
    public let placeholder: String
    public let query: String

    public init(placeholder: String, query: String) {
        self.placeholder = placeholder
        self.query = query
    }
}

/// The pop-up in a page's toolbar, naming what the page is showing.
///
/// Sometimes a choice and sometimes only a label — Insights' "Last 14 days" is not
/// something the user picks, it is the window the measurements happen to cover. Both
/// are drawn the same way, so ``options`` is empty rather than there being two controls.
public struct MainScope: Sendable, Equatable {
    public let title: String
    public let options: [MainScopeOption]

    public var isSelectable: Bool { !options.isEmpty }

    public init(title: String, options: [MainScopeOption] = []) {
        self.title = title
        self.options = options
    }
}

/// One choice behind a ``MainScope``.
///
/// Reported back by identifier and re-presented, exactly as the search field is: which
/// rows a scope keeps is a decision, and decisions do not live in views.
public struct MainScopeOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let isSelected: Bool

    public init(id: String, title: String, isSelected: Bool) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
    }
}

/// The heading and toolbar of a page.
///
/// The order is fixed here rather than in each page: scope, then search, then the one
/// thing this page can add. Every artboard lays its toolbar out that way, and a page
/// that could choose would eventually choose differently.
public struct MainPageChrome: Sendable, Equatable {
    public let title: String
    /// One sentence under the title, saying what this page is for.
    ///
    /// Here rather than in the view because it is copy, and copy that a page can change
    /// its mind about between builds is copy nobody reviews. Optional so a page that has
    /// nothing to add says nothing rather than padding the band with a restatement of
    /// its own name.
    public let caption: String?
    public let scope: MainScope?
    public let search: MainSearchField?
    public let addAction: MainAction?

    public init(
        title: String,
        caption: String? = nil,
        scope: MainScope? = nil,
        search: MainSearchField? = nil,
        addAction: MainAction? = nil
    ) {
        self.title = title
        self.caption = caption
        self.scope = scope
        self.search = search
        self.addAction = addAction
    }
}
