import BaulCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BaulPersistence

@Suite struct FileImageStoreTests {
    let directory: URL
    let store: FileImageStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "baul tests \(UUID().uuidString)")
        store = try FileImageStore(directory: directory, thumbnailMaxPixels: 50)
    }

    /// PNG sólido generado en memoria.
    func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func pixelSize(of url: URL) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test func `stores the image and a scaled-down thumbnail`() async throws {
        let png = try makePNG(width: 400, height: 200)
        let hash = ContentFingerprint.sha256(png)

        try await store.store(png: png, hash: hash)

        #expect(try Data(contentsOf: store.imageURL(for: hash)) == png)
        let (width, height) = try pixelSize(of: store.thumbnailURL(for: hash))
        #expect(width == 50)
        #expect(height == 25)
        #expect(await store.totalSize() > 0)
    }

    @Test func `remove deletes both files`() async throws {
        let png = try makePNG(width: 10, height: 10)
        try await store.store(png: png, hash: "h")
        await store.remove(hashes: ["h"])
        #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: "h").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(for: "h").path(percentEncoded: false)))
    }

    @Test func `invalid data throws`() async {
        await #expect(throws: ImageStoreError.self) {
            try await store.store(png: Data("no soy una imagen".utf8), hash: "bad")
        }
    }
}
