import Foundation

/// Lo que el monitor del portapapeles leyó, antes de clasificarlo y guardarlo.
/// Es independiente de AppKit para poder probar las reglas sin el portapapeles real.
public struct CapturedItem: Sendable {
    public enum Payload: Sendable {
        case text(String)
        /// Imagen ya convertida a PNG.
        case image(png: Data, width: Int, height: Int)
    }

    public let payload: Payload
    /// Formatos ricos que acompañan al texto (RTF, HTML), por tipo UTI.
    /// Se guardan para que "pegar" conserve el formato y "pegar como texto" lo descarte.
    public let richRepresentations: [String: Data]
    public let source: SourceApp?
    /// Tipos del portapapeles presentes (identificadores UTI), para detectar marcas de privacidad.
    public let pasteboardTypes: Set<String>
    public let capturedAt: Date

    public init(
        payload: Payload,
        richRepresentations: [String: Data] = [:],
        source: SourceApp?,
        pasteboardTypes: Set<String>,
        capturedAt: Date
    ) {
        self.payload = payload
        self.richRepresentations = richRepresentations
        self.source = source
        self.pasteboardTypes = pasteboardTypes
        self.capturedAt = capturedAt
    }
}
