//
//  PromptsMenuButton.swift
//  GeminiDesktop
//

import SwiftUI

struct PromptsMenuButton: View {
    var coordinator: AppCoordinator
    var injectionMode: String

    @AppStorage(UserDefaultsKeys.showPromptMetadata.rawValue) private var showPromptMetadata: Bool = false

    var body: some View {
        Menu {
            ForEach(coordinator.promptLibrary.rootNodes, id: \.id) { node in
                AnyView(nodeContent(for: node))
            }
        } label: {
            Image(systemName: "sparkles")
        }
        .disabled(coordinator.isInjecting)
    }

    private func nodeContent(for node: PromptNode) -> some View {
        switch node {
        case .directory(let name, let children):
            return AnyView(
                Menu(name) {
                    ForEach(children, id: \.id) { child in
                        AnyView(nodeContent(for: child))
                    }
                }
            )
        case .file(let file):
            return AnyView(fileMenuButton(for: file))
        }
    }

    private func metadataDetails(for metadata: PromptMetadata) -> [String] {
        var lines: [String] = []
        lines.append("Summary: \(metadata.summary)")
        if !metadata.tags.isEmpty {
            lines.append("Tags: \(metadata.tags.joined(separator: ", "))")
        }
        var versionLine = "v\(metadata.version)"
        if let updated = metadata.lastUpdated { versionLine += " · \(updated)" }
        lines.append(versionLine)
        return lines
    }

    @ViewBuilder
    private func fileMenuButton(for file: PromptFile) -> some View {
        let isDeprecated = file.metadata?.deprecated == true

        Button(file.displayTitle, action: { handleSelection(file) })
            .foregroundStyle(isDeprecated ? Color.secondary : Color.primary)

        if showPromptMetadata {
            if let metadata = file.metadata {
                // Disabled role item — acts as subtitle
                Button(metadata.role) {}
                    .disabled(true)

                // ⓘ Details submenu with summary, tags, version
                Menu {
                    ForEach(Array(metadataDetails(for: metadata).enumerated()), id: \.offset) { _, detail in
                        Button(detail) {}
                            .disabled(true)
                    }
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
            } else if file.yamlParseError {
                Button("YAML error — required fields missing") {}
                    .disabled(true)
            }
        }
    }

    private func handleSelection(_ file: PromptFile) {
        if case .danger = file.scanResult {
            showDangerAlert(for: file)
        } else {
            executePrompt(file)
        }
    }

    private func showDangerAlert(for file: PromptFile) {
        let alert = NSAlert()
        alert.messageText = "Dangerous Pattern Detected"
        alert.informativeText = "This prompt contains a pattern that could be misused. Are you sure you want to use it?"
        alert.addButton(withTitle: "Use Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            executePrompt(file)
        }
    }

    private func executePrompt(_ file: PromptFile) {
        if injectionMode == "copy" {
            coordinator.copyPromptToClipboard(file)
        } else {
            coordinator.injectPrompt(file)
        }
    }
}
