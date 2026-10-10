import Foundation

struct OperationsConfiguration {
    let apiBaseURL: URL?

    var isConfigured: Bool { apiBaseURL != nil }

    static func load(from bundle: Bundle = .main) -> OperationsConfiguration {
        guard let value = bundle.object(forInfoDictionaryKey: "DLC_API_BASE_URL") as? String,
              let url = URL(string: value),
              url.scheme == "https",
              url.host != nil else {
            return OperationsConfiguration(apiBaseURL: nil)
        }
        return OperationsConfiguration(apiBaseURL: url)
    }
}
