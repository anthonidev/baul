import BaulCore
import Foundation
import GRDB
import Testing
@testable import BaulPersistence

/// Las migraciones corren sobre datos reales de la app instalada: se prueban con una base
/// creada con el esquema anterior y con datos, no solo sobre una base vacía.
@Suite struct MigrationTests {
    /// Base con el esquema v1 y datos como los que tiene la app instalada.
    func makeV1Database() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO clip (id, kind, text, contentHash, byteSize, createdAt, lastCopiedAt, inHistory)
                VALUES (1, 'text', '20601000939', 'text:a', 11, '2026-10-16 20:00:00.000', '2026-10-16 20:00:00.000', 1),
                       (2, 'text', 'otra cosa', 'text:b', 9, '2026-10-16 20:01:00.000', '2026-10-16 20:01:00.000', 1);
                INSERT INTO board (id, name, color, sortOrder) VALUES (1, 'rxh', 'red', 0);
                INSERT INTO boardEntry (boardId, clipId, customTitle, customText, sortOrder, addedAt)
                VALUES (1, 1, 'RUC empresa', NULL, 0, '2026-10-16 20:02:00.000');
                """)
        }
        return queue
    }

    @Test func `v2 keeps all data and moves the title to the clip`() async throws {
        let queue = try makeV1Database()
        let store = SQLiteLibraryStore(database: try AppDatabase(queue))

        let history = try await store.items(matching: LibraryQuery())
        #expect(history.count == 2)
        let saved = try #require(history.first { $0.clip.id.rawValue == 1 })
        #expect(saved.title == "RUC empresa")
        #expect(saved.clip.boardIDs == [BoardID(rawValue: 1)])

        let boards = try await store.boards()
        #expect(boards.map(\.name) == ["rxh"])
        let inBoard = try await store.items(matching: LibraryQuery(scope: .board(BoardID(rawValue: 1))))
        #expect(inBoard.first?.title == "RUC empresa")
    }

    @Test func `v2 rebuilds the search index with existing clips`() async throws {
        let queue = try makeV1Database()
        let store = SQLiteLibraryStore(database: try AppDatabase(queue))

        #expect(try await store.items(matching: LibraryQuery(text: "otra")).count == 1)
        #expect(try await store.items(matching: LibraryQuery(text: "empresa")).count == 1)

        // Los disparadores siguen manteniendo el índice al día después de la migración.
        _ = try await store.record(NewClip(
            content: .text("nuevo después de migrar"), fingerprint: "text:c", source: nil, byteSize: 5, copiedAt: .now
        ))
        #expect(try await store.items(matching: LibraryQuery(text: "migrar")).count == 1)
    }
}
