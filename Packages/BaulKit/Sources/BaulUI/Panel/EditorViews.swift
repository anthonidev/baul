import BaulCore
import SwiftUI

/// Crear un tablero, o cambiarle nombre y color.
struct BoardEditorView: View {
    @State private var draft: PanelViewModel.BoardDraft
    let onCancel: () -> Void
    let onSave: (PanelViewModel.BoardDraft) -> Void

    init(
        draft: PanelViewModel.BoardDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (PanelViewModel.BoardDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.boardID == nil ? "Nuevo tablero" : "Editar tablero")
                .font(.headline)
            TextField("Nombre (p. ej. env)", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSave { onSave(draft) } }
            HStack(spacing: 8) {
                ForEach(BoardColor.allCases, id: \.self) { color in
                    Button {
                        draft.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if draft.color == color {
                                    Circle().strokeBorder(.primary, lineWidth: 2).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(color.displayName)
                    .accessibilityLabel(color.displayName)
                }
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

/// Ponerle título a una tarjeta. Si está guardada en un tablero, también se puede editar su texto.
struct ItemEditorView: View {
    let item: ClipItem
    let onCancel: () -> Void
    let onSave: (_ title: String, _ text: String?) -> Void

    @State private var title: String
    @State private var text: String

    init(item: ClipItem, onCancel: @escaping () -> Void, onSave: @escaping (String, String?) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: item.title ?? "")
        _text = State(initialValue: item.content.plainText ?? "")
    }

    /// El texto solo se edita en tableros: en el historial el elemento es tal cual se copió.
    private var canEditText: Bool { item.entry != nil && item.clip.kind != .image }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(canEditText ? "Editar elemento guardado" : "Título de la tarjeta")
                .font(.headline)
            TextField("Título (si lo dejas vacío dice “\(item.content.kind.displayName)”)", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            if canEditText {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                if let original = item.clip.content.plainText, text != original {
                    Button("Volver al texto original") { text = original }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: canEditText ? 460 : 380)
    }

    private func save() {
        onSave(title, canEditText ? text : nil)
    }
}
