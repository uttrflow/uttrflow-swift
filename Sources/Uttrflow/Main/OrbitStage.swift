import UttrflowUX
import SwiftUI

/// Where the window opens: a microphone at the centre of a ring of its own waveform.
///
/// The stage replaces a photograph, a gradient banner and every other thing a home screen
/// usually opens with, for one reason — it is the only picture on the page that is about
/// what this app does. It is drawn rather than fetched, so it costs no asset, no download
/// and no network, which matters in a product that never reaches for any of the three.
///
/// It is deliberately the only place the ring appears, apart from the sidebar's
/// microphone while a dictation is running. A mark repeated behind every page header
/// stops being a mark and becomes wallpaper, and it says nothing on a page about words
/// somebody typed a fortnight ago.
struct OrbitStage: View {
    let presentation: HomePresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    /// Built once for the whole process. Fifty-two bars is enough for the ring to read as
    /// sound rather than as a gear wheel, and few enough to draw as three paths.
    private static let ticks = OrbitTick.ring(count: 52)

    var body: some View {
        VStack(spacing: 14) {
            instrument
                .frame(width: 186, height: 186)
            words
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .padding(.horizontal, 24)
        .background(ground)
        .overlay(alignment: .bottom) { MainDivider() }
    }

    /// The stage's own ground, dark whichever appearance the rest of the window is in.
    ///
    /// Fixed rather than following the system, because the ring is two saturated colours
    /// that only hold their meaning against something dark — teal at `#00C3D0` on a white
    /// panel is a pale smudge. The words on it are drawn white to match, so the contrast
    /// is a property of the stage rather than a hope about the theme.
    private var ground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.stagePanel, Color.stageGround],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [
                    Color.dockAccent.opacity(presentation.status.isReady ? 0.26 : 0.10),
                    Color.dockActive.opacity(presentation.status.isReady ? 0.10 : 0.04),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.30), startRadius: 0, endRadius: 330)
        }
    }

    /// The ring, and the microphone it is around.
    ///
    /// Three paths rather than fifty-two views: one for each accent and one for the quiet
    /// bars between them. A `ForEach` of rotated rectangles would draw the same picture
    /// and cost fifty-two view identities on a page that redraws on every keystroke in
    /// the search field.
    private var instrument: some View {
        ZStack {
            ring(.quiet, colour: .white.opacity(presentation.status.isReady ? 0.16 : 0.10))
            ring(.primary, colour: .dockActive.opacity(presentation.status.isReady ? 0.95 : 0.30))
            ring(.secondary, colour: .dockAccent.opacity(presentation.status.isReady ? 0.95 : 0.30))
            microphone
        }
        // Decoration with a caption of its own already underneath it. A screen reader
        // reading "ring, ring, ring" before the greeting is a screen reader nobody
        // leaves switched on.
        .accessibilityHidden(true)
    }

    private func ring(_ voice: OrbitVoice, colour: Color) -> some View {
        OrbitRing(ticks: Self.ticks.filter { $0.voice == voice })
            .fill(colour)
    }

    private var microphone: some View {
        Circle()
            .fill(Color.stageWell)
            .overlay(Circle().strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .overlay {
                Image(systemName: "mic")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(
                        presentation.status.isReady ? Color.dockActive : .white.opacity(0.35))
            }
            .frame(width: 112, height: 112)
    }

    private var words: some View {
        VStack(spacing: 11) {
            // Only when it is not the answer somebody expects. "LISTENING · READY" over a
            // microphone that is plainly ready is a label reporting the absence of a
            // problem, every time the window opens, and a line that always says the same
            // thing is a line nobody reads — which is exactly the line you need read on
            // the day it changes.
            if !presentation.status.isReady {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.dockWarning)
                        .frame(width: 6, height: 6)
                    Text(presentation.status.text.uppercased())
                        .font(.system(size: MainMetrics.footnoteSize, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(Color.dockWarning)
                }
            }
            Text(presentation.greeting)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(Color.mainText)
                .multilineTextAlignment(.center)
            Text(presentation.subtitle)
                .font(.system(size: MainMetrics.bodySize))
                .foregroundStyle(Color.mainText.opacity(0.78))
                .multilineTextAlignment(.center)
            hint
                .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            """
            \(presentation.status.text). \(presentation.greeting). \
            \(presentation.subtitle) \(presentation.hint.sentence)
            """)
    }

    /// "Say it once — hold ⌥ Space anywhere on your Mac", with the shortcut drawn as the
    /// keys somebody has to find rather than as two more words in a sentence.
    private var hint: some View {
        HStack(spacing: 7) {
            Text(presentation.hint.lead)
            ForEach(Array(presentation.hint.keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: MainMetrics.calloutSize, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.10), in: .rect(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1))
            }
            Text(presentation.hint.trail)
        }
        .font(.system(size: MainMetrics.bodySize))
        .foregroundStyle(Color.mainText.opacity(0.72))
    }
}

