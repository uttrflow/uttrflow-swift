// The menu bar popover's keyboard order: which control each place is, and where an arrow key goes next.

import UttrflowUX

/// The popover's controls in drawing order, so the arrows and Return reach each as a click would.
struct MenuBarKeyboard: Equatable {
    /// Every control the keyboard can reach: the header's action, the learned words, the round buttons, then the rows.
    let commands: [MenuBarCommand]
    /// The place of the first learned word's Undo.
    let learnedStart: Int
    /// The place of the first round button.
    let buttonsStart: Int
    /// The place of the last dictation's row; its Undo, when offered, is the next place.
    let lastDictationPlace: Int
    /// The place of the first clipboard row.
    let clipsStart: Int

    init(_ presentation: MenuBarPresentation) {
        var commands: [MenuBarCommand] = []
        if case .status(let status) = presentation.header, let action = status.action {
            commands.append(action)
        }
        learnedStart = commands.count
        commands += presentation.learned.map(\.undo)
        buttonsStart = commands.count
        commands += presentation.buttons.map(\.command)
        lastDictationPlace = commands.count
        if let last = presentation.lastDictation {
            commands.append(last.insert)
            if let undo = last.undo?.command { commands.append(undo) }
        }
        clipsStart = commands.count
        commands += presentation.clips.map(\.insert)
        self.commands = commands
    }

    /// A row of buttons alone, with no header action and no rows.
    init(commands: [MenuBarCommand]) {
        self.commands = commands
        learnedStart = 0
        buttonsStart = 0
        lastDictationPlace = commands.count
        clipsStart = commands.count
    }

    /// The next usable place after `current`, forward or back, wrapping at either end; nil when none can be used.
    func place(after current: Int?, forward: Bool) -> Int? {
        guard commands.contains(where: \.isEnabled) else { return nil }
        let count = commands.count
        let step = forward ? 1 : -1
        var place = current ?? (forward ? -1 : count)
        repeat {
            place = ((place + step) % count + count) % count
        } while !commands[place].isEnabled
        return place
    }

    /// The command at `place` when it can be used now.
    func command(at place: Int?) -> MenuBarCommand? {
        guard let place, commands.indices.contains(place), commands[place].isEnabled else { return nil }
        return commands[place]
    }
}
