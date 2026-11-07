import SwiftUI
import OnionDesktopToolsKit

/// Checkboxes for the parts of a backup.
struct PartToggles: View {
    @Binding var selection: Set<BackupPart>
    let available: Set<BackupPart>

    var body: some View {
        ForEach(BackupPart.allCases) { part in
            Toggle(isOn: Binding(
                get: { selection.contains(part) && available.contains(part) },
                set: { on in if on { selection.insert(part) } else { selection.remove(part) } })) {
                Label(part.title, systemImage: part.symbol)
            }
            .disabled(!available.contains(part))
        }
    }
}

struct BackupView: View {
    @Environment(AppModel.self) private var model
    @State private var parts = Set(BackupPart.allCases)
    @State private var note = ""

    var body: some View {
        if model.root == nil {
            NoCardView()
        } else {
            let available = BackupPart.available(for: model.content?.state ?? .unreadable)
            Form {
                Section {
                    LabeledContent("Quelle", value: model.content?.summary ?? "…")
                    if available.isEmpty {
                        Text("Auf dieser Karte ist weder Onion noch das Miyoo Stock-OS. Es gibt nichts zu sichern.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if model.content?.state == .stock {
                        Text("Von einer Stock-Karte werden Roms, Bilder und BIOS gesichert. Bilder landen gleich im Onion-Format (Roms/<System>/Imgs).")
                    }
                }
                Section("Was sichern?") {
                    PartToggles(selection: $parts, available: available)
                }
                Section("Beschreibung") {
                    TextField("Beschreibung", text: $note, prompt: Text("z. B. vor dem Update auf 4.3"), axis: .vertical)
                        .lineLimit(2...4)
                        .labelsHidden()
                }
                Section {
                    HStack {
                        Button("Sicherungen im Finder zeigen") { model.revealInFinder(Store.backups) }
                            .buttonStyle(.link)
                        Spacer()
                        Button("Sicherung starten") { start() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.isBusy || parts.intersection(available).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func start() {
        let parts = parts
        let note = note
        model.perform("Sichere SD-Karte …") {
            _ = try await model.backup(parts: parts, description: note)
            self.note = ""
        }
    }
}

struct RestoreView: View {
    @Environment(AppModel.self) private var model
    @State private var backups: [BackupInfo] = []
    @State private var selected: BackupInfo.ID?
    @State private var parts = Set(BackupPart.allCases)

    private var backup: BackupInfo? { backups.first { $0.id == selected } }

    var body: some View {
        VStack(spacing: 0) {
            List(backups, selection: $selected) { backup in
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.name).font(.headline)
                    if !backup.description.isEmpty { Text(backup.description).lineLimit(2) }
                    Text(backup.parts.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Im Finder zeigen") { model.revealInFinder(backup.folder) }
                    Button("In den Papierkorb legen", role: .destructive) { trash(backup) }
                }
            }
            .overlay {
                if backups.isEmpty {
                    ContentUnavailableView("Keine Sicherungen", systemImage: "externaldrive.badge.timemachine",
                                           description: Text("Sicherungen, die du unter „Sichern“ anlegst, erscheinen hier."))
                }
            }
            Divider()
            Form {
                Section("Wiederherstellen von „\(backup?.name ?? "–")“") {
                    PartToggles(selection: $parts, available: backup?.parts ?? [])
                }
                Section {
                    HStack {
                        Text(model.root == nil ? "Keine SD-Karte" : "Ziel: \(model.card?.displayName ?? "") · \(model.content?.summary ?? "")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Wiederherstellen") { confirm() }
                            .buttonStyle(.borderedProminent)
                            .disabled(backup == nil || model.root == nil || model.isBusy || parts.intersection(backup?.parts ?? []).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 380)
        }
        .onAppear(perform: reload)
        .onChange(of: model.activity == nil) { reload() }
        .onChange(of: model.cardRevision) { reload() }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Sicherungsordner", systemImage: "folder") { model.revealInFinder(Store.backups) }
            }
        }
    }

    private func reload() {
        backups = BackupPlanner.list(in: Store.backups)
        if selected == nil || !backups.contains(where: { $0.id == selected }) { selected = backups.first?.id }
    }

    private func trash(_ backup: BackupInfo) {
        try? FileManager.default.trashItem(at: backup.folder, resultingItemURL: nil)
        reload()
    }

    private func confirm() {
        guard let backup else { return }
        let parts = parts.intersection(backup.parts)
        var message = "„\(backup.name)“ wird auf \(model.card?.displayName ?? "die Karte") kopiert. Vorhandene Dateien mit gleichem Namen werden ersetzt."
        if model.content?.state != .onion && model.content?.state != .onionPending {
            message += "\n\nAuf der Karte ist kein Onion. Installiere besser zuerst Onion."
        }
        model.confirmation = Confirmation(title: "Sicherung wiederherstellen?", message: message, confirm: "Wiederherstellen") {
            model.perform("Stelle Sicherung wieder her …") { try await model.restore(backup.folder, parts: parts) }
        }
    }
}

/// The guided move from a Miyoo stock card to a new card with Onion.
struct MigrateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Text("So kommen deine Roms, Bilder und BIOS-Dateien von der originalen Miyoo-Karte auf eine neue Karte mit Onion. Die alte Karte bleibt unverändert.")
            }
            Section {
                StepRow(number: 1, title: "Stock-Karte sichern",
                        detail: "Stecke die originale Miyoo-Karte ein und wähle sie oben rechts aus.",
                        done: model.lastMigrationBackup != nil)
                HStack {
                    Text(model.root == nil ? "Keine Karte" : "Gewählt: \(model.content?.summary ?? "…")").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stock-Karte sichern") {
                        model.perform("Sichere Stock-Karte …") {
                            model.lastMigrationBackup = try await model.backup(parts: [.roms, .imgs, .bios], description: "Umzug von Stock")
                            model.offerEject(message: "Die Stock-Karte ist gesichert. Wirf sie aus und stecke die neue Karte ein.")
                        }
                    }
                    .disabled(model.content?.state != .stock || model.isBusy)
                }
            }
            Section {
                StepRow(number: 2, title: "Neue Karte vorbereiten",
                        detail: "Stecke die neue Karte ein und wähle sie oben rechts aus. Sie wird formatiert, Onion wird installiert und die Sicherung kommt darauf.",
                        done: false)
                Picker("Onion-Version", selection: $model.selectedZip) {
                    ForEach(model.downloadedZips, id: \.self) { Text($0.lastPathComponent).tag(Optional($0)) }
                }
                .disabled(model.downloadedZips.isEmpty)
                if model.downloadedZips.isEmpty {
                    Button("Zuerst eine Onion-Version laden") { model.sidebar = .install }.buttonStyle(.link)
                }
                HStack {
                    Text(model.card.map { "Ziel: \($0.displayName)" } ?? "Keine Karte").foregroundStyle(.secondary)
                    Spacer()
                    Button("Formatieren, installieren, übertragen") { confirmTarget() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.lastMigrationBackup == nil || model.selectedZip == nil || !model.cardIsReal
                                  || model.content?.state == .stock || model.isBusy)
                }
            } footer: {
                if model.lastMigrationBackup == nil {
                    Text("Schritt 2 wird nach der Sicherung freigeschaltet. Eine ältere Sicherung kannst du auch unter „Wiederherstellen“ einspielen.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func confirmTarget() {
        guard let backup = model.lastMigrationBackup, let zip = model.selectedZip, let card = model.card else { return }
        model.confirmation = Confirmation(
            title: "Neue Karte vorbereiten?",
            message: "„\(card.displayName)“ (/dev/\(card.device)) wird komplett gelöscht. Danach werden \(zip.lastPathComponent) und die Sicherung „\(backup.lastPathComponent)“ aufgespielt.",
            confirm: "Löschen und vorbereiten", destructive: true) {
            model.perform("Bereite neue Karte vor …") {
                try await model.format()
                try await model.extract(zip, askToEject: false)
                try await model.restore(backup, parts: Set(BackupPart.allCases))
                model.offerEject(message: "Die neue Karte ist fertig. Wirf sie aus, stecke sie in den Miyoo Mini und schalte ihn ein – Onion richtet sich dann ein.")
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
