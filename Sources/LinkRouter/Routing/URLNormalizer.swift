import Foundation

enum URLNormalizer {
    static func normalize(_ url: URL) -> Result<NormalizedURL, RouteError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScheme = components.scheme?.lowercased(),
              ["http", "https"].contains(rawScheme) else {
            return .failure(url.scheme == nil ? .malformedURL : .unsupportedScheme)
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else { return .failure(.malformedURL) }
        return .success(NormalizedURL(original: url, scheme: rawScheme, host: host, path: components.percentEncodedPath))
    }
}
