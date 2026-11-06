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
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Allgemein"
        case .appearance: "Darstellung"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
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
        Section("Ordner") {
            LabeledContent("Downloads") {
                Button("Im Finder zeigen") { NSWorkspace.shared.open(Store.downloads) }
            }
            LabeledContent("Sicherungen") {
                Button("Im Finder zeigen") { NSWorkspace.shared.open(Store.backups) }
            }
        }
    }
}
