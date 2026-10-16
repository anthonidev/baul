import BaulCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Guarda imágenes como archivos PNG nombrados por su hash, más una miniatura
/// para las tarjetas. El trabajo de disco y de imagen corre fuera del main actor.
public final class FileImageStore: ImageStore {
    private let imagesDirectory: URL
    private let thumbnailsDirectory: URL
    /// Lado mayor de la miniatura en píxeles (tarjeta de ~220 pt en pantalla Retina).
    private let thumbnailMaxPixels: Int

    public init(directory: URL, thumbnailMaxPixels: Int = 560) throws {
        imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
        thumbnailsDirectory = directory.appending(path: "thumbnails", directoryHint: .isDirectory)
        self.thumbnailMaxPixels = thumbnailMaxPixels
        for url in [imagesDirectory, thumbnailsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func imageURL(for hash: String) -> URL {
        imagesDirectory.appending(path: "\(hash).png")
    }

    public func thumbnailURL(for hash: String) -> URL {
        thumbnailsDirectory.appending(path: "\(hash).png")
    }

    @concurrent
    public func store(png: Data, hash: String) async throws {
        let imageURL = imageURL(for: hash)
        if !FileManager.default.fileExists(atPath: imageURL.path(percentEncoded: false)) {
            try png.write(to: imageURL, options: .atomic)
        }
        let thumbnailURL = thumbnailURL(for: hash)
        if !FileManager.default.fileExists(atPath: thumbnailURL.path(percentEncoded: false)) {
            try writeThumbnail(of: png, to: thumbnailURL)
        }
    }

    @concurrent
    public func remove(hashes: [String]) async {
        for hash in hashes {
            try? FileManager.default.removeItem(at: imageURL(for: hash))
            try? FileManager.default.removeItem(at: thumbnailURL(for: hash))
        }
    }

    @concurrent
    public func totalSize() async -> Int64 {
        [imagesDirectory, thumbnailsDirectory].reduce(into: 0) { total, directory in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            for file in files {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }

    private func writeThumbnail(of png: Data, to url: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
        ]
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ImageStoreError.unreadableImage }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.writeFailed }
    }
}

public enum ImageStoreError: Error {
    case unreadableImage
    case writeFailed
}
