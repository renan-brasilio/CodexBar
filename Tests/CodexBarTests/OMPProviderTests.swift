import AppKit
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct OMPProviderTests {
    private static let sampleOMPUsageJSON = """
    {
      "generatedAt": 1792223107842,
      "reports": [
        {
          "provider": "google-antigravity",
          "fetchedAt": 1792222961116,
          "limits": [
            {
              "id": "google-antigravity:anthropic:default:3p-weekly",
              "label": "Claude & GPT (shared)",
              "window": {
                "id": "weekly",
                "label": "Weekly",
                "durationMs": 604800000,
                "resetsAt": 1792253782000
              },
              "amount": {
                "unit": "percent",
                "remainingFraction": 0,
                "usedFraction": 1,
                "remaining": 0,
                "used": 100,
                "limit": 100
              },
              "status": "exhausted"
            },
            {
              "id": "google-antigravity:google:default:gemini-5h",
              "label": "Gemini",
              "window": {
                "id": "5h",
                "label": "5 Hour",
                "durationMs": 18000000,
                "resetsAt": 1792240961000
              },
              "amount": {
                "unit": "percent",
                "remainingFraction": 1,
                "usedFraction": 0,
                "remaining": 100,
                "used": 0,
                "limit": 100
              },
              "status": "ok"
            }
          ],
          "metadata": {
            "email": "brasiliodarocha@gmail.com"
          }
        },
        {
          "provider": "openai-codex",
          "fetchedAt": 1792222961117,
          "limits": [
            {
              "id": "openai-codex:primary",
              "label": "5 hours",
              "window": {
                "id": "5h",
                "label": "5 hours",
                "durationMs": 18000000,
                "resetsAt": 1792234814000
              },
              "amount": {
                "used": 10,
                "limit": 100,
                "remaining": 90,
                "usedFraction": 0.1,
                "remainingFraction": 0.9,
                "unit": "percent"
              },
              "status": "ok"
            },
            {
              "id": "openai-codex:secondary",
              "label": "7 days",
              "window": {
                "id": "7d",
                "label": "7 days",
                "durationMs": 604800000,
                "resetsAt": 1792677613000
              },
              "amount": {
                "used": 5,
                "limit": 100,
                "remaining": 95,
                "usedFraction": 0.05,
                "remainingFraction": 0.95,
                "unit": "percent"
              },
              "status": "ok"
            }
          ],
          "metadata": {
            "email": "renanfamous@gmail.com"
          }
        }
      ],
      "capacity": {
        "google-antigravity": [
          {
            "window": "5h",
            "durationMs": 18000000,
            "accounts": 4,
            "usedAccounts": 0.4,
            "remainingAccounts": 3.6
          },
          {
            "window": "7d",
            "durationMs": 604800000,
            "accounts": 4,
            "usedAccounts": 2.0,
            "remainingAccounts": 2.0
          }
        ],
        "openai-codex": [
          {
            "window": "5h",
            "durationMs": 18000000,
            "accounts": 1,
            "usedAccounts": 0.1,
            "remainingAccounts": 0.9
          },
          {
            "window": "7d",
            "durationMs": 604800000,
            "accounts": 1,
            "usedAccounts": 0.05,
            "remainingAccounts": 0.95
          }
        ]
      }
    }
    """

    @Test
    func `omp provider descriptor is registered and configured`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .omp)
        #expect(descriptor.id == .omp)
        #expect(descriptor.metadata.displayName == "OMP")
        #expect(descriptor.cli.name == "omp")
        #expect(descriptor.branding.iconResourceName == "ProviderIcon-omp")
        #expect(descriptor.branding.color == ProviderColor(hex: 0x10B981))
        #expect(descriptor.fetchPlan.sourceModes.contains(.cli))
    }

    @Test
    func `omp usage parser parses combined usage accurately`() throws {
        let now = Date(timeIntervalSince1970: 1792220000)
        let snapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "all",
            now: now)

        let primary = try #require(snapshot.primary)
        // Total 5h accounts = 4 (AGY) + 1 (Codex) = 5.
        // Used 5h accounts = 0.4 (AGY) + 0.1 (Codex) = 0.5.
        // Used percent = 0.5 / 5.0 * 100 = 10%.
        #expect(abs(primary.usedPercent - 10.0) < 0.001)
        #expect(primary.windowMinutes == 300)

        let secondary = try #require(snapshot.secondary)
        // Total 7d accounts = 4 (AGY) + 1 (Codex) = 5.
        // Used 7d accounts = 2.0 + 0.05 = 2.05.
        // Used percent = 2.05 / 5.0 * 100 = 41.0%.
        #expect(abs(secondary.usedPercent - 41.0) < 0.001)
        #expect(secondary.windowMinutes == 10080)

        let extras = try #require(snapshot.extraRateWindows)
        #expect(extras.count >= 4)
        #expect(extras.contains { $0.id == "omp-google-antigravity-5h" })
        #expect(extras.contains { $0.id == "omp-google-antigravity-7d" })
        #expect(extras.contains { $0.id == "omp-openai-codex-5h" })
        #expect(extras.contains { $0.id == "omp-openai-codex-7d" })

        #expect(snapshot.details.count >= 2)
        #expect(snapshot.details[0].title == "Capacity Breakdown")
        #expect(snapshot.details[1].title == "Connected Accounts (2)")
    }

    @Test
    func `omp usage parser filters by antigravity subprovider`() throws {
        let now = Date(timeIntervalSince1970: 1792220000)
        let snapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "agy",
            now: now)

        let primary = try #require(snapshot.primary)
        // AGY 5h: 0.4 used / 4 total = 10%
        #expect(abs(primary.usedPercent - 10.0) < 0.001)

        let secondary = try #require(snapshot.secondary)
        // AGY 7d: 2.0 used / 4 total = 50%
        #expect(abs(secondary.usedPercent - 50.0) < 0.001)

        let details = snapshot.details
        #expect(details.contains { $0.title?.contains("Antigravity") == true })
    }

    @Test
    func `omp usage parser filters by codex subprovider`() throws {
        let now = Date(timeIntervalSince1970: 1792220000)
        let snapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "codex",
            now: now)

        let primary = try #require(snapshot.primary)
        // Codex 5h: 0.1 used / 1 total = 10%
        #expect(abs(primary.usedPercent - 10.0) < 0.001)

        let secondary = try #require(snapshot.secondary)
        // Codex 7d: 0.05 used / 1 total = 5%
        #expect(abs(secondary.usedPercent - 5.0) < 0.001)
    }

    @Test
    func `omp usage parser honors hidden usage item IDs for 5 vs 6 accounts`() throws {
        let now = Date(timeIntervalSince1970: 1792220000)

        // 1. When 6 accounts window is hidden (only 5 accounts checked)
        let only5AccountsSnapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "all",
            hiddenItemIDs: ["metric:secondary"],
            now: now)
        let primary5 = try #require(only5AccountsSnapshot.primary)
        #expect(abs(primary5.usedPercent - 10.0) < 0.001) // 5 accounts window
        #expect(only5AccountsSnapshot.secondary == nil)

        // 2. When 5 accounts window is hidden (only 6 accounts checked)
        let only6AccountsSnapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "all",
            hiddenItemIDs: ["metric:primary"],
            now: now)
        let primary6 = try #require(only6AccountsSnapshot.primary)
        #expect(abs(primary6.usedPercent - 41.0) < 0.001) // 6 accounts window
        #expect(only6AccountsSnapshot.secondary == nil)

        // The percentages distinctly differ between selecting 5 vs 6 accounts
        #expect(primary5.usedPercent != primary6.usedPercent)
    }

    @Test
    func `omp settings snapshot persists subprovider selection`() {
        let suite = "OMPProviderTests-settings-\(UUID().uuidString)"
        let settings = testSettingsStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        #expect(settings.ompSubprovider == "all")

        settings.ompSubprovider = "google-antigravity"
        #expect(settings.ompSubprovider == "google-antigravity")

        let snapshot = settings.ompSettingsSnapshot()
        #expect(snapshot.subprovider == "google-antigravity")
        #expect(snapshot.effectiveSubprovider == "google-antigravity")

        settings.ompSubprovider = "custom"
        settings.ompCustomSubprovider = "my-custom-provider"
        let customSnapshot = settings.ompSettingsSnapshot()
        #expect(customSnapshot.effectiveSubprovider == "my-custom-provider")
    }

    @Test
    func `omp brand icon is loaded as template`() throws {
        ProviderBrandIcon.resetCacheForTesting()
        defer { ProviderBrandIcon.resetCacheForTesting() }

        let image = try #require(ProviderBrandIcon.image(for: .omp))
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }
}
