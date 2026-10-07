import Foundation

// Recognises a credential handed to a command as an argument, or sent as an authorization header.

/// A password on a command line or in a header, which names no secret with `=` or `:` the named-secret rule reads. See Docs/clipboard-secrets.md.
enum CommandCredentialShape {
    /// Whether any line hands a command a credential, as `mysql -pX`, `curl -u a:b` or an `Authorization:` header do.
    static func matches(_ text: String, read: inout Int) -> Bool {
        var netrc = NetrcCredentialShape.Scanner()
        return matchesCommand(text, read: &read, netrc: &netrc)
    }

    /// Whether shell words in the text hand a command a credential or an authorization header.
    private static func matchesCommand(
        _ text: String, read: inout Int, netrc: inout NetrcCredentialShape.Scanner
    ) -> Bool {
        var words: [String] = []
        var word = ""
        var hasWord = false
        var hasCookieHeader = false
        var quote: Character?
        var interpolating = false
        var escaped = false
        /// Ends the word being read, and with a separator or a line end, the command it belongs to.
        func endWord() {
            if hasWord {
                words.append(word)
                if isCookieHeaderToken(word) { hasCookieHeader = true }
            }
            word = ""
            hasWord = false
        }
        for character in text {
            if netrc.consume(character, read: &read) { return true }
            read += 1
            if escaped {
                word.append(literalShellCharacter(character))
                escaped = false
                continue
            }
            if character.isNewline {
                quote = nil
                endWord()
                if handsOverCredential(words, read: &read) { return true }
                words.removeAll(keepingCapacity: true)
                hasCookieHeader = false
                continue
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else if interpolating, "{}".contains(character) {
                    word.append(character)
                } else if open == "'" || "{}<>".contains(character) {
                    word.append(literalShellCharacter(character))
                } else {
                    word.append(character)
                }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
                interpolating = false
                if let prefix = stringLiteralPrefixes[word.lowercased()] {
                    interpolating = prefix
                    word = ""
                }
                hasWord = true
            case "\\": escaped = true
            case "<", ">": endWord()
            case ";" where hasCookieHeader || isCookieHeaderToken(word):
                word.append(character)
                hasWord = true
            case "|", ";", "&":
                endWord()
                if handsOverCredential(words, read: &read) { return true }
                words.removeAll(keepingCapacity: true)
                hasCookieHeader = false
            default:
                if character.isWhitespace {
                    endWord()
                } else {
                    word.append(character)
                    hasWord = true
                }
            }
        }
        endWord()
        if netrc.finish(read: &read) { return true }
        return handsOverCredential(words, read: &read)
    }

    /// Code string prefixes, as `f"…"` and `rb'…'` write them, which are not part of the value; true where `{name}` is a placeholder.
    private static let stringLiteralPrefixes: [String: Bool] = [
        "f": true, "rf": true, "fr": true, "r": false, "b": false, "u": false, "rb": false, "br": false,
    ]

    /// Preserves metacharacters that shell quoting or escaping makes literal.
    private static func literalShellCharacter(_ character: Character) -> Character {
        switch character {
        case "$": "\u{E000}"
        case "{": "\u{E001}"
        case "}": "\u{E002}"
        case "<": "\u{E003}"
        case ">": "\u{E004}"
        default: character
        }
    }

    /// Whether the current command is reading a Cookie or Set-Cookie header value.
    private static func isCookieHeaderToken(_ word: String) -> Bool {
        if isBareCookieHeaderToken(word) { return true }
        guard let colon = word.firstIndex(of: ":") else { return false }
        let name = word[..<colon].trimmingSuffix(while: \.isWhitespace).lowercased()
        return name == "cookie" || name == "set-cookie"
    }

    /// Whether a complete empty cookie header has its ordinary spelling.
    private static func isBareCookieHeaderToken(_ word: String) -> Bool {
        word.caseInsensitiveCompare("Cookie:") == .orderedSame
            || word.caseInsensitiveCompare("Set-Cookie:") == .orderedSame
    }

    // MARK: - One command

