import Foundation
import Testing
@testable import BaulCore

@Suite struct ClipFormattingTests {
    let spanish = Locale(identifier: "es_PE")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `very recent shows now`() {
        #expect(ClipFormatting.relativeTime(now.addingTimeInterval(-10), now: now, locale: spanish) == "ahora")
    }

    @Test func `minutes and days are relative in Spanish`() {
        let minutes = ClipFormatting.relativeTime(now.addingTimeInterval(-5 * 60), now: now, locale: spanish)
        #expect(minutes.hasPrefix("hace 5 min"))

        let yesterday = ClipFormatting.relativeTime(now.addingTimeInterval(-26 * 3_600), now: now, locale: spanish)
        #expect(yesterday == "ayer")

        let days = ClipFormatting.relativeTime(now.addingTimeInterval(-3 * 86_400), now: now, locale: spanish)
        #expect(days.hasPrefix("hace 3 d"))
    }

    @Test func `character count is singular or plural`() {
        #expect(ClipFormatting.characterCount(1, locale: spanish) == "1 carácter")
        #expect(ClipFormatting.characterCount(31, locale: spanish) == "31 caracteres")
    }

    @Test func `preview keeps the first non-empty lines`() {
        let text = "uno\n\n  dos  \ntres\ncuatro"
        #expect(ClipFormatting.preview(of: text, maxLines: 2) == "uno\n  dos")
    }

    @Test func `preview truncates very long text`() {
        let preview = ClipFormatting.preview(of: String(repeating: "a", count: 1_000), maxCharacters: 10)
        #expect(preview == "aaaaaaaaaa…")
    }
}
