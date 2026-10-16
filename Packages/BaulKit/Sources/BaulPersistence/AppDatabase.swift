import BaulCore
import Foundation
import GRDB

/// La base de datos SQLite de Baúl: conexión + esquema (migraciones).
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Base de datos en disco. Usa WAL (DatabasePool) para leer mientras se escribe.
    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration)
        return try AppDatabase(pool)
    }

    /// Base de datos en memoria, para pruebas.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        #if DEBUG
        config.publicStatementArguments = true
        #endif
        return config
    }

    /// Bytes que ocupa la base de datos en disco (archivo principal + WAL).
    public func fileSize() -> Int64 {
        guard let path = (writer as? DatabasePool)?.path else { return 0 }
        return ["", "-wal", "-shm"].reduce(into: 0) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path + suffix)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
    }
}

// MARK: - Esquema

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // En desarrollo, si cambia una migración se recrea la base desde cero.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("text", .text)
                t.column("linkTitle", .text)
                t.column("imageHash", .text)
                t.column("imageWidth", .integer)
                t.column("imageHeight", .integer)
                t.column("contentHash", .text).notNull().unique()
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("byteSize", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastCopiedAt", .datetime).notNull().indexed()
                // false = se quitó del historial pero sigue vivo porque está en un tablero.
                t.column("inHistory", .boolean).notNull().defaults(to: true)
            }

            // Formatos ricos (RTF, HTML) de un texto, para pegar con formato.
            try db.create(table: "clipRepresentation") { t in
                t.belongsTo("clip", onDelete: .cascade).notNull()
                t.column("type", .text).notNull()
                t.column("data", .blob).notNull()
                t.primaryKey(["clipId", "type"])
            }

            try db.create(table: "board") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("sortOrder", .integer).notNull()
            }

            try db.create(table: "boardEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("board", onDelete: .cascade).notNull()
                // RESTRICT: la base de datos impide borrar un elemento que está en un tablero.
                t.belongsTo("clip", onDelete: .restrict).notNull()
                t.column("customTitle", .text)
                t.column("customText", .text)
                t.column("sortOrder", .integer).notNull()
                t.column("addedAt", .datetime).notNull()
                t.uniqueKey(["boardId", "clipId"])
            }

            try db.create(table: "excludedApp") { t in
                t.primaryKey("bundleID", .text)
                t.column("name", .text).notNull()
            }
            for app in CapturePolicy.defaultExcludedApps {
                try db.execute(
                    sql: "INSERT INTO excludedApp (bundleID, name) VALUES (?, ?)",
                    arguments: [app.bundleID, app.name]
                )
            }

            // Búsqueda: trigramas = coincidencia por fragmentos ("stag" encuentra "Staging"),
            // sin distinguir mayúsculas ni tildes.
            let trigram = FTS5TokenizerDescriptor(components: ["trigram", "remove_diacritics", "1"])
            try db.create(virtualTable: "clipFTS", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.tokenizer = trigram
                t.column("text")
                t.column("linkTitle")
                t.column("sourceAppName")
            }
            try db.create(virtualTable: "boardEntryFTS", using: FTS5()) { t in
                t.synchronize(withTable: "boardEntry")
                t.tokenizer = trigram
                t.column("customTitle")
                t.column("customText")
            }
        }

        return migrator
    }
}
