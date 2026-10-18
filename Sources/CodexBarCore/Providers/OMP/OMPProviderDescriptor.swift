import Foundation

public enum OMPProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .omp,
            settingsSection: .init(OMPProviderSettingsKey.self),
            metadata: ProviderMetadata(
                id: .omp,
                displayName: "OMP",
                sessionLabel: "5-Hour",
                weeklyLabel: "Weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show OMP usage",
                cliName: "omp",
                defaultEnabled: false,
                widgetSelectable: false,
                burnDownWidgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .omp),
                iconResourceName: "ProviderIcon-omp",
                color: ProviderColor(hex: 0x10B981),
                confettiPalette: [
                    ProviderColor(hex: 0x10B981),
                    ProviderColor(hex: 0x06B6D4),
                    ProviderColor(hex: 0x3B82F6),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "OMP cost summary is not supported." }),
            pace: ProviderPaceCapability(
                primary: .session(maximumMinutes: 300, requiresDuration: true),
                secondary: .weeklyWithDuration),
            history: .optIn,
            presentation: ProviderUsagePresentation(
                rateWindowLabeler: { metadata, snapshot, _ in
                    let primaryTitle = snapshot.primary?.windowMinutes.map { minutes in
                        minutes <= 300 ? metadata.sessionLabel : "\(minutes / 60)h"
                    } ?? metadata.sessionLabel
                    let secondaryTitle = snapshot.secondary?.windowMinutes.map { minutes in
                        if minutes >= 40000 { return "Monthly" }
                        if minutes >= 10000 { return metadata.weeklyLabel }
                        return "\(minutes / 60)h"
                    } ?? metadata.weeklyLabel
                    return ProviderRateWindowLabels(
                        primary: primaryTitle,
                        secondary: secondaryTitle,
                        tertiary: "",
                        showsTertiary: false)
                },
                iconWindowResolver: { context in
                    ProviderUsageWindowPair(primary: context.snapshot.primary, secondary: context.snapshot.secondary)
                },
                menuBarWindowResolver: { context in
                    switch context.metric {
                    case .primary:
                        return .resolved(context.snapshot.primary)
                    case .secondary:
                        return .resolved(context.snapshot.secondary ?? context.snapshot.primary)
                    case .automatic:
                        return .resolved(context.snapshot.primary ?? context.snapshot.secondary)
                    default:
                        return .unhandled
                    }
                }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [OMPCLIUsageStrategy()] })),
            cli: ProviderCLIConfig(
                name: "omp",
                aliases: ["oh-my-prompt"],
                versionDetector: { _ in ProviderVersionDetector.ompVersion() }))
    }
}

struct OMPCLIUsageStrategy: ProviderFetchStrategy {
    let id: String = "omp.cli"
    let kind: ProviderFetchKind = .cli

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        BinaryLocator.resolveOMPBinary(
            env: context.env,
            loginPATH: LoginShellPathCache.shared.current) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let subprovider = context.env["OMP_SUBPROVIDER"]
            ?? context.settings?.omp?.effectiveSubprovider
            ?? "all"

        let snapshot = try await OMPCLIProbe().fetch(
            environment: context.env,
            subprovider: subprovider)

        return self.makeResult(
            usage: snapshot,
            sourceLabel: "omp-cli")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
