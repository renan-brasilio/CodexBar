import Foundation

extension ProviderConfig {
    public var ompSubprovider: String? {
        get { self.extensionValue(forKey: "ompSubprovider") }
        set { self.setExtensionValue(newValue, forKey: "ompSubprovider") }
    }

    public var ompCustomSubprovider: String? {
        get { self.extensionValue(forKey: "ompCustomSubprovider") }
        set { self.setExtensionValue(newValue, forKey: "ompCustomSubprovider") }
    }
}
