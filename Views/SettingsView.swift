import SwiftUI
import KeyboardShortcuts
import WebKit
import ServiceManagement

struct SettingsView: View {
    @Binding var coordinator: AppCoordinator
    @AppStorage(UserDefaultsKeys.pageZoom.rawValue) private var pageZoom: Double = Constants.defaultPageZoom
    @AppStorage(UserDefaultsKeys.hideWindowAtLaunch.rawValue) private var hideWindowAtLaunch: Bool = false
    @AppStorage(UserDefaultsKeys.hideDockIcon.rawValue) private var hideDockIcon: Bool = false
    @AppStorage(UserDefaultsKeys.appTheme.rawValue) private var appTheme: String = AppTheme.system.rawValue
    @AppStorage(UserDefaultsKeys.useCustomToolbarColor.rawValue) private var useCustomToolbarColor: Bool = false
    @AppStorage(UserDefaultsKeys.toolbarColorHex.rawValue) private var toolbarColorHex: String = "#34A853"
    @AppStorage(UserDefaultsKeys.debugModeEnabled.rawValue) private var debugModeEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.minimizeToPrompt.rawValue) private var minimizeToPrompt: Bool = false
    @AppStorage(UserDefaultsKeys.userAgentOption.rawValue) private var userAgentOption: String = UserAgentOption.safari.rawValue
    @AppStorage(UserDefaultsKeys.customUserAgent.rawValue) private var customUserAgent: String = ""
    @AppStorage(UserDefaultsKeys.panelPosition.rawValue) private var panelPosition: String = PanelPosition.bottomCenter.rawValue

    @State private var showingResetAlert = false
    @State private var isClearing = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var promptsDirLabel: String = ""
    @State private var artifactsDirLabel: String = ""
    @State private var selectorSource: String = ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch MenuBar at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        } catch { launchAtLogin = !newValue }
                    }
                Toggle("Hide Desktop Window at Launch", isOn: $hideWindowAtLaunch)
                Toggle("Hide Dock Icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }
            }
            Section("Chat Bar") {
                HStack {
                    Label("Position on Screen", systemImage: "rectangle.bottomthird.inset.filled")
                    Spacer()
                    Picker("", selection: $panelPosition) {
                        ForEach([PanelPosition.bottomLeft, .bottomCenter, .bottomRight], id: \.rawValue) { pos in
                            Text(pos.displayName).tag(pos.rawValue)
                        }
                        Divider()
                        Text(PanelPosition.rememberLast.displayName).tag(PanelPosition.rememberLast.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .onChange(of: panelPosition) { _, _ in
                        coordinator.resetChatBarPosition()
                    }
                }
                HStack {
                    Label("Keyboard Shortcut", systemImage: "command")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .bringToFront)
                }
                Toggle("Minimize to Prompt", isOn: $minimizeToPrompt)
            }
            Section("Appearance") {
                HStack {
                    Text("Theme:")
                    Spacer()
                    Picker("", selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: appTheme) { _, newValue in
                        (AppTheme(rawValue: newValue) ?? .system).apply()
                    }
                }
                Toggle("Use Custom Toolbar Color", isOn: $useCustomToolbarColor)
                if useCustomToolbarColor {
                    HStack {
                        ColorPicker("Toolbar Color", selection: Binding(
                            get: { Color(toolbarColorHex) ?? .blue },
                            set: { if let hex = $0.toHex() { toolbarColorHex = hex } }
                        ))
                        Spacer()
                        Button("Reset") {
                            useCustomToolbarColor = false
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Text Size: \(Int((pageZoom * 100).rounded()))%")
                    Spacer()
                    Stepper("",
                            value: $pageZoom,
                            in: Constants.minPageZoom...Constants.maxPageZoom,
                            step: Constants.pageZoomStep)
                        .onChange(of: pageZoom) { coordinator.webViewModel.wkWebView.pageZoom = $1 }
                        .labelsHidden()
                }
            }
            Section("User Agent") {
                HStack {
                    Text("Browser Identity:")
                    Spacer()
                    Picker("", selection: $userAgentOption) {
                        ForEach(UserAgentOption.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: userAgentOption) { _, _ in
                        coordinator.webViewModel.applyUserAgent()
                    }
                }
                if userAgentOption == UserAgentOption.custom.rawValue {
                    TextField("Custom User Agent", text: $customUserAgent, prompt: Text("Enter custom user agent string"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            coordinator.webViewModel.applyUserAgent()
                        }
                }
                Text(currentUserAgentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Reset Website Data")
                        Text("Clears cookies, cache, and login sessions")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset", role: .destructive) { showingResetAlert = true }
                        .disabled(isClearing)
                        .overlay { if isClearing { ProgressView().scaleEffect(0.7) } }
                }
            }

            Section("Prompts & Artifacts") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prompts Folder")
                        Text("Markdown files in this folder appear in the Insert Prompt menu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(promptsDirLabel.isEmpty ? "No folder selected" : promptsDirLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…") {
                        chooseDirectory(label: $promptsDirLabel, key: .promptsDirectoryBookmark)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Artifacts Folder")
                        Text("Captured Gemini responses are saved here as Markdown files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(artifactsDirLabel.isEmpty ? "No folder selected" : artifactsDirLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…") {
                        chooseDirectory(label: $artifactsDirLabel, key: .artifactsDirectoryBookmark)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selectors")
                        Text("JS expressions that extract metadata (model, request, URL) from Gemini when saving artifacts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectorSource.isEmpty ? "Default (bundled)" : selectorSource)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        resetSelectorsToDefaults()
                    }
                }
            }
            Section("Advanced") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable Debug Mode", isOn: $debugModeEnabled)
                    Text("Only needed by developers or when filing a selector bug report. Restart the app after enabling for network capture to work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadDirectoryLabels()
        }
        .onDisappear {
            GeminiSelectors.reload()
            loadDirectoryLabels() // must follow reload() — reads isUsingUserFile to refresh selectorSource label
        }
        .alert("Reset Website Data?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { Task { await clearWebsiteData() } }
        } message: {
            Text("This will clear all cookies, cache, and login sessions. You will need to sign in to Gemini again.")
        }
    }

    private var currentUserAgentDescription: String {
        let option = UserAgentOption(rawValue: userAgentOption) ?? .safari
        return option.settingsDescription(custom: customUserAgent)
    }

    private func clearWebsiteData() async {
        isClearing = true
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records)
        isClearing = false
    }

    private func loadDirectoryLabels() {
        let bookmarkStore = BookmarkStore()
        if let url = bookmarkStore.resolveBookmark(for: .promptsDirectoryBookmark) {
            promptsDirLabel = url.lastPathComponent
        }
        if let url = bookmarkStore.resolveBookmark(for: .artifactsDirectoryBookmark) {
            artifactsDirLabel = url.lastPathComponent
        } else {
            artifactsDirLabel = "Downloads/Artifacts"
        }
        selectorSource = GeminiSelectors.isUsingUserFile ? "Custom (user file)" : "Default (bundled)"
    }

    private func chooseDirectory(label: Binding<String>, key: UserDefaultsKeys) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose \(key == .promptsDirectoryBookmark ? "Prompts" : "Artifacts") Folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let bookmarkStore = BookmarkStore()
            do {
                try bookmarkStore.saveBookmark(for: url, key: key)
                label.wrappedValue = url.lastPathComponent

                // Reload prompts library if it's the prompts directory
                if key == .promptsDirectoryBookmark {
                    coordinator.promptLibrary.reload()
                    coordinator.promptLibrary.startWatching()
                }
            } catch {
                // Silently fail if bookmark save fails
            }
        }
    }

    private func resetSelectorsToDefaults() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let dir = appSupport.appendingPathComponent("GeminiDesktop")
        let userURL = dir.appendingPathComponent("gemini-selectors.json")

        // Pre-flight: ensure bundle resource exists before touching user file
        guard let bundleURL = Bundle.main.url(forResource: "gemini-selectors", withExtension: "json") else { return }

        // Backup existing user file if present; track backupURL for restore on copy failure
        var backupURL: URL? = nil
        if FileManager.default.fileExists(atPath: userURL.path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HHmm"
            let timestamp = formatter.string(from: Date())
            let candidate = dir.appendingPathComponent("gemini-selectors-\(timestamp).bak")
            do {
                try FileManager.default.moveItem(at: userURL, to: candidate)
                backupURL = candidate
            } catch {
                // Backup failed — abort to avoid partial state (user file stays intact)
                return
            }
        }

        // Copy bundle default to user path
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: bundleURL, to: userURL)
        } catch {
            // Copy failed — restore backup to avoid leaving user with no selector file
            if let backup = backupURL {
                try? FileManager.default.moveItem(at: backup, to: userURL)
            }
            return
        }

        // Refresh the displayed source label
        selectorSource = GeminiSelectors.isUsingUserFile ? "Custom (user file)" : "Default (bundled)"
    }
}

extension SettingsView {

    struct Constants {
        static let defaultPageZoom: Double = 1.0
        static let minPageZoom: Double = 0.6
        static let maxPageZoom: Double = 1.4
        static let pageZoomStep: Double = 0.01
    }

}