/// The initials in the corner, which are also the way to the Account page.
struct AccountChip: View {
    let account: HomeAccount
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onIntent(account.open.intent)
        } label: {
            HStack(spacing: 8) {
                mark
                Text(label)
                    .font(.system(size: MainMetrics.calloutSize))
                    .foregroundStyle(Color.mainMuted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 3)
            .padding(.trailing, 9)
            .padding(.vertical, 3)
            .background(.primary.opacity(isHovered ? 0.10 : 0.05), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.mainSeparator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(spokenLabel)
    }

    /// The circle at the leading edge.
    ///
    /// Filled and teal for a person, outlined and grey for nobody. The difference is the
    /// point: a filled monogram is how a Mac window says *signed in*, so the signed-out
    /// state must not borrow it — not with a silhouette, and not with initials taken from
    /// whoever owns the Mac.
    @ViewBuilder private var mark: some View {
        switch account {
        case .signedIn(let initials, _, _):
            Text(initials)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(
                        colors: [Color.dockAccent, Color.stageTealDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .circle)
        // The same monogram, unfilled. There is a real account behind it — this Mac's —
        // and the ring says so without borrowing the gradient that means a session.
        case .onThisMac(let initials, _, _):
            Text(initials)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.mainMuted)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.mainSeparator, lineWidth: 1))
        case .signedOut:
            Image(systemName: "person.crop.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.mainDim)
                .frame(width: 26, height: 26)
        }
    }

    private var label: String {
        switch account {
        case .signedIn(_, let name, _), .onThisMac(_, let name, _): name
        case .signedOut(let open): open.title
        }
    }

    /// The title alone would read as "Account" with no clue whose, and initials are
    /// unpronounceable.
    private var spokenLabel: String {
        switch account {
        case .signedIn(_, let name, let open): "\(open.title), \(name)"
        // Said in full, because "Account, Naveen" beside an unfilled ring would tell
        // somebody using VoiceOver they have a session they do not.
        case .onThisMac(_, let name, let open): "\(open.title), \(name), on this Mac"
        case .signedOut(let open): open.title
        }
    }
}

extension Color {
    /// The stage's ground, and the well the microphone sits in. Fixed values rather than
    /// system ones: this panel is dark in both appearances by design.
    static let stageGround = Color(rgb: 0x0B_0C10)
    static let stagePanel = Color(rgb: 0x0E_1016)
    static let stageWell = Color(rgb: 0x12_141C)
    /// The brand teal taken down until white sits legibly on it, for the one place a
    /// small patch of it carries text: the monogram. `dockActive` at `#29C0B4` is
    /// lovely on a control and hopeless behind two white letters.
    static let stageTealDeep = Color(rgb: 0x0A_5F73)
}

/// One figure in the row under the stage.
///
/// The comment beneath is the whole reason this is not just a big number: "2,715" says
/// where you stand and nothing about which way you are going, and the presenter only ever
/// supplies the comparison when there is a real second figure to make it from.
struct OrbitFigure: View {
    let statistic: MainStatistic
    /// Which of the two accents this figure wears, or none.
    ///
    /// By position rather than by meaning: the presenter hands over four captions and no
    /// notion of which is the interesting one, and a view that matched on the words
    /// would be a view that fell silent the day one of them was reworded. Alternating
    /// keeps the row from reading as four of the same thing.
    let tint: Color?

    var body: some View {
        VStack(spacing: 5) {
            Text(statistic.value)
                .font(.system(size: 26, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
            Text(statistic.caption)
                .font(.system(size: MainMetrics.subheadSize))
                .foregroundStyle(Color.mainMuted)
                .multilineTextAlignment(.center)
            if let comment = statistic.comment {
                Text(comment)
                    .font(.system(size: MainMetrics.footnoteSize))
                    .foregroundStyle(Color.mainDim)
                    .multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The clipboard, beside today's dictations.
///
/// The same three rows the demonstration further down the page animates, held still. A
/// still panel and a moving one earn different things: this one says *what is in there*
/// at a glance, where the animation below teaches *how to get it out*. Neither shows the
/// user's own clips — a password on the first screen of the app, where anyone walking
/// past can read it, is the hazard the panel's mask exists to prevent, and a home page
/// must not undo it.
struct ClipboardRail: View {
    let demonstration: HomeDemonstration
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                MainSectionLabel(text: "Clipboard")
                Spacer(minLength: 6)
                ForEach(Array(demonstration.keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .cardSurface(.primary.opacity(0.06), cornerRadius: 4)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(demonstration.rows.enumerated()), id: \.element.id) { index, row in
                    demonstrationRow(row, isChosen: index == demonstration.chosen)
                    if index < demonstration.rows.count - 1 { MainDivider() }
                }
            }
            .cardSurface()
            Text(demonstration.footnote)
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(Color.mainDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(demonstration.title)
    }

    private func demonstrationRow(_ row: HomeDemonstrationRow, isChosen: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(row.isMasked ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.dockActive))
                .frame(width: 14)
            Text(row.text)
                .font(.system(size: MainMetrics.calloutSize))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(row.isMasked ? Color.mainDim : Color.mainText)
            Spacer(minLength: 4)
            // The chosen row wears the key that would paste it; the masked one says why
            // it is dots rather than words.
            if row.isMasked {
                Text("hidden")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.mainDim)
            } else if isChosen {
                Text("⏎")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.dockActive)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isChosen ? Color.mainHover : .clear)
        .accessibilityElement(children: .combine)
    }
}
