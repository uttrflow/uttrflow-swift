import Testing
import UttrflowCore
import UttrflowSettings

@testable import UttrflowUX

@MainActor
@Suite("Unbound dictation display")
struct UnboundDictationDisplayTests {
    private var unbound: Settings {
        var settings = Settings.default
        settings.shortcuts.removeAll(from: .dictate)
        return settings
    }

    @Test("Optional display bindings have no fallback and preserve bound glyphs")
    func optionalGlyphs() {
        #expect(SettingsShortcut.keycaps(for: nil).isEmpty)
        #expect(SettingsShortcut.compact(nil).isEmpty)
        for binding in [HotkeyBinding.functionHold, .optionSpace] {
            let optional: HotkeyBinding? = binding
            #expect(SettingsShortcut.keycaps(for: optional) == SettingsShortcut.keycaps(for: binding))
            #expect(SettingsShortcut.compact(optional) == SettingsShortcut.compact(binding))
        }
    }

    @Test("An unbound menu uses its status instead of teaching Fn")
    func menu() {
        let page = MenuBarPresenter.present(MenuBarState(shortcuts: unbound.shortcuts))
        guard case .status = page.header else {
            Issue.record("An unbound Dictate shortcut must not render a keyboard instruction")
            return
        }
        #expect(page.command(.startDictation) != nil)
    }

    @Test(
        "The legacy hint fallback stays hidden for either activation",
        arguments: [
            HotkeyActivation.holdToTalk, .pressToToggle,
        ])
    func legacyHint(_ activation: HotkeyActivation) {
        let state = MenuBarState(shortcuts: unbound.shortcuts, activation: activation)
        let fallback = MenuBarPresenter.hint(for: state)
        #expect(fallback.keys == "fn")
        #expect(MenuBarPresenter.present(state).header != .hint(fallback))
    }

    @Test("Home removes the complete shortcut instruction and retains its direct action")
    func home() {
        let page = HistoryFixture.home(shortcut: SettingsShortcut.compact(unbound.hotkey), settings: unbound)
        #expect(page.hint.keys.isEmpty)
        #expect(page.hint.lead.isEmpty)
        #expect(page.hint.trail.isEmpty)
        #expect(!page.subtitle.contains("Hold the shortcut"))
        #expect(page.emptyState?.message.isEmpty == true)
        #expect(page.emptyState?.action?.intent == .dictate)
    }

    @Test(
        "Every pending onboarding trial omits an absent shortcut",
        arguments: [
            OnboardingTrial.waiting, .listening, .stillLoading,
        ])
    func trial(_ trial: OnboardingTrial) {
        let page = OnboardingPresenter.page(
            for: OnboardingState(step: .ready, detail: .finishing(.ready, trial: trial)),
            hotkey: unbound.shortcuts.first(for: .dictate), shortcuts: unbound.shortcuts)
        guard case .keyboard(let keyboard) = page.picture else {
            Issue.record("Expected the existing onboarding keyboard presentation")
            return
        }
        #expect(keyboard.keys.isEmpty)
        #expect(keyboard.lit == nil)
        #expect(keyboard.bracket == nil)
        #expect(!keyboard.isHeld)
        #expect(!keyboard.demonstrates)
        #expect(page.subtitle == nil)
        #expect(page.action?.intent == .finish)
    }

    @Test("The onboarding flow does not animate or explain a nonexistent shortcut")
    func onboarding() async {
        let harness = Harness(microphone: .granted, accessibility: .granted, settings: unbound)
        await harness.flow.start()
        #expect(harness.step == .ready)
        let page = harness.page
        guard case .keyboard(let keyboard) = page.picture else {
            Issue.record("Expected the existing onboarding keyboard presentation")
            return
        }
        #expect(keyboard.keys.isEmpty)
        #expect(keyboard.lit == nil)
        #expect(keyboard.bracket == nil)
        #expect(!keyboard.demonstrates)
        #expect(page.subtitle == nil)
        #expect(page.action?.intent == .finish)
    }
}
