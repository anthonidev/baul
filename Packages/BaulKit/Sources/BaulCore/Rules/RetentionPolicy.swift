import Foundation

/// Cuánto tiempo vive un elemento del historial que no está en ningún tablero.
public struct RetentionPolicy: Hashable, Sendable {
    public var days: Int

    public static let standard = RetentionPolicy(days: 5)

    public init(days: Int) {
        precondition(days > 0, "La retención debe ser de al menos un día")
        self.days = days
    }

    /// Los elementos copiados por última vez antes de esta fecha se pueden borrar.
    public func cutoff(now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }
}
