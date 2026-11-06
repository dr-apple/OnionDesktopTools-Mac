import Foundation
import Testing
@testable import OnionDesktopToolsKit

@Test func versionFromStrings() {
    #expect(CardInspector.versionFromStrings("usage: installUI --version 4.3.1-1 [opts]") == "4.3.1-1")
    #expect(CardInspector.versionFromStrings("nothing here") == nil)
}

@Test func releaseVersion() {
    #expect(OnionReleases.version(fromFileName: "Onion-v4.3.1-1.zip") == "4.3.1-1")
}

@Test func parsesReleases() throws {
    let latest = """
    {"html_url":"https://github.com/OnionUI/Onion/releases/tag/v4.3.1-1","prerelease":false,"body":"notes",
     "published_at":"2024-05-01T10:00:00Z",
     "assets":[{"name":"Onion-v4.3.1-1.zip","size":123,"browser_download_url":"https://example.com/Onion-v4.3.1-1.zip"}]}
    """
    let release = try #require(try OnionReleases.parseLatest(Data(latest.utf8)))
    #expect(release.version == "4.3.1-1")
    #expect(release.size == 123)
    let list = "[{\"html_url\":\"https://x\",\"prerelease\":false,\"assets\":[]},{\"html_url\":\"https://y\",\"prerelease\":true,\"assets\":[{\"name\":\"Onion-v4.4.0-beta.zip\",\"size\":5,\"browser_download_url\":\"https://y/z.zip\"}]}]"
    #expect(try OnionReleases.parseBeta(Data(list.utf8))?.version == "4.4.0-beta")
}

@Test func unzipTotal() {
    let text = """
      Length      Date    Time    Name
    ---------  ---------- -----   ----
          10  01-01-2024 10:00   a
    ---------                     -------
    123456789                     2 files
    """
    #expect(OnionReleases.uncompressedSize(fromUnzipList: text) == 123456789)
}

@Test func copyFilter() {
    let roms = CopyFilter(excludeDirs: ["Imgs"])
    #expect(roms.accepts(file: ["GBA", "game.gba"]))
    #expect(!roms.accepts(file: ["GBA", "Imgs", "game.png"]))
    #expect(!roms.accepts(file: ["GBA", "._game.gba"]))
    let cfg = CopyFilter(includeFiles: ["*.cfg"], maxDepth: 1)
    #expect(cfg.accepts(file: ["retroarch.cfg"]))
    #expect(!cfg.accepts(file: ["config", "x.cfg"]))
    let imgs = CopyFilter(requireDir: "Imgs")
    #expect(imgs.accepts(file: ["GBA", "Imgs", "a.png"]))
    #expect(!imgs.accepts(file: ["GBA", "a.gba"]))
}

@Test func diskCandidates() {
    #expect(DiskUtil.isCandidate(info: ["VirtualOrPhysical": "Physical", "RemovableMedia": true, "Internal": true, "Size": 32_000_000_000]))
    #expect(!DiskUtil.isCandidate(info: ["VirtualOrPhysical": "Physical", "RemovableMedia": false, "Internal": true, "Size": 1_000_000_000_000]))
    #expect(!DiskUtil.isCandidate(info: ["VirtualOrPhysical": "Virtual", "Internal": false, "Size": 1_000]))
}
