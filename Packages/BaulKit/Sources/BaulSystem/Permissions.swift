import AppKit
import ApplicationServices

/// Permiso de Accesibilidad: necesario para simular ⌘V en otras apps.
public enum AccessibilityPermission {
    public static var isGranted: Bool { AXIsProcessTrusted() }

    /// Muestra el diálogo del sistema que lleva a Ajustes. Solo aparece si aún no se concedió.
    public static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openSettings() {
        SystemSettings.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}

/// Permiso para leer el portapapeles de otras apps (macOS 15.4+).
public enum PasteboardPermission {
    public enum Status: Sendable {
        /// "Permitir siempre".
        case allowed
        /// Nunca se preguntó: la primera lectura mostrará la alerta del sistema.
        case notDetermined
        /// macOS preguntará en cada lectura: hay que elegir "Permitir siempre".
        case asks
        case denied
    }

    public static var status: Status {
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: .allowed
        case .default: .notDetermined
        case .ask: .asks
        case .alwaysDeny: .denied
        @unknown default: .asks
        }
    }

    public static func openSettings() {
        SystemSettings.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")
    }
}

enum SystemSettings {
    static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        if !NSWorkspace.shared.open(url),
           let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
