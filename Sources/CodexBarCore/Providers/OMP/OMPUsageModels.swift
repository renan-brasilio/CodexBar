import Foundation

public struct OMPUsageResponse: Codable, Sendable {
    public let generatedAt: Double?
    public let reports: [OMPAccountReport]
    public let capacity: [String: [OMPCapacityWindow]]?
    public let accountsWithoutUsage: [OMPAccountWithoutUsage]?

    public init(
        generatedAt: Double? = nil,
        reports: [OMPAccountReport] = [],
        capacity: [String: [OMPCapacityWindow]]? = nil,
        accountsWithoutUsage: [OMPAccountWithoutUsage]? = nil)
    {
        self.generatedAt = generatedAt
        self.reports = reports
        self.capacity = capacity
        self.accountsWithoutUsage = accountsWithoutUsage
    }
}

public struct OMPAccountWithoutUsage: Codable, Sendable {
    public let provider: String
    public let type: String?

    public init(provider: String, type: String? = nil) {
        self.provider = provider
        self.type = type
    }
}

public struct OMPAccountReport: Codable, Sendable {
    public let provider: String
    public let fetchedAt: Double?
    public let limits: [OMPLimit]?
    public let resetCredits: OMPResetCredits?
    public let metadata: [String: String]?

    public init(
        provider: String,
        fetchedAt: Double? = nil,
        limits: [OMPLimit]? = nil,
        resetCredits: OMPResetCredits? = nil,
        metadata: [String: String]? = nil)
    {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.limits = limits
        self.resetCredits = resetCredits
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case fetchedAt
        case limits
        case resetCredits
        case metadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.fetchedAt = try container.decodeIfPresent(Double.self, forKey: .fetchedAt)
        self.limits = try container.decodeIfPresent([OMPLimit].self, forKey: .limits)
        self.resetCredits = try container.decodeIfPresent(OMPResetCredits.self, forKey: .resetCredits)

        if let metaContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .metadata) {
            var dict: [String: String] = [:]
            for key in metaContainer.allKeys {
                if let str = try? metaContainer.decode(String.self, forKey: key) {
                    dict[key.stringValue] = str
                } else if let num = try? metaContainer.decode(Double.self, forKey: key) {
                    dict[key.stringValue] = "\(num)"
                } else if let b = try? metaContainer.decode(Bool.self, forKey: key) {
                    dict[key.stringValue] = "\(b)"
                }
            }
            self.metadata = dict.isEmpty ? nil : dict
        } else {
            self.metadata = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.provider, forKey: .provider)
        try container.encodeIfPresent(self.fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(self.limits, forKey: .limits)
        try container.encodeIfPresent(self.resetCredits, forKey: .resetCredits)
        try container.encodeIfPresent(self.metadata, forKey: .metadata)
    }
}

public struct OMPResetCredits: Codable, Sendable {
    public let availableCount: Int?

    public init(availableCount: Int? = nil) {
        self.availableCount = availableCount
    }
}

public struct OMPLimit: Codable, Sendable {
    public let id: String
    public let label: String?
    public let scope: OMPLimitScope?
    public let window: OMPWindow?
    public let amount: OMPAmount?
    public let status: String?

    public init(
        id: String,
        label: String? = nil,
        scope: OMPLimitScope? = nil,
        window: OMPWindow? = nil,
        amount: OMPAmount? = nil,
        status: String? = nil)
    {
        self.id = id
        self.label = label
        self.scope = scope
        self.window = window
        self.amount = amount
        self.status = status
    }
}

public struct OMPLimitScope: Codable, Sendable {
    public let provider: String?
    public let projectId: String?
    public let windowId: String?
    public let shared: Bool?
    public let sharedGroup: String?

    public init(
        provider: String? = nil,
        projectId: String? = nil,
        windowId: String? = nil,
        shared: Bool? = nil,
        sharedGroup: String? = nil)
    {
        self.provider = provider
        self.projectId = projectId
        self.windowId = windowId
        self.shared = shared
        self.sharedGroup = sharedGroup
    }
}

public struct OMPWindow: Codable, Sendable {
    public let id: String?
    public let label: String?
    public let durationMs: Double?
    public let resetsAt: Double?

    public init(id: String? = nil, label: String? = nil, durationMs: Double? = nil, resetsAt: Double? = nil) {
        self.id = id
        self.label = label
        self.durationMs = durationMs
        self.resetsAt = resetsAt
    }
}

public struct OMPAmount: Codable, Sendable {
    public let unit: String?
    public let remainingFraction: Double?
    public let usedFraction: Double?
    public let remaining: Double?
    public let used: Double?
    public let limit: Double?

    public init(
        unit: String? = nil,
        remainingFraction: Double? = nil,
        usedFraction: Double? = nil,
        remaining: Double? = nil,
        used: Double? = nil,
        limit: Double? = nil)
    {
        self.unit = unit
        self.remainingFraction = remainingFraction
        self.usedFraction = usedFraction
        self.remaining = remaining
        self.used = used
        self.limit = limit
    }
}

public struct OMPCapacityWindow: Codable, Sendable {
    public let window: String
    public let durationMs: Double?
    public let accounts: Double
    public let usedAccounts: Double
    public let remainingAccounts: Double
    public let meter: String?

    public init(
        window: String,
        durationMs: Double? = nil,
        accounts: Double,
        usedAccounts: Double,
        remainingAccounts: Double,
        meter: String? = nil)
    {
        self.window = window
        self.durationMs = durationMs
        self.accounts = accounts
        self.usedAccounts = usedAccounts
        self.remainingAccounts = remainingAccounts
        self.meter = meter
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
