import AppKit
import Foundation
import OnionDesktopToolsKit

/// The long-running jobs: format, install, backup, restore, packages, Wi-Fi.
extension AppModel {
    private var cleansMacFiles: Bool { UserDefaults.standard.object(forKey: "cleanMacFiles") as? Bool ?? true }

    private func progressHandler() -> @Sendable (CopyProgress) -> Void {
        { progress in
            Task { @MainActor in
                guard self.activity != nil else { return }
                if !progress.title.isEmpty { self.activity?.title = "Kopiere \(progress.title) …" }
                self.activity?.fraction = progress.fraction
                self.activity?.detail = "\(progress.filesDone) von \(progress.filesTotal) Dateien · "
                    + ByteCountFormatter.string(fromByteCount: progress.bytesDone, countStyle: .file)
            }
        }
    }

    private func lineHandler() -> @Sendable (String) -> Void {
        { line in Task { @MainActor in self.note(line, .command) } }
    }

    /// Runs `work` as the one current activity, with errors shown in an alert.
    func perform(_ title: String, _ work: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        activity = Activity(title: title)
        note(title)
        Task {
            do { try await work() } catch { fail(error, while: title.replacingOccurrences(of: " …", with: "")) }
            activity = nil
            await inspectCard()
        }
    }

    // MARK: Format

    func confirmFormat() {
        guard let card else { return }
        let content = content?.summary ?? "unbekannt"
        confirmation = Confirmation(
            title: "„\(card.displayName)“ formatieren?",
            message: "Inhalt: \(content)\nGerät: /dev/\(card.device)\n\nDie ganze Karte wird als FAT32 mit dem Namen ONION neu angelegt. Alles auf der Karte wird gelöscht. Sichere vorher, was du behalten willst.",
            confirm: "Formatieren", destructive: true) { [weak self] in
            self?.perform("Formatiere SD-Karte …") { try await self?.format() }
        }
    }

