// Prueba de concepto desechable: valida en macOS 27 las 4 partes delicadas de Baúl.
// No se reutiliza en la app real.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI
import os

// MARK: - Log a archivo (para revisar desde la terminal)

@MainActor
enum PoCLog {
    private static let logger = Logger(subsystem: "dev.tonis.baul.poc", category: "poc")
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/BaulPoC.log")

    static func write(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(Date.now.formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

// MARK: - 1. Lectura continua del portapapeles

@MainActor
@Observable
final class PasteboardWatcher {
    private(set) var clips: [String] = []
    var selection = 0
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    /// changeCount producido por nosotros al pegar; se ignora para no re-guardar.
    var ownChangeCount: Int?

    func start() {
        PoCLog.write("watcher start; accessBehavior=\(Self.describe(NSPasteboard.general.accessBehavior))")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ownChangeCount else {
            PoCLog.write("change \(count) ignored (own write)")
            return
        }

        let source = NSWorkspace.shared.frontmostApplication
        let types = pasteboard.types?.map(\.rawValue) ?? []
        PoCLog.write("change \(count) from \(source?.bundleIdentifier ?? "?"); types=\(types)")

        let start = ContinuousClock.now
        let text = pasteboard.string(forType: .string)
        let elapsed = ContinuousClock.now - start
        PoCLog.write("read string in \(elapsed); got=\(text != nil); accessBehavior=\(Self.describe(pasteboard.accessBehavior))")

        if let text {
            clips.removeAll { $0 == text }
            clips.insert(text, at: 0)
            clips = Array(clips.prefix(9))
        } else if types.contains(NSPasteboard.PasteboardType.png.rawValue)
                    || types.contains(NSPasteboard.PasteboardType.tiff.rawValue) {
            let image = NSImage(pasteboard: pasteboard)
            PoCLog.write("image read: \(image.map { "\($0.size)" } ?? "nil")")
        }
    }

    static func describe(_ behavior: NSPasteboard.AccessBehavior) -> String {
        switch behavior {
        case .default: "default"
        case .ask: "ask"
        case .alwaysAllow: "alwaysAllow"
        case .alwaysDeny: "alwaysDeny"
        @unknown default: "unknown(\(behavior.rawValue))"
        }
    }
}

// MARK: - 2. Panel encima de todo sin quitar el foco

final class FloatingPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Ojo: isFloatingPanel = true reinicia el nivel a .floating, por eso va antes.
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = NSHostingView(rootView: content)
    }

    // Necesario para recibir teclado siendo .nonactivatingPanel.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct PanelView: View {
    let watcher: PasteboardWatcher
    let onPaste: (String) -> Void
    let onClose: () -> Void
    @State private var query = ""
    private var selection: Int { watcher.selection }
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Escribe para probar el teclado…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .frame(maxWidth: 320)
            HStack(spacing: 12) {
                ForEach(Array(watcher.clips.enumerated()), id: \.offset) { index, clip in
                    Text(clip)
                        .lineLimit(5)
                        .font(.callout)
                        .padding(10)
                        .frame(width: 180, height: 120, alignment: .topLeading)
                        .background(.background, in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(index == selection ? Color.accentColor : .clear, lineWidth: 3)
                        }
                        .onTapGesture(count: 2) { onPaste(clip) }
                }
                if watcher.clips.isEmpty {
                    Text("Copia algo para verlo aquí").foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .onAppear { searchFocused = true }
        // Las teclas de navegación se manejan en AppKit (monitor local en AppDelegate):
        // el editor del TextField se las come antes que .onKeyPress.
    }
}

// MARK: - 3. Pegar directo en la app activa

@MainActor
enum Paster {
    static func paste(_ text: String, watcher: PasteboardWatcher) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        watcher.ownChangeCount = pasteboard.changeCount

        guard AXIsProcessTrusted() else {
            PoCLog.write("paste: NOT trusted for Accessibility; only copied")
            return
        }
        // Pequeña espera para que el panel suelte el teclado antes de ⌘V.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyV = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            PoCLog.write("paste: posted ⌘V to \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        }
    }
}

// MARK: - 4. Atajo global ⌘⇧V (Carbon, sin permisos)

@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, selfPointer, &handler)

        let id = EventHotKeyID(signature: OSType(0x4241_554C), id: 1) // 'BAUL'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        PoCLog.write("RegisterEventHotKey status=\(status)")
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watcher = PasteboardWatcher()
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PoCLog.write("---- launch; AXIsProcessTrusted=\(AXIsProcessTrusted())")
        watcher.start()
        // `defaults write dev.tonis.baul.poc altHotKey -bool YES` → ⌃⌥⌘V, para probar sin chocar con Paste.
        let useAlt = UserDefaults.standard.bool(forKey: "altHotKey")
        let modifiers = useAlt ? (cmdKey | optionKey | controlKey) : (cmdKey | shiftKey)
        PoCLog.write("hotkey: \(useAlt ? "⌃⌥⌘V" : "⌘⇧V")")
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_V, modifiers: modifiers) { [weak self] in
            self?.togglePanel()
        }
        setUpStatusItem()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            PoCLog.write("local keyDown code=\(event.keyCode) chars=\(event.characters ?? "") window=\(event.window.map { String(describing: type(of: $0)) } ?? "nil") firstResponder=\(event.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
            let isPanel = event.window is FloatingPanel
            let keyCode = Int(event.keyCode)
            let consumed = MainActor.assumeIsolated { isPanel && self.handlePanelKey(keyCode) }
            return consumed ? nil : event
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🧳"
        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir panel (⌘⇧V)", action: #selector(togglePanelFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Pedir permiso de Accesibilidad", action: #selector(requestAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: "Registrar estado en el log", action: #selector(logStatus), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanelFromMenu() { togglePanel() }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        PoCLog.write("AXIsProcessTrustedWithOptions(prompt) = \(AXIsProcessTrustedWithOptions(options))")
    }

    @objc private func logStatus() {
        PoCLog.write("status: AX=\(AXIsProcessTrusted()) accessBehavior=\(PasteboardWatcher.describe(NSPasteboard.general.accessBehavior)) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
    }

    /// Devuelve true si la tecla se consumió.
    private func handlePanelKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Escape:
            hidePanel()
        case kVK_LeftArrow:
            watcher.selection = max(watcher.selection - 1, 0)
        case kVK_RightArrow:
            watcher.selection = min(watcher.selection + 1, max(watcher.clips.count - 1, 0))
        case kVK_Return:
            guard watcher.clips.indices.contains(watcher.selection) else { return true }
            let text = watcher.clips[watcher.selection]
            hidePanel()
            Paster.paste(text, watcher: watcher)
        default:
            return false
        }
        return true
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let panel = panel ?? makePanel()
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.minX + 8, y: visible.minY + 8, width: visible.width - 16, height: 210), display: true)
        }
        watcher.selection = 0
        panel.makeKeyAndOrderFront(nil)
        // Re-enfocar el campo de búsqueda en cada apertura (onAppear solo corre una vez).
        if let field = panel.contentView?.firstDescendant(ofType: NSTextField.self) {
            panel.makeFirstResponder(field)
        }

        let frontAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        PoCLog.write("panel shown on \(screen?.localizedName ?? "?"); frontmost before=\(frontBefore) after=\(frontAfter) isKey=\(panel.isKeyWindow) NSApp.isActive=\(NSApp.isActive)")
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        PoCLog.write("panel hidden")
    }

    private func makePanel() -> FloatingPanel {
        FloatingPanel(content: PanelView(
            watcher: watcher,
            onPaste: { [weak self] text in
                guard let self else { return }
                hidePanel()
                Paster.paste(text, watcher: watcher)
            },
            onClose: { [weak self] in self?.hidePanel() }
        ))
    }
}

extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}

@main
struct BaulPoCMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
