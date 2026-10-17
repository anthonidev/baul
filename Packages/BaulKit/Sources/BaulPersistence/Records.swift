import BaulCore
import Foundation
import GRDB

// Tipos de fila de la base de datos. Son privados del módulo: hacia afuera
// solo salen los modelos de dominio de BaulCore.

struct ClipRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "clip"
    static let entries = hasMany(BoardEntryRecord.self)

    var id: Int64?
    var kind: ClipKind
    var text: String?
    var linkTitle: String?
    var imageHash: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var contentHash: String
    var sourceBundleID: String?
    var sourceAppName: String?
    var byteSize: Int
    var createdAt: Date
    var lastCopiedAt: Date
    var inHistory: Bool
    var title: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let kind = Column(CodingKeys.kind)
        static let linkTitle = Column(CodingKeys.linkTitle)
        static let imageHash = Column(CodingKeys.imageHash)
        static let contentHash = Column(CodingKeys.contentHash)
        static let lastCopiedAt = Column(CodingKeys.lastCopiedAt)
        static let inHistory = Column(CodingKeys.inHistory)
        static let title = Column(CodingKeys.title)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension ClipKind: DatabaseValueConvertible {}

extension ClipRecord {
    init(_ clip: NewClip) {
        self.id = nil
        self.kind = clip.content.kind
        self.contentHash = clip.fingerprint
        self.sourceBundleID = clip.source?.bundleID
        self.sourceAppName = clip.source?.name
        self.byteSize = clip.byteSize
        self.createdAt = clip.copiedAt
        self.lastCopiedAt = clip.copiedAt
        self.inHistory = true
        switch clip.content {
        case .text(let text):
            self.text = text
        case .link(let url, let title):
            self.text = url.absoluteString
            self.linkTitle = title
        case .image(let image):
            self.imageHash = image.hash
            self.imageWidth = image.width
            self.imageHeight = image.height
        }
    }

    func toDomain(boardIDs: [BoardID] = []) throws -> Clip {
        guard let id else { throw PersistenceError.missingID }
        return Clip(
            id: ClipID(rawValue: id),
            content: try content(),
            contentHash: contentHash,
            source: sourceBundleID.map { SourceApp(bundleID: $0, name: sourceAppName ?? $0) },
            title: title,
            boardIDs: boardIDs,
            byteSize: byteSize,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt
        )
    }

    private func content() throws -> ClipContent {
        switch kind {
        case .text:
            return .text(text ?? "")
        case .link:
            guard let text, let url = URL(string: text) else { return .text(text ?? "") }
            return .link(url, title: linkTitle)
        case .image:
            guard let imageHash, let imageWidth, let imageHeight else { throw PersistenceError.corruptRow("clip \(id ?? -1)") }
            return .image(ImageReference(hash: imageHash, width: imageWidth, height: imageHeight))
        }
    }
}

struct BoardRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "board"

    var id: Int64?
    var name: String
    var color: String
    var sortOrder: Int

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func toDomain() throws -> Board {
        guard let id else { throw PersistenceError.missingID }
        return Board(id: BoardID(rawValue: id), name: name, color: BoardColor(rawValue: color) ?? .gray, sortOrder: sortOrder)
    }
}

struct BoardEntryRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "boardEntry"
    static let clip = belongsTo(ClipRecord.self)

    var id: Int64?
    var boardId: Int64
    var clipId: Int64
    /// Sin uso desde la migración v2 (el título vive en `clip.title`).
    var customTitle: String?
    var customText: String?
    var sortOrder: Int
    var addedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let boardId = Column(CodingKeys.boardId)
        static let clipId = Column(CodingKeys.clipId)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Una entrada con su elemento, tal como sale de un JOIN.
struct BoardEntryWithClip: Decodable, FetchableRecord {
    var boardEntry: BoardEntryRecord
    var clip: ClipRecord

    func toDomain(boardIDs: [BoardID]) throws -> BoardEntry {
        guard let id = boardEntry.id else { throw PersistenceError.missingID }
        return BoardEntry(
            id: BoardEntryID(rawValue: id),
            boardID: BoardID(rawValue: boardEntry.boardId),
            clip: try clip.toDomain(boardIDs: boardIDs),
            customText: boardEntry.customText,
            sortOrder: boardEntry.sortOrder,
            addedAt: boardEntry.addedAt
        )
    }
}

struct ExcludedAppRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "excludedApp"

    var bundleID: String
    var name: String
}

public enum PersistenceError: Error, Equatable {
    case missingID
    case corruptRow(String)
    case notFound
}
