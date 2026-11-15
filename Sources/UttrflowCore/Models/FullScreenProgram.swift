/// A terminal whose screen a full-screen program has taken, so the line at the caret is that program's and never a shell command.
public enum FullScreenProgram {
    /// Editors, pagers, pickers and monitors that draw the whole screen, named as a window title names the foreground one.
    static let programs: Set<String> = [
        "vim", "vi", "nvim", "view", "vimdiff", "nano", "pico", "emacs", "micro", "hx", "helix", "kak",
        "less",
        "more", "most", "man", "fzf", "sk", "peco", "fzy", "htop", "top", "btop", "atop", "glances",
        "lazygit",
        "tig", "gitui", "ranger", "nnn", "lf", "yazi", "mc", "ncdu", "k9s", "mutt", "neomutt", "w3m", "lynx",
        "watch",
    ]

    /// Shells, which a title names only while the prompt is in front, a login shell with a leading dash.
    static let shells: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "nu", "pwsh", "xonsh", "elvish", "login",
    ]

    /// Words that run the program after them, so `sudo vim` is read as `vim`.
    static let launchers: Set<String> = ["sudo", "doas", "env", "nice", "nohup", "exec", "command", "time"]

    /// Text that separates a title's parts: directory, foreground program and arguments, size, tab or host name.
    static let separators = [" — ", " – ", " - ", " | ", ": ", "(", ")", "[", "]", "\n"]

    /// Whether a window title names a program that owns the terminal's screen, judged by the word each part leads with.
    public static func isNamed(inWindowTitle title: String?) -> Bool {
        guard let title else { return false }
        let leading = leadingWords(of: title)
        // A shell in the title is the foreground process, so a listed word beside it is a directory, host or tab name.
        if leading.contains(where: { shells.contains(String($0.drop { $0 == "-" })) }) { return false }
        return leading.contains(where: programs.contains)
    }

    /// The word each part of a title leads with, read past launchers and their flags, lowercased.
    static func leadingWords(of title: String) -> [String] {
        var text = title
        for separator in separators { text = text.replacingOccurrences(of: separator, with: "\u{0}") }
        return text.split(separator: "\u{0}").compactMap { part in
            var words = RemoteSession.words(of: String(part)).map { $0.lowercased() }[...]
            while let first = words.first, launchers.contains(first), words.count > 1 {
                words.removeFirst()
                while let flag = words.first, flag.hasPrefix("-"), words.count > 1 { words.removeFirst() }
            }
            return words.first
        }
    }
}
