import Foundation

public struct BoardID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

/// Paleta cerrada de colores para los tableros. Se guarda por nombre,
/// así cambiar el tono exacto más adelante no requiere migrar datos.
public enum BoardColor: String, CaseIterable, Hashable, Sendable, Codable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray
}

/// Un tablero: una colección con nombre de elementos que nunca se borran solos.
public struct Board: Identifiable, Hashable, Sendable {
    public let id: BoardID
    public var name: String
    public var color: BoardColor
    public var sortOrder: Int

    public init(id: BoardID, name: String, color: BoardColor, sortOrder: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }
}

public struct BoardEntryID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

/// Un elemento guardado en un tablero. Apunta a un `Clip` y puede sobrescribir
/// su texto sin tocar el original del historial. El título vive en el `Clip`,
/// así se ve igual en el historial y en todos los tableros.
public struct BoardEntry: Identifiable, Hashable, Sendable {
    public let id: BoardEntryID
    public let boardID: BoardID
    public let clip: Clip
    public var customText: String?
    public var sortOrder: Int
    public let addedAt: Date

    public init(
        id: BoardEntryID,
        boardID: BoardID,
        clip: Clip,
        customText: String?,
        sortOrder: Int,
        addedAt: Date
    ) {
        self.id = id
        self.boardID = boardID
        self.clip = clip
        self.customText = customText
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }

    /// Contenido efectivo: el texto editado si existe, si no el original.
    public var content: ClipContent {
        guard let customText else { return clip.content }
        switch clip.content {
        case .text: return .text(customText)
        case .link(_, let title):
            if let url = URL(string: customText), url.scheme != nil { return .link(url, title: title) }
            return .text(customText)
        case .image: return clip.content
        }
    }
}
