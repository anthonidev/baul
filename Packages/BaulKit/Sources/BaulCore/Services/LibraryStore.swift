import Foundation

/// Persistencia de historial, tableros y apps excluidas.
/// La implementación real usa SQLite (BaulPersistence); las pruebas pueden usar una falsa.
public protocol LibraryStore: Sendable {
    // MARK: Captura

    /// Guarda un elemento nuevo o, si ya existía (misma huella), lo sube al principio.
    /// Los formatos ricos guardados se reemplazan por los de `clip`.
    func record(_ clip: NewClip) async throws -> RecordOutcome
    /// Sube un elemento al principio del historial (p. ej. al pegarlo desde Baúl).
    func touch(_ clipID: ClipID, at date: Date) async throws
    /// Formatos ricos guardados para pegar con formato.
    func richRepresentations(for clipID: ClipID) async throws -> [String: Data]
    func setLinkTitle(_ title: String, for clipID: ClipID) async throws

    // MARK: Consultas

    func items(matching query: LibraryQuery) async throws -> [ClipItem]
    /// Emite la lista cada vez que cambia algo relevante en la base de datos.
    func observeItems(matching query: LibraryQuery) -> AsyncThrowingStream<[ClipItem], any Error>
    func boards() async throws -> [Board]
    func observeBoards() -> AsyncThrowingStream<[Board], any Error>

    // MARK: Historial

    func deleteClip(_ id: ClipID) async throws -> [String]
    /// Borra todo el historial salvo lo que está guardado en tableros.
    /// Devuelve los hashes de imágenes que quedaron sin uso.
    func clearHistory() async throws -> [String]
    /// Borra lo copiado antes de `cutoff` que no esté en ningún tablero.
    /// Devuelve los hashes de imágenes que quedaron sin uso.
    func purgeHistory(copiedBefore cutoff: Date) async throws -> [String]

    // MARK: Tableros

    func createBoard(name: String, color: BoardColor) async throws -> Board
    func updateBoard(_ id: BoardID, name: String, color: BoardColor) async throws
    func deleteBoard(_ id: BoardID) async throws -> [String]
    /// Reordena según la lista recibida.
    func reorderBoards(_ ids: [BoardID]) async throws
    /// Guarda un elemento en un tablero. Si ya estaba, no lo duplica.
    @discardableResult
    func save(_ clipID: ClipID, to boardID: BoardID, at date: Date) async throws -> BoardEntryID
    func updateEntry(_ id: BoardEntryID, title: String?, text: String?) async throws
    func removeEntry(_ id: BoardEntryID) async throws -> [String]

    // MARK: Apps excluidas

    func excludedApps() async throws -> [SourceApp]
    func observeExcludedApps() -> AsyncThrowingStream<[SourceApp], any Error>
    func addExcludedApp(_ app: SourceApp) async throws
    func removeExcludedApp(bundleID: String) async throws

    // MARK: Estadísticas

    func historyCount() async throws -> Int
}

/// Un elemento listo para guardar, ya clasificado.
public struct NewClip: Sendable {
    public var content: ClipContent
    /// Huella para no duplicar. Ver `ContentFingerprint`.
    public var fingerprint: String
    /// Formatos ricos (RTF, HTML) por tipo UTI.
    public var richRepresentations: [String: Data]
    public var source: SourceApp?
    public var byteSize: Int
    public var copiedAt: Date

    public init(
        content: ClipContent,
        fingerprint: String,
        richRepresentations: [String: Data] = [:],
        source: SourceApp?,
        byteSize: Int,
        copiedAt: Date
    ) {
        self.content = content
        self.fingerprint = fingerprint
        self.richRepresentations = richRepresentations
        self.source = source
        self.byteSize = byteSize
        self.copiedAt = copiedAt
    }
}

public enum RecordOutcome: Hashable, Sendable {
    case inserted(Clip)
    /// Ya existía: se actualizó la fecha y subió al principio.
    case bumped(Clip)

    public var clip: Clip {
        switch self {
        case .inserted(let clip), .bumped(let clip): clip
        }
    }
}

/// Almacén de imágenes en disco, nombradas por su hash.
public protocol ImageStore: Sendable {
    /// Guarda el PNG y su miniatura. No hace nada si ya existe.
    func store(png: Data, hash: String) async throws
    func imageURL(for hash: String) -> URL
    func thumbnailURL(for hash: String) -> URL
    func remove(hashes: [String]) async
    /// Bytes ocupados por imágenes y miniaturas.
    func totalSize() async -> Int64
}
