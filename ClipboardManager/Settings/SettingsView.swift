import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updates: UpdateManager
    let onClearHistory: (_ includingPinned: Bool) -> Void
    let storageDescription: () -> String

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            HistorySettingsView(onClearHistory: onClearHistory, storageDescription: storageDescription)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ExclusionsSettingsView()
                .tabItem { Label("Exclusions", systemImage: "hand.raised") }
            UpdatesSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 520)
        .padding(.top, 8)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Toggle panel") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ShortcutRecorder(hotKey: $settings.hotKey)
                        if let error = settings.hotKeyError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        } else {
                            Text("Works in every app. Needs ⌘, ⌃ or ⌥, or a function key.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Shortcut")
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Copy text without formatting by default", isOn: $settings.copyAsPlainTextByDefault)
                Text("Hold ⌥ while choosing an item to do the opposite of this setting.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Behavior")
            }

            Section {
                LabeledContent("Panel height") {
                    HStack {
                        Slider(value: $settings.panelHeightFraction, in: AppSettings.panelHeightRange, step: 0.05)
                            .frame(width: 200)
                        Text("\(Int((settings.panelHeightFraction * 100).rounded()))% of screen")
                            .monospacedDigit()
                            .frame(width: 100, alignment: .trailing)
                    }
                }
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

private struct HistorySettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    let onClearHistory: (_ includingPinned: Bool) -> Void
    let storageDescription: () -> String
    @State private var storage = ""

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.retentionDays, in: AppSettings.retentionRange) {
                    LabeledContent("Keep unpinned items for") {
                        Text(settings.retentionDays == 1 ? "1 day" : "\(settings.retentionDays) days").monospacedDigit()
                    }
                }
                Stepper(value: $settings.storeCapMB, in: AppSettings.storeCapRange, step: 50) {
                    LabeledContent("Maximum storage") {
                        Text(settings.storeCapMB >= 1000
                             ? String(format: "%.1f GB", Double(settings.storeCapMB) / 1000)
                             : "\(settings.storeCapMB) MB").monospacedDigit()
                    }
                }
                Text("Pinned items never expire and are not counted against the limit when evicting.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Retention")
            }

            Section {
                LabeledContent("Storage used", value: storage)
                HStack {
                    Button("Clear Unpinned…") { confirmClear(includingPinned: false) }
                    Button("Clear Everything…", role: .destructive) { confirmClear(includingPinned: true) }
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppConfig.storageRoot])
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .onAppear { storage = storageDescription() }
    }

    private func confirmClear(includingPinned: Bool) {
        let alert = NSAlert()
        alert.messageText = includingPinned ? "Clear all clipboard history?" : "Clear unpinned clipboard history?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: includingPinned ? "Clear Everything" : "Clear Unpinned").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onClearHistory(includingPinned)
            storage = storageDescription()
        }
    }
}

private struct ExclusionsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var manualBundleID = ""

    var body: some View {
        Form {
            Section {
                if settings.excludedBundleIDs.isEmpty {
                    Text("Nothing copied from an excluded app is recorded. Add password managers or terminals that don't mark their clipboard data as concealed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            if let icon = AppIconCache.shared.icon(forBundleID: bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(appName(for: bundleID))
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                settings.removeExclusion(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                }
            } header: {
                Text("Excluded apps")
            }

            Section {
                HStack {
                    Button("Choose Application…", action: chooseApplication)
                    Spacer()
                }
                HStack {
                    TextField("Bundle identifier, e.g. com.example.app", text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addManual)
                    Button("Add", action: addManual)
                        .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Add")
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "Not installed" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose apps whose copies should never be recorded."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                settings.addExclusion(bundleID)
            }
        }
    }

    private func addManual() {
        settings.addExclusion(manualBundleID)
        manualBundleID = ""
    }
}

private struct UpdatesSettingsView: View {
    @EnvironmentObject private var updates: UpdateManager

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                    .disabled(!updates.isConfigured)
                HStack {
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(updates.isConfigured && !updates.canCheckForUpdates)
                    Spacer()
                    Text(updates.statusDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Update checks are the only network activity this app can perform, and only when you allow them here. Your clipboard contents are never sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Software updates")
            }
            Section {
                LabeledContent("Version", value: updates.versionDescription)
            }
        }
        .formStyle(.grouped)
    }
}
