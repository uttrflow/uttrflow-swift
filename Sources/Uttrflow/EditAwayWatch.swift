// Reads the field a dictation landed in once more and vetoes provisional words replaced by hand.

import Foundation
import UttrflowContext
import UttrflowDictionary

/// One read of the focused field: which field it is and what it says.
struct LandedFieldRead: Sendable, Equatable {
    let field: FocusedFieldIdentity
    let text: String
}

/// Sends each provisional word edited away after a dictation through `recordRevert(of:)`, and counts each applied word left unedited as accepted. See `Docs/app-dictionary-store.md`.
struct EditAwayWatch: Sendable {
    /// How long after landing the field is read again; long enough for a quick fix, short enough to be about this dictation.
    static let window: Duration = .seconds(10)

    let dictionary: PersonalDictionaryStore
    /// The field as it reads now, or `nil` when nothing readable is focused.
    var readField: @Sendable () async -> LandedFieldRead? = { await Self.focusedField() }
    var wait: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// Reads the field at landing, again after `window`, and vetoes only when both reads are the same field.
    func watch(_ applied: [EditAway.Applied], inserted: String) async {
        guard !applied.isEmpty, let landed = await readField() else { return }
        await wait(Self.window)
        guard let later = await readField(), later.field == landed.field else { return }
        let away = Set(EditAway.editedAway(applied, inserted: inserted, fieldNow: later.text))
        let probation = Set(applied.filter(\.isProvisional).map(\.entryID))
        for id in away.intersection(probation) {
            _ = try? await dictionary.recordRevert(of: id)
        }
        let accepted = EditAway.kept(applied, fieldNow: later.text).filter { !away.contains($0) }
        if !accepted.isEmpty { _ = try? await dictionary.recordAccepted(of: accepted) }
    }

    /// The existing field reader, kept to fields that name themselves and give their text.
    private static func focusedField() async -> LandedFieldRead? {
        guard let snapshot = await FocusedFieldReader.read(), let field = snapshot.focusedFieldIdentity,
            let text = snapshot.value
        else { return nil }
        return LandedFieldRead(field: field, text: text)
    }
}
