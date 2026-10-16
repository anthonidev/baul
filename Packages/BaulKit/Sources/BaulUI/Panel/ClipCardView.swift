import BaulCore
import SwiftUI

/// Una tarjeta del panel: encabezado (tipo, hace cuánto, app), vista previa y detalle.
struct ClipCardView: View {
    let item: ClipItem
    /// Posición visible (1, 2, 3…) para ⌘1…⌘9; `nil` después de la 9.
    let position: Int?
    let isSelected: Bool
    let thumbnailURL: URL?
    let now: Date

    static let size = CGSize(width: 236, height: 248)

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.background.opacity(0.92), in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.25 : 0.1), radius: isSelected ? 8 : 3, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Encabezado

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title ?? item.content.kind.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(ClipFormatting.relativeTime(item.date, now: now))
                    .font(.caption)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
            appIcon
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.content.kind.tint.gradient)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleID = item.clip.source?.bundleID, let icon = ImageCache.shared.appIcon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 30, height: 30)
                .help(item.clip.source?.name ?? "")
        }
    }

    // MARK: Vista previa

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text(let text):
            Text(ClipFormatting.preview(of: text))
                .font(.system(size: 12, design: looksLikeCode(text) ? .monospaced : .default))
                .lineLimit(10)
                .padding(12)
        case .link(let url, let title):
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(3)
                }
                Text(url.absoluteString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .padding(12)
        case .image:
            if let thumbnailURL, let image = ImageCache.shared.thumbnail(at: thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Pie

    private var footer: some View {
        HStack {
            Text(detail)
            Spacer()
            if let position {
                Text("⌘\(position)")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var detail: String {
        switch item.content {
        case .text(let text): ClipFormatting.characterCount(text.count)
        case .link(let url, _): url.host() ?? ""
        case .image(let image): ClipFormatting.imageSize(width: image.width, height: image.height)
        }
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let codeMarkers: [Character] = ["{", "}", ";", "$", "=", "<", ">", "/"]
        let sample = text.prefix(300)
        let hits = sample.filter { codeMarkers.contains($0) }.count
        return hits >= 4 || sample.contains("    ") || sample.contains("\t")
    }

    private var accessibilityText: String {
        let position = position.map { "Posición \($0). " } ?? ""
        let body = item.content.plainText.map { ClipFormatting.preview(of: $0, maxLines: 2) } ?? "Imagen"
        return "\(position)\(item.title ?? item.content.kind.displayName). \(body)"
    }
}
