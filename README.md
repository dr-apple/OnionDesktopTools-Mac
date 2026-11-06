# Onion Desktop Tools für Mac

Native macOS-Umsetzung von [Onion Desktop Tools](https://github.com/schmurtzm/Onion-Desktop-Tools) (Schmurtz, Onion Team).
Bereitet SD-Karten für Miyoo Mini / Miyoo Mini Plus mit [Onion OS](https://github.com/OnionUI/Onion) vor.

## Funktionen

- Onion (stabil oder Beta) direkt von GitHub laden und auf die Karte entpacken – Neuinstallation oder Update
- SD-Karte in FAT32 formatieren (`diskutil eraseDisk FAT32 ONION MBRFormat`), auch über 32 GB
- Dateisystem prüfen und reparieren (statt chkdsk)
- Sichern und Wiederherstellen: Roms, Bilder, Spielstände, BIOS, RetroArch-Konfiguration, Onion-Einstellungen
- Umzug von der Miyoo-Stock-Karte auf eine neue Onion-Karte (geführt)
- Onion-Einstellungen (Marker-Dateien in `.tmp_update/config`) umschalten
- Emulatoren- und App-Manager (Paketmanager von Onion), inkl. „Fehlende installieren“
- WLAN für den Miyoo Mini Plus einrichten, Passwort optional aus dem Schlüsselbund
- Mac-spezifisch: entfernt „._“-Dateien und .DS_Store, schaltet Spotlight für die Karte ab, sicheres Auswerfen

## Bauen

Voraussetzungen: macOS 26, Swift 6.2 (Xcode Command Line Tools).

```bash
./build.sh --open
```

Die App landet in `~/Applications/OnionDesktopTools.app`. Downloads und Sicherungen liegen in
`~/Library/Application Support/OnionDesktopTools`.

Tests: `swift test --scratch-path ~/Library/Developer/OnionDesktopTools/test-build` und `tools/selftest.sh`.

## Lizenz und Dank

Dieses Projekt ist eine Mac-Umsetzung von [Onion Desktop Tools](https://github.com/schmurtzm/Onion-Desktop-Tools)
von Schmurtz und steht wie das Original unter der [GNU GPL v3](LICENSE).
Onion OS stammt vom [Onion-Team](https://github.com/OnionUI/Onion).
