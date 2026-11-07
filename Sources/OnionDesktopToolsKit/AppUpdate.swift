import Foundation

/// A release of this app on GitHub (dr-apple/OnionDesktopTools-Mac).
public struct AppRelease: Sendable, Equatable {
    public var version: String
    public var tag: String
    public var isPrerelease: Bool
    public var fileName: String
    public var size: Int64
    public var downloadURL: URL
    public var pageURL: URL
    /// "sha256:…" from the GitHub API, when GitHub has one for the asset.
    public var digest: String?
    public var notes: String
    public var published: Date?

    public init(version: String, tag: String, isPrerelease: Bool, fileName: String, size: Int64, downloadURL: URL,
                pageURL: URL, digest: String? = nil, notes: String = "", published: Date? = nil) {
        self.version = version
        self.tag = tag
        self.isPrerelease = isPrerelease
        self.fileName = fileName
        self.size = size
        self.downloadURL = downloadURL
        self.pageURL = pageURL
        self.digest = digest
        self.notes = notes
        self.published = published
    }

    /// The SHA-256 hex string from `digest`, if any.
    public var sha256: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        return String(digest.dropFirst(7)).lowercased()
    }
}

public enum AppUpdate {
    public static let repository = "dr-apple/OnionDesktopTools-Mac"
    public static let bundleID = "local.onion.desktoptools"
    public static let listURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browser_download_url: URL
            let digest: String?
        }
        let tag_name: String
        let html_url: URL
        let prerelease: Bool
        let draft: Bool?
        let body: String?
        let published_at: Date?
        let assets: [Asset]
    }

    /// "v0.2.0" -> [0, 2, 0]. Anything after a "-" or "+" is ignored.
    public static func components(_ version: String) -> [Int] {
        var value = version.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        if let cut = value.firstIndex(where: { $0 == "-" || $0 == "+" }) { value = String(value[..<cut]) }
        return value.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// True when `version` is newer than `current` ("0.10.0" is newer than "0.9.1").
    public static func isNewer(_ version: String, than current: String) -> Bool {
        let a = components(version), b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Every release with an app zip, newest version first. Drafts are left out.
    public static func parse(_ data: Data) throws -> [AppRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let all = try decoder.decode([APIRelease].self, from: data)
        let releases: [AppRelease] = all.compactMap { api in
            guard api.draft != true,
                  let asset = api.assets.first(where: { $0.name.hasPrefix("OnionDesktopTools") && $0.name.hasSuffix(".zip") })
            else { return nil }
            var version = api.tag_name
            if version.hasPrefix("v") { version.removeFirst() }
            return AppRelease(version: version, tag: api.tag_name, isPrerelease: api.prerelease, fileName: asset.name,
                              size: asset.size, downloadURL: asset.browser_download_url, pageURL: api.html_url,
                              digest: asset.digest, notes: api.body ?? "", published: api.published_at)
        }
        return releases.sorted { isNewer($0.version, than: $1.version) }
    }

    /// The release to offer, or nil when `current` is up to date.
    public static func newest(in releases: [AppRelease], current: String, includePrereleases: Bool) -> AppRelease? {
        releases.first { (includePrereleases || !$0.isPrerelease) && isNewer($0.version, than: current) }
    }
}
