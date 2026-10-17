import BaulCore
import Foundation
import GRDB

/// Implementación de `LibraryStore` sobre SQLite (GRDB).
public final class SQLiteLibraryStore: LibraryStore {
    private let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Captura

    public func record(_ clip: NewClip) async throws -> RecordOutcome {
        try await writer.write { db in
            let outcome: RecordOutcome
            if var existing = try ClipRecord.filter(ClipRecord.Columns.contentHash == clip.fingerprint).fetchOne(db) {
                existing.lastCopiedAt = clip.copiedAt
                existing.inHistory = true
                if let source = clip.source {
                    existing.sourceBundleID = source.bundleID
                    existing.sourceAppName = source.name
                }
                try existing.update(db)
                outcome = .bumped(try existing.toDomain())
            } else {
                var record = ClipRecord(clip)
                try record.insert(db)
                outcome = .inserted(try record.toDomain())
            }
            try Self.replaceRepresentations(db, clipID: outcome.clip.id, with: clip.richRepresentations)
            return outcome
        }
    }

    public func touch(_ clipID: ClipID, at date: Date) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET lastCopiedAt = ?, inHistory = 1 WHERE id = ?",
                arguments: [date, clipID.rawValue]
            )
        }
    }

    public func richRepresentations(for clipID: ClipID) async throws -> [String: Data] {
        try await writer.read { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT type, data FROM clipRepresentation WHERE clipId = ?", arguments: [clipID.rawValue]
            )
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["type"] as String, $0["data"] as Data) })
        }
    }

    private static func replaceRepresentations(_ db: Database, clipID: ClipID, with representations: [String: Data]) throws {
        try db.execute(sql: "DELETE FROM clipRepresentation WHERE clipId = ?", arguments: [clipID.rawValue])
        for (type, data) in representations {
            try db.execute(
                sql: "INSERT INTO clipRepresentation (clipId, type, data) VALUES (?, ?, ?)",
                arguments: [clipID.rawValue, type, data]
            )
        }
    }

    public func setTitle(_ title: String?, for clipID: ClipID) async throws {
        try await writer.write { db in
            _ = try ClipRecord
                .filter(ClipRecord.Columns.id == clipID.rawValue)
                .updateAll(db, ClipRecord.Columns.title.set(to: title.nilIfBlank?.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    public func setLinkTitle(_ title: String, for clipID: ClipID) async throws {
        try await writer.write { db in
            _ = try ClipRecord
                .filter(ClipRecord.Columns.id == clipID.rawValue)
                .updateAll(db, ClipRecord.Columns.linkTitle.set(to: title))
        }
    }

    // MARK: - Consultas

    public func items(matching query: LibraryQuery) async throws -> [ClipItem] {
        try await writer.read { db in try Self.fetchItems(db, query) }
    }

    public func observeItems(matching query: LibraryQuery) -> AsyncThrowingStream<[ClipItem], any Error> {
        observe { db in try Self.fetchItems(db, query) }
    }

    public func boards() async throws -> [Board] {
        try await writer.read(Self.fetchBoards)
    }

    public func observeBoards() -> AsyncThrowingStream<[Board], any Error> {
        observe(Self.fetchBoards)
    }

    static func fetchItems(_ db: Database, _ query: LibraryQuery) throws -> [ClipItem] {
        let search = SearchTerms(query.normalizedText)
        let kinds: SQL = query.kinds.isEmpty
            ? "1"
            : "clip.kind IN \(query.kinds.map(\.rawValue))"

        switch query.scope {
        case .history:
            return try fetchHistory(db, search: search, kinds: kinds, limit: query.limit).map(ClipItem.clip)

        case .board(let boardID):
            let condition: SQL = "boardEntry.boardId = \(boardID.rawValue)"
            return try fetchEntries(db, where: condition, search: search, kinds: kinds, limit: query.limit)
                .map(ClipItem.entry)

        case .everything:
            let entries = try fetchEntries(db, where: "1", search: search, kinds: kinds, limit: query.limit)
            let savedClipIDs = Set(entries.map(\.clip.id))
            let clips = try fetchHistory(db, search: search, kinds: kinds, limit: query.limit)
                .filter { !savedClipIDs.contains($0.id) }
            let merged = entries.map(ClipItem.entry) + clips.map(ClipItem.clip)
            return Array(merged.sorted { $0.date > $1.date }.prefix(query.limit))
        }
    }

    private static func fetchHistory(_ db: Database, search: SearchTerms, kinds: SQL, limit: Int) throws -> [Clip] {
        let sql: SQL = """
            SELECT clip.* FROM clip
            WHERE clip.inHistory AND \(kinds) AND \(search.clipCondition())
            ORDER BY clip.lastCopiedAt DESC
            LIMIT \(limit)
            """
        let records = try ClipRecord.fetchAll(db, SQLRequest(literal: sql))
        let memberships = try boardMemberships(db, clipIDs: records.compactMap(\.id))
        return try records.map { try $0.toDomain(boardIDs: memberships[$0.id ?? -1] ?? []) }
    }

    private static func fetchEntries(
        _ db: Database, where condition: SQL, search: SearchTerms, kinds: SQL, limit: Int
    ) throws -> [BoardEntry] {
        let rows = try BoardEntryRecord
            .including(required: BoardEntryRecord.clip)
            .filter(literal: "\(condition) AND \(kinds) AND \(search.entryCondition())")
            .order(BoardEntryRecord.Columns.sortOrder.desc)
            .limit(limit)
            .asRequest(of: BoardEntryWithClip.self)
            .fetchAll(db)
        let memberships = try boardMemberships(db, clipIDs: rows.map(\.boardEntry.clipId))
        return try rows.map { try $0.toDomain(boardIDs: memberships[$0.boardEntry.clipId] ?? []) }
    }

    /// En qué tableros está cada elemento, en el orden de las pestañas.
    private static func boardMemberships(_ db: Database, clipIDs: [Int64]) throws -> [Int64: [BoardID]] {
        guard !clipIDs.isEmpty else { return [:] }
        let rows = try Row.fetchAll(db, SQLRequest(literal: """
            SELECT boardEntry.clipId, boardEntry.boardId FROM boardEntry
            JOIN board ON board.id = boardEntry.boardId
            WHERE boardEntry.clipId IN \(Set(clipIDs))
            ORDER BY board.sortOrder
            """))
        return rows.reduce(into: [:]) { result, row in
            result[row["clipId"], default: []].append(BoardID(rawValue: row["boardId"]))
        }
    }

    private static func fetchBoards(_ db: Database) throws -> [Board] {
        try BoardRecord.order(BoardRecord.Columns.sortOrder).fetchAll(db).map { try $0.toDomain() }
    }

    // MARK: - Historial

    public func deleteClip(_ id: ClipID) async throws -> [String] {
        try await writer.write { db in
            guard let clip = try ClipRecord.fetchOne(db, key: id.rawValue) else { return [] }
            let isSaved = try BoardEntryRecord.filter(BoardEntryRecord.Columns.clipId == id.rawValue).isEmpty(db) == false
            if isSaved {
                // Sigue vivo en su tablero; solo desaparece del historial.
                _ = try ClipRecord.filter(key: id.rawValue).updateAll(db, ClipRecord.Columns.inHistory.set(to: false))
                return []
            }
            try clip.delete(db)
            return [clip.imageHash].compactMap(\.self)
        }
    }

    public func clearHistory() async throws -> [String] {
        try await writer.write { db in try Self.removeFromHistory(db, copiedBefore: nil) }
    }

    public func purgeHistory(copiedBefore cutoff: Date) async throws -> [String] {
        try await writer.write { db in try Self.removeFromHistory(db, copiedBefore: cutoff) }
    }

    /// Lo guardado en tableros solo se oculta del historial; lo demás se borra.
    private static func removeFromHistory(_ db: Database, copiedBefore cutoff: Date?) throws -> [String] {
        let age: SQL = cutoff.map { "lastCopiedAt < \($0)" } ?? "1"
        let saved: SQL = "id IN (SELECT clipId FROM boardEntry)"

        try db.execute(literal: "UPDATE clip SET inHistory = 0 WHERE \(age) AND \(saved)")
        let hashes = try String.fetchAll(db, SQLRequest(literal: """
            SELECT imageHash FROM clip WHERE \(age) AND NOT \(saved) AND imageHash IS NOT NULL
            """))
        try db.execute(literal: "DELETE FROM clip WHERE \(age) AND NOT \(saved)")
        return hashes
    }

    /// Borra los elementos que ya no están ni en el historial ni en ningún tablero.
    private static func deleteOrphans(_ db: Database, among clipIDs: [Int64]) throws -> [String] {
        guard !clipIDs.isEmpty else { return [] }
        let orphan: SQL = "id IN \(clipIDs) AND NOT inHistory AND id NOT IN (SELECT clipId FROM boardEntry)"
        let hashes = try String.fetchAll(db, SQLRequest(literal: "SELECT imageHash FROM clip WHERE \(orphan) AND imageHash IS NOT NULL"))
        try db.execute(literal: "DELETE FROM clip WHERE \(orphan)")
        return hashes
    }

    // MARK: - Tableros

    public func createBoard(name: String, color: BoardColor) async throws -> Board {
        try await writer.write { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM board") ?? -1
            var record = BoardRecord(id: nil, name: name, color: color.rawValue, sortOrder: maxOrder + 1)
            try record.insert(db)
            return try record.toDomain()
        }
    }

    public func updateBoard(_ id: BoardID, name: String, color: BoardColor) async throws {
        try await writer.write { db in
            guard var record = try BoardRecord.fetchOne(db, key: id.rawValue) else { throw PersistenceError.notFound }
            record.name = name
            record.color = color.rawValue
            try record.update(db)
        }
    }

    public func deleteBoard(_ id: BoardID) async throws -> [String] {
        try await writer.write { db in
            let clipIDs = try Int64.fetchAll(db, sql: "SELECT clipId FROM boardEntry WHERE boardId = ?", arguments: [id.rawValue])
            _ = try BoardRecord.deleteOne(db, key: id.rawValue)
            return try Self.deleteOrphans(db, among: clipIDs)
        }
    }

    public func reorderBoards(_ ids: [BoardID]) async throws {
        try await writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE board SET sortOrder = ? WHERE id = ?", arguments: [index, id.rawValue])
            }
        }
    }

    @discardableResult
    public func save(_ clipID: ClipID, to boardID: BoardID, at date: Date) async throws -> BoardEntryID {
        try await writer.write { db in
            let sameEntry = BoardEntryRecord
                .filter(BoardEntryRecord.Columns.boardId == boardID.rawValue)
                .filter(BoardEntryRecord.Columns.clipId == clipID.rawValue)
            if let existing = try sameEntry.fetchOne(db), let id = existing.id {
                return BoardEntryID(rawValue: id)
            }
            let maxOrder = try Int.fetchOne(
                db, sql: "SELECT MAX(sortOrder) FROM boardEntry WHERE boardId = ?", arguments: [boardID.rawValue]
            ) ?? -1
            var record = BoardEntryRecord(
                id: nil, boardId: boardID.rawValue, clipId: clipID.rawValue,
                customTitle: nil, customText: nil, sortOrder: maxOrder + 1, addedAt: date
            )
            try record.insert(db)
            guard let id = record.id else { throw PersistenceError.missingID }
            return BoardEntryID(rawValue: id)
        }
    }

    public func updateEntry(_ id: BoardEntryID, text: String?) async throws {
        try await writer.write { db in
            guard var record = try BoardEntryRecord.fetchOne(db, key: id.rawValue) else { throw PersistenceError.notFound }
            record.customText = text.nilIfBlank
            try record.update(db)
        }
    }

    public func removeEntry(_ id: BoardEntryID) async throws -> [String] {
        try await writer.write { db in
            guard let record = try BoardEntryRecord.fetchOne(db, key: id.rawValue) else { return [] }
            try record.delete(db)
            return try Self.deleteOrphans(db, among: [record.clipId])
        }
    }

    // MARK: - Apps excluidas

    public func excludedApps() async throws -> [SourceApp] {
        try await writer.read(Self.fetchExcludedApps)
    }

    public func observeExcludedApps() -> AsyncThrowingStream<[SourceApp], any Error> {
        observe(Self.fetchExcludedApps)
    }

    public func addExcludedApp(_ app: SourceApp) async throws {
        try await writer.write { db in
            try ExcludedAppRecord(bundleID: app.bundleID, name: app.name).upsert(db)
        }
    }

    public func removeExcludedApp(bundleID: String) async throws {
        try await writer.write { db in
            _ = try ExcludedAppRecord.deleteOne(db, key: bundleID)
        }
    }

    private static func fetchExcludedApps(_ db: Database) throws -> [SourceApp] {
        try ExcludedAppRecord.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
            .map { SourceApp(bundleID: $0.bundleID, name: $0.name) }
    }

    // MARK: - Estadísticas

    public func historyCount() async throws -> Int {
        try await writer.read { db in try ClipRecord.filter(ClipRecord.Columns.inHistory).fetchCount(db) }
    }

    // MARK: - Observación

    /// Convierte una consulta en un flujo que emite cada vez que cambian sus tablas.
    private func observe<Value: Sendable & Equatable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, any Error> {
        let values = ValueObservation.tracking(fetch).removeDuplicates().values(in: writer)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in values { continuation.yield(value) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension Optional<String> {
    var nilIfBlank: String? {
        guard let self, !self.allSatisfy(\.isWhitespace) else { return nil }
        return self
    }
}
