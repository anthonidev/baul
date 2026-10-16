import BaulCore
import Foundation
import Observation
import os

/// Acciones que el panel delega a la app (pegar implica cerrar el panel,
/// escribir en el portapapeles y simular ⌘V).
public protocol PanelActions: AnyObject {
    func paste(_ item: ClipItem, plainText: Bool) async
    func copy(_ item: ClipItem) async
    func closePanel()
}

/// Estado y lógica del panel. No conoce AppKit: se puede probar con un almacén falso.
@Observable
public final class PanelViewModel {
    public enum Tab: Hashable, Sendable {
        case history
        case board(BoardID)
    }

    /// Edición de un tablero (crear o renombrar/cambiar color).
    public struct BoardDraft: Identifiable, Hashable {
        public let id = UUID()
        public var boardID: BoardID?
        public var name: String
        public var color: BoardColor
    }

    public private(set) var boards: [Board] = []
    public private(set) var items: [ClipItem] = []
    public var selection = 0

    public var tab: Tab = .history {
        didSet { if tab != oldValue { queryDidChange() } }
    }
    public var query = "" {
        didSet { if query != oldValue { queryDidChange() } }
    }
    /// Buscar en el historial y en todos los tableros a la vez.
    public var searchEverywhere = false {
        didSet { if searchEverywhere != oldValue { queryDidChange() } }
    }
    public var kindFilter: ClipKind? {
        didSet { if kindFilter != oldValue { queryDidChange() } }
    }

    public var entryBeingEdited: BoardEntry?
    public var boardDraft: BoardDraft?
    public var boardPendingDeletion: Board?
    public var errorMessage: String?

    /// Cuando hay una hoja o diálogo abierto, el teclado no navega las tarjetas.
    public var isShowingModal: Bool {
        entryBeingEdited != nil || boardDraft != nil || boardPendingDeletion != nil || errorMessage != nil
    }

    public var selectedItem: ClipItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    public var currentBoard: Board? {
        guard case .board(let id) = tab else { return nil }
        return boards.first { $0.id == id }
    }

    /// Cambia cada vez que se abre el panel, para que la vista vuelva al inicio.
    public private(set) var presentationID = UUID()
    /// Cambia cuando el campo de búsqueda debe recibir el foco.
    public private(set) var focusRequest = UUID()

    public weak var actions: (any PanelActions)?

    private let store: any LibraryStore
    private let images: any ImageStore
    private let logger = Logger(subsystem: "dev.tonis.baul", category: "panel")
    private var itemsTask: Task<Void, Never>?
    private var boardsTask: Task<Void, Never>?

    public init(store: any LibraryStore, images: any ImageStore) {
        self.store = store
        self.images = images
    }

    var currentQuery: LibraryQuery {
        let scope: LibraryQuery.Scope
        if searchEverywhere, !query.isEmpty {
            scope = .everything
        } else {
            switch tab {
            case .history: scope = .history
            case .board(let id): scope = .board(id)
            }
        }
        return LibraryQuery(scope: scope, text: query, kinds: kindFilter.map { [$0] } ?? [], limit: 300)
    }

    // MARK: - Ciclo de vida

    public func start() {
        guard boardsTask == nil else { return }
        boardsTask = Task { [weak self, store] in
            do {
                for try await boards in store.observeBoards() {
                    self?.apply(boards: boards)
                }
            } catch {
                self?.report(error)
            }
        }
        observeItems()
    }

    /// Se llama justo antes de mostrar el panel: siempre abre en el historial, sin búsqueda.
    public func prepareForPresentation() {
        query = ""
        kindFilter = nil
        searchEverywhere = false
        tab = .history
        selection = 0
        presentationID = UUID()
        focusSearch()
    }

    /// ⌘F, o al abrir el panel.
    public func focusSearch() {
        focusRequest = UUID()
    }

    private func queryDidChange() {
        selection = 0
        observeItems()
    }

    private func observeItems() {
        itemsTask?.cancel()
        let query = currentQuery
        itemsTask = Task { [weak self, store] in
            do {
                for try await items in store.observeItems(matching: query) {
                    guard !Task.isCancelled else { return }
                    self?.apply(items: items)
                }
            } catch is CancellationError {
            } catch {
                self?.report(error)
            }
        }
    }

