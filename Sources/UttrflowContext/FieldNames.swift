import UttrflowCore

enum FieldNamesReadStatus: Sendable, Equatable {
    case complete
    case refused
}

/// The names a focused field publishes for itself, which the secure check reads before any of its text.
public struct FieldNames: Sendable, Equatable {
    public let role: String?
    public let subrole: String?
    public let identifier: String?
    public let placeholder: String?
    public let description: String?
    public let title: String?
    private let readStatus: FieldNamesReadStatus

    public init(
        role: String?, subrole: String?, identifier: String?, placeholder: String?, description: String?,
        title: String? = nil
    ) {
        self.init(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description, title: title, readStatus: .complete)
    }

    init(
        role: String?, subrole: String?, identifier: String?, placeholder: String?, description: String?,
        title: String? = nil, readStatus: FieldNamesReadStatus
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.placeholder = placeholder
        self.description = description
        self.title = title
        self.readStatus = readStatus
    }

    /// What the field is called: its title, else its placeholder, else its description; nothing for a secure field.
    public var label: String? {
        guard !isSecureOrUnknown else { return nil }
        return [title, placeholder, description].lazy.compactMap { $0.flatMap(AppContext.fieldLabel) }.first
    }

    var isSecureOrUnknown: Bool {
        readStatus == .refused || isDeclaredSecure
    }

    /// Whether the field declares itself secure, decided before its value is fetched.
    public var isDeclaredSecure: Bool {
        SecureField.isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
    }

    /// The one secure-check order every focused-field read uses: the names first, the value only when they clear it.
    public func isSecure(value: () -> String?) -> Bool {
        isSecureOrUnknown || (value().map(SecureField.looksMasked) ?? false)
    }
}
