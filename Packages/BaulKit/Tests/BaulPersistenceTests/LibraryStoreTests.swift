import BaulCore
import Foundation
import Testing
@testable import BaulPersistence

/// Pruebas del almacén contra SQLite en memoria (mismo esquema y FTS5 que en disco).
@Suite struct LibraryStoreTests {
    let store: SQLiteLibraryStore
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let terminal = SourceApp(bundleID: "com.apple.Terminal", name: "Terminal")
    let chrome = SourceApp(bundleID: "com.google.Chrome", name: "Google Chrome")

    init() throws {
        store = SQLiteLibraryStore(database: try AppDatabase.inMemory())
    }

    @discardableResult
    func copy(_ text: String, from source: SourceApp? = nil, minutesAgo: Double = 0) async throws -> Clip {
        let content = LinkDetector.url(in: text).map { ClipContent.link($0, title: nil) } ?? .text(text)
        return try await store.record(NewClip(
            content: content,
            fingerprint: ContentFingerprint.of(.text(text)),
            source: source ?? terminal,
            byteSize: text.utf8.count,
            copiedAt: base.addingTimeInterval(-minutesAgo * 60)
        )).clip
    }

    @discardableResult
    func copyImage(hash: String, minutesAgo: Double = 0) async throws -> Clip {
        try await store.record(NewClip(
            content: .image(ImageReference(hash: hash, width: 10, height: 10)),
            fingerprint: "image:\(hash)",
            source: chrome,
            byteSize: 100,
            copiedAt: base.addingTimeInterval(-minutesAgo * 60)
        )).clip
    }

    func historyTexts(_ text: String = "", kinds: Set<ClipKind> = []) async throws -> [String] {
        try await store.items(matching: LibraryQuery(scope: .history, text: text, kinds: kinds))
            .compactMap { $0.content.plainText ?? ($0.clip.kind == .image ? "<image>" : nil) }
    }

    // MARK: Historial

    @Test func `newest first`() async throws {
        try await copy("viejo", minutesAgo: 10)
        try await copy("nuevo", minutesAgo: 1)
        #expect(try await historyTexts() == ["nuevo", "viejo"])
    }

    @Test func `copying again does not duplicate and moves to the front`() async throws {
        try await copy("a", minutesAgo: 10)
        try await copy("b", minutesAgo: 5)
        let outcome = try await store.record(NewClip(
            content: .text("a"), fingerprint: ContentFingerprint.of(.text("a")),
            source: chrome, byteSize: 1, copiedAt: base
        ))
        guard case .bumped(let clip) = outcome else {
            Issue.record("expected bump, got \(outcome)")
            return
        }
        #expect(clip.source == chrome)
        #expect(try await historyTexts() == ["a", "b"])
        #expect(try await store.historyCount() == 2)
    }

    @Test func `links keep their type and title`() async throws {
        let clip = try await copy("https://example.com")
        try await store.setLinkTitle("Example Domain", for: clip.id)
        let item = try #require(try await store.items(matching: LibraryQuery()).first)
        #expect(item.content == .link(try #require(URL(string: "https://example.com")), title: "Example Domain"))
    }

    @Test func `purge removes old clips and reports orphan images`() async throws {
        try await copy("reciente", minutesAgo: 60)
        try await copy("viejo", minutesAgo: 6 * 24 * 60)
        try await copyImage(hash: "abc", minutesAgo: 7 * 24 * 60)

        let cutoff = RetentionPolicy.standard.cutoff(now: base)
        let orphans = try await store.purgeHistory(copiedBefore: cutoff)

        #expect(orphans == ["abc"])
        #expect(try await historyTexts() == ["reciente"])
    }

    @Test func `purge never deletes what is saved in a board`() async throws {
        let saved = try await copy("guardado", minutesAgo: 10 * 24 * 60)
        let board = try await store.createBoard(name: "env", color: .orange)
        try await store.save(saved.id, to: board.id, at: base)

        let orphans = try await store.purgeHistory(copiedBefore: RetentionPolicy.standard.cutoff(now: base))

        #expect(orphans.isEmpty)
        #expect(try await historyTexts().isEmpty)
        let inBoard = try await store.items(matching: LibraryQuery(scope: .board(board.id)))
        #expect(inBoard.map(\.content) == [.text("guardado")])
    }

    @Test func `clear history keeps saved items`() async throws {
        let saved = try await copy("guardado")
        try await copy("efímero")
        let board = try await store.createBoard(name: "code", color: .blue)
        try await store.save(saved.id, to: board.id, at: base)

        _ = try await store.clearHistory()

        #expect(try await store.historyCount() == 0)
        #expect(try await store.items(matching: LibraryQuery(scope: .board(board.id))).count == 1)
    }