    /// Programs that take a password through a short flag, and how each passes the value.
    private static let passwordFlags: [String: [(flag: String, form: ValueForm)]] = {
        let mysql: [(String, ValueForm)] = [("-p", .attached)]
        let login: [(String, ValueForm)] = [("-p", .attachedOrNext)]
        var table: [String: [(flag: String, form: ValueForm)]] = [
            "curl": [("-u", .userAndPassword), ("-U", .userAndPassword)],
            "sshpass": [("-p", .attachedOrNext)],
            "redis-cli": [("-a", .attachedOrNext)],
            "ssh-keygen": [("-N", .attachedOrNext), ("-P", .attachedOrNext)],
            "mongosh": [("-p", .attachedOrNext)],
            "mongo": [("-p", .attachedOrNext)],
            "zip": [("-P", .attachedOrNext)],
            "unzip": [("-P", .attachedOrNext)],
            "7z": [("-p", .attached)],
            "7za": [("-p", .attached)],
            "rar": [("-p", .attached)],
            "unrar": [("-p", .attached)],
            "smbclient": [("-U", .userAndPassword), ("--user", .userAndPassword)],
            // hdiutil reads the credential from stdin rather than an argument value.
            "hdiutil": [],
        ]
        for program in mysqlPrograms {
            table[program] = mysql
        }
        for program in ["docker", "podman", "nerdctl"] { table[program] = login }
        return table
    }()

    /// The MySQL and MariaDB clients, which share one flag grammar.
    private static let mysqlPrograms = [
        "mysql", "mariadb", "mysqldump", "mysqladmin", "mysqlimport", "mysqlshow", "mysqlcheck",
    ]

    /// Short letters whose value runs on in the same word, so a cluster stops being read at them.
    private static let valueLetters: [String: Set<Character>] = {
        var table: [String: Set<Character>] = ["curl": Set("AbcCdDeEFHKmoPQrtTwxXyYz")]
        for program in mysqlPrograms {
            table[program] = Set("hPuDeS")
        }
        for program in ["docker", "podman", "nerdctl"] { table[program] = Set("u") }
        table["redis-cli"] = Set("hpnu")
        table["ssh-keygen"] = Set("tbCfI")
        return table
    }()

    /// Long flags that carry a user and password together, for the programs that read them so.
    private static let userFlags: [String: Set<String>] = [
        "curl": ["user", "proxy-user"], "smbclient": ["user"],
    ]

    /// Programs whose `-p` is a password only under one subcommand, as `docker login -p` is and `docker run -p` is not.
    private static let passwordSubcommand: [String: String] = [
        "docker": "login", "podman": "login", "nerdctl": "login",
    ]

    /// Every subcommand a password flag waits for.
    private static let subcommandNames = Set(passwordSubcommand.values)

    /// How a flag hands over its value.
    private enum ValueForm {
        /// Joined to the flag only, as `-pX`; a bare `-p` asks for the password instead.
        case attached
        /// Joined to the flag or in the next word.
        case attachedOrNext
        /// `user:password`, or `user%password` as smbclient reads it, joined or in the next word; a user alone asks for the password.
        case userAndPassword
    }

    /// Whether one command's words hand a credential to a program or a header.
    private static func handsOverCredential(_ words: [String], read: inout Int) -> Bool {
        guard !words.isEmpty else { return false }
        var programs: Set<String> = []
        var subcommands: Set<String> = []
        var htpasswdBatch = false
        for (index, word) in words.enumerated() {
            read += 1
            let next = index + 1 < words.count ? words[index + 1] : nil
            if carriesHeaderCredential(word, following: words[(index + 1)...], read: &read) { return true }
            if isNamedAssignment(word) { return true }
            if word.hasPrefix("--"), let value = longFlagValue(word, next: next, programs: programs),
                isCredential(value)
            {
                return true
            }
            if word.hasPrefix("-"), !word.hasPrefix("--") {
                if programs.contains("hdiutil"), word == "-stdinpass" { return true }
                for program in programs {
                    if let value = shortFlagValue(word, next: next, program: program, after: subcommands),
                        isCredential(value)
                    {
                        return true
                    }
                }
                let command = words[..<index].last.flatMap { previousWord in
                    previousWord.split(separator: "/").last.map { String($0).lowercased() }
                }
                let usesPasswordLetterForAnotherPurpose =
                    knownNonPasswordShortFlag(word, command: command)
                    || command == "use" && next == "to"
                if programs.isEmpty, command != nil,
                    !usesPasswordLetterForAnotherPurpose,
                    let value = unknownProgramPasswordFlagValue(word, next: next), isCredential(value)
                {
                    return true
                }
                if programs.contains("htpasswd"), word.dropFirst().contains("b") { htpasswdBatch = true }
            }
            if programs.contains("openssl"), word.hasPrefix("pass:"), isCredential(String(word.dropFirst(5)))
            {
                return true
            }
            let program = String(word.split(separator: "/").last ?? "").lowercased()
            if passwordFlags[program] != nil || program == "htpasswd" || program == "openssl" {
                programs.insert(program)
            }
            if !programs.isEmpty, subcommandNames.contains(word) { subcommands.insert(word) }
        }
        // `htpasswd -b file user password` and `htpasswd -nb user password` end with the password.
        if htpasswdBatch, let last = words.last, !last.hasPrefix("-"), isCredential(last) { return true }
        return false
    }

