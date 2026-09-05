// The furniture every page in the main window shares: tones, pills, callouts, meters, and chrome.

/// How loudly something is drawn; a closed set, since the palette belongs to the design.
public enum MainTone: Sendable, Equatable, CaseIterable {
    /// Plain.
    case neutral
    /// The product's colour.
    case accent
    /// Something the user should look at, but which is not yet wrong.
    case warning
    /// Something is fine.
    case good
    /// Something that has gone wrong and is costing them.
    case critical
}

/// A short label on a tinted background.
public struct MainPill: Sendable, Equatable {
    /// The words in the pill.
    public let text: String
    /// How it is tinted.
    public let tone: MainTone

    /// Builds a pill; neutral unless said otherwise.
    public init(text: String, tone: MainTone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// A tinted paragraph saying what a page is for, or what it promises; context, never an instruction.
public struct MainCallout: Sendable, Equatable {
    /// The SF Symbol beside the paragraph.
    public let symbolName: String
    /// How it is tinted.
    public let tone: MainTone
    /// The paragraph.
    public let message: String

    /// Builds a callout; accent-tinted unless said otherwise.
    public init(symbolName: String, tone: MainTone = .accent, message: String) {
        self.symbolName = symbolName
        self.tone = tone
        self.message = message
    }
}

/// One bar in a figure and the thing it is compared with; no second meter is ever invented.
public struct MainMeter: Sendable, Equatable, Identifiable {
    /// What the bar measures.
    public let label: String
    /// Between zero and one, clamped on the way in so a bad measurement cannot draw outside its track.
    public let fraction: Double
    /// Whether this is the figure compared against rather than the current one; drawn quietly.
    public let isBaseline: Bool

    /// The label, which is unique within a figure.
    public var id: String { label }

    /// Builds a meter, clamping the fraction to 0…1.
    public init(label: String, fraction: Double, isBaseline: Bool = false) {
        self.label = label
        self.fraction = min(max(fraction, 0), 1)
        self.isBaseline = isBaseline
    }
}

/// How far off a page is from having something worth drawing; shown only when the answer is "wait".
public struct MainProgress: Sendable, Equatable {
    /// How far along, 0…1, clamped on the way in.
    public let fraction: Double
    /// What is done so far — "2 of 7 days".
    public let leading: String
    /// What happens when it finishes — "Charts appear on Tuesday".
    public let trailing: String

    /// Builds the progress, clamping the fraction to 0…1.
    public init(fraction: Double, leading: String, trailing: String) {
        self.fraction = min(max(fraction, 0), 1)
        self.leading = leading
        self.trailing = trailing
    }
}

/// The search field in a page's toolbar, carrying the query so the field and the list agree.
public struct MainSearchField: Sendable, Equatable {
    /// What the empty field says.
    public let placeholder: String
    /// What has been typed.
    public let query: String

    /// Builds the field.
    public init(placeholder: String, query: String) {
        self.placeholder = placeholder
        self.query = query
    }
}

/// The pop-up in a page's toolbar naming what it shows; a label when ``options`` is empty.
public struct MainScope: Sendable, Equatable {
    /// What the pop-up reads.
    public let title: String
    /// The choices, empty for a plain label.
    public let options: [MainScopeOption]

    /// Whether there is anything to pick.
    public var isSelectable: Bool { !options.isEmpty }

    /// Builds a scope; a label unless given options.
    public init(title: String, options: [MainScopeOption] = []) {
        self.title = title
        self.options = options
    }
}

/// One choice behind a ``MainScope``, reported back by identifier and re-presented.
public struct MainScopeOption: Sendable, Equatable, Identifiable {
    /// What the page is told when this is picked.
    public let id: String
    /// The words in the menu.
    public let title: String
    /// Whether this is the one showing.
    public let isSelected: Bool

    /// Builds an option.
    public init(id: String, title: String, isSelected: Bool) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
    }
}

/// The heading and toolbar of a page, in a fixed order: scope, then search, then the add button.
public struct MainPageChrome: Sendable, Equatable {
    /// The page's name.
    public let title: String
    /// One sentence under the title saying what this page is for; absent rather than restating the name.
    public let caption: String?
    /// The pop-up naming what the page shows, when it has one.
    public let scope: MainScope?
    /// The search field, when there is something to search.
    public let search: MainSearchField?
    /// The one thing this page can add, when it can.
    public let addAction: MainAction?

    /// Builds the chrome; everything but the title is optional.
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
