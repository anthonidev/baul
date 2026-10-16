import AppKit
import BaulCore
import BaulSystem
import KeyboardShortcuts
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Estado de la ventana de Configuración.
@Observable
public final class SettingsModel {
    public private(set) var excludedApps: [SourceApp] = []
    public private(set) var historyCount = 0
    public private(set) var storageBytes: Int64 = 0
    public private(set) var launchAtLogin = LaunchAtLogin.isEnabled
    public var errorMessage: String?

    private let store: any LibraryStore
    private let images: any ImageStore
    private let databaseSize: () -> Int64
    private var excludedAppsTask: Task<Void, Never>?

    public init(store: any LibraryStore, images: any ImageStore, databaseSize: @escaping () -> Int64) {
        self.store = store
        self.images = images
        self.databaseSize = databaseSize
    }

    public func start() {
        guard excludedAppsTask == nil else { return }
        excludedAppsTask = Task { [weak self, store] in
            do {
                for try await apps in store.observeExcludedApps() { self?.excludedApps = apps }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    public func refreshStats() async {
        historyCount = (try? await store.historyCount()) ?? 0
        storageBytes = databaseSize() + (await images.totalSize())
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            errorMessage = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    public func excludeApp(at url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacing(".app", with: "")
        Task {
            do {
                try await store.addExcludedApp(SourceApp(bundleID: bundleID, name: name))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func removeExcludedApp(_ app: SourceApp) {
        Task {
            do {
                try await store.removeExcludedApp(bundleID: app.bundleID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func clearHistory() async {
        do {
            let orphans = try await store.clearHistory()
            await images.remove(hashes: orphans)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshStats()
    }
}

public struct SettingsView: View {
    let model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView(model: model) }
            Tab("Privacidad", systemImage: "hand.raised") { PrivacySettingsView(model: model) }
            Tab("Almacenamiento", systemImage: "internaldrive") { StorageSettingsView(model: model) }
        }
        .frame(width: 520, height: 400)
        .task { model.start() }
        .alert(
            "Algo salió mal",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("Aceptar") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Abrir Baúl:", name: .togglePanel)
                Toggle(
                    "Iniciar Baúl al encender la Mac",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
                )
            }
            Section("Permisos") {
                PermissionsStatusView()
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshStats() }
    }
}

private struct PrivacySettingsView: View {
    let model: SettingsModel
    @State private var isChoosingApp = false

    var body: some View {
        Form {
            Section {
                ForEach(model.excludedApps, id: \.bundleID) { app in
                    HStack {
                        if let icon = ImageCache.shared.appIcon(forBundleID: app.bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        } else {
                            // App no instalada: mismo hueco para que los nombres queden alineados.
                            Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundStyle(.tertiary)
                        }
                        Text(app.name)
                        Spacer()
                        Button("Quitar", role: .destructive) { model.removeExcludedApp(app) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Agregar app…") { isChoosingApp = true }
            } header: {
                Text("Apps excluidas")
            } footer: {
                Text(
                    "Lo que copies en estas apps no se guarda. Las contraseñas de los gestores que marcan "
                        + "su contenido como privado (1Password, Bitwarden…) nunca se guardan."
                )
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result { model.excludeApp(at: url) }
        }
        .fileDialogDefaultDirectory(URL(filePath: "/Applications"))
    }
}

private struct StorageSettingsView: View {
    let model: SettingsModel
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Elementos en el historial", value: model.historyCount.formatted())
                LabeledContent("Espacio ocupado", value: ClipFormatting.byteCount(model.storageBytes))
                LabeledContent("Se conserva", value: "\(RetentionPolicy.standard.days) días")
            } footer: {
                Text("Lo guardado en tableros no se borra nunca, aunque pasen los \(RetentionPolicy.standard.days) días.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Borrar todo el historial…", role: .destructive) { isConfirmingClear = true }
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshStats() }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Borrar historial", role: .destructive) {
                Task { await model.clearHistory() }
            }
        } message: {
            Text("Los elementos guardados en tableros se conservan.")
        }
    }
}

/// Estado de los permisos, con botones para ir a Ajustes. Se refresca solo.
struct PermissionsStatusView: View {
    @State private var accessibility = AccessibilityPermission.isGranted
    @State private var pasteboard = PasteboardPermission.status

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionRow(
                isOK: accessibility,
                title: "Accesibilidad",
                detail: "Necesario para pegar directo en la app donde estás."
            ) {
                if !accessibility {
                    Button("Dar permiso…") {
                        AccessibilityPermission.request()
                        AccessibilityPermission.openSettings()
                    }
                }
            }
            PermissionRow(
                isOK: pasteboard == .allowed || pasteboard == .notDetermined,
                title: "Leer el portapapeles",
                detail: pasteboardDetail
            ) {
                if pasteboard != .allowed {
                    Button("Abrir Ajustes…") { PasteboardPermission.openSettings() }
                }
            }
        }
        .task {
            // Ajustes del Sistema no avisa cuando cambia un permiso: se consulta cada segundo.
            while !Task.isCancelled {
                accessibility = AccessibilityPermission.isGranted
                pasteboard = PasteboardPermission.status
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var pasteboardDetail: String {
        switch pasteboard {
        case .allowed: "Permitido siempre."
        case .notDetermined: "Si macOS pregunta, elige “Permitir siempre”."
        case .asks: "macOS pregunta cada vez: elige “Permitir siempre” para Baúl en Ajustes."
        case .denied: "Denegado: Baúl no puede guardar lo que copias."
        }
    }
}

private struct PermissionRow<Action: View>: View {
    let isOK: Bool
    let title: String
    let detail: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isOK ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            action
        }
    }
}
