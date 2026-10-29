import Foundation

/// Qué atajo simular al pegar en la app activa.
public enum PasteKeystroke: Sendable, Equatable {
    case commandV
    case controlV

    /// Terminales donde ⌘V solo pega texto: las imágenes las lee el programa que
    /// corre dentro (Claude Code, por ejemplo) cuando recibe ⌃V. Warp no está porque
    /// intercepta ⌘V y ya entrega la imagen.
    static let terminalsWithTextOnlyPaste: Set<String> = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.alacritty",
    ]

    public static func forPasting(image isImage: Bool, into bundleID: String?) -> PasteKeystroke {
        guard isImage, let bundleID, terminalsWithTextOnlyPaste.contains(bundleID) else { return .commandV }
        return .controlV
    }
}
