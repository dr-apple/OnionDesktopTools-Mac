import Foundation

/// What is on an SD card, as the Windows tool detects it.
public enum CardState: String, Sendable, Codable {
    case empty = "Empty"
    case onion = "Onion"
    case onionPending = "Onion_InstallPending"
    case stock = "Stock"
    case other = "Other"
    case unreadable = "Unreadable"

    public var title: String {
        switch self {
        case .empty: "Leer"
        case .onion: "Onion OS"
        case .onionPending: "Onion (Installation ausstehend)"
        case .stock: "Miyoo Stock-OS"
        case .other: "Andere Dateien"
        case .unreadable: "Nicht lesbar"
        }
    }
}

public struct CardContent: Sendable, Equatable {
    public var state: CardState
    public var version: String?

    public init(state: CardState, version: String? = nil) {
        self.state = state
        self.version = version
    }

    public var summary: String {
        if let version, !version.isEmpty { return "\(state.title) \(version)" }
        return state.title
    }
}

public enum CardInspector {
    /// Files macOS and Windows put on every volume. They do not make a card "non-empty".
    public static let systemEntries: Set<String> = [
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems", ".DS_Store",
        ".metadata_never_index", ".metadata_never_index_unless_rootfs", "System Volume Information",
        ".VolumeIcon.icns", "._.Trashes", "._.TemporaryItems",
    ]

    public static func isSystemEntry(_ name: String) -> Bool {
        systemEntries.contains(name) || name.hasPrefix("._")
    }

    /// Mirrors Get_SDcardType from the PowerShell tool.
    public static func inspect(root: URL) -> CardContent {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: root.path) else {
            return CardContent(state: .unreadable)
        }
        if items.filter({ !isSystemEntry($0) }).isEmpty { return CardContent(state: .empty) }

        let installUI = root.appending(path: ".tmp_update/bin/installUI")
        if fm.fileExists(atPath: installUI.path) {
            var version = versionFromBinary(installUI)
            if version == nil {
                let txt = root.appending(path: ".tmp_update/onionVersion/version.txt")
                version = (try? String(contentsOf: txt, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return CardContent(state: .onion, version: version)
        }
        if fm.fileExists(atPath: root.appending(path: ".tmp_update").path),
           fm.fileExists(atPath: root.appending(path: "miyoo/app/.tmp_update/onion.pak").path) {
            let version = versionFromBinary(root.appending(path: "miyoo/app/.tmp_update/bin/installUI"))
            return CardContent(state: .onionPending, version: version)
        }
        if fm.fileExists(atPath: root.appending(path: "RApp").path) {
            return CardContent(state: .stock)
        }
        return CardContent(state: .other)
    }

    /// Like `strings installUI | grep --version`: the word after "--version".
    public static func versionFromBinary(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return versionFromStrings(printableRuns(data))
    }

    public static func versionFromStrings(_ text: String) -> String? {
        guard let match = text.firstMatch(of: /--version\s+(\S+)/) else { return nil }
        let value = String(match.1)
        return value.isEmpty ? nil : value
    }

    /// The printable ASCII runs of at least four characters, joined by spaces.
    static func printableRuns(_ data: Data) -> String {
        var runs: [String] = []
        var current: [UInt8] = []
        for byte in data {
            if byte >= 0x20 && byte < 0x7F {
                current.append(byte)
            } else {
                if current.count >= 4 { runs.append(String(decoding: current, as: UTF8.self)) }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 4 { runs.append(String(decoding: current, as: UTF8.self)) }
        return runs.joined(separator: " ")
    }
}
