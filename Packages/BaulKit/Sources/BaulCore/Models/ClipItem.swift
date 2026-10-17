import Foundation

/// Lo que se muestra como tarjeta en el panel: un elemento del historial
/// o un elemento guardado en un tablero.
public enum ClipItem: Identifiable, Hashable, Sendable {
    case clip(Clip)
    case entry(BoardEntry)

    public enum ID: Hashable, Sendable {
        case clip(ClipID)
        case entry(BoardEntryID)
    }

    public var id: ID {
        switch self {
        case .clip(let clip): .clip(clip.id)
        case .entry(let entry): .entry(entry.id)
        }
    }

    public var clip: Clip {
        switch self {
        case .clip(let clip): clip
        case .entry(let entry): entry.clip
        }
    }

    public var entry: BoardEntry? {
        if case .entry(let entry) = self { return entry }
        return nil
    }

    /// Contenido efectivo (respeta el texto editado en un tablero).
    public var content: ClipContent {
        entry?.content ?? clip.content
    }

    public var title: String? { clip.title }

    /// Fecha que se muestra en la tarjeta.
    public var date: Date {
        entry?.addedAt ?? clip.lastCopiedAt
    }
}

/// Qué mostrar en el panel.
public struct LibraryQuery: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        /// La pestaña "Portapapeles".
        case history
        case board(BoardID)
        /// Buscar en el historial y en todos los tableros.
        case everything
    }

    public var scope: Scope
    /// Texto a buscar; vacío = sin filtro.
    public var text: String
    /// Tipos a mostrar; vacío = todos.
    public var kinds: Set<ClipKind>
    public var limit: Int

    public init(scope: Scope = .history, text: String = "", kinds: Set<ClipKind> = [], limit: Int = 500) {
        self.scope = scope
        self.text = text
        self.kinds = kinds
        self.limit = limit
    }

    public var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
