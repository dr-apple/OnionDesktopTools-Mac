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

@Test func appVersionOrder() {
    #expect(AppUpdate.isNewer("0.2.0", than: "0.1.0"))
    #expect(AppUpdate.isNewer("v0.10.0", than: "0.9.1"))
    #expect(AppUpdate.isNewer("1.0", than: "0.9.9"))
    #expect(!AppUpdate.isNewer("0.1.0", than: "0.1"))
    #expect(!AppUpdate.isNewer("0.1.0", than: "0.2.0"))
}

@Test func appReleases() throws {
    let json = """
    [{"tag_name":"v0.1.0","html_url":"https://g/1","prerelease":true,"assets":[{"name":"OnionDesktopTools-0.1.0.zip","size":3,"browser_download_url":"https://g/1.zip"}]},
     {"tag_name":"v0.3.0","html_url":"https://g/3","prerelease":false,"draft":true,"assets":[{"name":"OnionDesktopTools-0.3.0.zip","size":3,"browser_download_url":"https://g/3.zip"}]},
     {"tag_name":"v0.2.0","html_url":"https://g/2","prerelease":true,"assets":[{"name":"OnionDesktopTools-0.2.0.zip","size":4,"browser_download_url":"https://g/2.zip","digest":"sha256:ABCD"}]},
     {"tag_name":"v0.1.5","html_url":"https://g/15","prerelease":false,"assets":[{"name":"notes.txt","size":1,"browser_download_url":"https://g/n"}]}]
    """
    let releases = try AppUpdate.parse(Data(json.utf8))
    #expect(releases.map(\.version) == ["0.2.0", "0.1.0"])
    #expect(releases.first?.sha256 == "abcd")
    #expect(AppUpdate.newest(in: releases, current: "0.1.0", includePrereleases: true)?.version == "0.2.0")
    #expect(AppUpdate.newest(in: releases, current: "0.1.0", includePrereleases: false) == nil)
    #expect(AppUpdate.newest(in: releases, current: "0.2.0", includePrereleases: true) == nil)
}
