import Foundation
import LinkPresentation

/// Obtiene el título de una página para mostrarlo en la tarjeta de un link.
public enum LinkTitleFetcher {
    public static func title(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        provider.shouldFetchSubresources = false
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            return metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } catch {
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
