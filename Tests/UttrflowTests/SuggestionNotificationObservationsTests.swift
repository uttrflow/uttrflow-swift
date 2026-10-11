import Foundation
import Testing

@testable import Uttrflow

private enum NoticeKind: Sendable, Hashable, CaseIterable { case activation, spaces, screen, session }

@MainActor
private final class NoticeRecipient {
    var events: [NoticeKind] = []
}

@MainActor
@Suite("Suggestion notification lifetimes")
struct SuggestionNotificationObservationsTests {
    private func observer(
        _ name: String, in center: NotificationCenter, kind: NoticeKind, recipient: NoticeRecipient
    ) -> any NSObjectProtocol {
        center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) {
            [weak recipient] _ in MainActor.assumeIsolated { recipient?.events.append(kind) }
        }
    }

    @Test("activation cleanup leaves every space token until space cleanup")
    func workspaceCategories() {
        let center = NotificationCenter()
        let owner = SuggestionNotificationObservations()
        let recipient = NoticeRecipient()
        owner.observeActivations {
            observer("activation", in: center, kind: .activation, recipient: recipient)
        }
        for _ in 0..<2 {
            owner.observeSpace { observer("space", in: center, kind: .spaces, recipient: recipient) }
        }
        center.post(name: Notification.Name("activation"), object: nil)
        center.post(name: Notification.Name("space"), object: nil)
        #expect(recipient.events == [.activation, .spaces, .spaces])
        owner.removeActivations(from: center)
        recipient.events = []
        center.post(name: Notification.Name("activation"), object: nil)
        center.post(name: Notification.Name("space"), object: nil)
        #expect(recipient.events == [.spaces, .spaces])
        owner.removeSpaces(from: center)
        owner.removeActivations(from: center)
        owner.removeSpaces(from: center)
        recipient.events = []
        center.post(name: Notification.Name("space"), object: nil)
        #expect(recipient.events.isEmpty)
    }

    @Test("a screen guard keeps its first center and permits another after removal")
    func guardedScreen() {
        let first = NotificationCenter()
        let second = NotificationCenter()
        let owner = SuggestionNotificationObservations()
        let recipient = NoticeRecipient()
        var factories = 0
        let unowned = observer("screen", in: first, kind: .activation, recipient: recipient)
        defer { first.removeObserver(unowned) }
        for center in [first, second] {
            owner.observeScreen(in: center) {
                factories += 1
                return observer("screen", in: center, kind: .screen, recipient: recipient)
            }
        }
        #expect(factories == 1)
        second.post(name: Notification.Name("screen"), object: nil)
        #expect(recipient.events.isEmpty)
        first.post(name: Notification.Name("screen"), object: nil)
        #expect(Set(recipient.events) == [.screen, .activation])
        owner.removeScreen()
        owner.removeScreen()
        recipient.events = []
        first.post(name: Notification.Name("screen"), object: nil)
        #expect(recipient.events == [.activation])
        owner.observeScreen(in: second) {
            observer("screen", in: second, kind: .screen, recipient: recipient)
        }
        second.post(name: Notification.Name("screen"), object: nil)
        #expect(recipient.events == [.activation, .screen])
        owner.removeScreen()
    }

    @Test("a session group stops every workspace and lock callback and re-registers")
    func guardedSessionGroup() {
        let workspace = NotificationCenter()
        let lock = NotificationCenter()
        let owner = SuggestionNotificationObservations()
        let recipient = NoticeRecipient()
        var factories = 0
        for _ in 0..<2 {
            owner.observeSessionEnd(in: workspace, screenLockCenter: lock) {
                factories += 1
                return { [weak recipient] in MainActor.assumeIsolated { recipient?.events.append(.session) } }
            }
        }
        #expect(factories == 1)
        func postAll() {
            for name in DictationSessionEndObserver.notices { workspace.post(name: name, object: nil) }
            lock.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)
        }
        postAll()
        #expect(recipient.events == [.session, .session, .session, .session])
        owner.removeSessionEnd()
        owner.removeSessionEnd()
        recipient.events = []
        postAll()
        #expect(recipient.events.isEmpty)
        owner.observeSessionEnd(in: workspace, screenLockCenter: lock) {
            { [weak recipient] in MainActor.assumeIsolated { recipient?.events.append(.session) } }
        }
        postAll()
        #expect(recipient.events.count == 4)
        owner.removeSessionEnd()
    }

    @Test(
        "each original teardown order removes only its next category",
        arguments: [
            [NoticeKind.activation, .spaces, .screen, .session], [.activation, .session, .spaces, .screen],
        ])
    fileprivate func teardownOrders(order: [NoticeKind]) {
        let workspace = NotificationCenter()
        let screen = NotificationCenter()
        let lock = NotificationCenter()
        let owner = SuggestionNotificationObservations()
        let recipient = NoticeRecipient()
        owner.observeActivations {
            observer("activation", in: workspace, kind: .activation, recipient: recipient)
        }
        owner.observeSpace { observer("space", in: workspace, kind: .spaces, recipient: recipient) }
        owner.observeScreen(in: screen) {
            observer("screen", in: screen, kind: .screen, recipient: recipient)
        }
        owner.observeSessionEnd(in: workspace, screenLockCenter: lock) {
            { [weak recipient] in MainActor.assumeIsolated { recipient?.events.append(.session) } }
        }
        var live = Set(NoticeKind.allCases)
        for kind in order {
            switch kind {
            case .activation: owner.removeActivations(from: workspace)
            case .spaces: owner.removeSpaces(from: workspace)
            case .screen: owner.removeScreen()
            case .session: owner.removeSessionEnd()
            }
            live.remove(kind)
            recipient.events = []
            workspace.post(name: Notification.Name("activation"), object: nil)
            workspace.post(name: Notification.Name("space"), object: nil)
            screen.post(name: Notification.Name("screen"), object: nil)
            lock.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)
            #expect(Set(recipient.events) == live)
        }
    }

    @Test("a weak callback recipient and the cleaned-up owner are released")
    func weakLifetimes() {
        let center = NotificationCenter()
        var owner: SuggestionNotificationObservations? = SuggestionNotificationObservations()
        var recipient: NoticeRecipient? = NoticeRecipient()
        weak let observedOwner = owner
        weak let observedRecipient = recipient
        owner?.observeScreen(in: center) {
            center.addObserver(forName: Notification.Name("screen"), object: nil, queue: .main) {
                [weak recipient] _ in MainActor.assumeIsolated { recipient?.events.append(.screen) }
            }
        }
        center.post(name: Notification.Name("screen"), object: nil)
        #expect(recipient?.events == [.screen])
        recipient = nil
        #expect(observedRecipient == nil)
        center.post(name: Notification.Name("screen"), object: nil)
        owner?.removeScreen()
        owner = nil
        #expect(observedOwner == nil)
        center.post(name: Notification.Name("screen"), object: nil)
    }
}
