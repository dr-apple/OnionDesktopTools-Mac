import AppKit
import Foundation
import OnionDesktopToolsKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case install, migrate, onionSettings, packages, wifi, backup, restore, tools, log, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .install: "Onion installieren"
        case .migrate: "Von Stock umziehen"
        case .onionSettings: "Onion-Einstellungen"
        case .packages: "Emulatoren & Apps"
        case .wifi: "WLAN"
        case .backup: "Sichern"
        case .restore: "Wiederherstellen"
        case .tools: "SD-Karten-Werkzeuge"
        case .log: "Protokoll"
        case .about: "Über"
        }
    }

    var symbol: String {
        switch self {
        case .install: "square.and.arrow.down.on.square"
        case .migrate: "arrow.right.doc.on.clipboard"
        case .onionSettings: "switch.2"
        case .packages: "gamecontroller"
        case .wifi: "wifi"
        case .backup: "externaldrive.badge.timemachine"
        case .restore: "clock.arrow.circlepath"
        case .tools: "sdcard"
        case .log: "text.alignleft"
        case .about: "info.circle"
        }
    }

    static let groups: [(String, [SidebarItem])] = [
        ("Onion", [.install, .migrate]),
        ("Konfiguration", [.onionSettings, .packages, .wifi]),
        ("Daten", [.backup, .restore]),
        ("Weiteres", [.tools, .log, .about]),
    ]
}

/// Where downloads and backups live: ~/Library/Application Support/OnionDesktopTools,
/// or the folder in APP_STORE (tests, snapshots).
enum Store {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var dataDirectory: URL {
        let dir: URL
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            dir = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            dir = URL.applicationSupportDirectory.appending(path: "OnionDesktopTools", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var downloads: URL { folder("Downloads") }
    static var backups: URL { folder("Backups") }

    private static func folder(_ name: String) -> URL {
        let url = dataDirectory.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct LogLine: Identifiable {
    enum Kind { case info, success, error, command }
    let id = UUID()
    let date = Date.now
    let text: String
    let kind: Kind
}

/// A question the app asks before something it cannot undo.
struct Confirmation: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirm: String
    var destructive: Bool = false
    var action: () -> Void
}

/// The running operation, shown in the bar at the bottom of the window.
struct Activity {
    var title: String
    var detail: String = ""
    var fraction: Double?
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    var sidebar: SidebarItem? = .install
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    // SD cards
    var cards: [SDCard] = []
    var selectedCardID: String?
    var content: CardContent?
    var isScanning = false

    var card: SDCard? { cards.first { $0.id == selectedCardID } }
    var root: URL? { card?.mountPoint }

    // Onion releases
    var stable: OnionRelease?
    var beta: OnionRelease?
    var releaseError: String?
    var downloadedZips: [URL] = []
    var selectedZip: URL?

    // Running work
    var activity: Activity?
    var isBusy: Bool { activity != nil }
    var confirmation: Confirmation?
    var errorMessage: String?
    var log: [LogLine] = []
    /// Bumps when files on the card change, so pages reload.
    var cardRevision = 0
    var lastMigrationBackup: URL?

    init() {
        refreshDownloads()
    }

    // MARK: Log

    func note(_ text: String, _ kind: LogLine.Kind = .info) {
        log.append(LogLine(text: text, kind: kind))
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    func fail(_ error: Error, while action: String) {
        if error is CancellationError { note("\(action) abgebrochen."); return }
        let message = error.localizedDescription
        note("\(action) fehlgeschlagen: \(message)", .error)
        errorMessage = "\(action) fehlgeschlagen.\n\n\(message)"
        Sounds.failure()
    }

    // MARK: Cards

    func refreshCards() async {
        isScanning = true
        let found = (try? await offMain { DiskService.listCards() }) ?? []
        cards = found
        if selectedCardID == nil || !found.contains(where: { $0.id == selectedCardID }) {
            selectedCardID = found.first(where: { $0.mountPoint != nil })?.id ?? found.first?.id
        }
        isScanning = false
        await inspectCard()
    }

    func inspectCard() async {
        guard let root else { content = nil; cardRevision += 1; return }
        content = try? await offMain { CardInspector.inspect(root: root) }
        cardRevision += 1
    }

    func select(card id: String?) {
        selectedCardID = id
        Task { await inspectCard() }
    }

    var cardIsReal: Bool { card.map { $0.device != "fake" } ?? false }

    // MARK: Releases

    func refreshDownloads() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Store.downloads, includingPropertiesForKeys: [.creationDateKey])) ?? []
        downloadedZips = files.filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        if selectedZip == nil || !downloadedZips.contains(where: { $0 == selectedZip }) {
            selectedZip = downloadedZips.first { $0.lastPathComponent == stable?.fileName } ?? downloadedZips.first
        }
    }

    func isDownloaded(_ release: OnionRelease) -> Bool {
        let url = Store.downloads.appending(path: release.fileName)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return size == release.size
    }

    func loadReleases() async {
        releaseError = nil
        do {
            var request = URLRequest(url: OnionReleases.latestURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (latest, _) = try await URLSession.shared.data(for: request)
            stable = try OnionReleases.parseLatest(latest)
            request.url = OnionReleases.listURL
            let (list, _) = try await URLSession.shared.data(for: request)
            beta = try OnionReleases.parseBeta(list)
            refreshDownloads()
        } catch {
            releaseError = "Die Onion-Versionen konnten nicht von GitHub geladen werden. Prüfe die Internetverbindung. (\(error.localizedDescription))"
        }
    }

    func download(_ release: OnionRelease) async {
        guard !isBusy else { return }
        activity = Activity(title: "Lade Onion \(release.version) herunter …", fraction: 0)
        note("Download: \(release.downloadURL.absoluteString)", .command)
        let target = Store.downloads.appending(path: release.fileName)
        let downloader = Downloader(destination: target) { done, total in
            Task { @MainActor in
                guard self.activity != nil else { return }
                let size = ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
                self.activity?.detail = size
                self.activity?.fraction = total > 0 ? Double(done) / Double(total) : nil
            }
        }
        do {
            _ = try await downloader.download(release.downloadURL)
            note("Onion \(release.version) heruntergeladen.", .success)
            selectedZip = target
        } catch {
            fail(error, while: "Download")
        }
        activity = nil
        refreshDownloads()
        selectedZip = target
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