    @Test func `deleting a saved clip only hides it from history`() async throws {
        let saved = try await copy("guardado")
        let board = try await store.createBoard(name: "code", color: .blue)
        try await store.save(saved.id, to: board.id, at: base)

        let orphans = try await store.deleteClip(saved.id)

        #expect(orphans.isEmpty)
        #expect(try await historyTexts().isEmpty)
        #expect(try await store.items(matching: LibraryQuery(scope: .board(board.id))).count == 1)
    }

    @Test func `copying a hidden saved clip brings it back to history`() async throws {
        let saved = try await copy("guardado", minutesAgo: 5)
        let board = try await store.createBoard(name: "code", color: .blue)
        try await store.save(saved.id, to: board.id, at: base)
        _ = try await store.deleteClip(saved.id)

        try await copy("guardado")

        #expect(try await historyTexts() == ["guardado"])
    }

    @Test func `rich formats are stored and replaced on the next copy`() async throws {
        let rtf = Data("{\\rtf1 hola}".utf8)
        let first = try await store.record(NewClip(
            content: .text("hola"), fingerprint: "text:hola", richRepresentations: ["public.rtf": rtf],
            source: nil, byteSize: 4, copiedAt: base
        ))
        #expect(try await store.richRepresentations(for: first.clip.id) == ["public.rtf": rtf])

        _ = try await store.record(NewClip(
            content: .text("hola"), fingerprint: "text:hola", source: nil, byteSize: 4, copiedAt: base
        ))
        #expect(try await store.richRepresentations(for: first.clip.id).isEmpty)
    }

    @Test func `touch moves a clip to the front`() async throws {
        let old = try await copy("viejo", minutesAgo: 10)
        try await copy("nuevo", minutesAgo: 1)
        try await store.touch(old.id, at: base)
        #expect(try await historyTexts() == ["viejo", "nuevo"])
    }

    // MARK: Tableros

    @Test func `boards keep their order and can be reordered`() async throws {
        let env = try await store.createBoard(name: "env", color: .orange)
        let rxh = try await store.createBoard(name: "rxh", color: .red)
        let code = try await store.createBoard(name: "code", color: .blue)
        #expect(try await store.boards().map(\.name) == ["env", "rxh", "code"])

        try await store.reorderBoards([code.id, env.id, rxh.id])
        #expect(try await store.boards().map(\.name) == ["code", "env", "rxh"])

        try await store.updateBoard(code.id, name: "código", color: .purple)
        let renamed = try #require(try await store.boards().first)
        #expect(renamed.name == "código")
        #expect(renamed.color == .purple)
    }

    @Test func `saving twice to the same board does not duplicate`() async throws {
        let clip = try await copy("token")
        let board = try await store.createBoard(name: "env", color: .orange)
        let first = try await store.save(clip.id, to: board.id, at: base)
        let second = try await store.save(clip.id, to: board.id, at: base)
        #expect(first == second)
    }

    @Test func `newest saved entry appears first in a board`() async throws {
        let board = try await store.createBoard(name: "env", color: .orange)
        try await store.save(try await copy("primero").id, to: board.id, at: base)
        try await store.save(try await copy("segundo").id, to: board.id, at: base)
        let items = try await store.items(matching: LibraryQuery(scope: .board(board.id)))
        #expect(items.map(\.content) == [.text("segundo"), .text("primero")])
    }

    @Test func `editing an entry keeps the original clip intact`() async throws {
        let clip = try await copy("sk-original")
        let board = try await store.createBoard(name: "env", color: .orange)
        let entryID = try await store.save(clip.id, to: board.id, at: base)

        try await store.updateEntry(entryID, title: "Token de staging", text: "sk-editado")

        let entry = try #require(try await store.items(matching: LibraryQuery(scope: .board(board.id))).first)
        #expect(entry.title == "Token de staging")
        #expect(entry.content == .text("sk-editado"))
        #expect(try await historyTexts() == ["sk-original"])
    }

    @Test func `blank title and text are stored as nil`() async throws {
        let board = try await store.createBoard(name: "env", color: .orange)
        let entryID = try await store.save(try await copy("x").id, to: board.id, at: base)
        try await store.updateEntry(entryID, title: "  ", text: "")
        let entry = try #require(try await store.items(matching: LibraryQuery(scope: .board(board.id))).first)
        #expect(entry.title == nil)
        #expect(entry.content == .text("x"))
    }

