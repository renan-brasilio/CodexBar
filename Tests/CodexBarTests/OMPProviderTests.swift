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
                "remainingFraction": 0.27,
                "usedFraction": 0.73,
                "remaining": 27,
                "used": 73,
                "limit": 100
              },
              "status": "ok"
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
                "remainingFraction": 0.99,
                "usedFraction": 0.01,
                "remaining": 99,
                "used": 1,
                "limit": 100
              },
              "status": "ok"
            }
          ],
          "metadata": {
            "email": "user1@example.com"
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
                "used": 0,
                "limit": 100,
                "remaining": 100,
                "usedFraction": 0,
                "remainingFraction": 1,
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
                "used": 0,
                "limit": 100,
                "remaining": 100,
                "usedFraction": 0,
                "remainingFraction": 1,
                "unit": "percent"
              },
              "status": "ok"
            }
          ],
          "metadata": {
            "email": "user2@example.com"
          }
        }
      ],
      "capacity": {
        "google-antigravity": [
          {
            "window": "5h",
            "durationMs": 18000000,
            "accounts": 4,
            "usedAccounts": 0.04,
            "remainingAccounts": 3.96
          },
          {
            "window": "7d",
            "durationMs": 604800000,
            "accounts": 4,
            "usedAccounts": 1.4,
            "remainingAccounts": 2.6
          }
        ],
        "openai-codex": [
          {
            "window": "5h",
            "durationMs": 18000000,
            "accounts": 1,
            "usedAccounts": 0,
            "remainingAccounts": 1
          },
          {
            "window": "7d",
            "durationMs": 604800000,
            "accounts": 1,
            "usedAccounts": 0,
            "remainingAccounts": 1
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
    func `omp usage parser calculates combined usage from capacity totals`() throws {
        let now = Date(timeIntervalSince1970: 1792220000)
        let snapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "all",
            now: now)

        let primary = try #require(snapshot.primary)
        #expect(primary.windowMinutes == 300)
        // 5h capacity: 0.04 used / 5 accounts = 0.8%
        #expect(abs(primary.usedPercent - 0.8) < 0.001)

        let secondary = try #require(snapshot.secondary)
        #expect(secondary.windowMinutes == 10080)
        // 7d capacity: 1.4 used / 5 accounts = 28.0%
        #expect(abs(secondary.usedPercent - 28.0) < 0.001)

        let extras = try #require(snapshot.extraRateWindows)
        #expect(extras.count >= 2)
        #expect(extras.contains { $0.id == "omp-agy-gemini-5h" })
        #expect(extras.contains { $0.id == "omp-agy-3p-7d" })

        #expect(!snapshot.details.isEmpty)
        #expect(snapshot.details.contains { $0.title?.contains("Antigravity") == true })
    }

    @Test
    func `omp usage parser filters by antigravity subprovider`() throws {
        let now = Date(timeIntervalSince1970: 1792220000)
        let snapshot = try OMPUsageParser.parse(
            jsonString: Self.sampleOMPUsageJSON,
            subprovider: "agy",
            now: now)

        let primary = try #require(snapshot.primary)
        #expect(primary.windowMinutes == 300)
        // 0.04 / 4 = 1.0%
        #expect(abs(primary.usedPercent - 1.0) < 0.001)

        let secondary = try #require(snapshot.secondary)
        #expect(secondary.windowMinutes == 10080)
        // 1.4 / 4 = 35.0%
        #expect(abs(secondary.usedPercent - 35.0) < 0.001)

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
        #expect(primary.usedPercent == 0)

        let secondary = try #require(snapshot.secondary)
        #expect(secondary.usedPercent == 0)
    }

    @Test
    func `omp usage parser normalizes copilot request counts at parser level`() throws {
        let json = """
        {
          "reports": [
            {
              "provider": "github-copilot",
              "metadata": { "accountId": "octocat" },
              "limits": [
                {
                  "id": "copilot:chat",
                  "label": "Chat Requests",
                  "window": { "id": "monthly" },
                  "amount": { "unit": "requests", "used": 20, "limit": 200 }
                }
              ]
            }
          ]
        }
        """
        // Combined mode
        let combined = try OMPUsageParser.parse(jsonString: json, subprovider: "all")
        let extra = try #require(combined.extraRateWindows?.first { $0.id.contains("chat") })
        #expect(abs(extra.window.usedPercent - 10.0) < 0.001)
        #expect(extra.title == "Chat Requests")

        // Filtered subprovider mode
        let filtered = try OMPUsageParser.parse(jsonString: json, subprovider: "copilot")
        let secondary = try #require(filtered.secondary)
        #expect(abs(secondary.usedPercent - 10.0) < 0.001)
        #expect(secondary.windowMinutes == 43200)

        let labels = ProviderDescriptorRegistry.descriptor(for: .omp).presentation
            .rateWindowLabels(metadata: ProviderDescriptorRegistry.descriptor(for: .omp).metadata, snapshot: filtered)
        #expect(labels.secondary.contains("Monthly"))
    }

    @Test
    func `omp usage parser reflects active usable items in combined capacity and label`() throws {
        let json = """
        {
          "capacity": {
            "google-antigravity": [
              { "window": "5h", "accounts": 4, "usedAccounts": 1.8, "remainingAccounts": 2.2 }
            ],
            "openai-codex": [
              { "window": "5h", "accounts": 1, "usedAccounts": 0.35, "remainingAccounts": 0.65 }
            ],
            "xai-oauth": [
              { "window": "5h", "accounts": 1, "usedAccounts": 0.5, "remainingAccounts": 0.5 }
            ]
          },
          "reports": [
            {
              "provider": "google-antigravity",
              "metadata": { "email": "user@gmail.com" },
              "limits": [
                { "id": "gemini:5h", "window": { "id": "5h" }, "amount": { "used": 10, "limit": 100 } }
              ]
            },
            {
              "provider": "openai-codex",
              "metadata": { "email": "dev@gmail.com" },
              "limits": [
                { "id": "codex:5h", "window": { "id": "5h" }, "amount": { "used": 35, "limit": 100 } }
              ]
            },
            {
              "provider": "xai-oauth",
              "metadata": { "email": "grok@gmail.com" },
              "limits": [
                { "id": "xai:5h", "window": { "id": "5h" }, "amount": { "used": 50, "limit": 100 } }
              ]
            }
          ]
        }
        """
        // Exclude xAI Grok via hiddenItemIDs (simulating unchecking xAI in Settings -> Visible usage items)
        let hidden = ["metric:omp-xai-0-7d", "detailSection:xAI Grok"]
        let snapshot = try OMPUsageParser.parse(jsonString: json, subprovider: "all", hiddenItemIDs: hidden)
        let primary = try #require(snapshot.primary)
        // Total accounts = 4 (AGY) + 1 (Codex) = 5 accounts (xAI's 1 account is excluded!)
        // Total used = 1.8 + 0.35 = 2.15 accounts -> 2.15 / 5 = 43.0%
        #expect(abs(primary.usedPercent - 43.0) < 0.001)
        #expect(primary.resetDescription == "4 AGY + 1 Codex")
        let labels = ProviderDescriptorRegistry.descriptor(for: .omp).presentation
            .rateWindowLabels(metadata: ProviderDescriptorRegistry.descriptor(for: .omp).metadata, snapshot: snapshot)
        #expect(labels.primary == "4 AGY + 1 Codex")
    }

    @Test
    func `omp usage parser preserves anthropic weekly duration in combined mode`() throws {
        let json = """
        {
          "reports": [
            {
              "provider": "anthropic",
              "limits": [
                {
                  "id": "anthropic:weekly",
                  "label": "Weekly Limit",
                  "window": { "id": "weekly", "durationMs": 604800000 },
                  "amount": { "used": 40, "limit": 100 }
                }
              ]
            }
          ]
        }
        """
        let snapshot = try OMPUsageParser.parse(jsonString: json, subprovider: "all")
        let extra = try #require(snapshot.extraRateWindows?.first { $0.id.contains("anthropic") })
        #expect(extra.window.windowMinutes == 10080)
        #expect(abs(extra.window.usedPercent - 40.0) < 0.001)
    }
    @Test
    func `omp usage parser omits aggregate windows when no matching quota exists`() throws {
        let json = """
        {
          "reports": [
            {
              "provider": "github-copilot",
              "limits": [
                {
                  "id": "copilot:chat",
                  "window": { "id": "monthly" },
                  "amount": { "used": 20, "limit": 200 }
                }
              ]
            }
          ]
        }
        """
        let snapshot = try OMPUsageParser.parse(jsonString: json, subprovider: "all")
        // No 5h or 7d capacity accounts contributed
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.extraRateWindows?.contains { $0.id.contains("chat") } == true)
    }

    @Test
    func `omp usage parser derives usage from remaining fields and skips unknown limits with missing amount`() throws {
        let json = """
        {
          "reports": [
            {
              "provider": "openai-codex",
              "limits": [
                {
                  "id": "codex:remaining-fraction",
                  "label": "Remaining Only",
                  "window": { "id": "5h" },
                  "amount": { "remainingFraction": 0.8 }
                },
                {
                  "id": "codex:missing-amount",
                  "label": "No Amount",
                  "window": { "id": "7d" }
                }
              ]
            }
          ]
        }
        """
        let snapshot = try OMPUsageParser.parse(jsonString: json, subprovider: "all")
        let extra = try #require(snapshot.extraRateWindows)
        // remainingFraction 0.8 should derive usedPercent = 20.0
        let remLimit = try #require(extra.first { $0.id.contains("5h") })
        #expect(abs(remLimit.window.usedPercent - 20.0) < 0.001)
        // missing-amount limit should be completely skipped, not treated as 0% used
        #expect(!extra.contains { $0.id.contains("7d") })
    }

    @Test
    func `omp usage parser preserves full email in breakdown for privacy redactor`() throws {
        let json = """
        {
          "reports": [
            {
              "provider": "google-antigravity",
              "metadata": { "email": "testuser@gmail.com" },
              "limits": [
                {
                  "id": "gemini:5h",
                  "window": { "id": "5h" },
                  "amount": { "used": 10, "limit": 100 }
                }
              ]
            }
          ]
        }
        """
        let snapshot = try OMPUsageParser.parse(jsonString: json, subprovider: "all")
        let agySection = try #require(snapshot.details.first { $0.title?.contains("Antigravity") == true })
        let row = try #require(agySection.rows.first)
        // The breakdown in secondaryValue must preserve the full email "testuser@gmail.com" so email redactors match it
        let secondary = try #require(row.secondaryValue)
        #expect(secondary.contains("testuser@gmail.com"))
        #expect(!secondary.hasPrefix("testuser:"))
    }

    @Test
    func `omp usage parser keeps aggregate identity neutral without subprovider email`() throws {
        let json = """
        {
          "capacity": {
            "google-antigravity": [
              { "window": "5h", "accounts": 4, "usedAccounts": 1, "remainingAccounts": 3 }
            ]
          },
          "reports": [
            {
              "provider": "google-antigravity",
              "metadata": { "email": "user1@gmail.com" },
              "limits": [
                { "id": "gemini:5h", "window": { "id": "5h" }, "amount": { "used": 10, "limit": 100 } }
              ]
            }
          ]
        }
        """
        let snapshot = try OMPUsageParser.parse(jsonString: json, subprovider: "agy")
        // Snapshot identity must remain neutral across multi-account aggregates
        #expect(snapshot.identity?.accountEmail == nil)
        #expect(snapshot.identity?.accountID == "google-antigravity")
        // Section title must reflect total capacity accounts (4), not just 1 report
        let agySection = try #require(snapshot.details.first { $0.title?.contains("Accounts") == true })
        #expect(agySection.title?.contains("(4)") == true)
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
