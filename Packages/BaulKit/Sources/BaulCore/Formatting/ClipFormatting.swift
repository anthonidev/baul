import Foundation

/// Textos que se muestran en las tarjetas. Reciben `Locale` y `Calendar`
/// explícitos para que las pruebas no dependan del sistema.
public enum ClipFormatting {
    /// "hace 5 min", "ayer", "hace 3 días", "ahora".
    public static func relativeTime(
        _ date: Date,
        now: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        if now.timeIntervalSince(date) < 60 {
            return "ahora"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "1.234 caracteres" / "1 carácter".
    public static func characterCount(_ count: Int, locale: Locale = .current) -> String {
        let number = count.formatted(.number.locale(locale))
        return count == 1 ? "\(number) carácter" : "\(number) caracteres"
    }

    /// "1920 × 1080".
    public static func imageSize(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }

    /// "1,2 MB".
    public static func byteCount(_ bytes: Int64, locale: Locale = .current) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// Las primeras líneas no vacías de un texto, para la vista previa.
    public static func preview(of text: String, maxLines: Int = 8, maxCharacters: Int = 600) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingTrailingWhitespace() }
            .prefix(maxLines)
        let joined = lines.joined(separator: "\n")
        return joined.count > maxCharacters ? String(joined.prefix(maxCharacters)) + "…" : joined
    }
}

private extension Substring {
    func trimmingTrailingWhitespace() -> Substring {
        guard let last = lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return self[...last]
    }
}
