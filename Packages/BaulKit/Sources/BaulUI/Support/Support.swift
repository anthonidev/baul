import AppKit
import BaulCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension BoardColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }

    var displayName: String {
        switch self {
        case .red: "Rojo"
        case .orange: "Naranja"
        case .yellow: "Amarillo"
        case .green: "Verde"
        case .mint: "Menta"
        case .teal: "Verde azulado"
        case .blue: "Azul"
        case .indigo: "Índigo"
        case .purple: "Morado"
        case .pink: "Rosa"
        case .gray: "Gris"
        }
    }
}

extension ClipKind {
    var displayName: String {
        switch self {
        case .text: "Texto"
        case .link: "Link"
        case .image: "Imagen"
        }
    }

    var pluralName: String {
        switch self {
        case .text: "Textos"
        case .link: "Links"
        case .image: "Imágenes"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        }
    }

    var tint: Color {
        switch self {
        case .text: .blue
        case .link: .purple
        case .image: .orange
        }
    }
}

/// Cachés de imágenes para que desplazarse por las tarjetas no relea disco.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let thumbnails = NSCache<NSURL, NSImage>()
    private let appIcons = NSCache<NSString, NSImage>()

    private init() {
        thumbnails.countLimit = 300
    }

    func thumbnail(at url: URL) -> NSImage? {
        if let cached = thumbnails.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }

    func appIcon(forBundleID bundleID: String) -> NSImage? {
        if let cached = appIcons.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        appIcons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}

nonisolated extension UTType {
    /// Tipo interno para arrastrar tarjetas a las pestañas. Declarado en el Info.plist de la app.
    static let baulClip = UTType(exportedAs: "dev.tonis.baul.clip")
}

/// Lo que se arrastra al mover una tarjeta. Dentro de Baúl viaja el ID;
/// si se suelta en otra app, viaja el texto.
nonisolated struct ClipDragPayload: Codable, Transferable {
    let clipID: Int64
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .baulClip)
        ProxyRepresentation(exporting: \.text)
    }
}
