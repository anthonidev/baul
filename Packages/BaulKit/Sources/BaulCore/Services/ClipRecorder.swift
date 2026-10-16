import Foundation

/// Convierte lo capturado del portapapeles en un elemento guardado:
/// aplica la política, clasifica, guarda la imagen y registra en la base de datos.
public struct ClipRecorder: Sendable {
    public enum Result: Hashable, Sendable {
        case recorded(RecordOutcome)
        case skipped(CapturePolicy.Reason)
    }

    private let store: any LibraryStore
    private let images: any ImageStore

    public init(store: any LibraryStore, images: any ImageStore) {
        self.store = store
        self.images = images
    }

    public func record(_ item: CapturedItem, policy: CapturePolicy) async throws -> Result {
        if case .skip(let reason) = policy.decide(item) {
            return .skipped(reason)
        }

        let fingerprint = ContentFingerprint.of(item.payload)
        let content: ClipContent
        let byteSize: Int

        switch item.payload {
        case .text(let text):
            content = LinkDetector.url(in: text).map { .link($0, title: nil) } ?? .text(text)
            byteSize = text.utf8.count
        case .image(let png, let width, let height):
            let hash = ContentFingerprint.sha256(png)
            // La imagen se escribe antes que la fila: nunca hay una fila apuntando a un archivo inexistente.
            try await images.store(png: png, hash: hash)
            content = .image(ImageReference(hash: hash, width: width, height: height))
            byteSize = png.count
        }

        let rich: [String: Data] = if case .text = content { item.richRepresentations } else { [:] }
        let outcome = try await store.record(NewClip(
            content: content,
            fingerprint: fingerprint,
            richRepresentations: rich,
            source: item.source,
            byteSize: byteSize,
            copiedAt: item.capturedAt
        ))
        return .recorded(outcome)
    }
}
