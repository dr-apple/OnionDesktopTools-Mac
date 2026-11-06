import AppKit
import SwiftUI
import OnionDesktopToolsKit

/// Onion's on/off options (.tmp_update/config).
struct OnionSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var states: [String: Bool] = [:]
    @State private var error: String?

    var body: some View {
        if let root = model.root, model.content?.state == .onion {
            Form {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                ForEach(OnionFlags.sections) { section in
                    Section(section.title) {
                        ForEach(section.flags) { flag in
                            Toggle(isOn: binding(flag, root: root)) {
                                Text(flag.title)
                                Text(flag.help)
                            }
                            .padding(.leading, flag.isSubOption ? Space.xl : 0)
                            .help(flag.help)
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Änderungen werden sofort auf die Karte geschrieben und gelten beim nächsten Start der Konsole.")
                }
            }
            .formStyle(.grouped)
            .onAppear { load(root) }
            .onChange(of: model.cardRevision) { load(root) }
        } else if model.root == nil {
            NoCardView()
        } else {
            ContentUnavailableView("Kein Onion auf der Karte", systemImage: "switch.2",
                                   description: Text(model.content?.state == .onionPending
                                                     ? "Onion ist entpackt, aber noch nicht installiert. Starte die Konsole einmal mit der Karte, dann sind die Einstellungen hier verfügbar."
                                                     : "Installiere zuerst Onion auf dieser Karte."))
        }
    }

    private func load(_ root: URL) {
        var result: [String: Bool] = [:]
        for flag in OnionFlags.sections.flatMap(\.flags) { result[flag.file] = OnionFlags.isOn(flag, root: root) }
        states = result
    }

    private func binding(_ flag: OnionFlag, root: URL) -> Binding<Bool> {
        Binding(get: { states[flag.file] ?? false }, set: { on in
            do {
                try OnionFlags.set(flag, on: on, root: root)
                states[flag.file] = on
                error = nil
                model.note("\(flag.title): \(on ? "an" : "aus")")
            } catch {
                self.error = "Konnte \(flag.file) nicht ändern: \(error.localizedDescription)"
            }
        })
    }
}

/// Emulators and apps from Onion's package manager.
struct PackagesView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, emu, app, rapp
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .emu: "Emulatoren"
            case .app: "Apps"
            case .rapp: "RetroArch"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var packages: [OnionPackage] = []
    @State private var selection = Set<OnionPackage.ID>()
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\OnionPackage.status), KeyPathComparator(\OnionPackage.name)]

    private var visible: [OnionPackage] {
        packages.filter { package in
            switch filter {
            case .all: true
            case .emu: package.kind == .emu
            case .app: package.kind == .app
            case .rapp: package.kind == .rapp
            }
        }
        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.romFolder ?? "").localizedCaseInsensitiveContains(search) }
        .sorted(using: sortOrder)
    }

    private var selected: [OnionPackage] { packages.filter { selection.contains($0.id) } }
    private var romsWaiting: [OnionPackage] { packages.filter { $0.status == .romsPresent } }

    var body: some View {
        if model.root == nil {
            NoCardView()
        } else if model.content?.state != .onion && model.content?.state != .onionPending {
            ContentUnavailableView("Kein Onion auf der Karte", systemImage: "gamecontroller",
                                   description: Text("Der Paketmanager braucht eine Karte mit Onion."))
        } else {
            table
                .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
                .searchable(text: $search, prompt: "Emulator oder Rom-Ordner")
                .onAppear(perform: reload)
                .onChange(of: model.cardRevision) { reload() }
        }
    }

    private var table: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Status", value: \.status) { package in
                StatusBadge(status: package.status)
            }
            .width(min: 130, ideal: 140)
            TableColumn("Name", value: \.name)
                .width(min: 200, ideal: 280)
            TableColumn("Typ", value: \.kind.rawValue) { Text($0.kind.title) }
                .width(min: 80, ideal: 100)
            TableColumn("Rom-Ordner") { package in
                if let folder = package.romFolder {
                    Text(package.romCount > 0 ? "\(folder) (\(package.romCount))" : folder)
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)
            TableColumn("Ordner", value: \.folder)
                .width(min: 100, ideal: 140)
        }
        .contextMenu(forSelectionType: OnionPackage.ID.self) { ids in
            let items = packages.filter { ids.contains($0.id) }
            Button("Installieren") { confirmInstall(items) }
            Button("Deinstallieren") { confirmUninstall(items) }
            if items.count == 1, let folder = items.first?.romFolder, let root = model.root {
                Divider()
                Button("Rom-Ordner im Finder zeigen") {
                    let url = root.appending(path: "Roms/\(folder)")
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .overlay {
            if packages.isEmpty {
                ContentUnavailableView("Keine Pakete gefunden", systemImage: "shippingbox",
                                       description: Text("Auf der Karte fehlt App/PackageManager. Starte die Konsole einmal mit Onion."))
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: Space.md) {
            Picker("Typ", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button("Fehlende installieren (\(romsWaiting.count))") { confirmInstall(romsWaiting) }
                .help("Installiert alle Emulatoren, für die schon Roms auf der Karte liegen")
                .disabled(romsWaiting.isEmpty || model.isBusy)
            Button("Deinstallieren") { confirmUninstall(selected) }
                .disabled(selected.isEmpty || model.isBusy)
            Button("Installieren") { confirmInstall(selected) }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || model.isBusy)
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.md)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func reload() {
        guard let root = model.root else { packages = []; return }
        packages = PackageManager.scan(root: root)
        selection = selection.filter { id in packages.contains { $0.id == id } }
    }

    private func list(_ items: [OnionPackage]) -> String {
        let names = items.prefix(12).map { "• \($0.name)" }.joined(separator: "\n")
        return items.count > 12 ? names + "\n… und \(items.count - 12) weitere" : names
    }

    private func confirmInstall(_ items: [OnionPackage]) {
        guard !items.isEmpty else { return }
        model.confirmation = Confirmation(title: "\(items.count) Pakete installieren?", message: list(items), confirm: "Installieren") {
            model.perform("Installiere Pakete …") {
                try await model.install(items)
                reload()
            }
        }
    }

    private func confirmUninstall(_ items: [OnionPackage]) {
        guard !items.isEmpty else { return }
        model.confirmation = Confirmation(title: "\(items.count) Pakete entfernen?", message: list(items) + "\n\nDeine Roms bleiben erhalten.",
                                          confirm: "Entfernen", destructive: true) {
            model.perform("Entferne Pakete …") {
                try await model.uninstall(items)
                reload()
            }
        }
    }
}

struct StatusBadge: View {
    let status: OnionPackage.Status

    var body: some View {
        switch status {
        case .installed: Label(status.title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .romsPresent: Label(status.title, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .notInstalled: Label(status.title, systemImage: "circle").foregroundStyle(.secondary)
        }
    }
}

/// Wi-Fi for the Miyoo Mini Plus.
struct WifiView: View {
    @Environment(AppModel.self) private var model
    @State private var ssid = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var message: String?

    var body: some View {
        if model.root == nil {
            NoCardView()
        } else {
            Form {
                Section {
                    Text("Für den Miyoo Mini Plus: Das WLAN wird beim nächsten Start der Konsole eingerichtet.")
                    if let root = model.root, WifiSetup.isPending(root: root) {
                        Label("Eine WLAN-Einrichtung wartet bereits auf den nächsten Start.", systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Netzwerk") {
                    TextField("Name (SSID)", text: $ssid)
                    HStack {
                        if showPassword {
                            TextField("Passwort", text: $password)
                        } else {
                            SecureField("Passwort", text: $password)
                        }
                        Button(showPassword ? "Ausblenden" : "Zeigen", systemImage: showPassword ? "eye.slash" : "eye") {
                            showPassword.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(showPassword ? "Passwort ausblenden" : "Passwort zeigen")
                    }
                    Button("Passwort aus dem Schlüsselbund dieses Macs holen") { fromKeychain() }
                        .buttonStyle(.link)
                        .disabled(ssid.isEmpty)
                        .help("macOS fragt nach deinem Mac-Passwort, bevor das WLAN-Passwort gelesen wird.")
                }
                Section {
                    HStack {
                        if let message { Text(message).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Auf die SD-Karte schreiben") { write() }
                            .buttonStyle(.borderedProminent)
                            .disabled(ssid.isEmpty || model.content?.state != .onion || model.isBusy)
                    }
                } footer: {
                    if model.content?.state != .onion {
                        Text("Dafür muss Onion auf der Karte installiert und einmal gestartet worden sein.")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func fromKeychain() {
        let ssid = ssid
        Task {
            let result = try? await offMain {
                try Shell.run("/usr/bin/security", ["find-generic-password", "-D", "AirPort network password", "-a", ssid, "-w"], separateErrors: true)
            }
            if let result, result.ok {
                password = result.output.trimmingCharacters(in: .newlines)
                message = "Passwort übernommen."
            } else {
                message = "Kein gespeichertes Passwort für „\(ssid)“ gefunden."
            }
        }
    }

    private func write() {
        guard let root = model.root else { return }
        do {
            try WifiSetup.write(ssid: ssid, password: password, root: root)
            message = "Gespeichert. Starte die Konsole mit dieser Karte."
            model.note("WLAN „\(ssid)“ wird beim nächsten Start eingerichtet.", .success)
            Sounds.success()
        } catch {
            message = nil
            model.errorMessage = error.localizedDescription
        }
    }
}
