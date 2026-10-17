import Foundation

public struct OMPProviderSettings: Sendable, Equatable {
    public let subprovider: String
    public let customSubprovider: String?
    public let hiddenUsageItemIDs: [String]

    public init(
        subprovider: String = "all",
        customSubprovider: String? = nil,
        hiddenUsageItemIDs: [String] = [])
    {
        self.subprovider = subprovider
        self.customSubprovider = customSubprovider
        self.hiddenUsageItemIDs = hiddenUsageItemIDs
    }

    public var effectiveSubprovider: String {
        if self.subprovider == "custom",
           let custom = self.customSubprovider?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty
        {
            return custom
        }
        return self.subprovider
    }
}

public enum OMPProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.omp
    public typealias Section = OMPProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias OMPProviderSettings = CodexBarCore.OMPProviderSettings
    public var omp: OMPProviderSettings? {
        self[OMPProviderSettingsKey.self]
    }

    public static func make(omp: OMPProviderSettings?) -> Self {
        self.make(omp, for: OMPProviderSettingsKey.self)
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func omp(_ section: OMPProviderSettings) -> Self {
        Self(section, for: OMPProviderSettingsKey.self)
    }
}
