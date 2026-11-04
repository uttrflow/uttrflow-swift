// Banking and health applications, which ship with clipboard capture and suggestions switched off.

/// One family of bundle identifiers: an identifier is in it when it is the prefix or continues it after a dot.
package struct ApplicationFamily: Sendable, Equatable {
    /// The lowercased identifier the family starts from.
    package let prefix: String

    /// What a list calls the family.
    package let name: String

    package init(prefix: String, name: String) {
        self.prefix = ApplicationKey.of(prefix)
        self.name = name
    }

    /// Whether this identifier is the family's own or a build of it, such as a beta or a helper.
    package func contains(_ bundleIdentifier: String) -> Bool {
        Self.member(ApplicationKey.of(bundleIdentifier), of: prefix)
    }

    /// Whether a lowercased identifier equals a lowercased prefix or continues it after a dot.
    package static func member(_ identifier: String, of prefix: String) -> Bool {
        identifier == prefix || identifier.hasPrefix(prefix + ".")
    }
}

/// The shipped list of banking and health applications, matched by family so a renamed build stays covered.
package enum SensitiveApplications {
    package static let families: [ApplicationFamily] = [
        ApplicationFamily(prefix: "com.chase", name: "Chase"),
        ApplicationFamily(prefix: "com.bankofamerica", name: "Bank of America"),
        ApplicationFamily(prefix: "com.wellsfargo", name: "Wells Fargo"),
        ApplicationFamily(prefix: "com.paypal", name: "PayPal"),
        ApplicationFamily(prefix: "com.revolut", name: "Revolut"),
        ApplicationFamily(prefix: "com.monzo", name: "Monzo"),
        ApplicationFamily(prefix: "com.apple.health", name: "Health"),
        ApplicationFamily(prefix: "com.myfitnesspal", name: "MyFitnessPal"),
        ApplicationFamily(prefix: "com.fitbit", name: "Fitbit"),
        ApplicationFamily(prefix: "com.withings", name: "Withings"),
    ]

    /// The family this identifier belongs to, if any.
    package static func family(of bundleIdentifier: String) -> ApplicationFamily? {
        families.first { $0.contains(bundleIdentifier) }
    }
}
