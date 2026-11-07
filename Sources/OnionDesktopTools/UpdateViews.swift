import AppKit
import SwiftUI
import OnionDesktopToolsKit

/// The update sheet on the main window: searching, what is new, download progress, restart.
struct UpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .top, spacing: Space.lg) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            if let release = updater.release, showsNotes {
                ScrollView {
                    Text(notes(release))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(Space.md)
                }
                .frame(height: 180)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            }
            if case .downloading(let fraction) = updater.phase {
                if let fraction { ProgressView(value: fraction) } else { ProgressView().progressViewStyle(.linear) }
            }
            if updater.phase == .ready, model.isBusy {
                Label("Warte, bis die laufende Aufgabe fertig ist, dann kann die App neu starten.", systemImage: "clock")
                    .foregroundStyle(.orange)
            }
            buttons
        }
        .padding(Space.xl)
        .frame(width: 480)
        .noInitialFocus()
    }

    private var showsNotes: Bool {
        switch updater.phase {
        case .available, .downloading, .ready: true
        default: false
        }
    }

    private var title: String {
        switch updater.phase {
        case .idle, .checking: "Suche nach Updates …"
        case .upToDate: "Onion Desktop Tools ist aktuell"
        case .available: "Version \(updater.release?.version ?? "") ist verfügbar"
        case .downloading: "Lade Version \(updater.release?.version ?? "") …"
        case .ready: "Update bereit"
        case .failed: "Update fehlgeschlagen"
        }
    }

    private var subtitle: String {
        switch updater.phase {
        case .idle, .checking: "Frage GitHub nach der neuesten Version."
        case .upToDate: "Du hast Version \(updater.currentVersion), das ist die neueste."
        case .available, .downloading: "Du hast Version \(updater.currentVersion)." + (updater.release?.isPrerelease == true ? " Das Update ist eine Vorabversion." : "")
        case .ready: "Version \(updater.release?.version ?? "") ist geladen und geprüft. Die App startet für die Installation neu."
        case .failed(let message): message
        }
    }

    private func notes(_ release: AppRelease) -> AttributedString {
        let text = release.notes.isEmpty ? "Keine Beschreibung." : release.notes
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: Space.sm) {
            switch updater.phase {
            case .available:
                Button("Diese Version überspringen") { updater.skip() }
                Spacer()
                Button("Später") { updater.showSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Laden und installieren") { Task { await updater.download() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .downloading:
                Spacer()
                Button("Im Hintergrund laden") { updater.showSheet = false }
                    .keyboardShortcut(.cancelAction)
            case .ready:
                Spacer()
                Button("Beim Beenden installieren") { updater.installLater() }
                    .keyboardShortcut(.cancelAction)
                Button("Jetzt neu starten") { updater.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy)
            case .failed:
                Button("Releases auf GitHub") { openURL(updater.release?.pageURL ?? AppUpdate.releasesPage) }
                Spacer()
                Button("OK") { updater.showSheet = false; updater.phase = .idle }
                    .keyboardShortcut(.defaultAction)
            case .idle, .checking:
                ProgressView().controlSize(.small)
                Spacer()
                Button("Abbrechen") { updater.showSheet = false }
                    .keyboardShortcut(.cancelAction)
            case .upToDate:
                Spacer()
                Button("OK") { updater.showSheet = false; updater.phase = .idle }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Settings > Updates.
struct UpdateSettings: View {
    @AppStorage(Updater.Key.autoCheck) private var autoCheck = true
    @AppStorage(Updater.Key.autoInstall) private var autoInstall = false
    @AppStorage(Updater.Key.prereleases) private var prereleases = true
    let updater: Updater

    var body: some View {
        Section {
            LabeledContent {
                Button("Jetzt suchen") { Task { await updater.check(userInitiated: true) } }
                    .disabled(updater.phase == .checking)
            } label: {
                Text("Version \(updater.currentVersion)")
                Text(updater.lastCheckText)
            }
        }
        Section {
            Toggle("Automatisch nach Updates suchen", isOn: $autoCheck)
            Toggle(isOn: $autoInstall) {
                Text("Updates automatisch laden")
                Text("Die App lädt und prüft ein Update im Hintergrund und fragt dann, ob sie neu starten darf.")
            }
            .disabled(!autoCheck)
            Toggle(isOn: $prereleases) {
                Text("Auch Vorabversionen anbieten")
                Text("Vorabversionen sind neuer, aber weniger getestet.")
            }
        } footer: {
            Text("Updates kommen von github.com/\(AppUpdate.repository). Die App sucht beim Start und dann einmal am Tag.")
        }
    }
}