    /// Erases the selected card and waits for it to mount again.
    func format() async throws {
        guard let card else { throw AppError("Keine SD-Karte ausgewählt.") }
        guard card.device != "fake" else { throw AppError("Die Test-Karte kann nicht formatiert werden.") }
        activity?.title = "Formatiere \(card.displayName) …"
        let device = card.device
        let onLine = lineHandler()
        try await offMain { try DiskService.formatFAT32(device: device, onLine: onLine) }
        note("Formatiert als FAT32 (ONION).", .success)
        activity?.title = "Warte auf die Karte …"
        for _ in 0..<20 {
            await refreshCards()
            if let fresh = cards.first(where: { $0.device == device }), let mount = fresh.mountPoint {
                selectedCardID = device
                MacJunk.preventIndexing(root: mount)
                await inspectCard()
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw AppError("Die Karte wurde formatiert, ist aber nicht wieder erschienen. Ziehe sie ab und stecke sie neu ein.")
    }

    // MARK: Install

    func installMessage(zip: String, formatting: Bool) -> String {
        if formatting {
            return "Die Karte wird formatiert (alles wird gelöscht) und \(zip) wird installiert."
        }
        let version = content?.version ?? ""
        switch content?.state {
        case .empty: return "\(zip) wird auf die leere Karte installiert."
        case .onion: return "Onion \(version) wird auf \(zip) aktualisiert.\n\nSpielstände, Roms und Einstellungen bleiben erhalten."
        case .onionPending: return "Auf der Karte liegt schon eine noch nicht gestartete Onion-Installation (\(version)). Sie wird mit \(zip) überschrieben.\n\nWenn die Karte sonst keine Daten enthält, ist Formatieren und neu Installieren die bessere Wahl."
        case .stock: return "Auf der Karte ist das Stock-OS von Miyoo. Onion darüber zu installieren wird nicht empfohlen und kann Probleme machen.\n\nBesser: eine neue Karte nehmen und „Von Stock umziehen“ verwenden.\n\nTrotzdem installieren?"
        case .other: return "Die Karte enthält schon andere Dateien. Onion darauf zu installieren geht, wird aber nicht empfohlen. Wenn nichts Wichtiges darauf ist, formatiere die Karte besser vorher.\n\nTrotzdem installieren?"
        default: return "\(zip) wird auf die Karte installiert."
        }
    }

    func confirmInstall(formatting: Bool) {
        guard let zip = selectedZip, card != nil else { return }
        let risky = formatting || content?.state == .stock || content?.state == .other
        confirmation = Confirmation(
            title: formatting ? "Formatieren und Onion installieren?" : "Onion installieren?",
            message: installMessage(zip: zip.lastPathComponent, formatting: formatting),
            confirm: formatting ? "Formatieren und installieren" : "Installieren", destructive: risky) { [weak self] in
            self?.perform("Installiere Onion …") {
                if formatting { try await self?.format() }
                try await self?.extract(zip)
            }
        }
    }

    /// Unzips an Onion release onto the card, like 7z x -aoa on Windows.
    func extract(_ zip: URL, askToEject: Bool = true) async throws {
        guard let root else { throw AppError("Die Karte ist nicht verbunden.") }
        if let card, card.mountPoint != nil, !card.isFAT32, card.device != "fake" {
            note("Achtung: Dateisystem \(card.fileSystem ?? "?") – Onion braucht FAT32.", .error)
        }
        let listing = try await offMain { try Shell.run("/usr/bin/unzip", ["-l", zip.path]) }
        guard listing.ok else { throw AppError("Die ZIP-Datei ist beschädigt. Lösche sie und lade sie neu herunter.") }
        let needed = OnionReleases.uncompressedSize(fromUnzipList: listing.output) ?? 0
        let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
        if let free, needed > free {
            throw AppError("Nicht genug Platz: gebraucht \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), frei \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)).")
        }
        let total = max(1, listing.output.split(separator: "\n").count - 5)
        activity = Activity(title: "Entpacke \(zip.lastPathComponent) …", fraction: 0)
        MacJunk.preventIndexing(root: root)
        let counter = Counter()
        let result = try await offMain {
            try Shell.run("/usr/bin/unzip", ["-o", zip.path, "-d", root.path]) { _ in
                let done = counter.increment()
                if done % 25 == 0 {
                    Task { @MainActor in
                        self.activity?.fraction = min(1, Double(done) / Double(total))
                        self.activity?.detail = "\(done) von \(total) Dateien"
                    }
                }
            }
        }
        guard result.ok else {
            note(String(result.output.suffix(800)), .command)
            throw AppError("Beim Entpacken ist etwas schiefgegangen (unzip \(result.status)). Versuche es erneut oder formatiere die Karte.")
        }
        // unzip on macOS leaves a "._" file next to every file on FAT32. Always remove them.
        let removed = try await offMain { () -> Int in
            try? FileManager.default.removeItem(at: root.appending(path: "__MACOSX"))
            return MacJunk.clean(root: root)
        }
        note("\(removed) macOS-Hilfsdateien entfernt.")
        note("Onion entpackt. Lege die Karte in die Konsole und schalte sie ein, um die Installation abzuschließen.", .success)
        Sounds.success()
        if askToEject { offerEject(message: "Onion ist auf der Karte. Wirf sie aus, stecke sie in den Miyoo Mini und schalte ihn ein – die Installation läuft dann auf der Konsole.") }
    }

    // MARK: Backup and restore

    func backup(parts: Set<BackupPart>, description: String) async throws -> URL {
        guard let root, let content else { throw AppError("Keine SD-Karte ausgewählt.") }
        let parts = parts.intersection(BackupPart.available(for: content.state))
        guard !parts.isEmpty else { throw AppError("Diese Karte enthält nichts, was gesichert werden kann.") }
        let date = Date.now
        let folder = Store.backups.appending(path: BackupPlanner.folderName(date: date, content: content), directoryHint: .isDirectory)
        try BackupPlanner.writeInfo(folder: folder, date: date, content: content, description: description)
        let jobs = BackupPlanner.backupJobs(card: root, state: content.state, parts: parts, into: folder)
        activity = Activity(title: "Sichere …", fraction: 0)
        let handler = progressHandler()
        let count = try await offMain { try FileCopier.run(jobs, progress: handler) }
        note("Sicherung fertig: \(count) Dateien in „\(folder.lastPathComponent)“.", .success)
        Sounds.success()
        return folder
    }

    func restore(_ backup: URL, parts: Set<BackupPart>) async throws {
        guard let root else { throw AppError("Keine SD-Karte ausgewählt.") }
        let jobs = BackupPlanner.restoreJobs(backup: backup, parts: parts, card: root)
        activity = Activity(title: "Stelle wieder her …", fraction: 0)
        let handler = progressHandler()
        let count = try await offMain { try FileCopier.run(jobs, progress: handler) }
        if cleansMacFiles { MacJunk.clean(root: root) }
        note("Wiederhergestellt: \(count) Dateien aus „\(backup.lastPathComponent)“.", .success)
        Sounds.success()
    }

    // MARK: Packages

    func install(_ packages: [OnionPackage]) async throws {
        guard let root else { return }
        let jobs = packages.map { PackageManager.installJob($0, root: root) }
        activity = Activity(title: "Installiere \(packages.count) Pakete …", fraction: 0)
        let handler = progressHandler()
        _ = try await offMain { try FileCopier.run(jobs, progress: handler) }
        if cleansMacFiles { MacJunk.clean(root: root) }
        note("Installiert: \(packages.map(\.name).joined(separator: ", "))", .success)
    }

    func uninstall(_ packages: [OnionPackage]) async throws {
        guard let root else { return }
        for package in packages { try PackageManager.uninstall(package, root: root) }
        note("Entfernt: \(packages.map(\.name).joined(separator: ", "))", .success)
    }

    // MARK: Tools

    func cleanMacFiles() {
        guard let root else { return }
        perform("Entferne macOS-Hilfsdateien …") {
            let removed = try await offMain { () -> Int in
                MacJunk.preventIndexing(root: root)
                return MacJunk.clean(root: root)
            }
            self.note("\(removed) macOS-Hilfsdateien (._* und .DS_Store) entfernt.", .success)
        }
    }

    func checkDisk(repair: Bool) {
        guard let card, let volume = card.volumeDevice, card.device != "fake" else { return }
        let verb = repair ? "repairVolume" : "verifyVolume"
        perform(repair ? "Repariere Dateisystem …" : "Prüfe Dateisystem …") {
            let onLine = self.lineHandler()
            let result = try await offMain { try Shell.run(DiskService.diskutil, [verb, volume], onLine: onLine) }
            if result.ok {
                self.note(repair ? "Reparatur abgeschlossen." : "Keine Fehler gefunden.", .success)
                Sounds.success()
            } else {
                throw AppError(repair ? "Die Reparatur hat Fehler gemeldet. Details im Protokoll." : "Es wurden Fehler gefunden. Versuche „Reparieren“. Details im Protokoll.")
            }
            await self.refreshCards()
        }
    }

    func eject() {
        guard let card, card.device != "fake" else { return }
        let device = card.device
        perform("Werfe SD-Karte aus …") {
            if let root = self.root, self.cleansMacFiles { _ = try? await offMain { MacJunk.clean(root: root) } }
            _ = try await offMain { try DiskService.eject(device: device) }
            self.note("Karte ausgeworfen. Du kannst sie jetzt abziehen.", .success)
            await self.refreshCards()
        }
    }

    func offerEject(message: String) {
        guard cardIsReal else { return }
        confirmation = Confirmation(title: "Fertig!", message: message, confirm: "Auswerfen") { [weak self] in
            self?.eject()
        }
    }
}

/// A thread-safe counter for progress from background lines.
nonisolated final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int { lock.withLock { value += 1; return value } }
}
