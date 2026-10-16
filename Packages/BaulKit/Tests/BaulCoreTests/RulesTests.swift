import Foundation
import Testing
@testable import BaulCore

@Suite struct LinkDetectorTests {
    @Test(arguments: [
        "https://github.com/groue/GRDB.swift",
        "http://localhost:3000/api",
        "  https://example.com/path?q=1  \n",
        "HTTPS://EXAMPLE.COM",
    ])
    func `detects web links`(text: String) {
        #expect(LinkDetector.url(in: text) != nil)
    }

    @Test(arguments: [
        "hola mundo",
        "mira https://example.com",
        "example.com",
        "ftp://files.example.com",
        "file:///Users/tonis",
        "https://",
        "",
    ])
    func `ignores text that is not just a web link`(text: String) {
        #expect(LinkDetector.url(in: text) == nil)
    }
}

@Suite struct ContentFingerprintTests {
    @Test func `same text gives same fingerprint`() {
        #expect(ContentFingerprint.of(.text("a")) == ContentFingerprint.of(.text("a")))
        #expect(ContentFingerprint.of(.text("a")) != ContentFingerprint.of(.text("b")))
    }

    @Test func `text and image never collide`() {
        let data = Data("a".utf8)
        #expect(ContentFingerprint.of(.text("a")) != ContentFingerprint.of(.image(png: data, width: 1, height: 1)))
    }

    @Test func `sha256 is hex`() {
        #expect(ContentFingerprint.sha256(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@Suite struct RetentionPolicyTests {
    @Test func `cutoff is five days before now`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Lima"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = RetentionPolicy.standard.cutoff(now: now, calendar: calendar)
        #expect(now.timeIntervalSince(cutoff) == 5 * 86_400)
    }
}

@Suite struct BoardEntryTests {
    func entry(content: ClipContent, customText: String?) -> BoardEntry {
        let clip = Clip(
            id: ClipID(rawValue: 1), content: content, contentHash: "h", source: nil,
            byteSize: 1, createdAt: .now, lastCopiedAt: .now
        )
        return BoardEntry(
            id: BoardEntryID(rawValue: 1), boardID: BoardID(rawValue: 1), clip: clip,
            customTitle: nil, customText: customText, sortOrder: 0, addedAt: .now
        )
    }

    @Test func `custom text overrides the original`() {
        #expect(entry(content: .text("original"), customText: "editado").content == .text("editado"))
        #expect(entry(content: .text("original"), customText: nil).content == .text("original"))
    }

    @Test func `editing a link into plain text turns it into text`() throws {
        let url = try #require(URL(string: "https://a.com"))
        #expect(entry(content: .link(url, title: "A"), customText: "ya no es link").content == .text("ya no es link"))
    }
}
