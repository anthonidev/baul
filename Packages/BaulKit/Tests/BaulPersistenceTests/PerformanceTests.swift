import BaulCore
import Foundation
import Testing
@testable import BaulPersistence

/// Comprueba que consultar y buscar siga siendo instantáneo con un historial grande.
/// 5.000 elementos es bastante más de lo que se acumula en 5 días de uso normal.
@Suite(.serialized) struct PerformanceTests {
    static let clipCount = 5_000

    func makeStore() async throws -> SQLiteLibraryStore {
        let store = SQLiteLibraryStore(database: try AppDatabase.inMemory())
        let base = Date.now
        for index in 0..<Self.clipCount {
            let text = "elemento \(index) con texto de ejemplo para buscar, token-\(index % 97) en staging"
            _ = try await store.record(NewClip(
                content: .text(text),
                fingerprint: ContentFingerprint.of(.text(text)),
                source: SourceApp(bundleID: "com.apple.Terminal", name: "Terminal"),
                byteSize: text.utf8.count,
                copiedAt: base.addingTimeInterval(-Double(index))
            ))
        }
        return store
    }

    func milliseconds(_ operation: () async throws -> Void) async rethrows -> Double {
        let start = ContinuousClock.now
        try await operation()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1_000
    }

    @Test func `history and search stay fast with thousands of clips`() async throws {
        let store = try await makeStore()

        let listing = try await milliseconds {
            let items = try await store.items(matching: LibraryQuery(limit: 300))
            #expect(items.count == 300)
        }
        let search = try await milliseconds {
            let items = try await store.items(matching: LibraryQuery(text: "token-42 staging", limit: 300))
            #expect(!items.isEmpty)
        }
        let shortSearch = try await milliseconds {
            _ = try await store.items(matching: LibraryQuery(text: "42", limit: 300))
        }

        // Un cuadro de pantalla dura ~16 ms; la consulta debe caber holgadamente.
        #expect(listing < 50, "listado: \(listing) ms")
        #expect(search < 50, "búsqueda: \(search) ms")
        #expect(shortSearch < 100, "búsqueda corta: \(shortSearch) ms")
    }
}
