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
    // Built-in SD reader.
    #expect(DiskUtil.isCandidate(info: ["VirtualOrPhysical": "Physical", "BusProtocol": "Secure Digital", "Internal": true, "Size": 64_000_000_000]))
}

/// A cheap USB hard disk case that reports removable media, like a card reader (500 GB "Generic DISK02").
@Test func removableHardDiskIsNoCard() {
    let info: [String: Any] = ["VirtualOrPhysical": "Physical", "RemovableMedia": true, "Removable": true, "Internal": false,
                               "BusProtocol": "USB", "MediaName": "Generic DISK02", "Size": 500_107_862_016, "DeviceIdentifier": "disk4"]
    #expect(!DiskUtil.isCandidate(info: info))
    // 256 GB card in a USB reader still shows, and a 512 GB card with the setting on.
    #expect(DiskUtil.isCandidate(info: ["VirtualOrPhysical": "Physical", "RemovableMedia": true, "BusProtocol": "USB", "Size": 255_869_321_216]))
    #expect(DiskUtil.isCandidate(info: ["VirtualOrPhysical": "Physical", "RemovableMedia": true, "BusProtocol": "USB", "Size": 512_110_190_592],
                                 maxSize: DiskUtil.largeMaxCardSize))
}

/// A Samsung USB SSD: ejectable and external, but no removable media. It must never be offered.
@Test func externalSSDIsNoCard() throws {
    let info: [String: Any] = ["VirtualOrPhysical": "Physical", "RemovableMedia": false, "Removable": false,
                               "RemovableMediaOrExternalDevice": true, "Ejectable": true, "Internal": false,
                               "BusProtocol": "USB", "Size": 256_060_514_304, "DeviceIdentifier": "disk6"]
    #expect(!DiskUtil.isCandidate(info: info))
    let list: [String: Any] = ["WholeDisks": ["disk6", "disk7"], "AllDisksAndPartitions": [
        ["DeviceIdentifier": "disk6", "Content": "GUID_partition_scheme", "Size": 256_060_514_304, "Partitions": [
            ["DeviceIdentifier": "disk6s1", "Content": "EFI", "VolumeName": "EFI", "Size": 209_715_200],
            ["DeviceIdentifier": "disk6s2", "Content": "Apple_APFS", "Size": 255_850_758_144]]],
        ["DeviceIdentifier": "disk7", "Content": "FDisk_partition_scheme", "Size": 32_000_000_000, "Partitions": [
            ["DeviceIdentifier": "disk7s1", "Content": "DOS_FAT_32", "VolumeName": "ONION", "MountPoint": "/Volumes/ONION"]]]]]
    let data = try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
    #expect(DiskUtil.hasMacPartitions(listPlist: data, disk: "disk6"))
    #expect(!DiskUtil.hasMacPartitions(listPlist: data, disk: "disk7"))
    // The EFI partition is never taken as the volume.
    #expect(!DiskUtil.partitions(listPlist: data, disk: "disk6").contains { $0.name == "EFI" })
    #expect(DiskUtil.partitions(listPlist: data, disk: "disk7").first?.name == "ONION")
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
