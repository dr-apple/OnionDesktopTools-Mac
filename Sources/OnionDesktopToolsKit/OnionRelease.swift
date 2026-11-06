import Foundation

/// One Onion release zip on GitHub (OnionUI/Onion).
public struct OnionRelease: Sendable, Equatable, Identifiable {
    public enum Channel: String, Sendable { case stable, beta }

    public var channel: Channel
    public var version: String
    public var fileName: String
    public var size: Int64
    public var downloadURL: URL
    public var pageURL: URL
    public var notes: String
    public var published: Date?

    public var id: String { fileName }

    public init(channel: Channel, version: String, fileName: String, size: Int64,
                downloadURL: URL, pageURL: URL, notes: String = "", published: Date? = nil) {
        self.channel = channel
        self.version = version
        self.fileName = fileName
        self.size = size
        self.downloadURL = downloadURL
        self.pageURL = pageURL
        self.notes = notes
        self.published = published
    }
}

public enum OnionReleases {
    public static let repository = "OnionUI/Onion"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let listURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!

    struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browser_download_url: URL
        }
        let html_url: URL
        let prerelease: Bool
        let draft: Bool?
        let body: String?
        let published_at: Date?
        let assets: [Asset]
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// "Onion-v4.3.1-1.zip" -> "4.3.1-1"
    public static func version(fromFileName name: String) -> String {
        var value = name
        if let range = value.range(of: "Onion-v") { value = String(value[range.upperBound...]) }
        if value.hasSuffix(".zip") { value.removeLast(4) }
        return value
    }

    static func release(from api: APIRelease, channel: OnionRelease.Channel) -> OnionRelease? {
        guard let asset = api.assets.first(where: { $0.name.contains("Onion-v") && $0.name.hasSuffix(".zip") })
        else { return nil }
        return OnionRelease(channel: channel, version: version(fromFileName: asset.name), fileName: asset.name,
                            size: asset.size, downloadURL: asset.browser_download_url, pageURL: api.html_url,
                            notes: api.body ?? "", published: api.published_at)
    }

    /// The latest stable release from /releases/latest.
    public static func parseLatest(_ data: Data) throws -> OnionRelease? {
        release(from: try decoder.decode(APIRelease.self, from: data), channel: .stable)
    }

    /// The newest pre-release from /releases.
    public static func parseBeta(_ data: Data) throws -> OnionRelease? {
        let all = try decoder.decode([APIRelease].self, from: data)
        guard let beta = all.first(where: { $0.prerelease && $0.draft != true }) else { return nil }
        return release(from: beta, channel: .beta)
    }

    /// Total uncompressed size from the last line of `unzip -l`.
    public static func uncompressedSize(fromUnzipList text: String) -> Int64? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = lines.last, let first = last.split(separator: " ").first else { return nil }
        return Int64(first)
    }
}
