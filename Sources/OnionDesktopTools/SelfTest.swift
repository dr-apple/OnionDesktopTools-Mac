import AppKit
import Foundation
import OnionDesktopToolsKit

/// A pretend SD card in /tmp, for the self-test and snapshots (APP_FAKE_CARD).
nonisolated enum FakeCard {
    static func file(_ root: URL, _ path: String, _ text: String = "x") {
        let url = root.appending(path: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    /// An installed Onion card with a few packages, roms, and saves.
    static func makeOnion(at root: URL) {
        try? FileManager.default.removeItem(at: root)
        file(root, ".tmp_update/bin/installUI", "\u{0}\u{1}usage: installUI --version 4.3.1-1 [options]\u{0}")
        file(root, ".tmp_update/runtime.sh", "#!/bin/sh\necho onion\n")
        file(root, ".tmp_update/config/.noAutoStart", "")
        file(root, ".tmp_update/config/.showRecents_", "")
        file(root, ".tmp_update/config/.sshState", "")
        let packs: [(String, String, String, String?)] = [
            ("Emu", "Nintendo - Game Boy Advance (gpSP)", "GBA", "GBA"),
            ("Emu", "Sega - Mega Drive - Genesis (PicoDrive)", "MD", "MD"),
            ("Emu", "Sony - PlayStation (PCSX ReARMed)", "PS", "PS"),
            ("Emu", "Nintendo - SNES (Snes9x 2005)", "SFC", "SFC"),
            ("RApp", "Arcade (FBNeo)", "FBNEO", "FBNEO"),
            ("App", "Tweaks", "Tweaks", nil),
            ("App", "Retroarch Manager", "RetroArchManager", nil),
        ]
        for (kind, name, folder, roms) in packs {
            let base = "App/PackageManager/data/\(kind)/\(name)"
            file(root, "\(base)/\(kind)/\(folder)/config.json", "{}")
            if let roms { file(root, "\(base)/Roms/\(roms)/.keep", "") }
        }
        file(root, "Emu/GBA/config.json", "{}")
        file(root, "Roms/GBA/Pokemon Emerald.gba", String(repeating: "g", count: 4096))
        file(root, "Roms/GBA/Imgs/Pokemon Emerald.png", "png")
        file(root, "Roms/MD/Sonic.md", String(repeating: "s", count: 2048))
        file(root, "Saves/CurrentProfile/saves/gpSP/Pokemon Emerald.srm", "save")
        file(root, "BIOS/gba_bios.bin", "bios")
        file(root, "RetroArch/.retroarch/retroarch.cfg", "video_smooth = false")
        file(root, "RetroArch/.retroarch/cores/skip.so", "core")
    }

    static func makeStock(at root: URL) {
        try? FileManager.default.removeItem(at: root)
        file(root, "RApp/readme.txt", "stock")
        file(root, "Roms/GBA/Zelda.gba", "zelda")
        file(root, "Imgs/GBA/Zelda.png", "png")
        file(root, "RetroArch/.retroarch/system/gba_bios.bin", "bios")
        file(root, "RetroArch/.retroarch/system/cheats/huge.cht", "cheat")
        file(root, "RetroArch/.retroarch/system/scph3900.bin", "skip")
    }
}

/// Self-test for agents: runs the app's real functions on /tmp folders,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/odt-self APP_FAKE_CARD=/tmp/odt-self-card OnionDesktopTools --selftest
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden, let fake = ProcessInfo.processInfo.environment["APP_FAKE_CARD"],
              fake.hasPrefix("/tmp") || fake.hasPrefix("/private/tmp") else {
            print("SELFTEST refused: set APP_STORE and APP_FAKE_CARD to folders in /tmp")
            finish(code: 1)
            return
        }
        Task {
            let fm = FileManager.default
            let root = URL(fileURLWithPath: fake, isDirectory: true)
            FakeCard.makeOnion(at: root)
            await model.refreshCards()
            check("the pretend card is found", model.cards.contains { $0.device == "fake" })
            model.select(card: "fake")
            await model.inspectCard()
            check("an installed Onion is detected", model.content?.state == .onion, "\(String(describing: model.content))")
            check("the Onion version is read from installUI", model.content?.version == "4.3.1-1", model.content?.version ?? "nil")

            // Settings flags
            let flag = OnionFlags.sections[0].flags[0] // .noAutoStart
            check("an existing flag reads as on", OnionFlags.isOn(flag, root: root))
            try? OnionFlags.set(flag, on: false, root: root)
            check("turning a flag off renames it to name_", fm.fileExists(atPath: root.appending(path: ".tmp_update/config/.noAutoStart_").path) && !OnionFlags.isOn(flag, root: root))
            try? OnionFlags.set(flag, on: true, root: root)
            check("turning it on again restores it", OnionFlags.isOn(flag, root: root))
            let recents = OnionFlags.sections.flatMap(\.flags).first { $0.file == ".showRecents" }!
            try? OnionFlags.set(recents, on: true, root: root)
            check("a flag stored as name_ turns on", OnionFlags.isOn(recents, root: root))

            // Packages
            var packages = PackageManager.scan(root: root)
            check("packages are found", packages.count == 7, "\(packages.count)")
            check("GBA is installed", packages.first { $0.folder == "Emu/GBA" }?.status == .installed)
            check("MD has roms but no emulator", packages.first { $0.folder == "Emu/MD" }?.status == .romsPresent)
            if let md = packages.first(where: { $0.folder == "Emu/MD" }) {
                try? await model.install([md])
                packages = PackageManager.scan(root: root)
                check("installing MD copies Emu/MD", packages.first { $0.folder == "Emu/MD" }?.status == .installed)
                try? await model.uninstall([md])
                check("uninstalling MD removes Emu/MD but keeps roms",
                      !fm.fileExists(atPath: root.appending(path: "Emu/MD").path) && fm.fileExists(atPath: root.appending(path: "Roms/MD/Sonic.md").path))
            }

            // Wi-Fi
            try? WifiSetup.write(ssid: "Home", password: "secret$1", root: root)
            let script = (try? String(contentsOf: root.appending(path: ".tmp_update/runtime.sh"), encoding: .utf8)) ?? ""
            check("Wi-Fi script keeps the original runtime.sh", fm.fileExists(atPath: root.appending(path: ".tmp_update/runtime_ori.sh").path))
            check("Wi-Fi script contains the network", script.contains("ssid=\"Home\"") && script.contains("psk=\"secret$1\"") && !script.contains("\r"))
            check("quotes in passwords are refused", (try? WifiSetup.validate(ssid: "a", password: "x\"y")) == nil)

            // Backup and restore
            FakeCard.file(root, "Roms/GBA/._Pokemon Emerald.gba", "junk")
            model.activity = Activity(title: "test")
            let folder = try? await model.backup(parts: Set(BackupPart.allCases), description: "Selbsttest")
            model.activity = nil
            if let folder {
                check("backup copies roms without images", fm.fileExists(atPath: folder.appending(path: "Roms/GBA/Pokemon Emerald.gba").path))
                check("backup copies images", fm.fileExists(atPath: folder.appending(path: "Roms/GBA/Imgs/Pokemon Emerald.png").path))
                check("backup skips ._ files", !fm.fileExists(atPath: folder.appending(path: "Roms/GBA/._Pokemon Emerald.gba").path))
                check("backup copies saves and BIOS", fm.fileExists(atPath: folder.appending(path: "Saves/CurrentProfile/saves/gpSP/Pokemon Emerald.srm").path)
                      && fm.fileExists(atPath: folder.appending(path: "BIOS/gba_bios.bin").path))
                check("backup copies only top-level RetroArch .cfg", fm.fileExists(atPath: folder.appending(path: "RetroArch/.retroarch/retroarch.cfg").path)
                      && !fm.fileExists(atPath: folder.appending(path: "RetroArch/.retroarch/cores").path))
                check("backup copies config flags", fm.fileExists(atPath: folder.appending(path: ".tmp_update/config/.sshState").path))
                let listed = BackupPlanner.list(in: Store.backups).first { $0.folder.lastPathComponent == folder.lastPathComponent }
                check("backup list reads description and parts", listed?.description == "Selbsttest" && listed?.parts.contains(.saves) == true,
                      "\(String(describing: listed))")

                let target = URL(fileURLWithPath: fake + "-restore", isDirectory: true)
                try? fm.removeItem(at: target)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                let jobs = BackupPlanner.restoreJobs(backup: folder, parts: [.roms, .saves], card: target)
                _ = try? FileCopier.run(jobs)
                check("restore of roms leaves images out", fm.fileExists(atPath: target.appending(path: "Roms/GBA/Pokemon Emerald.gba").path)
                      && !fm.fileExists(atPath: target.appending(path: "Roms/GBA/Imgs").path))
                check("restore copies saves", fm.fileExists(atPath: target.appending(path: "Saves/CurrentProfile/saves/gpSP/Pokemon Emerald.srm").path))
            } else {
                check("backup runs", false)
            }

            // Mac junk
            FakeCard.file(root, "Roms/MD/._Sonic.md", "junk")
            FakeCard.file(root, ".DS_Store", "junk")
            let removed = MacJunk.clean(root: root)
            check("cleaning removes ._ files and .DS_Store", removed >= 2 && !fm.fileExists(atPath: root.appending(path: "Roms/MD/._Sonic.md").path), "\(removed)")

            // Stock card
            FakeCard.makeStock(at: root)
            await model.inspectCard()
            check("a stock card is detected", model.content?.state == .stock)
            let stockBackup = fm.temporaryDirectory.appending(path: "odt-stock-backup")
            try? fm.removeItem(at: stockBackup)
            _ = try? FileCopier.run(BackupPlanner.backupJobs(card: root, state: .stock, parts: Set(BackupPart.allCases), into: stockBackup))
            check("stock images move to Roms/<System>/Imgs", fm.fileExists(atPath: stockBackup.appending(path: "Roms/GBA/Imgs/Zelda.png").path))
            check("stock BIOS comes from RetroArch/system without cheats or scph39",
                  fm.fileExists(atPath: stockBackup.appending(path: "BIOS/gba_bios.bin").path)
                  && !fm.fileExists(atPath: stockBackup.appending(path: "BIOS/cheats").path)
                  && !fm.fileExists(atPath: stockBackup.appending(path: "BIOS/scph3900.bin").path))

            // Empty card
            try? fm.removeItem(at: root)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            MacJunk.preventIndexing(root: root)
            await model.inspectCard()
            check("a card with only macOS files counts as empty", model.content?.state == .empty)

            FakeCard.makeOnion(at: root)
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
