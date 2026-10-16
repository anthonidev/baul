import AppKit
import BaulCore
import os

/// Vigila el portapapeles general y entrega cada copia nueva como `CapturedItem`.
///
/// macOS no avisa cuando cambia el portapapeles: hay que revisar `changeCount`
/// periódicamente. Leer `changeCount` es barato y no dispara la alerta de privacidad;
/// el contenido solo se lee cuando cambió.
public final class PasteboardMonitor {
    public typealias Handler = (CapturedItem) -> Void

    /// Tipos de formato rico que se conservan junto al texto.
    static let richTypes: [NSPasteboard.PasteboardType] = [.rtf, .html]
    /// Formatos ricos más grandes que esto se descartan (el texto plano se guarda igual).
    static let maxRichBytes = 2_000_000

    private let pasteboard: NSPasteboard
    private let interval: Duration
    private let onCapture: Handler
    private let logger = Logger(subsystem: "dev.tonis.baul", category: "pasteboard")
    private var lastChangeCount: Int
    private var ignoredChangeCounts: Set<Int> = []
    private var pollTask: Task<Void, Never>?

    public init(
        pasteboard: NSPasteboard = .general,
        interval: Duration = .milliseconds(500),
        onCapture: @escaping Handler
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.onCapture = onCapture
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        guard pollTask == nil else { return }
        // Lo que ya estaba en el portapapeles al arrancar no se considera una copia nueva.
        lastChangeCount = pasteboard.changeCount
        let interval = interval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: interval, tolerance: .milliseconds(100))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Marca un cambio hecho por Baúl (al pegar) para no guardarlo como copia nueva.
    public func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard ignoredChangeCounts.remove(count) == nil else { return }
        // Los cambios ignorados que nunca se vieron (p. ej. dos escrituras seguidas) no deben acumularse.
        ignoredChangeCounts = ignoredChangeCounts.filter { $0 > count }

        if let item = read() {
            onCapture(item)
        }
    }

    private func read() -> CapturedItem? {
        let types = Set(pasteboard.types?.map(\.rawValue) ?? [])

        // Contraseñas: ni siquiera se lee el contenido.
        guard types.isDisjoint(with: CapturePolicy.privacyMarkerTypes) else {
            logger.info("Copia marcada como privada; no se lee")
            return nil
        }
        // Copiar archivos en Finder queda fuera de alcance por ahora (guardaría solo el nombre).
        guard !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) else { return nil }

        let source = NSWorkspace.shared.frontmostApplication.flatMap(SourceApp.init(runningApplication:))
        let now = Date.now

        if let text = pasteboard.string(forType: .string) {
            return CapturedItem(
                payload: .text(text),
                richRepresentations: readRichRepresentations(types: types),
                source: source,
                pasteboardTypes: types,
                capturedAt: now
            )
        }
        if let image = readImage(types: types) {
            return CapturedItem(payload: image, source: source, pasteboardTypes: types, capturedAt: now)
        }
        return nil
    }

    private func readRichRepresentations(types: Set<String>) -> [String: Data] {
        var result: [String: Data] = [:]
        for type in Self.richTypes where types.contains(type.rawValue) {
            if let data = pasteboard.data(forType: type), data.count <= Self.maxRichBytes {
                result[type.rawValue] = data
            }
        }
        return result
    }

    private func readImage(types: Set<String>) -> CapturedItem.Payload? {
        if types.contains(NSPasteboard.PasteboardType.png.rawValue),
           let png = pasteboard.data(forType: .png),
           let bitmap = NSBitmapImageRep(data: png) {
            return .image(png: png, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        if types.contains(NSPasteboard.PasteboardType.tiff.rawValue),
           let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return .image(png: png, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        return nil
    }
}

extension SourceApp {
    public init?(runningApplication app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
