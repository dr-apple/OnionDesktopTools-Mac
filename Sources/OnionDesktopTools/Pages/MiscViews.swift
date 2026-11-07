import AppKit
import SwiftUI
import OnionDesktopToolsKit

struct ToolsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let card = model.card {
            Form {
                Section("SD-Karte") {
                    LabeledContent("Name", value: card.mediaName)
                    LabeledContent("Gerät", value: "/dev/\(card.device)\(card.isInternalReader ? " (eingebauter Kartenleser)" : "")")
                    LabeledContent("Größe", value: ByteCountFormatter.string(fromByteCount: card.size, countStyle: .file))
                    LabeledContent("Dateisystem", value: card.fileSystem ?? "nicht eingebunden")
                    if let mount = card.mountPoint { LabeledContent("Eingebunden unter", value: mount.path) }
                    LabeledContent("Inhalt", value: model.content?.summary ?? "–")
                }
                Section {
                    ToolRow(title: "In FAT32 formatieren", symbol: "eraser",
                            detail: "Löscht die ganze Karte und legt eine FAT32-Partition „ONION“ an (MBR). Funktioniert auch bei Karten über 32 GB.",
                            button: "Formatieren…", destructive: true, enabled: model.cardIsReal) { model.confirmFormat() }
                    ToolRow(title: "Auf Fehler prüfen", symbol: "stethoscope",
                            detail: "Prüft das Dateisystem mit diskutil, ohne etwas zu ändern.",
                            button: "Prüfen", enabled: model.cardIsReal && card.volumeDevice != nil) { model.checkDisk(repair: false) }
                    ToolRow(title: "Reparieren", symbol: "wrench.and.screwdriver",
                            detail: "Repariert Fehler im Dateisystem (wie chkdsk /F unter Windows).",
                            button: "Reparieren", enabled: model.cardIsReal && card.volumeDevice != nil) { model.checkDisk(repair: true) }
                    ToolRow(title: "macOS-Hilfsdateien entfernen", symbol: "sparkles",
                            detail: "Löscht „._“-Dateien und .DS_Store, die der Finder anlegt und die auf dem Miyoo als kaputte Spiele erscheinen. Schaltet Spotlight für die Karte ab.",
                            button: "Aufräumen", enabled: model.root != nil) { model.cleanMacFiles() }
                    ToolRow(title: "Auswerfen", symbol: "eject",
                            detail: "Räumt auf und wirft die Karte sicher aus.",
                            button: "Auswerfen", enabled: model.cardIsReal && model.root != nil) { model.eject() }
                }
            }
            .formStyle(.grouped)
            .disabled(model.isBusy)
        } else {
            NoCardView()
        }
    }
}

struct ToolRow: View {
    let title: String
    let symbol: String
    let detail: String
    let button: String
    var destructive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, role: destructive ? .destructive : nil, action: action)
                .disabled(!enabled)
        }
        .padding(.vertical, 2)
    }
}

struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            List(model.log) { line in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(line.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(line.text)
                        .font(line.kind == .command ? .callout.monospaced() : .body)
                        .foregroundStyle(color(line.kind))
                        .textSelection(.enabled)
                }
                .id(line.id)
            }
            .onChange(of: model.log.count) {
                if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .overlay {
            if model.log.isEmpty {
                ContentUnavailableView("Noch nichts passiert", systemImage: "text.alignleft",
                                       description: Text("Hier steht, was die App auf der Karte macht."))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Kopieren", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log.map(\.text).joined(separator: "\n"), forType: .string)
                }
                Button("Leeren", systemImage: "trash") { model.log.removeAll() }
            }
        }
    }

    private func color(_ kind: LogLine.Kind) -> Color {
        switch kind {
        case .info: .primary
        case .success: .green
        case .error: .red
        case .command: .secondary
        }
    }
}

struct AboutView: View {
    private let links: [(String, String)] = [
        ("Onion-Dokumentation", "https://github.com/OnionUI/Onion/wiki"),
        ("Onion auf GitHub", "https://github.com/OnionUI/Onion"),
        ("Original: Onion Desktop Tools für Windows", "https://github.com/schmurtzm/Onion-Desktop-Tools"),
    ]
    private let sponsors: [(String, String)] = [
        ("Schmurtz auf Patreon", "https://www.patreon.com/schmurtz"),
        ("Schmurtz: Buy me a coffee", "https://www.buymeacoffee.com/schmurtz"),
        ("Aemiii91 auf GitHub Sponsors", "https://github.com/sponsors/Aemiii91"),
        ("Aemiii91 auf Ko-fi", "https://ko-fi.com/Aemiii91"),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: Space.lg) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Onion Desktop Tools für Mac").font(.title2.bold())
                        HStack(spacing: Space.sm) {
                            Text("Version \(Updater.shared.currentVersion)")
                                .foregroundStyle(.secondary)
                            Button("Nach Updates suchen …") { Task { await Updater.shared.check(userInitiated: true) } }
                                .buttonStyle(.link)
                        }
                        Text("Mac-Umsetzung von Onion Desktop Tools von Schmurtz (Onion Team). Bereitet SD-Karten für den Miyoo Mini und Miyoo Mini Plus mit Onion OS vor.")
                    }
                }
            }
            Section("Links") {
                ForEach(links, id: \.1) { Link($0.0, destination: URL(string: $0.1)!) }
            }
            Section("Das Onion-Team unterstützen") {
                ForEach(sponsors, id: \.1) { Link($0.0, destination: URL(string: $0.1)!) }
            }
            Section("Daten dieser App") {
                Button("Downloads im Finder zeigen") { NSWorkspace.shared.open(Store.downloads) }
                Button("Sicherungen im Finder zeigen") { NSWorkspace.shared.open(Store.backups) }
            }
        }
        .formStyle(.grouped)
    }
}
