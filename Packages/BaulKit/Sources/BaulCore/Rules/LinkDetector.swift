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
}
