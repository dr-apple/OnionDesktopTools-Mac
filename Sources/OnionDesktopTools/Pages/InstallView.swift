import SwiftUI
import OnionDesktopToolsKit

/// Download an Onion release and put it on the card (with or without formatting).
struct InstallView: View {
    @Environment(AppModel.self) private var model
    @State private var formatFirst = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if let error = model.releaseError {
                    Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    Button("Erneut versuchen") { Task { await model.loadReleases() } }
                } else if model.stable == nil && model.beta == nil {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Lade Versionen von GitHub …").foregroundStyle(.secondary)
                    }
                }
                if let stable = model.stable { ReleaseRow(release: stable) }
                if let beta = model.beta { ReleaseRow(release: beta) }
            } header: {
                Text("1. Version herunterladen")
            } footer: {
                Text("Die Versionen kommen direkt von github.com/OnionUI/Onion.")
            }

            Section("2. Version wählen") {
                if model.downloadedZips.isEmpty {
                    Text("Noch nichts heruntergeladen.").foregroundStyle(.secondary)
                } else {
                    Picker("Installieren", selection: $model.selectedZip) {
                        ForEach(model.downloadedZips, id: \.self) { zip in
                            Text(zip.lastPathComponent).tag(Optional(zip))
                        }
                    }
                    Button("Downloads im Finder zeigen") { model.revealInFinder(model.selectedZip ?? Store.downloads) }
                        .buttonStyle(.link)
                }
            }

            Section {
                if let card = model.card {
                    LabeledContent("SD-Karte", value: card.displayName)
                    LabeledContent("Inhalt", value: card.mountPoint == nil ? "Nicht eingebunden" : (model.content?.summary ?? "…"))
                    if let fs = card.fileSystem { LabeledContent("Dateisystem", value: fs) }
                    Toggle("Karte vorher formatieren (FAT32, löscht alles)", isOn: $formatFirst)
                        .disabled(!model.cardIsReal)
                } else {
                    Text("Keine SD-Karte gefunden. Stecke sie in den Kartenleser.").foregroundStyle(.secondary)
                }
            } header: {
                Text("3. Auf die SD-Karte")
            } footer: {
                Text(footer)
            }

            Section {
                HStack {
                    Spacer()
                    Button(formatFirst ? "Formatieren und installieren" : "Installieren") {
                        model.confirmInstall(formatting: formatFirst)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canInstall)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.selectedCardID) { formatFirst = needsFormat }
        .onChange(of: model.cardRevision) { formatFirst = needsFormat }
        .onAppear { formatFirst = needsFormat }
    }

    private var needsFormat: Bool {
        guard let card = model.card, model.cardIsReal else { return false }
        return card.mountPoint == nil || !card.isFAT32
    }

    private var canInstall: Bool {
        guard model.selectedZip != nil, let card = model.card, !model.isBusy else { return false }
        return formatFirst || card.mountPoint != nil
    }

    private var footer: String {
        if formatFirst { return "Neue Karte oder Neuanfang: die Karte wird komplett gelöscht und als FAT32 angelegt." }
        switch model.content?.state {
        case .onion: return "Update: Spielstände, Roms und Einstellungen bleiben erhalten."
        case .stock: return "Auf dieser Karte ist das Miyoo Stock-OS. Nimm lieber eine neue Karte und „Von Stock umziehen“."
        default: return "Nach dem Entpacken die Karte in den Miyoo Mini stecken und einschalten – die Installation läuft dann auf der Konsole."
        }
    }
}

struct ReleaseRow: View {
    @Environment(AppModel.self) private var model
    let release: OnionRelease

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: release.channel == .stable ? "checkmark.seal" : "flask")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(release.channel == .stable ? "Stabil" : "Beta") – Onion \(release.version)")
                    .font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            Link("Versionshinweise", destination: release.pageURL)
            if model.isDownloaded(release) {
                Label("Geladen", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Laden") { Task { await model.download(release) } }
                    .disabled(model.isBusy)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = [ByteCountFormatter.string(fromByteCount: release.size, countStyle: .file)]
        if let date = release.published { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
}
