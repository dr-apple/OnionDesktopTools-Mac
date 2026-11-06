import Foundation

/// The parts of a card that can be backed up and restored.
public enum BackupPart: String, CaseIterable, Sendable, Identifiable {
    case roms, imgs, saves, retroarch, bios, configFlags

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .roms: "Roms"
        case .imgs: "Bilder (Boxarts)"
        case .saves: "Spielstände"
        case .retroarch: "RetroArch-Konfiguration"
        case .bios: "BIOS"
        case .configFlags: "Onion-Einstellungen"
        }
    }

    public var symbol: String {
        switch self {
        case .roms: "gamecontroller"
        case .imgs: "photo"
        case .saves: "externaldrive.badge.checkmark"
        case .retroarch: "slider.horizontal.3"
        case .bios: "cpu"
        case .configFlags: "switch.2"
        }
    }

    /// Which parts a card in this state can give. Matches the Windows tool.
    public static func available(for state: CardState) -> Set<BackupPart> {
        switch state {
        case .onion, .onionPending: Set(allCases)
        case .stock: [.roms, .imgs, .bios]
        default: []
        }
    }

    /// The folder inside a backup that holds this part.
    public var backupFolder: String {
        switch self {
        case .roms, .imgs: "Roms"
        case .saves: "Saves"
        case .retroarch: "RetroArch/.retroarch"
        case .bios: "BIOS"
        case .configFlags: ".tmp_update/config"
        }
    }
}

public struct BackupInfo: Sendable, Identifiable, Hashable {
    public var folder: URL
    public var name: String { folder.lastPathComponent }
    public var description: String
    public var source: String
    public var date: Date?
    public var parts: Set<BackupPart>
    public var id: URL { folder }
}

public enum BackupPlanner {
    static let stockBiosExcludes: Set<String> = ["cheats", "cheats备用版", "GLupeN64", "Mupen64plus", "pscnbios"]

    /// "2024-05-01 18.30.12_Onion_4.3.1"
    public static func folderName(date: Date, content: CardContent) -> String {
        let format = Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                                              timeZone: .current, calendar: .current)
        let version = (content.version?.isEmpty == false ? content.version! : "(unknown version)")
            .replacingOccurrences(of: "/", with: "-")
        return "\(date.formatted(format))_\(content.state.rawValue)_\(version)"
    }

    /// Copy jobs for a backup of `card` into `folder`.
    public static func backupJobs(card root: URL, state: CardState, parts: Set<BackupPart>, into folder: URL) -> [CopyJob] {
        let fm = FileManager.default
        var jobs: [CopyJob] = []
        let isStock = state == .stock
        let roms = root.appending(path: "Roms")
        if parts.contains(.roms) {
            jobs.append(CopyJob(source: roms, destination: folder.appending(path: "Roms"),
                                filter: CopyFilter(excludeDirs: ["Imgs"]), title: "Roms"))
        }
        if parts.contains(.imgs) {
            if isStock {
                // Stock keeps images in /Imgs/<System>; Onion wants /Roms/<System>/Imgs.
                let imgs = root.appending(path: "Imgs")
                let systems = (try? fm.contentsOfDirectory(at: imgs, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for system in systems where (try? system.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    jobs.append(CopyJob(source: system,
                                        destination: folder.appending(path: "Roms/\(system.lastPathComponent)/Imgs"),
                                        filter: CopyFilter(includeFiles: ["*.png"]), title: "Bilder: \(system.lastPathComponent)"))
                }
            }
            jobs.append(CopyJob(source: roms, destination: folder.appending(path: "Roms"),
                                filter: CopyFilter(includeFiles: ["*.png"]), title: "Bilder"))
        }
        if parts.contains(.saves), !isStock {
            jobs.append(CopyJob(source: root.appending(path: "Saves"), destination: folder.appending(path: "Saves"), title: "Spielstände"))
        }
        if parts.contains(.bios) {
            if isStock {
                jobs.append(CopyJob(source: root.appending(path: "RetroArch/.retroarch/system"),
                                    destination: folder.appending(path: "BIOS"),
                                    filter: CopyFilter(excludeDirs: stockBiosExcludes, excludePaths: ["scummvm"],
                                                       excludeFiles: ["scph39*"]),
                                    title: "BIOS"))
            } else {
                jobs.append(CopyJob(source: root.appending(path: "BIOS"), destination: folder.appending(path: "BIOS"), title: "BIOS"))
            }
        }
        if parts.contains(.retroarch), !isStock {
            jobs.append(CopyJob(source: root.appending(path: "RetroArch/.retroarch"),
                                destination: folder.appending(path: "RetroArch/.retroarch"),
                                filter: CopyFilter(includeFiles: ["*.cfg"], maxDepth: 1), title: "RetroArch-Konfiguration"))
        }
        if parts.contains(.configFlags), !isStock {
            jobs.append(CopyJob(source: root.appending(path: OnionFlags.configPath),
                                destination: folder.appending(path: OnionFlags.configPath),
                                filter: CopyFilter(includeFiles: [".*"]), title: "Onion-Einstellungen"))
        }
        return jobs
    }

    /// Copy jobs to put a backup back on a card.
    public static func restoreJobs(backup folder: URL, parts: Set<BackupPart>, card root: URL) -> [CopyJob] {
        var jobs: [CopyJob] = []
        for part in BackupPart.allCases where parts.contains(part) {
            let source = folder.appending(path: part.backupFolder)
            let target = root.appending(path: part.backupFolder)
            switch part {
            case .roms:
                jobs.append(CopyJob(source: source, destination: target, filter: CopyFilter(excludeDirs: ["Imgs"]), title: part.title))
            case .imgs:
                jobs.append(CopyJob(source: source, destination: target, filter: CopyFilter(requireDir: "Imgs"), title: part.title))
            default:
                jobs.append(CopyJob(source: source, destination: target, title: part.title))
            }
        }
        return jobs
    }

    public static func infoText(date: Date, content: CardContent, description: String) -> String {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.space))
        return "Date: \(stamp)\r\nSource: \(content.state.rawValue) \(content.version ?? "")\r\nDescription:\r\n\(description)"
    }

    public static func writeInfo(folder: URL, date: Date, content: CardContent, description: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "Backupinfo_\(folder.lastPathComponent.prefix(19).replacingOccurrences(of: " ", with: "_")).txt"
        try infoText(date: date, content: content, description: description)
            .write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
    }

    /// Backups in `directory`, newest first.
    public static func list(in directory: URL) -> [BackupInfo] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey])) ?? []
        return folders.compactMap { folder -> BackupInfo? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            var info = BackupInfo(folder: folder, description: "", source: "",
                                  date: try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate, parts: [])
            if let file = (try? fm.contentsOfDirectory(atPath: folder.path))?.first(where: { $0.hasPrefix("Backupinfo_") }),
               let text = try? String(contentsOf: folder.appending(path: file), encoding: .utf8) {
                let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                info.source = lines.first { $0.hasPrefix("Source:") }.map { String($0.dropFirst(7)).trimmingCharacters(in: .whitespaces) } ?? ""
                if let index = lines.firstIndex(of: "Description:") {
                    info.description = lines[(index + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            for part in BackupPart.allCases where fm.fileExists(atPath: folder.appending(path: part.backupFolder).path) {
                info.parts.insert(part)
            }
            return info
        }
        .sorted { $0.name > $1.name }
    }
}
