import Foundation

/// Onion's on/off settings are empty marker files in .tmp_update/config.
/// "name" means on, "name_" (or no file) means off. Same list as config.json in the Windows tool.
public struct OnionFlag: Sendable, Identifiable, Hashable {
    public let file: String
    public let title: String
    public let help: String
    /// Indented under the option before it (e.g. authentication for a server).
    public let isSubOption: Bool
    public var id: String { file }
}

public struct OnionFlagSection: Sendable, Identifiable {
    public let title: String
    public let flags: [OnionFlag]
    public var id: String { title }
}

public enum OnionFlags {
    public static let configPath = ".tmp_update/config"

    public static let sections: [OnionFlagSection] = [
        OnionFlagSection(title: "System", flags: [
            OnionFlag(file: ".noAutoStart", title: "Letztes Spiel nicht automatisch fortsetzen",
                      help: "Beim Start wird immer die normale Oberfläche gezeigt statt das letzte Spiel fortzusetzen.", isSubOption: false),
            OnionFlag(file: ".disableStandby", title: "Ausschalten mit einem Druck auf die Power-Taste",
                      help: "Ein kurzer Druck schaltet die Konsole aus. Ohne diese Option startet er den Standby.", isSubOption: false),
            OnionFlag(file: ".noMenuHaptics", title: "Vibration der Menü-Taste ausschalten",
                      help: "Die Menü-Taste vibriert nicht mehr.", isSubOption: false),
            OnionFlag(file: ".noLowBatteryAutoSave", title: "Kein automatisches Speichern bei schwachem Akku",
                      help: "Die Konsole speichert und beendet nicht automatisch, wenn der Akku fast leer ist.", isSubOption: false),
            OnionFlag(file: ".logging", title: "Ereignisse protokollieren",
                      help: "Protokolle landen in .tmp_update/logs.", isSubOption: false),
        ]),
        OnionFlagSection(title: "Zeit", flags: [
            OnionFlag(file: ".ntpState", title: "Datum und Uhrzeit aus dem Internet",
                      help: "Stellt die Uhr über das Netzwerk (Miyoo Mini Plus).", isSubOption: false),
            OnionFlag(file: ".manual_tz", title: "Zeitzone manuell festlegen",
                      help: "Die Zeitzone wird in der App „Onion Tools“ auf der Konsole eingestellt. Ohne VPN besser aus lassen.", isSubOption: false),
            OnionFlag(file: ".ntpWait", title: "Auf NTP warten",
                      help: "Stellt die Zeit über NTP. Dauert länger als die HTTP-Abfrage, daher meist aus.", isSubOption: false),
        ]),
        OnionFlagSection(title: "Oberfläche", flags: [
            OnionFlag(file: ".showExpert", title: "Bereich „Expert“ zeigen",
                      help: "Das Expert-Symbol erscheint im Hauptmenü.", isSubOption: false),
            OnionFlag(file: ".showRecents", title: "Bereich „Zuletzt gespielt“ zeigen",
                      help: "Das Symbol für zuletzt gespielte Spiele erscheint im Hauptmenü.", isSubOption: false),
        ]),
        OnionFlagSection(title: "Netzwerk (Miyoo Mini Plus)", flags: [
            OnionFlag(file: ".hotspotState", title: "Hotspot",
                      help: "Die Konsole öffnet ein eigenes WLAN für SSH, FTP, HTTP und Netplay unterwegs.", isSubOption: false),
            OnionFlag(file: ".smbdState", title: "Samba-Dateifreigabe",
                      help: "Die SD-Karte erscheint im Netzwerk, z. B. im Finder unter „Netzwerk“.", isSubOption: false),
            OnionFlag(file: ".authsmbdState", title: "Samba mit Anmeldung", help: "Samba verlangt Benutzername und Passwort.", isSubOption: true),
            OnionFlag(file: ".httpState", title: "HTTP-Dateimanager im Browser",
                      help: "Webserver mit Dateimanager unter http://<IP der Konsole>. Braucht viel Speicher, bei anspruchsvollen Spielen ausschalten.", isSubOption: false),
            OnionFlag(file: ".authhttpState", title: "HTTP mit Anmeldung", help: "Der Webserver verlangt eine Anmeldung.", isSubOption: true),
            OnionFlag(file: ".ftpState", title: "FTP-Server", help: "Dateien per FTP-Programm übertragen.", isSubOption: false),
            OnionFlag(file: ".authftpState", title: "FTP mit Anmeldung", help: "Der FTP-Server verlangt eine Anmeldung.", isSubOption: true),
            OnionFlag(file: ".sshState", title: "SSH-Server", help: "Sichere Kommandozeile und SFTP.", isSubOption: false),
            OnionFlag(file: ".authsshState", title: "SSH mit Anmeldung", help: "Der SSH-Server verlangt eine Anmeldung.", isSubOption: true),
            OnionFlag(file: ".telnetState", title: "Telnet", help: "Unverschlüsselte Kommandozeile.", isSubOption: false),
            OnionFlag(file: ".authtelnetState", title: "Telnet mit Anmeldung", help: "Telnet verlangt eine Anmeldung.", isSubOption: true),
        ]),
    ]

    public static func url(_ flag: OnionFlag, root: URL) -> URL {
        root.appending(path: configPath).appending(path: flag.file)
    }

    public static func isOn(_ flag: OnionFlag, root: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(flag, root: root).path)
    }

    /// Turns a flag on or off the way the Windows tool does: rename to and from "name_".
    /// Creates the marker file when neither exists.
    public static func set(_ flag: OnionFlag, on: Bool, root: URL) throws {
        let fm = FileManager.default
        let active = url(flag, root: root)
        let inactive = active.deletingLastPathComponent().appending(path: flag.file + "_")
        try fm.createDirectory(at: active.deletingLastPathComponent(), withIntermediateDirectories: true)
        let isOn = fm.fileExists(atPath: active.path)
        let hasOff = fm.fileExists(atPath: inactive.path)
        if on && !isOn {
            if hasOff { try fm.moveItem(at: inactive, to: active) } else { try Data().write(to: active) }
        } else if !on && isOn {
            if hasOff { try fm.removeItem(at: inactive) }
            try fm.moveItem(at: active, to: inactive)
        }
    }
}
