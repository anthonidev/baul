import Testing
@testable import BaulCore

@Suite struct PasteKeystrokeTests {
    @Test(arguments: ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2"])
    func `images in terminals use control V`(bundleID: String) {
        #expect(PasteKeystroke.forPasting(image: true, into: bundleID) == .controlV)
    }

    @Test(arguments: ["com.mitchellh.ghostty", "dev.zed.Zed"])
    func `text always uses command V`(bundleID: String) {
        #expect(PasteKeystroke.forPasting(image: false, into: bundleID) == .commandV)
    }

    @Test(arguments: ["dev.warp.Warp-Stable", "com.tinyspeck.slackmacgap", "dev.zed.Zed"])
    func `images in other apps use command V`(bundleID: String) {
        #expect(PasteKeystroke.forPasting(image: true, into: bundleID) == .commandV)
    }

    @Test func `unknown frontmost app uses command V`() {
        #expect(PasteKeystroke.forPasting(image: true, into: nil) == .commandV)
    }
}
