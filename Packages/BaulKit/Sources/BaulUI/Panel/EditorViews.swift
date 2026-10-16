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

/// Editar el título y el texto de un elemento guardado en un tablero.
struct EntryEditorView: View {
    let entry: BoardEntry
    let onCancel: () -> Void
    let onSave: (_ title: String, _ text: String) -> Void

    @State private var title: String
    @State private var text: String

    init(entry: BoardEntry, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.entry = entry
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: entry.customTitle ?? "")
        _text = State(initialValue: entry.content.plainText ?? "")
    }

    private var isImage: Bool { entry.clip.kind == .image }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editar elemento guardado")
                .font(.headline)
            TextField("Título (p. ej. Token de staging)", text: $title)
                .textFieldStyle(.roundedBorder)
            if !isImage {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                if let original = entry.clip.content.plainText, text != original {
                    Button("Volver al texto original") { text = original }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") { onSave(title, text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
