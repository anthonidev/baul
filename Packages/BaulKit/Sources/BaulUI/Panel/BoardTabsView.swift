import BaulCore
import SwiftUI

/// Pestañas: "Portapapeles" + un tablero por pestaña. Se puede soltar una tarjeta
/// sobre un tablero para guardarla ahí.
struct BoardTabsView: View {
    @Bindable var model: PanelViewModel
    @State private var dropTarget: BoardID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                tab(.history, title: "Portapapeles", systemImage: "clock.arrow.circlepath", color: nil)
                ForEach(model.boards) { board in
                    tab(.board(board.id), title: board.name, systemImage: nil, color: board.color.color)
                        .dropDestination(for: ClipDragPayload.self) { payloads, _ in
                            save(payloads, to: board)
                        } isTargeted: { isTargeted in
                            dropTarget = isTargeted ? board.id : (dropTarget == board.id ? nil : dropTarget)
                        }
                        .contextMenu { boardMenu(board) }
                }
                Button {
                    model.beginCreatingBoard()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Nuevo tablero")
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tab(_ tab: PanelViewModel.Tab, title: String, systemImage: String?, color: Color?) -> some View {
        let isSelected = model.tab == tab
        let isDropTarget: Bool = if case .board(let id) = tab { dropTarget == id } else { false }
        return Button {
            model.tab = tab
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                if let color {
                    Circle().fill(color).frame(width: 9, height: 9)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(isSelected || isDropTarget ? Color.primary.opacity(0.12) : .clear)
            }
            .overlay {
                if isDropTarget { Capsule().strokeBorder(color ?? .accentColor, lineWidth: 2) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func boardMenu(_ board: Board) -> some View {
        Button("Renombrar o cambiar color…") { model.beginEditing(board) }
        Button("Mover a la izquierda") { model.move(board, by: -1) }
            .disabled(model.boards.first == board)
        Button("Mover a la derecha") { model.move(board, by: 1) }
            .disabled(model.boards.last == board)
        Divider()
        Button("Eliminar tablero…", role: .destructive) { model.requestDeletion(of: board) }
    }

    private func save(_ payloads: [ClipDragPayload], to board: Board) -> Bool {
        let draggedIDs = Set(payloads.map(\.clipID))
        let dragged = model.items.filter { draggedIDs.contains($0.clip.id.rawValue) }
        dragged.forEach { model.save($0, to: board) }
        return !dragged.isEmpty
    }
}
