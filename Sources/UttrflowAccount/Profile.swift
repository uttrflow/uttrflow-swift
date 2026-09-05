public import struct Foundation.Date

/// Everything the backend knows about the person using this Mac, as of a moment it names.
///
/// The rule this type exists to make structural:
///
///   **the server is the source of truth; this is a copy of it, and the copy is never
///   edited.**
///
/// Nothing in the app writes a field here and expects it to mean anything. A change is
/// made by asking the server to make it and re-reading the answer, which is the only way
/// a Mac, a phone and a website can be looking at the same account and agree about it.
/// That is also why the type is a single value rather than a set of stored properties
/// scattered across the app: a snapshot can be replaced wholesale, and a scattering
/// cannot.
///
/// It is cached on disk so the second launch needs no network — but the cache is a
/// convenience, not an authority, and everything in it except ``entitlement`` is
/// unsigned. Anything that decides what somebody may *do* reads the entitlement, which
/// carries the backend's signature; anything that merely draws a screen may read the
/// rest.
public struct Profile: Sendable, Equatable, Codable {
    /// Who this is. The same shape the entitlement carries, so the two can be compared.
    public let account: Account

    /// What they are paying for, and what that allows.
    public let subscription: Subscription

    /// Every machine signed into this account, most recently seen first.
    public let devices: [Device]

    /// The signed statement. The only part of this document that decides anything.
    public let entitlement: Entitlement

    /// When the **server** produced this document.
    ///
    /// Not when the app received it. A device clock can be wrong by years — a Mac
    /// restored from a backup routinely is — and a copy stamped from a wrong clock either
    /// looks fresh for ever or is discarded on every launch. The server's clock is the one
    /// both ends can agree about, so it is the one written down.
    public let fetchedAt: Date

    /// The cache validator the server issued with this document, if it is still known.
    ///
    /// Sent back as `If-None-Match` on the next read, which is what makes re-reading the
    /// truth on every launch cost a header rather than a signature. Optional because a
    /// document can outlive knowledge of its validator — an older cache, a response that
    /// carried no `ETag` — and a missing one costs a full response, never correctness.
    public let validator: String?

    public init(
        account: Account,
        subscription: Subscription,
        devices: [Device],
        entitlement: Entitlement,
        fetchedAt: Date,
        validator: String? = nil
    ) {
        self.account = account
        self.subscription = subscription
        self.devices = devices
        self.entitlement = entitlement
        self.fetchedAt = fetchedAt
        self.validator = validator
    }

    /// The same document, remembering the validator the response carried.
    ///
    /// A copy rather than a mutable property because everything else about a profile
    /// arrived from the server together and must stay together; the validator is the one
    /// part that comes from a header rather than the body.
    public func remembering(validator: String?) -> Profile {
        Profile(
            account: account, subscription: subscription, devices: devices,
            entitlement: entitlement, fetchedAt: fetchedAt, validator: validator)
    }

    /// Whether this document describes the account the entitlement was signed for.
    ///
    /// The account and nothing else. The plan beside it is **not** covered, so a free
    /// entitlement inside a document claiming Pro passes this and verifies perfectly.
    /// What stops that mattering is that the unsigned half decides nothing — see
    /// `Docs/entitlements.md`, and `UnsignedHalfTests`, which is where that is checked
    /// rather than asserted.
    public var isInternallyConsistent: Bool {
        entitlement.account.identifier == account.identifier
    }

    /// The device this Mac is, as the server knows it. `nil` before the first read, and
    /// for a client that never registered one.
    public var currentDevice: Device? {
        devices.first(where: \.isCurrent)
    }

    /// The date on the wire that the app reads as a date, and every other as a string.
    ///
    /// Deliberately narrow: only ``fetchedAt`` and the timestamps below are ISO-8601
    /// strings, while ``Entitlement/expiresAt`` is a number, because it is signed and its
    /// shape is dictated by what Swift's synthesised `Codable` emits. One document with
    /// two date encodings cannot be decoded by one `dateDecodingStrategy`, so this type
    /// converts the strings itself and leaves the number alone.
    private enum CodingKeys: String, CodingKey {
        case account, subscription, devices, entitlement, fetchedAt, validator
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decode(Account.self, forKey: .account)
        subscription = try container.decode(Subscription.self, forKey: .subscription)
        // A device the app cannot read is dropped rather than fatal: a newer server that
        // has learned a platform this build has never heard of must not cost somebody
        // their account page.
        devices = try container.decode([Device].self, forKey: .devices)
        entitlement = try container.decode(Entitlement.self, forKey: .entitlement)
        fetchedAt = try Timestamp.decode(from: container, forKey: .fetchedAt)
        validator = try container.decodeIfPresent(String.self, forKey: .validator)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(account, forKey: .account)
        try container.encode(subscription, forKey: .subscription)
        try container.encode(devices, forKey: .devices)
        try container.encode(entitlement, forKey: .entitlement)
        try container.encode(Timestamp.string(from: fetchedAt), forKey: .fetchedAt)
        try container.encodeIfPresent(validator, forKey: .validator)
    }
}

