import CodexBarCore
import Foundation

extension SettingsStore {
    public var ompSubprovider: String {
        get { self.configSnapshot.providerConfig(for: .omp)?.ompSubprovider ?? "all" }
        set {
            self.updateProviderConfig(provider: .omp) { $0.ompSubprovider = newValue }
        }
    }

    public var ompCustomSubprovider: String {
        get { self.configSnapshot.providerConfig(for: .omp)?.ompCustomSubprovider ?? "" }
        set {
            self.updateProviderConfig(provider: .omp) { $0.ompCustomSubprovider = newValue }
        }
    }

    public func ompSettingsSnapshot() -> OMPProviderSettings {
        OMPProviderSettings(
            subprovider: self.ompSubprovider,
            customSubprovider: self.ompCustomSubprovider)
    }
}
