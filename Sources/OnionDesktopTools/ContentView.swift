import AppKit
import SwiftUI
import OnionDesktopToolsKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .install)
                .navigationTitle((model.sidebar ?? .install).title)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let activity = model.activity { ActivityBar(activity: activity) }
                }
        }
        .toolbar { CardToolbar() }
        .task {
            await model.refreshCards()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
        .task { await model.loadReleases() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification))) { _ in
            guard !model.isBusy else { return }
            Task { await model.refreshCards() }
        }
        .alert(model.confirmation?.title ?? "", isPresented: Binding(
            get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
               presenting: model.confirmation) { confirmation in
            Button(confirmation.confirm, role: confirmation.destructive ? .destructive : nil) { confirmation.action() }
            Button("Abbrechen", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
            Button("Protokoll zeigen") { model.sidebar = .log }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            ForEach(SidebarItem.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { page in
                        Label(page.title, systemImage: page.symbol).tag(page)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 224)
        .safeAreaInset(edge: .bottom, spacing: 0) { CardSummary() }
    }

    @ViewBuilder
    private func page(_ page: SidebarItem) -> some View {
        switch page {
        case .install: InstallView()
        case .migrate: MigrateView()
        case .onionSettings: OnionSettingsView()
        case .packages: PackagesView()
        case .wifi: WifiView()
        case .backup: BackupView()
        case .restore: RestoreView()
        case .tools: ToolsView()
        case .log: LogView()
        case .about: AboutView()
        }
    }
}

/// Card picker, refresh, and eject in the window toolbar.
struct CardToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("SD-Karte", selection: Binding(get: { model.selectedCardID }, set: { model.select(card: $0) })) {
                if model.cards.isEmpty { Text("Keine SD-Karte").tag(String?.none) }
                ForEach(model.cards) { card in
                    Text(card.displayName).tag(Optional(card.id))
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 200)
            .help("Die SD-Karte, mit der gearbeitet wird")
            .disabled(model.isBusy)

            Button("Aktualisieren", systemImage: "arrow.clockwise") { Task { await model.refreshCards() } }
                .help("SD-Karten neu suchen (Befehl-R)")
                .disabled(model.isBusy)
            Button("Auswerfen", systemImage: "eject") { model.eject() }
                .help("Die SD-Karte sicher auswerfen (Befehl-E)")
                .disabled(model.isBusy || !model.cardIsReal || model.root == nil)
        }
    }
}

/// What is on the selected card, at the bottom of the sidebar.
struct CardSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let card = model.card {
                Label(card.volumeName ?? card.mediaName, systemImage: "sdcard.fill")
                    .font(.headline)
                    .lineLimit(1)
                if card.mountPoint == nil {
                    Text("Nicht eingebunden – formatieren unter SD-Karten-Werkzeuge")
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.content?.summary ?? "Wird gelesen …")
                    HStack(spacing: Space.xs) {
                        Text(card.fileSystem ?? "")
                        if !card.isFAT32 && card.device != "fake" {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Onion braucht FAT32")
                        }
                    }
                    .foregroundStyle(.secondary)
                    if let free = card.freeSpace {
                        Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) frei von \(ByteCountFormatter.string(fromByteCount: card.size, countStyle: .file))")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("Keine SD-Karte", systemImage: "sdcard")
                    .font(.headline)
                Text("Stecke die SD-Karte in den Kartenleser.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .padding(Space.md)
    }
}

/// The running operation with its progress.
struct ActivityBar: View {
    let activity: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(activity.title).font(.headline)
                Spacer()
                Text(activity.detail).foregroundStyle(.secondary).monospacedDigit()
            }
            if let fraction = activity.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.md)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Shown on pages that need a mounted card.
struct NoCardView: View {
    var detail = "Stecke die SD-Karte in den Kartenleser und wähle sie oben rechts aus."

    var body: some View {
        ContentUnavailableView("Keine SD-Karte", systemImage: "sdcard", description: Text(detail))
    }
}