    /// Whether a Cookie header's named session value looks generated.
    private static func hasGeneratedCookieCredential(_ text: String) -> Bool {
        let sensitiveNames: Set<String> = [
            "auth", "auth_token", "access_token", "id_token", "jwt", "refresh_token", "session",
            "session_id", "session_key", "sessionid", "sid",
        ]
        for pair in text.split(separator: ";") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            var name = pair[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            for prefix in ["__host-", "__secure-"] where name.hasPrefix(prefix) {
                name.removeFirst(prefix.count)
            }
            guard sensitiveNames.contains(name) else { continue }
            let token = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if SecretShapes.looksGenerated(token) { return true }
        }
        return false
    }

    /// The value a short flag passes to a program that takes a password through it, when this word is that flag.
    private static func shortFlagValue(
        _ word: String, next: String?, program: String, after subcommands: Set<String>
    ) -> String? {
        guard let rules = passwordFlags[program] else { return nil }
        if let subcommand = passwordSubcommand[program], !subcommands.contains(subcommand) { return nil }
        let valued = valueLetters[program] ?? []
        // A cluster such as `-sSu` is read letter by letter, up to a letter whose value runs on in the word.
        let letters = word.dropFirst()
        for index in letters.indices {
            let letter = letters[index]
            guard let rule = rules.first(where: { $0.flag == "-\(letter)" }) else {
                if valued.contains(letter) { return nil }
                continue
            }
            let attached = String(letters[letters.index(after: index)...])
            switch rule.form {
            case .attached:
                return attached.isEmpty ? nil : attached
            case .attachedOrNext:
                return attached.isEmpty ? next.flatMap { $0.hasPrefix("-") ? nil : $0 } : attached
            case .userAndPassword:
                return password(inUserPair: attached.isEmpty ? next : attached)
            }
        }
        return nil
    }

    /// A conventional password flag on a command outside the table is still sensitive.
    private static func unknownProgramPasswordFlagValue(_ word: String, next: String?) -> String? {
        guard word.hasPrefix("-p") || word.hasPrefix("-P") else { return nil }
        let attached = String(word.dropFirst(2))
        if !attached.isEmpty { return attached }
        return next.flatMap { $0.hasPrefix("-") ? nil : $0 }
    }

    /// Options these common commands use for something other than a password.
    private static let nonPasswordShortFlags: [String: Set<Character>] = [
        "cp": ["p"], "find": ["P"], "grep": ["P"], "install": ["p"], "scp": ["P"],
        "ssh": ["p"], "rsync": ["p"], "sudo": ["p"], "tar": ["p"],
    ]

    /// Whether a common command uses the password letter for an unrelated option.
    private static func knownNonPasswordShortFlag(_ word: String, command: String?) -> Bool {
        guard let command, let flag = word.dropFirst().first else { return false }
        return nonPasswordShortFlags[command]?.contains(flag) == true
    }

    /// The value a long flag passes when its name ends in a secret's name, or a user flag passes a password.
    private static func longFlagValue(_ word: String, next: String?, programs: Set<String>) -> String? {
        let body = word.dropFirst(2)
        let name = body.prefix { $0 != "=" }.lowercased()
        let joined = body.count > name.count ? String(body.dropFirst(name.count + 1)) : nil
        let value = joined ?? next.flatMap { $0.hasPrefix("-") ? nil : $0 }
        if programs.contains(where: { userFlags[$0]?.contains(name) ?? false }) {
            return password(inUserPair: value)
        }
        guard !name.hasPrefix("no-"), namesSecret(name) else { return nil }
        return value
    }

    /// The last parts of a flag or variable name that say it holds a secret.
    private static let secretNameEndings: Set<String> = [
        "password", "passwd", "pass", "passphrase", "pwd", "token", "secret", "apikey", "credentials",
    ]

    /// Words that, anywhere before a final `key`, make the name a secret key's, as `AWS_SECRET_ACCESS_KEY` and `--private-key` do.
    private static let secretKeyQualifiers: Set<String> = [
        "secret", "private", "access", "api", "auth", "cert", "account", "storage", "subscription",
    ]

