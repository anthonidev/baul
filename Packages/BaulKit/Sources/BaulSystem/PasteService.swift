import AppKit
import ApplicationServices
import BaulCore
import Carbon.HIToolbox
import os

/// Lo que se va a poner en el portapapeles.
public enum PasteContent: Sendable {
    /// Texto con sus formatos ricos opcionales (RTF, HTML) por tipo UTI.
    case text(String, rich: [String: Data])
    case image(png: Data)
}

/// Escribe en el portapapeles y simula ⌘V (o ⌃V, ver `PasteKeystroke`) en la app activa.
public final class PasteService {
    private let pasteboard: NSPasteboard
    private let logger = Logger(subsystem: "dev.tonis.baul", category: "paste")

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Pone el contenido en el portapapeles y devuelve el `changeCount` resultante,
    /// para que el monitor no lo guarde como copia nueva.
    @discardableResult
    public func write(_ content: PasteContent, plainTextOnly: Bool = false) -> Int {
        pasteboard.clearContents()
        switch content {
        case .text(let text, let rich):
            pasteboard.setString(text, forType: .string)
            if !plainTextOnly {
                for (type, data) in rich {
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            }
        case .image(let png):
            pasteboard.setData(png, forType: .png)
            // Algunas apps antiguas solo leen TIFF.
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
        return pasteboard.changeCount
    }

    /// Simula ⌘V en la app que tiene el foco. Requiere el permiso de Accesibilidad.
    /// Con `isImage`, en terminales envía ⌃V para que la imagen llegue al programa de adentro.
    ///
    /// La espera breve deja que el panel suelte el teclado antes del evento;
    /// sin ella, algunas apps reciben el ⌘V antes de recuperar el foco.
    public func pasteIntoFrontmostApp(isImage: Bool = false, after delay: Duration = .milliseconds(60)) async {
        guard AccessibilityPermission.isGranted else {
            logger.notice("Sin permiso de Accesibilidad: el contenido quedó copiado pero no se pegó")
            return
        }
        try? await Task.sleep(for: delay)
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let keystroke = PasteKeystroke.forPasting(image: isImage, into: bundleID)
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        // Solo ⌘ (o ⌃): así ⇧ (pegar como texto) o el ⌘ de ⌘1…9 no se cuelan en el atajo.
        let flags: CGEventFlags = keystroke == .controlV ? .maskControl : .maskCommand
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
