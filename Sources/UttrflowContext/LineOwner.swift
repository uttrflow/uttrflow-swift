/// The program a terminal line belongs to, read from the visible prompt text alone.
package enum LineOwner: Equatable, Sendable {
    /// A shell prompt, with the notation the prompt shape implies.
    case shell(ShellDialect)
    /// An interactive interpreter prompt such as `psql` or Python.
    case repl(ReplLanguage)
    /// A line with no prompt this recogniser knows, so no program is named.
    case unknown
}

/// The shell family a prompt shape implies.
package enum ShellDialect: Equatable, Sendable {
    case posix
    case zsh
    case powerShell
    /// A recognised prompt whose shape does not name a family.
    case unspecified
}

/// The language spoken at an interpreter prompt.
package enum ReplLanguage: Equatable, Sendable {
    case sql
    case python
    case ruby
}
