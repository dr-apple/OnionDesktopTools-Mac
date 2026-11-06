import AppKit
import Foundation
import OnionDesktopToolsKit

/// Finds SD cards and runs diskutil. Every function here blocks: call from a background task.
nonisolated enum DiskService {
    static let diskutil = "/usr/sbin/diskutil"

    nonisolated static func listCards() -> [SDCard] {
        var cards: [SDCard] = []
        if let fake = ProcessInfo.processInfo.environment["APP_FAKE_CARD"], !fake.isEmpty {
            let url = URL(fileURLWithPath: fake, isDirectory: true)
            let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
            cards.append(SDCard(device: "fake", mediaName: "Test-Karte", size: 32_000_000_000, mountPoint: url,
                                volumeName: "ONION", fileSystem: "MS-DOS (FAT32)", freeSpace: free ?? 20_000_000_000))
        }
        guard let list = try? Shell.run(diskutil, ["list", "-plist", "physical"], separateErrors: true), list.ok else { return cards }
        for disk in DiskUtil.wholeDisks(listPlist: list.data) {
            guard let infoRun = try? Shell.run(diskutil, ["info", "-plist", disk], separateErrors: true) else { continue }
            let info = DiskUtil.plist(infoRun.data)
            guard DiskUtil.isCandidate(info: info) else { continue }
            let size = (info["Size"] as? Int64) ?? Int64((info["Size"] as? Int) ?? 0)
            var card = SDCard(device: disk, mediaName: (info["MediaName"] as? String) ?? disk, size: size,
                              isInternalReader: (info["Internal"] as? Bool) == true)
            let parts = DiskUtil.partitions(listPlist: list.data, disk: disk)
            if let part = parts.first(where: { $0.mount != nil }) ?? parts.first(where: { $0.device != disk }) {
                card.volumeDevice = part.device
                card.volumeName = part.name
                if let mount = part.mount {
                    let url = URL(fileURLWithPath: mount, isDirectory: true)
                    card.mountPoint = url
                    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey])
                    card.freeSpace = values?.volumeAvailableCapacity.map(Int64.init)
                    card.fileSystem = values?.volumeLocalizedFormatDescription
                }
            }
            cards.append(card)
        }
        return cards
    }

    /// Erases the whole disk as one FAT32 partition named ONION (MBR), like RMPARTUSB on Windows.
    nonisolated static func formatFAT32(device: String, onLine: @escaping @Sendable (String) -> Void) throws {
        precondition(device.hasPrefix("disk") && device != "disk0" && device != "disk1", "refusing to format \(device)")
        let args = ["eraseDisk", "FAT32", "ONION", "MBRFormat", "/dev/\(device)"]
        let result = try Shell.run(diskutil, args, onLine: onLine)
        if result.ok { return }
        // Some readers need admin rights. Ask macOS for the password.
        onLine("diskutil braucht Administratorrechte, frage nach dem Passwort …")
        let command = ([diskutil] + args).map(Shell.quote).joined(separator: " ")
        let script = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let admin = try Shell.run("/usr/bin/osascript", ["-e", script], onLine: onLine)
        if !admin.ok { throw AppError("Formatieren fehlgeschlagen.\n\(result.output.suffix(400))") }
    }

    nonisolated static func eject(device: String) throws {
        let result = try Shell.run(diskutil, ["eject", device])
        if !result.ok { throw AppError("Auswerfen fehlgeschlagen: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))\nSchließe Fenster und Programme, die Dateien von der Karte geöffnet haben.") }
    }
}

nonisolated struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Downloads a file with progress.
nonisolated final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private let destination: URL

    init(destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw AppError("Download fehlgeschlagen (HTTP \(http.statusCode)).")
            }
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

enum Sounds {
    static func success() {
        guard UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true else { return }
        NSSound(named: "Glass")?.play()
    }

    static func failure() {
        guard UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true else { return }
        NSSound(named: "Basso")?.play()
    }
}

/// Runs blocking work off the main thread.
func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated) { try work() }.value
}
