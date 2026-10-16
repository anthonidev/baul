import AppKit
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    /// Abrir o cerrar el panel. ⌘⇧V por defecto, como en Paste.
    public static let togglePanel = Self("togglePanel", initial: .init(.v, modifiers: [.command, .shift]))
}

/// Iniciar Baúl al encender la Mac.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Detecta si Paste está abierto: comparte el atajo ⌘⇧V y ambos paneles se abrirían a la vez.
public enum ConflictingApps {
    static let pasteBundleIDs = ["com.wiheads.paste", "com.wiheads.paste-setapp"]

    public static var isPasteRunning: Bool {
        pasteBundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }
}
