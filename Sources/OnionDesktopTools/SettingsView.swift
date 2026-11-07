import AppKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .updates: UpdateSettings(updater: Updater.shared)
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Allgemein"
        case .appearance: "Darstellung"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct GeneralSettings: View {
    @AppStorage("cleanMacFiles") private var cleanMacFiles = true
    @AppStorage("playSounds") private var playSounds = true

    var body: some View {
        Section {
            Toggle("macOS-Hilfsdateien nach dem Schreiben entfernen", isOn: $cleanMacFiles)
            Toggle("Ton bei Erfolg und Fehler", isOn: $playSounds)
        } footer: {
            Text("Der Finder legt „._“-Dateien auf FAT32-Karten an. Der Miyoo zeigt sie als kaputte Spiele.")
        }
        Section {
            ForEach(Store.Folder.allCases) { FolderRow(folder: $0) }
        } header: {
            Text("Ordner")
        } footer: {
            Text("Vorhandene Dateien bleiben beim Wechsel im alten Ordner. Ist ein gewählter Ordner nicht erreichbar, etwa auf einem nicht angeschlossenen Laufwerk, nutzt die App den Standardordner.")
        }
    }
}

/// One folder in Settings: where it is, and buttons to change, reset, and show it.
struct FolderRow: View {
    let folder: Store.Folder
    @Environment(AppModel.self) private var model
    /// Same key Store reads, so the row redraws when the folder changes.
    @AppStorage private var path: String
    @State private var problem: String?

    init(folder: Store.Folder) {
        self.folder = folder
        _path = AppStorage(wrappedValue: "", folder.key)
    }

    private var shown: URL { folder.isAvailable ? (folder.customURL ?? folder.defaultURL) : folder.defaultURL }

    var body: some View {
        LabeledContent {
            HStack(spacing: Space.sm) {
                if !path.isEmpty {
                    Button("Standard") { change(to: nil) }
                        .help("Wieder den Standardordner in „Application Support“ nutzen")
                }
                Button("Ändern …") { choose() }
                Button("Im Finder zeigen", systemImage: "folder") { NSWorkspace.shared.open(folder.url) }
                    .labelStyle(.iconOnly)
                    .help("\(folder.title)-Ordner im Finder zeigen")
            }
        } label: {
            Text(folder.title)
            Text((shown.path as NSString).abbreviatingWithTildeInPath)
                .truncationMode(.middle)
                .lineLimit(1)
                .help(shown.path)
            if !folder.isAvailable {
                Label("„\(URL(fileURLWithPath: path).lastPathComponent)“ ist nicht erreichbar.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.message = "Ordner für \(folder.title) wählen"
        panel.directoryURL = folder.url
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            problem = "In „\(url.lastPathComponent)“ darf die App nicht schreiben."
            return
        }
        change(to: url)
    }

    private func change(to url: URL?) {
        problem = nil
        folder.set(url)
        path = url?.path ?? ""
        model.note("\(folder.title)-Ordner: \(folder.url.path)")
        if folder == .downloads { model.refreshDownloads() }
        model.cardRevision += 1
    }
}
