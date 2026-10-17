import BaulCore
import BaulPersistence
import Foundation
import Testing
@testable import BaulUI

/// Acciones falsas: registra lo que el panel pidió pegar o copiar.
final class RecordingActions: PanelActions {
    var pasted: [(ClipItem, Bool)] = []
    var copied: [ClipItem] = []

    func paste(_ item: ClipItem, plainText: Bool) async { pasted.append((item, plainText)) }
    func copy(_ item: ClipItem) async { copied.append(item) }
    func closePanel() {}
}

/// Imágenes en memoria (el panel solo pide URLs y borrar).
final class NullImageStore: ImageStore {
    func store(png: Data, hash: String) async throws {}
    func imageURL(for hash: String) -> URL { URL(filePath: "/dev/null") }
    func thumbnailURL(for hash: String) -> URL { URL(filePath: "/dev/null") }
    func remove(hashes: [String]) async {}
    func totalSize() async -> Int64 { 0 }
}

@Suite struct PanelViewModelTests {
    let store: SQLiteLibraryStore
    let model: PanelViewModel
    let actions = RecordingActions()

    init() throws {
        store = SQLiteLibraryStore(database: try AppDatabase.inMemory())
        model = PanelViewModel(store: store, images: NullImageStore())
        model.actions = actions
    }

    func copy(_ text: String, secondsAgo: Double = 0) async throws {
        _ = try await store.record(NewClip(
            content: .text(text), fingerprint: ContentFingerprint.of(.text(text)),
            source: nil, byteSize: text.utf8.count, copiedAt: Date.now.addingTimeInterval(-secondsAgo)
        ))
    }

    /// Espera a que la observación de la base de datos llegue al modelo.
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    func texts() -> [String] {
        model.items.compactMap { $0.content.plainText }
    }

    @Test func `shows history newest first`() async throws {
        try await copy("uno", secondsAgo: 20)
        try await copy("dos", secondsAgo: 10)
        model.start()
        try await waitUntil { model.items.count == 2 }
        #expect(texts() == ["dos", "uno"])
    }

    @Test func `selection stays within bounds`() async throws {
        try await copy("a", secondsAgo: 2)
        try await copy("b", secondsAgo: 1)
        model.start()
        try await waitUntil { model.items.count == 2 }

        model.moveSelection(by: -1)
        #expect(model.selection == 0)
        model.moveSelection(by: 5)
        #expect(model.selection == 1)
    }

    @Test func `searching filters and resets the selection`() async throws {
        try await copy("token de staging", secondsAgo: 2)
        try await copy("otra cosa", secondsAgo: 1)
        model.start()
        try await waitUntil { model.items.count == 2 }
        model.selection = 1

        model.query = "staging"

        try await waitUntil { model.items.count == 1 }
        #expect(model.selection == 0)
        #expect(texts() == ["token de staging"])
    }

    @Test func `command number pastes that position`() async throws {
        try await copy("primero", secondsAgo: 2)
        try await copy("segundo", secondsAgo: 1)
        model.start()
        try await waitUntil { model.items.count == 2 }

        model.paste(position: 2, plainText: true)
        try await waitUntil { actions.pasted.count == 1 }

        #expect(actions.pasted.first?.0.content == .text("primero"))
        #expect(actions.pasted.first?.1 == true)
    }

    @Test func `positions outside the list do nothing`() async throws {
        try await copy("solo")
        model.start()
        try await waitUntil { model.items.count == 1 }
        model.paste(position: 9)
        try await Task.sleep(for: .milliseconds(50))
        #expect(actions.pasted.isEmpty)
    }

    @Test func `creating a board opens its tab`() async throws {
        model.start()
        model.beginCreatingBoard()
        model.boardDraft?.name = "  env  "
        model.commitBoardDraft()

        try await waitUntil { model.boards.count == 1 }
        #expect(model.boards.first?.name == "env")
        try await waitUntil { model.currentBoard?.name == "env" }
    }

    @Test func `a blank board name is ignored`() async throws {
        model.start()
        model.beginCreatingBoard()
        model.boardDraft?.name = "   "
        model.commitBoardDraft()
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await store.boards().isEmpty)
    }

    @Test func `new boards get an unused color`() async throws {
        _ = try await store.createBoard(name: "a", color: BoardColor.allCases[0])
        model.start()
        try await waitUntil { model.boards.count == 1 }
        model.beginCreatingBoard()
        #expect(model.boardDraft?.color == BoardColor.allCases[1])
    }

    @Test func `tabs wrap around with command arrows`() async throws {
        let env = try await store.createBoard(name: "env", color: .orange)
        model.start()
        try await waitUntil { model.boards.count == 1 }

        model.moveTab(by: 1)
        #expect(model.tab == .board(env.id))
        model.moveTab(by: 1)
        #expect(model.tab == .history)
        model.moveTab(by: -1)
        #expect(model.tab == .board(env.id))
    }

    @Test func `deleting the current board returns to history`() async throws {
        let env = try await store.createBoard(name: "env", color: .orange)
        model.start()
        try await waitUntil { model.boards.count == 1 }
        model.tab = .board(env.id)

        model.requestDeletion(of: env)
        #expect(model.isShowingModal)
        model.confirmBoardDeletion()

        try await waitUntil { model.boards.isEmpty }
        #expect(model.tab == .history)
    }

    @Test func `editing back to the original text clears the override`() async throws {
        try await copy("original")
        let board = try await store.createBoard(name: "env", color: .orange)
        let clip = try #require(try await store.items(matching: LibraryQuery()).first).clip
        try await store.save(clip.id, to: board.id, at: .now)
        model.start()
        model.tab = .board(board.id)
        try await waitUntil { model.items.count == 1 }
        let item = try #require(model.items.first)

        model.beginEditing(item)
        model.commitEdit(title: "Mi título", text: "original")

        try await waitUntil { model.items.first?.title == "Mi título" }
        #expect(model.items.first?.entry?.customText == nil)
    }

    @Test func `history items can get a title too`() async throws {
        try await copy("20601000939")
        model.start()
        try await waitUntil { model.items.count == 1 }

        model.beginEditing(try #require(model.items.first))
        model.commitEdit(title: "RUC", text: nil)

        try await waitUntil { model.items.first?.title == "RUC" }
    }

    @Test func `cards in a board tab use that board's color first`() async throws {
        try await copy("dato")
        let rxh = try await store.createBoard(name: "rxh", color: .red)
        let env = try await store.createBoard(name: "env", color: .orange)
        let clip = try #require(try await store.items(matching: LibraryQuery()).first).clip
        try await store.save(clip.id, to: rxh.id, at: .now)
        try await store.save(clip.id, to: env.id, at: .now)
        model.start()
        try await waitUntil { model.boards.count == 2 && model.items.first?.clip.boardIDs.count == 2 }

        #expect(model.boards(for: try #require(model.items.first)).map(\.name) == ["rxh", "env"])

        model.tab = .board(env.id)
        try await waitUntil { model.items.first?.entry?.boardID == env.id }
        #expect(model.boards(for: try #require(model.items.first)).map(\.name) == ["env", "rxh"])
    }

    @Test func `opening the panel resets search and tab`() async throws {
        let env = try await store.createBoard(name: "env", color: .orange)
        model.start()
        model.tab = .board(env.id)
        model.query = "algo"
        model.kindFilter = .image

        model.prepareForPresentation()

        #expect(model.tab == .history)
        #expect(model.query.isEmpty)
        #expect(model.kindFilter == nil)
    }
}
