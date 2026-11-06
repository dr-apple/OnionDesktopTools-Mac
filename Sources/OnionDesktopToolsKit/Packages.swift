import Foundation

/// An emulator or app from Onion's package manager (App/PackageManager/data/<Type>/<Name>).
public struct OnionPackage: Sendable, Identifiable, Hashable {
    public enum Kind: String, CaseIterable, Sendable {
        case emu = "Emu", app = "App", rapp = "RApp"
        public var title: String {
            switch self {
            case .emu: "Emulator"
            case .app: "App"
            case .rapp: "RetroArch-Kern"
            }
        }
    }

    public enum Status: Int, Sendable, Comparable {
        /// Roms are on the card but the emulator is missing.
        case romsPresent = 0
        case notInstalled = 1
        case installed = 2
        public static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .installed: "Installiert"
            case .romsPresent: "Roms vorhanden"
            case .notInstalled: "Nicht installiert"
            }
        }
    }

    public var name: String
    public var kind: Kind
    /// The folder it installs to, e.g. Emu/GBA.
    public var folder: String
    /// The rom folder it uses, e.g. GBA.
    public var romFolder: String?
    public var romCount: Int
    public var status: Status
    public var id: String { "\(kind.rawValue)/\(name)/\(folder)" }
}

public enum PackageManager {
    public static func dataURL(root: URL, kind: OnionPackage.Kind) -> URL {
        root.appending(path: "App/PackageManager/data/\(kind.rawValue)")
    }

    static func subfolders(_ url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !CardInspector.isSystemEntry($0.lastPathComponent) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func gameCount(_ url: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { !CardInspector.isSystemEntry($0) && $0 != "Imgs" && !$0.hasSuffix(".db") }.count
    }

    public static func scan(root: URL) -> [OnionPackage] {
        let fm = FileManager.default
        var result: [OnionPackage] = []
        for kind in OnionPackage.Kind.allCases {
            for pack in subfolders(dataURL(root: root, kind: kind)) {
                let romDirs = subfolders(pack.appending(path: "Roms"))
                let romFolder = romDirs.last?.lastPathComponent
                for content in subfolders(pack.appending(path: kind.rawValue)) where content.lastPathComponent != "romscripts" {
                    let folder = "\(kind.rawValue)/\(content.lastPathComponent)"
                    let installed = fm.fileExists(atPath: root.appending(path: folder).path)
                    let roms = romFolder.map { gameCount(root.appending(path: "Roms/\($0)")) } ?? 0
                    let status: OnionPackage.Status = installed ? .installed : (roms > 0 ? .romsPresent : .notInstalled)
                    result.append(OnionPackage(name: pack.lastPathComponent, kind: kind, folder: folder,
                                               romFolder: romFolder, romCount: roms, status: status))
                }
            }
        }
        return result
    }

    /// Copies the package's content (Emu/, App/, Roms/, BIOS/ ...) to the card root.
    public static func installJob(_ package: OnionPackage, root: URL) -> CopyJob {
        CopyJob(source: dataURL(root: root, kind: package.kind).appending(path: package.name),
                destination: root, title: package.name)
    }

    /// Removes the installed folder. Roms stay.
    public static func uninstall(_ package: OnionPackage, root: URL) throws {
        let url = root.appending(path: package.folder)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// Wi-Fi setup for Onion: a one-shot script that adds the network to
/// /appconfigs/wpa_supplicant.conf at the next boot, then restores runtime.sh.
public enum WifiSetup {
    public enum Problem: Error, Equatable, LocalizedError {
        case notOnion, emptySSID, invalidCharacters
        public var errorDescription: String? {
            switch self {
            case .notOnion: "Auf dieser Karte ist kein gestartetes Onion. Lege die Karte einmal in die Konsole und starte sie, dann versuche es erneut."
            case .emptySSID: "Bitte gib den Namen des WLANs ein."
            case .invalidCharacters: "Name und Passwort dürfen keine Anführungszeichen und keine Zeilenumbrüche enthalten."
            }
        }
    }

    public static func script(ssid: String, password: String) -> String {
        """
        #!/bin/sh
        killall -9 main
        killall -9 updater
        if [ ! -f /appconfigs/wpa_supplicant.conf ]; then
            echo "ctrl_interface=/var/run/wpa_supplicant" > /appconfigs/wpa_supplicant.conf
            echo "update_config=1" >> /appconfigs/wpa_supplicant.conf
        fi
        cat >> /appconfigs/wpa_supplicant.conf <<'ODT_EOF'

        network={
                ssid="\(ssid)"
                psk="\(password)"
        }
        ODT_EOF
        mv "/mnt/SDCARD/.tmp_update/runtime_ori.sh" "/mnt/SDCARD/.tmp_update/runtime.sh"
        /mnt/SDCARD/.tmp_update/runtime.sh

        """
    }

    public static func validate(ssid: String, password: String) throws {
        if ssid.trimmingCharacters(in: .whitespaces).isEmpty { throw Problem.emptySSID }
        if (ssid + password).contains(where: { $0 == "\"" || $0.isNewline }) { throw Problem.invalidCharacters }
    }

    /// True when a Wi-Fi setup waits for the next boot.
    public static func isPending(root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: ".tmp_update/runtime_ori.sh").path)
    }

    public static func write(ssid: String, password: String, root: URL) throws {
        try validate(ssid: ssid, password: password)
        let fm = FileManager.default
        let runtime = root.appending(path: ".tmp_update/runtime.sh")
        let original = root.appending(path: ".tmp_update/runtime_ori.sh")
        guard fm.fileExists(atPath: runtime.path) else { throw Problem.notOnion }
        if !fm.fileExists(atPath: original.path) { try fm.moveItem(at: runtime, to: original) }
        try Data(script(ssid: ssid, password: password).utf8).write(to: runtime)
    }
}
