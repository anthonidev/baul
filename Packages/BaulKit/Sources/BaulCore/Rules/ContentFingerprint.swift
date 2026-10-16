import CryptoKit
import Foundation

/// Huella estable del contenido copiado. Dos copias con la misma huella
/// se consideran el mismo elemento: la segunda solo lo sube al principio.
public enum ContentFingerprint {
    public static func of(_ payload: CapturedItem.Payload) -> String {
        switch payload {
        case .text(let text): "text:" + sha256(Data(text.utf8))
        case .image(let png, _, _): "image:" + sha256(png)
        }
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