    func apply(items newItems: [ClipItem]) {
        // Conserva la tarjeta seleccionada si sigue en la lista.
        let selectedID = selectedItem?.id
        items = newItems
        if let selectedID, let index = newItems.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = min(selection, max(newItems.count - 1, 0))
        }
    }

    func apply(boards newBoards: [Board]) {
        boards = newBoards
        if case .board(let id) = tab, !newBoards.contains(where: { $0.id == id }) {
            tab = .history
        }
    }

    // MARK: - Navegación

    public func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + offset, 0), items.count - 1)
    }

    public var tabs: [Tab] {
        [.history] + boards.map { .board($0.id) }
    }

    /// ⌘← / ⌘→
    public func moveTab(by offset: Int) {
        let tabs = tabs
        guard let index = tabs.firstIndex(of: tab) else { return }
        let newIndex = (index + offset + tabs.count) % tabs.count
        tab = tabs[newIndex]
    }

    // MARK: - Pegar y copiar

    public func pasteSelected(plainText: Bool = false) {
        guard let item = selectedItem else { return }
        paste(item, plainText: plainText)
    }

    /// ⌘1…⌘9: posición visible empezando en 1.
    public func paste(position: Int, plainText: Bool = false) {
        let index = position - 1
        guard items.indices.contains(index) else { return }
        paste(items[index], plainText: plainText)
    }

    public func paste(_ item: ClipItem, plainText: Bool = false) {
        Task { await actions?.paste(item, plainText: plainText) }
    }

    public func copySelected() {
        guard let item = selectedItem else { return }
        copy(item)
    }

    public func copy(_ item: ClipItem) {
        Task { await actions?.copy(item) }
    }

    // MARK: - Borrar

    public func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    /// En el historial borra el elemento; en un tablero lo quita del tablero.
    public func delete(_ item: ClipItem) {
        perform {
            let orphans = switch item {
            case .clip(let clip): try await self.store.deleteClip(clip.id)
            case .entry(let entry): try await self.store.removeEntry(entry.id)
            }
            await self.images.remove(hashes: orphans)
        }
    }

    // MARK: - Tableros

    public func save(_ item: ClipItem, to board: Board) {
        perform { try await self.store.save(item.clip.id, to: board.id, at: .now) }
    }

    public func beginCreatingBoard() {
        let usedColors = Set(boards.map(\.color))
        let color = BoardColor.allCases.first { !usedColors.contains($0) } ?? .blue
        boardDraft = BoardDraft(boardID: nil, name: "", color: color)
    }

    public func beginEditing(_ board: Board) {
        boardDraft = BoardDraft(boardID: board.id, name: board.name, color: board.color)
    }

    public func commitBoardDraft() {
        guard let draft = boardDraft else { return }
        boardDraft = nil
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        perform {
            if let id = draft.boardID {
                try await self.store.updateBoard(id, name: name, color: draft.color)
            } else {
                let board = try await self.store.createBoard(name: name, color: draft.color)
                self.tab = .board(board.id)
            }
        }
    }

    public func requestDeletion(of board: Board) {
        boardPendingDeletion = board
    }

    public func confirmBoardDeletion() {
        guard let board = boardPendingDeletion else { return }
        boardPendingDeletion = nil
        perform {
            let orphans = try await self.store.deleteBoard(board.id)
            await self.images.remove(hashes: orphans)
        }
    }

    /// Mueve un tablero una posición a la izquierda (-1) o derecha (+1).
    public func move(_ board: Board, by offset: Int) {
        var ids = boards.map(\.id)
        guard let index = ids.firstIndex(of: board.id) else { return }
        let newIndex = index + offset
        guard ids.indices.contains(newIndex) else { return }
        ids.swapAt(index, newIndex)
        perform { try await self.store.reorderBoards(ids) }
    }

    // MARK: - Editar elementos guardados

    public func beginEditing(_ entry: BoardEntry) {
        entryBeingEdited = entry
    }

    public func commitEdit(title: String, text: String) {
        guard let entry = entryBeingEdited else { return }
        entryBeingEdited = nil
        // Si el texto no cambió respecto al original, no se guarda como edición.
        let original = entry.clip.content.plainText
        let customText: String? = (text == original) ? nil : text
        perform { try await self.store.updateEntry(entry.id, title: title, text: customText) }
    }

    // MARK: - Utilidades

    public func thumbnailURL(for image: ImageReference) -> URL {
        images.thumbnailURL(for: image.hash)
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: any Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
    }
}