    /// Whether a flag or header name, split at `-` and `_`, ends in a secret's name, as `--db-password` and `x-api-key` do.
    private static func namesSecret(_ name: String) -> Bool {
        let parts = name.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let last = parts.last else { return false }
        if secretNameEndings.contains(String(last)) { return true }
        return last == "key" && parts.dropLast().contains { secretKeyQualifiers.contains(String($0)) }
    }

    /// The password in `user:password` or `user%password`, or nothing when only a user is given.
    private static func password(inUserPair value: String?) -> String? {
        guard let value, let colon = value.firstIndex(where: { $0 == ":" || $0 == "%" }) else { return nil }
        let password = value[value.index(after: colon)...]
        return password.isEmpty ? nil : String(password)
    }

    /// Whether a word assigns a variable whose name ends in a secret's name, as `PGPASSWORD=…` and `MYSQL_PWD=…` do.
    private static func isNamedAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "=") else { return false }
        let name = word[..<equals]
        guard let first = name.first, first.isLetter || first == "_",
            name.allSatisfy({ ($0.isLetter && $0.isUppercase) || $0.isASCIIDigit || $0 == "_" })
        else { return false }
        let fused = ["PASSWORD", "PASSWD", "PASSPHRASE", "TOKEN", "SECRET", "APIKEY"]
        guard fused.contains(where: name.hasSuffix) || namesSecret(String(name)) else { return false }
        return isCredential(String(word[word.index(after: equals)...]))
    }

    // MARK: - Headers

    /// Header schemes that name how a credential is sent, which alone send none.
    private static let schemes: Set<String> = ["basic", "bearer", "digest", "token", "negotiate", "ntlm"]

    /// Whether a word holds `Authorization:` or a secret-named header, with a value in it or in the words after it.
    private static func carriesHeaderCredential(
        _ word: String, following: ArraySlice<String>, read: inout Int
    ) -> Bool {
        if isBareCookieHeaderToken(word), following.first.map(isCookieHeaderToken) == true {
            return false
        }
        guard let colon = word.firstIndex(of: ":") else { return false }
        let name = word[..<colon].trimmingSuffix(while: \.isWhitespace)
        let lowered = name.lowercased()
        // The header name is the last run of name characters before the colon, as `{Authorization` or `Proxy-Authorization` holds.
        let headerWord = lowered.hasPrefix("-h") ? lowered.dropFirst(2) : lowered[...]
        let header = String(headerWord.reversed().prefix { $0.isLetter || $0 == "-" || $0 == "_" }.reversed())
        if header == "cookie" || header == "set-cookie" {
            let rest = word[word.index(after: colon)...]
            let cookieWords = following.prefix { !isCookieHeaderToken($0) }
            let value = ([String(rest)] + cookieWords).joined(separator: " ")
            read += value.count
            return hasGeneratedCookieCredential(value)
        }
        guard header.hasSuffix("authorization") || header.contains("-") && namesSecret(header) else {
            return false
        }
        let after = header.dropLast("authorization".count)
        guard !header.hasSuffix("authorization") || after.isEmpty || after.hasSuffix("-") else {
            return false
        }
        let rest = word[word.index(after: colon)...]
        // The value is in this word, as a quoted `-H` argument holds it, or in the next two words.
        let text =
            rest.contains(where: { !$0.isWhitespace })
            ? String(rest) : following.prefix(2).joined(separator: " ")
        var values = text.split(whereSeparator: \.isWhitespace).prefix(2)
            .map { String($0).strippingEnds(of: headerPunctuation) }.filter { !$0.isEmpty }
        if let scheme = values.first, schemes.contains(scheme.lowercased()) { values.removeFirst() }
        return !values.isEmpty && values.allSatisfy(isCredential)
    }

    /// What surrounds a header value in code and is not part of it.
    private static let headerPunctuation = Set<Character>(",;`\"'")

    // MARK: - Values

    /// Whether a value is a credential rather than nothing, a variable, a substitution or a placeholder.
    private static func isCredential(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return !value.contains(where: { "${}<>".contains($0) })
    }
}

extension StringProtocol {
    /// The text without the characters at its end that satisfy `predicate`.
    fileprivate func trimmingSuffix(while predicate: (Character) -> Bool) -> SubSequence {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) { end = index(before: end) }
        return self[startIndex..<end]
    }
}

extension String {
    /// The string without any character in `set` at either end.
    fileprivate func strippingEnds(of set: Set<Character>) -> String {
        var slice = Substring(self)
        while let first = slice.first, set.contains(first) { slice = slice.dropFirst() }
        while let last = slice.last, set.contains(last) { slice = slice.dropLast() }
        return String(slice)
    }
}
