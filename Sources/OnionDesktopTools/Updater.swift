import AppKit
import CryptoKit
import Foundation
import OnionDesktopToolsKit

/// Keeps the app itself up to date from its GitHub releases.
///
/// Check: the GitHub releases list, at launch and then once a day (Settings > Updates).
/// Install: download the zip, check its SHA-256 (when GitHub lists one), unpack it, check the
/// bundle id, version, and signature, then a small shell script swaps the app bundle after
/// this process quits and opens the new one.
@Observable
final class Updater {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(Double?)
        /// Unpacked and checked, waiting to replace the app.
        case ready
        case failed(String)
    }

    enum Key {
        static let autoCheck = "update.autoCheck"
        static let autoInstall = "update.autoInstall"
        static let prereleases = "update.prereleases"
        static let lastCheck = "update.lastCheck"
        static let skipped = "update.skippedVersion"
    }

    var phase: Phase = .idle
    var release: AppRelease?
    /// The sheet on the main window.
    var showSheet = false
    var lastCheck: Date? = UserDefaults.standard.object(forKey: Key.lastCheck) as? Date
    /// Install the ready update when the app quits (people picked "Beim Beenden").
    var installOnQuit = false

    private var staged: URL?
    private var timer: Task<Void, Never>?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var defaults: UserDefaults { .standard }
    var autoCheck: Bool { defaults.object(forKey: Key.autoCheck) as? Bool ?? true }
    var autoInstall: Bool { defaults.object(forKey: Key.autoInstall) as? Bool ?? false }
    /// On by default: every release so far is a pre-release.
    var includePrereleases: Bool { defaults.object(forKey: Key.prereleases) as? Bool ?? true }

    /// Tests, snapshots, and builds started from a terminal outside an app bundle never update.
    private var isDisabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return Store.isOverridden || env["APP_SNAPSHOT"] != nil || SelfTest.requested
            || Bundle.main.bundleURL.pathExtension != "app"
    }

    // MARK: Checking

    /// Checks at launch (when it is a day since the last check), then every six hours looks again.
    func start() {
        guard !isDisabled, timer == nil else { return }
        timer = Task {
            while !Task.isCancelled {
                if autoCheck, Date.now.timeIntervalSince(lastCheck ?? .distantPast) > 23 * 3600 {
                    await check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check(userInitiated: Bool) async {
        switch phase {
        case .checking, .downloading: return
        case .ready, .available:
            if userInitiated { showSheet = true }
            return
        default: break
        }
        guard !isDisabled || userInitiated else { return }
        phase = .checking
        if userInitiated { showSheet = true }
        do {
            // APP_UPDATE_FEED=<url> points at a test release list (end-to-end update test).
            let feed = ProcessInfo.processInfo.environment["APP_UPDATE_FEED"].flatMap(URL.init(string:)) ?? AppUpdate.listURL
            var request = URLRequest(url: feed)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw AppError("GitHub antwortet mit HTTP \(http.statusCode).")
            }
            let releases = try AppUpdate.parse(data)
            lastCheck = .now
            defaults.set(lastCheck, forKey: Key.lastCheck)
            guard let newest = AppUpdate.newest(in: releases, current: currentVersion, includePrereleases: includePrereleases) else {
                phase = .upToDate
                release = nil
                return
            }
            release = newest
            phase = .available
            if userInitiated { return }
            // Automatic checks stay quiet about a version people chose to skip.
            if defaults.string(forKey: Key.skipped) == newest.version { phase = .idle; return }
            if autoInstall {
                await download()
            } else {
                showSheet = true
            }
        } catch {
            phase = userInitiated ? .failed("Die Suche nach Updates hat nicht geklappt. \(error.localizedDescription)") : .idle
        }
    }

    func skip() {
        if let release { defaults.set(release.version, forKey: Key.skipped) }
        phase = .idle
        showSheet = false
    }

    // MARK: Download and check

    private var updateFolder: URL {
        URL.cachesDirectory.appending(path: "OnionDesktopTools/Update", directoryHint: .isDirectory)
    }

    func download() async {
        guard let release else { return }
        if case .downloading = phase { return }
        phase = .downloading(0)
        let fm = FileManager.default
        let folder = updateFolder
        do {
            try? fm.removeItem(at: folder)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let zip = folder.appending(path: release.fileName)
            let downloader = Downloader(destination: zip) { done, total in
                Task { @MainActor in
                    let updater = Updater.shared
                    if case .downloading = updater.phase { updater.phase = .downloading(total > 0 ? Double(done) / Double(total) : nil) }
                }
            }
            _ = try await downloader.download(release.downloadURL)
            let app = try await offMain { try Self.unpackAndCheck(zip: zip, in: folder, release: release) }
            staged = app
            phase = .ready
            showSheet = true
            // End-to-end test: with a test feed, APP_UPDATE_RESTART=1 presses "Jetzt neu starten".
            let env = ProcessInfo.processInfo.environment
            if env["APP_UPDATE_FEED"] != nil, env["APP_UPDATE_RESTART"] == "1" { installAndRelaunch() }
        } catch {
            phase = .failed("Das Update konnte nicht geladen werden. \(error.localizedDescription)")
            showSheet = true
        }
    }

    /// Returns the checked OnionDesktopTools.app inside `folder`.
    nonisolated static func unpackAndCheck(zip: URL, in folder: URL, release: AppRelease) throws -> URL {
        if let expected = release.sha256 {
            let data = try Data(contentsOf: zip)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw AppError("Die Prüfsumme der geladenen Datei stimmt nicht.") }
        }
        let unpacked = folder.appending(path: "unpacked", directoryHint: .isDirectory)
        let unzip = try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path], separateErrors: true)
        guard unzip.ok else { throw AppError("Entpacken fehlgeschlagen: \(unzip.output)") }
        let app = unpacked.appending(path: "OnionDesktopTools.app", directoryHint: .isDirectory)
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == AppUpdate.bundleID else {
            throw AppError("Im Download steckt keine Onion Desktop Tools-App.")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard version == release.version else {
            throw AppError("Die geladene App hat Version \(version), erwartet war \(release.version).")
        }
        _ = try? Shell.run("/usr/bin/xattr", ["-cr", app.path], separateErrors: true)
        let sign = try Shell.run("/usr/bin/codesign", ["--verify", "--strict", app.path], separateErrors: true)
        guard sign.ok else { throw AppError("Die Signatur der geladenen App ist ungültig.") }
        return app
    }

    // MARK: Install

    /// Where the running app lives, if this user may replace it.
    var installProblem: String? {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else { return "Diese App läuft nicht aus einem App-Paket." }
        let parent = target.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            return "Die App liegt in „\(parent)“, dort darf dein Benutzer nicht schreiben. Lade das Update von GitHub und ersetze die App selbst."
        }
        return nil
    }

    /// Swaps the app after this process ends, then (optionally) opens the new one.
    private func launchSwap(relaunch: Bool) -> Bool {
        guard let staged, installProblem == nil else { return false }
        let target = Bundle.main.bundleURL.path
        let script = """
        pid="$1"; new="$2"; target="$3"; relaunch="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$target.old"
        if mv "$target" "$target.old"; then
          if mv "$new" "$target"; then rm -rf "$target.old"; else mv "$target.old" "$target"; fi
        fi
        [ "$relaunch" = 1 ] && /usr/bin/open "$target"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "swap", "\(ProcessInfo.processInfo.processIdentifier)", staged.path, target, relaunch ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        return true
    }

    func installAndRelaunch() {
        if launchSwap(relaunch: true) {
            installOnQuit = false
            NSApp.terminate(nil)
        } else {
            phase = .failed(installProblem ?? "Das Update konnte nicht gestartet werden.")
        }
    }

    func installLater() {
        installOnQuit = true
        showSheet = false
    }

    /// Called from applicationWillTerminate.
    func installIfPending() {
        guard installOnQuit, phase == .ready else { return }
        installOnQuit = false
        _ = launchSwap(relaunch: false)
    }

    // MARK: Text

    var lastCheckText: String {
        guard let lastCheck else { return "Noch nie gesucht" }
        return "Zuletzt gesucht: \(lastCheck.formatted(date: .abbreviated, time: .shortened))"
    }
}
