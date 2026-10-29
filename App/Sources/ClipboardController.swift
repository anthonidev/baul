import BaulCore
import BaulPersistence
import BaulSystem
import BaulUI
import Foundation

/// Pegar y copiar desde el panel: arma el contenido, lo escribe en el portapapeles
/// (sin que el monitor lo vuelva a guardar) y simula ⌘V.
final class ClipboardController: PanelActions {
    private let store: SQLiteLibraryStore
    private let images: FileImageStore
    private let panel: PanelController
    private let pasteService = PasteService()
    var monitor: PasteboardMonitor?
    var onMissingAccessibility: (() -> Void)?

    init(store: SQLiteLibraryStore, images: FileImageStore, panel: PanelController) {
        self.store = store
        self.images = images
        self.panel = panel
    }

    func paste(_ item: ClipItem, plainText: Bool) async {
        // Primero se cierra el panel: el ⌘V debe llegar a la app que estaba debajo.
        panel.hide()
        guard await write(item, plainText: plainText) else { return }
        if AccessibilityPermission.isGranted {
            let isImage = if case .image = item.content { true } else { false }
            await pasteService.pasteIntoFrontmostApp(isImage: isImage)
        } else {
            onMissingAccessibility?()
        }
    }

    func copy(_ item: ClipItem) async {
        panel.hide()
        await write(item, plainText: false)
    }

    func closePanel() {
        panel.hide()
    }

    @discardableResult
    private func write(_ item: ClipItem, plainText: Bool) async -> Bool {
        guard let content = await content(for: item) else { return false }
        let changeCount = pasteService.write(content, plainTextOnly: plainText)
        monitor?.ignore(changeCount: changeCount)
        // Usar algo del historial lo sube al principio, como si se hubiera copiado de nuevo.
        if case .clip(let clip) = item {
            try? await store.touch(clip.id, at: .now)
        }
        return true
    }

    private func content(for item: ClipItem) async -> PasteContent? {
        switch item.content {
        case .text(let text):
            // Si se editó el texto en un tablero, el formato original ya no corresponde.
            let isEdited = item.entry?.customText != nil
            let rich = isEdited ? [:] : ((try? await store.richRepresentations(for: item.clip.id)) ?? [:])
            return .text(text, rich: rich)
        case .link(let url, _):
            return .text(url.absoluteString, rich: [:])
        case .image(let image):
            guard let png = try? Data(contentsOf: images.imageURL(for: image.hash)) else { return nil }
            return .image(png: png)
        }
    }
}
