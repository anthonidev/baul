import Foundation

/// Identificador de un elemento del historial.
public struct ClipID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

/// Referencia a una imagen guardada en el almacén de archivos.
public struct ImageReference: Hashable, Sendable {
    /// SHA-256 del PNG; también es el nombre del archivo.
    public let hash: String
    public let width: Int
    public let height: Int

    public init(hash: String, width: Int, height: Int) {
        self.hash = hash
        self.width = width
        self.height = height
    }
}

/// Lo que contiene un elemento. Cada caso trae solo los datos que le corresponden,
/// así no existen combinaciones inválidas (p. ej. una imagen con texto).
public enum ClipContent: Hashable, Sendable {
    case text(String)
    case link(URL, title: String?)
    case image(ImageReference)

    public var kind: ClipKind {
        switch self {
        case .text: .text
        case .link: .link
        case .image: .image
        }
    }

    /// Texto plano asociado (para buscar y para pegar sin formato).
    public var plainText: String? {
        switch self {
        case .text(let text): text
        case .link(let url, _): url.absoluteString
        case .image: nil
        }
    }
}

public enum ClipKind: String, CaseIterable, Hashable, Sendable, Codable {
    case text
    case link
    case image
}

/// La app desde donde se copió algo.
public struct SourceApp: Hashable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Un elemento del historial del portapapeles.
public struct Clip: Identifiable, Hashable, Sendable {
    public let id: ClipID
    public var content: ClipContent
    /// Huella del contenido para no duplicar. Ver `ContentFingerprint`.
    public let contentHash: String
    public let source: SourceApp?
    /// Tamaño del contenido original en bytes.
    public let byteSize: Int
    public let createdAt: Date
    /// Última vez que se copió. Define el orden y la retención.
    public var lastCopiedAt: Date

    public init(
        id: ClipID,
        content: ClipContent,
        contentHash: String,
        source: SourceApp?,
        byteSize: Int,
        createdAt: Date,
        lastCopiedAt: Date
    ) {
        self.id = id
        self.content = content
        self.contentHash = contentHash
        self.source = source
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
    }

    public var kind: ClipKind { content.kind }

    /// Cantidad de caracteres para la línea de detalle; `nil` en imágenes.
    public var characterCount: Int? { content.plainText?.count }
}
