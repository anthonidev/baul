import BaulSystem
import KeyboardShortcuts
import SwiftUI

/// Pantalla de primer uso: permisos y cómo se usa Baúl.
public struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var isPasteRunning = ConflictingApps.isPasteRunning

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("🧳").font(.system(size: 44))
                VStack(alignment: .leading) {
                    Text("Bienvenido a Baúl").font(.title.bold())
                    Text("Todo lo que copias, guardado, ordenado y a un atajo de distancia.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("1. Permisos") {
                PermissionsStatusView().padding(6)
            }

            if isPasteRunning {
                GroupBox {
                    Label {
                        Text("Paste está abierto y usa el mismo atajo. Ciérralo o cambia su atajo para que solo se abra Baúl.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .padding(6)
                }
            }

            GroupBox("2. Cómo se usa") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    shortcutRow(shortcutText, "Abrir o cerrar el panel")
                    shortcutRow("← →", "Moverse entre tarjetas")
                    shortcutRow("Enter", "Pegar en la app donde estabas")
                    shortcutRow("⇧ Enter", "Pegar como texto, sin formato")
                    shortcutRow("⌘1 … ⌘9", "Pegar la tarjeta en esa posición")
                    shortcutRow("⌘← ⌘→", "Cambiar de pestaña")
                    shortcutRow("⌘⌫", "Borrar la tarjeta")
                    shortcutRow("Escribir", "Buscar")
                }
                .padding(6)
                Text("Crea tableros con el botón + y arrastra tarjetas a sus pestañas para guardarlas para siempre.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], 6)
            }

            HStack {
                Spacer()
                Button("Empezar", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 560)
        .task {
            while !Task.isCancelled {
                isPasteRunning = ConflictingApps.isPasteRunning
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var shortcutText: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "⌘⇧V"
    }

    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: .rect(cornerRadius: 5))
            Text(action)
        }
    }
}