    @Test func `deleting a board removes clips that only lived there`() async throws {
        let onlyInBoard = try await copyImage(hash: "img1")
        let board = try await store.createBoard(name: "env", color: .orange)
        try await store.save(onlyInBoard.id, to: board.id, at: base)
        _ = try await store.clearHistory()

        let orphans = try await store.deleteBoard(board.id)

        #expect(orphans == ["img1"])
        #expect(try await store.boards().isEmpty)
    }

    @Test func `removing an entry keeps the clip if it is still in history`() async throws {
        let clip = try await copy("sigue")
        let board = try await store.createBoard(name: "env", color: .orange)
        let entryID = try await store.save(clip.id, to: board.id, at: base)

        let orphans = try await store.removeEntry(entryID)

        #expect(orphans.isEmpty)
        #expect(try await historyTexts() == ["sigue"])
    }

    // MARK: Búsqueda

    @Test func `search matches fragments ignoring case and accents`() async throws {
        try await copy("API_KEY de Staging")
        try await copy("canción favorita")
        try await copy("otra cosa")

        #expect(try await historyTexts("stag") == ["API_KEY de Staging"])
        #expect(try await historyTexts("CANCION") == ["canción favorita"])
    }

    @Test func `every word must match`() async throws {
        try await copy("token de staging")
        try await copy("token de producción")
        #expect(try await historyTexts("token staging") == ["token de staging"])
    }

    @Test func `short terms fall back to LIKE`() async throws {
        try await copy("ls -la")
        try await copy("pwd")
        #expect(try await historyTexts("la") == ["ls -la"])
        #expect(try await historyTexts("%") == [])
    }

    @Test func `search finds the source app name`() async throws {
        try await copy("algo", from: chrome)
        try await copy("otra", from: terminal)
        #expect(try await historyTexts("chrome") == ["algo"])
    }

    @Test func `quotes in the query are not FTS syntax`() async throws {
        try await copy(#"say "hello" now"#)
        #expect(try await historyTexts(#""hello""#) == [#"say "hello" now"#])
    }

    @Test func `filters by kind`() async throws {
        try await copy("texto")
        try await copy("https://example.com")
        try await copyImage(hash: "img")
        #expect(try await historyTexts(kinds: [.link]) == ["https://example.com"])
        #expect(try await historyTexts(kinds: [.image]) == ["<image>"])
        #expect(try await historyTexts(kinds: [.text, .link]).count == 2)
    }

    @Test func `board search includes the custom title`() async throws {
        let board = try await store.createBoard(name: "env", color: .orange)
        let entryID = try await store.save(try await copy("sk-123").id, to: board.id, at: base)
        try await store.updateEntry(entryID, title: "Token de staging", text: nil)
        try await store.save(try await copy("otro").id, to: board.id, at: base)

        let found = try await store.items(matching: LibraryQuery(scope: .board(board.id), text: "staging"))
        #expect(found.map(\.content) == [.text("sk-123")])
    }

    @Test func `everything scope merges boards and history without duplicates`() async throws {
        let board = try await store.createBoard(name: "env", color: .orange)
        let saved = try await copy("token guardado", minutesAgo: 5)
        try await store.save(saved.id, to: board.id, at: base)
        try await copy("token suelto")

        let found = try await store.items(matching: LibraryQuery(scope: .everything, text: "token"))
        #expect(found.count == 2)
        #expect(found.contains { $0.entry != nil })
    }

    // MARK: Apps excluidas

    @Test func `default excluded apps are seeded`() async throws {
        let apps = try await store.excludedApps()
        #expect(apps.contains { $0.bundleID == "com.apple.Passwords" })
    }

    @Test func `excluded apps can be added and removed`() async throws {
        let bank = SourceApp(bundleID: "com.bank.app", name: "Banco")
        try await store.addExcludedApp(bank)
        #expect(try await store.excludedApps().contains(bank))
        try await store.removeExcludedApp(bundleID: bank.bundleID)
        #expect(try await !store.excludedApps().contains(bank))
    }

    // MARK: En disco

    @Test func `opens a database in a folder with spaces`() async throws {
        // "Application Support" tiene un espacio: URL.path() lo devolvería como %20.
        let folder = FileManager.default.temporaryDirectory.appending(path: "Baul tests \(UUID().uuidString)/Application Support")
        let database = try AppDatabase.onDisk(at: folder.appending(path: "baul.sqlite"))
        let store = SQLiteLibraryStore(database: database)
        #expect(try await store.historyCount() == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "baul.sqlite").path(percentEncoded: false)))
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    // MARK: Observación

    @Test func `observation emits when history changes`() async throws {
        var iterator = store.observeItems(matching: LibraryQuery()).makeAsyncIterator()
        #expect(try await iterator.next()?.isEmpty == true)
        try await copy("nuevo")
        #expect(try await iterator.next()?.count == 1)
    }
}
