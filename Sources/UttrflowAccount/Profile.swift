// The profile document: the server's copy of the account, replaced whole and never edited on this Mac.
public import struct Foundation.Date

/// The backend's answer about this person, replaced whole and never edited here. See `Docs/entitlements.md`.
public struct Profile: Sendable, Equatable, Codable {
    /// Who this is, in the same shape the entitlement carries so the two can be compared.
    public let account: Account

    /// What they are paying for, and what that allows.
    public let subscription: Subscription

    /// Every machine signed into this account, most recently seen first.
    public let devices: [Device]

    /// The signed statement, and the only part of this document that decides anything.
    public let entitlement: Entitlement

    /// When the server produced this document, by the server's clock; a device clock can be years out.
    public let fetchedAt: Date

    /// The `ETag` the server issued, sent back as `If-None-Match`; `nil` costs a full response, nothing more.
    public let validator: String?

    /// Assembles a document as the server produced it.
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

    /// The same document with the validator the response's header carried.
    public func remembering(validator: String?) -> Profile {
        Profile(
            account: account, subscription: subscription, devices: devices,
            entitlement: entitlement, fetchedAt: fetchedAt, validator: validator)
    }

    /// Whether the entitlement names this document's account; not the plan. See `Docs/entitlements.md`.
    public var isInternallyConsistent: Bool {
        entitlement.account.identifier == account.identifier
    }

    /// The device this Mac is, as the server knows it; `nil` before the first read or with none registered.
    public var currentDevice: Device? {
        devices.first(where: \.isCurrent)
    }

    /// The wire keys; `fetchedAt` is an ISO-8601 string, while the entitlement's signed expiry is a number.
    private enum CodingKeys: String, CodingKey {
        case account, subscription, devices, entitlement, fetchedAt, validator
    }

    /// Decodes the document, converting the timestamp string itself.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decode(Account.self, forKey: .account)
        subscription = try container.decode(Subscription.self, forKey: .subscription)
        // An unknown platform decodes as ``Platform/unrecognised``, so a newer server costs nobody a page.
        devices = try container.decode([Device].self, forKey: .devices)
        entitlement = try container.decode(Entitlement.self, forKey: .entitlement)
        fetchedAt = try Timestamp.decode(from: container, forKey: .fetchedAt)
        validator = try container.decodeIfPresent(String.self, forKey: .validator)
    }

    /// Encodes the document with the timestamp as a string.
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
    /// What the subscription allows, as numbers; `nil` means unlimited, which differs from zero.
    public struct Limits: Sendable, Equatable, Codable {
        /// Minutes of dictation a month, or `nil` for unlimited.
        public let monthlyMinutes: Int?
        /// Custom dictionary entries, or `nil` for unlimited.
        public let customDictionaryEntries: Int?

        /// Both limits, `nil` for unlimited.
        public init(monthlyMinutes: Int?, customDictionaryEntries: Int?) {
            self.monthlyMinutes = monthlyMinutes
            self.customDictionaryEntries = customDictionaryEntries
        }
    }

    /// Whether the payment for the plan worked; kept apart from ``Plan``, which is what was bought.
    public enum Status: String, Sendable, Equatable, CaseIterable, Codable {
        case active
        case pastDue = "past_due"
        case cancelled
        case expired
    }

    /// What is billed for, and what is in force.
    public struct Subscription: Sendable, Equatable, Codable {
        /// The plan being billed for.
        public let plan: Plan

        /// Whether the payment worked.
        public let status: Status

        /// When the paid period ends. `nil` on free, which does not end.
        public let currentPeriodEnd: Date?

        /// The plan to behave as though somebody is on, computed by the server; displayed, never enforced.
        public let effectivePlan: Plan

        /// What the plan allows.
        public let limits: Limits

        /// Assembles a subscription as the server produced it.
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

        /// The wire keys.
        private enum CodingKeys: String, CodingKey {
            case plan, status, currentPeriodEnd, effectivePlan, limits
        }

        /// Decodes, converting `currentPeriodEnd` from a string.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plan = try container.decode(Plan.self, forKey: .plan)
            status = try container.decode(Status.self, forKey: .status)
            currentPeriodEnd = try Timestamp.decodeIfPresent(from: container, forKey: .currentPeriodEnd)
            effectivePlan = try container.decode(Plan.self, forKey: .effectivePlan)
            limits = try container.decode(Limits.self, forKey: .limits)
        }

        /// Encodes with `currentPeriodEnd` as a string.
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
        /// The server's identifier for the installation.
        public let identifier: String
        /// Which kind of machine.
        public let platform: Platform
        /// What the person will recognise it by. Theirs to change, so never parsed.
        public let name: String
        /// The build last seen from it, if reported.
        public let appVersion: String?
        /// When it last spoke to the server.
        public let lastSeenAt: Date
        /// Marked by the server, so the app never matches a name it chose itself against a list of three.
        public let isCurrent: Bool

        /// Assembles a device as the server produced it.
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

        /// The wire keys.
        private enum CodingKeys: String, CodingKey {
            case identifier, platform, name, appVersion, lastSeenAt, isCurrent
        }

        /// Decodes, converting `lastSeenAt` from a string.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            platform = try container.decode(Platform.self, forKey: .platform)
            name = try container.decode(String.self, forKey: .name)
            appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
            lastSeenAt = try Timestamp.decode(from: container, forKey: .lastSeenAt)
            isCurrent = try container.decode(Bool.self, forKey: .isCurrent)
        }

        /// Encodes with `lastSeenAt` as a string.
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

    /// The kind of machine a device is; an unknown wire value decodes as ``unrecognised``, not as a failure.
    public enum Platform: String, Sendable, Equatable, CaseIterable, Codable {
        case macOS = "macos"
        case iOS = "ios"
        case iPadOS = "ipados"
        case web
        case windows
        case android
        case linux
        case unrecognised

        /// Decodes any platform this build has not heard of as ``unrecognised``.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Platform(rawValue: raw) ?? .unrecognised
        }
    }
}
