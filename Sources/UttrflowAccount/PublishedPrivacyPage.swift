// The address of the Privacy page the site publishes, kept where web addresses may live.
public import Foundation

/// Where the published Privacy page is; the site publishes no Terms page, so none is named.
public enum PublishedPrivacyPage {
    /// The page's address.
    public static let address: URL = {
        guard let address = URL(string: "https://uttrflow.com/privacy") else {
            preconditionFailure("the Privacy address is a constant and parses")
        }
        return address
    }()
}
