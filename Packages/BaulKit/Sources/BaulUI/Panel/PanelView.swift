import BaulCore
import SwiftUI

/// Contenido del panel inferior: barra superior (búsqueda, pestañas, filtros) y tarjetas.
public struct PanelView: View {
    @Bindable var model: PanelViewModel
    @FocusState private var isSearchFocused: Bool

    public init(model: PanelViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 10) {
            topBar
            cards
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08))
        }
        .onChange(of: model.focusRequest, initial: true) { isSearchFocused = true }
        .sheet(item: $model.boardDraft) { draft in
            BoardEditorView(
                draft: draft,
                onCancel: { model.boardDraft = nil },
                onSave: { edited in
                    model.boardDraft = edited
                    model.commitBoardDraft()
                }
            )
        }
        .sheet(item: $model.itemBeingEdited) { item in
            ItemEditorView(
                item: item,
                onCancel: { model.itemBeingEdited = nil },
                onSave: { title, text in model.commitEdit(title: title, text: text) }
            )
        }
        .confirmationDialog(
            "¿Eliminar el tablero “\(model.boardPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { model.boardPendingDeletion != nil },
                set: { if !$0 { model.boardPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar tablero", role: .destructive) { model.confirmBoardDeletion() }
            Button("Cancelar", role: .cancel) { model.boardPendingDeletion = nil }
        } message: {
            Text("Se borrarán los elementos guardados en él. Los que sigan en el historial no se tocan.")
        }
        .alert(
            "Algo salió mal",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("Aceptar") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Barra superior

    private var topBar: some View {
        HStack(spacing: 12) {
            searchField
            BoardTabsView(model: model)
                .frame(maxWidth: .infinity)
            filterMenu
            appMenu
        }
        .frame(height: 30)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar", text: $model.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .frame(width: 170)
            if !model.query.isEmpty {
                Toggle("En todo", isOn: $model.searchEverywhere)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Buscar en el historial y en todos los tableros")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: .capsule)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Tipo", selection: $model.kindFilter) {
                Text("Todo").tag(ClipKind?.none)
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    Label(kind.pluralName, systemImage: kind.systemImage).tag(Optional(kind))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                model.kindFilter?.pluralName ?? "Todo",
                systemImage: model.kindFilter?.systemImage ?? "line.3.horizontal.decrease.circle"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filtrar por tipo")
    }

    private var appMenu: some View {
        Menu {
            Button("Nuevo tablero…") { model.beginCreatingBoard() }
            Divider()
            if model.isCapturePaused {
                Button("Reanudar Baúl") { model.onResume() }
            } else {
                Menu("Pausar Baúl") {
                    Button("15 minutos") { model.onPause(.seconds(15 * 60)) }
                    Button("1 hora") { model.onPause(.seconds(3_600)) }
                    Button("Hasta que lo reanude") { model.onPause(nil) }
                }
            }
            Divider()
            Button("Configuración…") {
                model.actions?.closePanel()
                model.onOpenSettings()
            }
            Button("Bienvenida y atajos…") {
                model.actions?.closePanel()
                model.onShowWelcome()
            }
            Divider()
            Button("Salir de Baúl") { model.onQuit() }
        } label: {
            Image(systemName: model.isCapturePaused ? "pause.circle.fill" : "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Más opciones")
    }

    // MARK: - Tarjetas

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // Un solo reloj para todas las tarjetas: "hace 5 min" se actualiza cada minuto.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    LazyHStack(spacing: 14) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            card(for: item, at: index, now: context.date)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if model.items.isEmpty { emptyState }
            }
            .onChange(of: model.selection) {
                guard let item = model.selectedItem else { return }
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(item.id, anchor: .center) }
            }
            .onChange(of: model.presentationID) {
                if let first = model.items.first { proxy.scrollTo(first.id, anchor: .leading) }
            }
        }
    }

    private func card(for item: ClipItem, at index: Int, now: Date) -> some View {
        ClipCardView(
            item: item,
            boards: model.boards(for: item),
            position: index < 9 ? index + 1 : nil,
            isSelected: index == model.selection,
            thumbnailURL: thumbnailURL(for: item),
            now: now
        )
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture(count: 2) { model.paste(item) }
        .onTapGesture { model.selection = index }
        .draggable(ClipDragPayload(clipID: item.clip.id.rawValue, text: item.content.plainText ?? ""))
        .contextMenu { contextMenu(for: item) }
    }

    private func thumbnailURL(for item: ClipItem) -> URL? {
        guard case .image(let image) = item.content else { return nil }
        return model.thumbnailURL(for: image)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("Pegar") { model.paste(item) }
        if item.content.kind != .image {
            Button("Pegar como texto") { model.paste(item, plainText: true) }
        }
        Button("Copiar") { model.copy(item) }
        Divider()
        Menu("Guardar en…") {
            ForEach(model.boards) { board in
                Button(board.name) { model.save(item, to: board) }
            }
            if !model.boards.isEmpty { Divider() }
            Button("Nuevo tablero…") { model.beginCreatingBoard() }
        }
        if item.entry != nil {
            Button("Editar título y texto…") { model.beginEditing(item) }
            Divider()
            Button("Quitar del tablero", role: .destructive) { model.delete(item) }
        } else {
            Button(item.title == nil ? "Ponerle título…" : "Cambiar título…") { model.beginEditing(item) }
            Divider()
            Button("Eliminar", role: .destructive) { model.delete(item) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let message: String = if !model.query.isEmpty {
            "Nada coincide con “\(model.query)”"
        } else if model.currentBoard != nil {
            "Arrastra una tarjeta a esta pestaña, o usa clic derecho → Guardar en…"
        } else {
            "Lo que copies aparecerá aquí"
        }
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
