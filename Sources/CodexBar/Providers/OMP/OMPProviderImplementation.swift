import CodexBarCore
import Foundation
import SwiftUI

struct OMPProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .omp

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .omp(context.settings.ompSettingsSnapshot())
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        [
            ProviderSettingsPickerDescriptor(
                id: "omp-subprovider",
                title: "Subprovider",
                subtitle: "Select which provider limits to display from OMP, or Combined for all aggregated limits.",
                binding: context.binding(\.ompSubprovider),
                options: [
                    ProviderSettingsPickerOption(id: "all", title: "Combined (All Limits)"),
                    ProviderSettingsPickerOption(id: "google-antigravity", title: "Google Antigravity (agy)"),
                    ProviderSettingsPickerOption(id: "openai-codex", title: "OpenAI Codex"),
                    ProviderSettingsPickerOption(id: "anthropic", title: "Anthropic Claude"),
                    ProviderSettingsPickerOption(id: "github-copilot", title: "GitHub Copilot"),
                    ProviderSettingsPickerOption(id: "xai-oauth", title: "xAI Grok"),
                    ProviderSettingsPickerOption(id: "custom", title: "Custom Subprovider…"),
                ],
                isVisible: nil,
                onChange: { _ in
                    await context.store.refreshProvider(.omp)
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "omp-custom-subprovider",
                title: "Custom Subprovider ID",
                subtitle: "Specify a custom subprovider ID (e.g. for new providers added to OMP).",
                kind: .plain,
                placeholder: "e.g. google-antigravity",
                binding: context.binding(\.ompCustomSubprovider),
                actions: [],
                isVisible: { context.settings.ompSubprovider == "custom" }),
        ]
    }
}