extension Profile {
    /// What the subscription allows. Numbers rather than sentences, so the app can compare
    /// them; `nil` means unlimited, which is a different statement from zero.
    public struct Limits: Sendable, Equatable, Codable {
        public let monthlyMinutes: Int?
        public let customDictionaryEntries: Int?

        public init(monthlyMinutes: Int?, customDictionaryEntries: Int?) {
            self.monthlyMinutes = monthlyMinutes
            self.customDictionaryEntries = customDictionaryEntries
        }
    }

    /// Where a subscription stands.
    ///
    /// Kept apart from ``Plan`` because the two answer different questions: the plan is
    /// what somebody bought, the status is whether the payment for it worked, and the app
    /// needs both to say anything useful about a card that has expired.
    public enum Status: String, Sendable, Equatable, CaseIterable, Codable {
        case active
        case pastDue = "past_due"
        case cancelled
        case expired
    }

    public struct Subscription: Sendable, Equatable, Codable {
        /// The plan being billed for.
        public let plan: Plan

        public let status: Status

        /// When the paid period ends. `nil` on free, which does not end.
        public let currentPeriodEnd: Date?

        /// The plan to *behave* as though somebody is on, which is not always the one
        /// they are billed for: a cancelled subscription is still Pro until the period it
        /// paid for runs out. Computed by the server so that three clients cannot each
        /// have a slightly different idea of when Pro stops.
        ///
        /// Displayed, never enforced. What may actually be done is decided by the signed
        /// ``Entitlement``.
        public let effectivePlan: Plan

        public let limits: Limits

        public init(
            plan: Plan, status: Status, currentPeriodEnd: Date?, effectivePlan: Plan,
            limits: Limits
        ) {
            self.plan = plan
            self.status = status
            self.currentPeriodEnd = currentPeriodEnd
            self.effectivePlan = effectivePlan
            self.limits = limits
        }

        private enum CodingKeys: String, CodingKey {
            case plan, status, currentPeriodEnd, effectivePlan, limits
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plan = try container.decode(Plan.self, forKey: .plan)
            status = try container.decode(Status.self, forKey: .status)
            currentPeriodEnd = try Timestamp.decodeIfPresent(from: container, forKey: .currentPeriodEnd)
            effectivePlan = try container.decode(Plan.self, forKey: .effectivePlan)
            limits = try container.decode(Limits.self, forKey: .limits)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(plan, forKey: .plan)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(
                currentPeriodEnd.map(Timestamp.string(from:)), forKey: .currentPeriodEnd)
            try container.encode(effectivePlan, forKey: .effectivePlan)
            try container.encode(limits, forKey: .limits)
        }
    }

    /// One installation of the app, on one machine.
    public struct Device: Sendable, Equatable, Codable {
        public let identifier: String
        public let platform: Platform
        /// What the person will recognise it by. Theirs to change, so never parsed.
        public let name: String
        public let appVersion: String?
        public let lastSeenAt: Date
        /// Marked by the server, so the app is not left matching a name it chose itself
        /// against a list of three similar ones.
        public let isCurrent: Bool

        public init(
            identifier: String, platform: Platform, name: String, appVersion: String?,
            lastSeenAt: Date, isCurrent: Bool
        ) {
            self.identifier = identifier
            self.platform = platform
            self.name = name
            self.appVersion = appVersion
            self.lastSeenAt = lastSeenAt
            self.isCurrent = isCurrent
        }

        private enum CodingKeys: String, CodingKey {
            case identifier, platform, name, appVersion, lastSeenAt, isCurrent
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            platform = try container.decode(Platform.self, forKey: .platform)
            name = try container.decode(String.self, forKey: .name)
            appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
            lastSeenAt = try Timestamp.decode(from: container, forKey: .lastSeenAt)
            isCurrent = try container.decode(Bool.self, forKey: .isCurrent)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(platform, forKey: .platform)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(appVersion, forKey: .appVersion)
            try container.encode(Timestamp.string(from: lastSeenAt), forKey: .lastSeenAt)
            try container.encode(isCurrent, forKey: .isCurrent)
        }
    }

    /// The kind of machine a device is.
    ///
    /// ``unrecognised`` is the important case. This app will one day be older than the
    /// service it talks to, and a phone signing in from a platform added after this build
    /// shipped must cost the user an unfamiliar icon in a list — not a decoding failure
    /// that takes the whole account page with it.
    public enum Platform: String, Sendable, Equatable, CaseIterable, Codable {
        case macOS = "macos"
        case iOS = "ios"
        case iPadOS = "ipados"
        case web
        case windows
        case android
        case linux
        case unrecognised

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Platform(rawValue: raw) ?? .unrecognised
        }
    }
}
