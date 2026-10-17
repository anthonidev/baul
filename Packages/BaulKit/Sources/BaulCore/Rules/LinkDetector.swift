import Foundation

/// Decide si un texto copiado es un link (y no un texto que contiene un link).
public enum LinkDetector {
    private static let webSchemes: Set<String> = ["http", "https"]

    /// Devuelve la URL si el texto completo, sin espacios alrededor, es una dirección web.
    public static func url(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              webSchemes.contains(scheme),
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    /// Si conviene pedir el título de la página. Nunca para direcciones locales o privadas:
    /// un GET a `localhost:3000/api/...` podría tener efectos en un servidor de desarrollo.
    public static func shouldFetchTitle(for url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".internal") || host.hasSuffix(".lan") || !host.contains(".") {
            return false
        }
        return !isPrivateAddress(host)
    }

    /// IPv4 privadas, loopback y link-local; cualquier IPv6 literal.
    private static func isPrivateAddress(_ host: String) -> Bool {
        if host.contains(":") || host.hasPrefix("[") { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (0, _): return true
        case (172, 16...31), (192, 168), (169, 254), (100, 64...127): return true
        default: return false
        }
    }
}
