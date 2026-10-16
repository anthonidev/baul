import AppKit
import BaulUI
import SwiftUI

@main
struct BaulApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            if let model = appDelegate.model {
                MenuBarContent(model: model)
            }
        } label: {
            Image(systemName: appDelegate.model?.isPaused == true ? "pause.circle" : "list.clipboard")
                .accessibilityLabel("Baúl")
        }
    }
}

/// Arranca la app una vez que AppKit está listo.
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel()
            self.model = model
            model.start()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Baúl no pudo abrir su base de datos"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}

/// Menú de la barra superior.
struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        Button("Abrir Baúl") { model.togglePanel() }
        Divider()
        if model.isPaused {
            Button("Reanudar Baúl") { model.resume() }
        } else {
            Menu("Pausar Baúl") {
                Button("15 minutos") { model.pause(for: .seconds(15 * 60)) }
                Button("1 hora") { model.pause(for: .seconds(3_600)) }
                Button("Hasta que lo reanude") { model.pause(for: nil) }
            }
        }
        Divider()
        Button("Configuración…") { model.showSettings() }
        .keyboardShortcut(",")
        Button("Bienvenida y permisos…") { model.showOnboarding() }
        Divider()
        Button("Salir de Baúl") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
