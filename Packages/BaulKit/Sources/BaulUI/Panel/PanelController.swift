import AppKit
import Carbon.HIToolbox
import os
import SwiftUI

/// Muestra y oculta el panel inferior y traduce el teclado en acciones.
///
/// Detalles validados en la prueba de concepto (ver docs/HALLAZGOS.md):
/// - `.nonactivatingPanel` + `canBecomeKey`: recibe teclado sin quitarle el foco a la app activa.
/// - `isFloatingPanel` se asigna antes que `level` (si no, el nivel vuelve a `.floating`).
/// - Las teclas de navegación se interceptan con un monitor local, porque el campo de
///   búsqueda se come las flechas, Enter y Esc antes que SwiftUI.
public final class PanelController {
    public let model: PanelViewModel
    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?
    private let logger = Logger(subsystem: "dev.tonis.baul", category: "panel")

    static let height: CGFloat = 340
    static let margin: CGFloat = 8

    public init(model: PanelViewModel) {
        self.model = model
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        model.prepareForPresentation()
        panel.setFrame(frameOnScreenWithMouse(), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        guard let panel, panel.isVisible else { return }
        // Cierra hojas abiertas (editor de tablero, etc.) para no dejarlas huérfanas.
        model.boardDraft = nil
        model.entryBeingEdited = nil
        model.boardPendingDeletion = nil
        panel.orderOut(nil)
    }

    // MARK: - Ventana

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(rootView: PanelView(model: model))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Los monitores locales corren en el hilo principal.
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
        // Clic fuera del panel → se cierra, salvo que tenga una hoja abierta.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.attachedSheet == nil, !self.model.isShowingModal else { return }
                self.hide()
            }
        }
        return panel
    }

    private func frameOnScreenWithMouse() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        return NSRect(
            x: visible.minX + Self.margin,
            y: visible.minY + Self.margin,
            width: visible.width - Self.margin * 2,
            height: Self.height
        )
    }

    // MARK: - Teclado

    /// Devuelve `true` si la tecla se consumió.
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel, panel.attachedSheet == nil, !model.isShowingModal else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)
        logger.debug("keyDown \(keyCode) modifiers=\(modifiers.rawValue)")

        if modifiers.contains(.command) {
            return handleCommand(keyCode, shift: modifiers.contains(.shift))
        }
        switch keyCode {
        case kVK_Escape: hide()
        case kVK_LeftArrow: model.moveSelection(by: -1)
        case kVK_RightArrow: model.moveSelection(by: 1)
        case kVK_Home: model.selection = 0
        case kVK_End: model.selection = max(model.items.count - 1, 0)
        case kVK_Return, kVK_ANSI_KeypadEnter: model.pasteSelected(plainText: modifiers.contains(.shift))
        // ⌦ borra la tarjeta. El ⌫ solo siempre edita la búsqueda: con un ⌫ de más
        // (p. ej. tras enfocar el campo, que selecciona todo) se perdería un elemento.
        case kVK_ForwardDelete: model.deleteSelected()
        default: return false
        }
        return true
    }

    /// Atajos con ⌘.
    private func handleCommand(_ keyCode: Int, shift: Bool) -> Bool {
        switch keyCode {
        case kVK_LeftArrow: model.moveTab(by: -1)
        case kVK_RightArrow: model.moveTab(by: 1)
        case kVK_Delete: model.deleteSelected()
        case kVK_ANSI_C: model.copySelected()
        case kVK_ANSI_F: model.focusSearch()
        default:
            guard let digit = Self.digit(for: keyCode) else { return false }
            model.paste(position: digit, plainText: shift)
        }
        return true
    }

    private static func digit(for keyCode: Int) -> Int? {
        let digits = [
            kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
            kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        ]
        return digits[keyCode]
    }
}

/// Panel sin bordes que flota sobre todo, incluso apps en pantalla completa.
final class FloatingPanel: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true // ⚠️ antes de `level`: reinicia el nivel a .floating
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
