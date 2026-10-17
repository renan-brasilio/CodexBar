import Foundation

public enum OMPUsageParser {
    public static func parse(
        jsonString: String,
        subprovider: String = "all",
        hiddenItemIDs: [String] = [],
        now: Date = Date()) throws -> UsageSnapshot
    {
        guard let data = jsonString.data(using: .utf8) else {
            throw OMPUsageError.parseFailed("Invalid UTF-8 in OMP usage output")
        }
        return try self.parse(data: data, subprovider: subprovider, hiddenItemIDs: hiddenItemIDs, now: now)
    }

    public static func parse(
        data: Data,
        subprovider: String = "all",
        hiddenItemIDs: [String] = [],
        now: Date = Date()) throws -> UsageSnapshot
    {
        let response = try JSONDecoder().decode(OMPUsageResponse.self, from: data)
        return self.makeSnapshot(response: response, subprovider: subprovider, hiddenItemIDs: hiddenItemIDs, now: now)
    }

    public static func makeSnapshot(
        response: OMPUsageResponse,
        subprovider: String,
        hiddenItemIDs: [String] = [],
        now: Date) -> UsageSnapshot
    {
        let normalized = self.normalizeSubproviderKey(subprovider)
        if normalized == "all" || normalized.isEmpty {
            return self.makeCombinedSnapshot(response: response, hiddenItemIDs: hiddenItemIDs, now: now)
        } else {
            return self.makeSubproviderSnapshot(response: response, target: normalized, hiddenItemIDs: hiddenItemIDs, now: now)
        }
    }

    public static func normalizeSubproviderKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Provider-specific by design: This normalizes user-selected subprovider aliases.
        switch trimmed {
        case "all", "combined", "":
            return "all"
        case "agy", "antigravity", "google", "google-antigravity":
            return "google-antigravity"
        case "codex", "openai", "openai-codex":
            return "openai-codex"
        case "claude", "anthropic":
            return "anthropic"
        case "copilot", "github", "github-copilot":
            return "github-copilot"
        case "grok", "xai", "xai-oauth":
            return "xai-oauth"
        default:
            return trimmed
        }
    }

    private static func displayNameForProvider(_ key: String) -> String {
        switch key.lowercased() {
        case "google-antigravity": return "Google Antigravity"
        case "openai-codex": return "OpenAI Codex"
        case "anthropic": return "Anthropic Claude"
        case "github-copilot": return "GitHub Copilot"
        case "xai-oauth": return "xAI Grok"
        default: return key
        }
    }

    private static func makeCombinedSnapshot(
        response: OMPUsageResponse,
        hiddenItemIDs: [String],
        now: Date) -> UsageSnapshot
    {
        var total5hAccounts: Double = 0
        var used5hAccounts: Double = 0
        var totalWeeklyAccounts: Double = 0
        var usedWeeklyAccounts: Double = 0
        var min5hResetDate: Date?
        var minWeeklyResetDate: Date?

        let capacityMap = response.capacity ?? [:]
        for (_, windows) in capacityMap {
            for cap in windows {
                let winName = cap.window.lowercased()
                let duration = cap.durationMs ?? 0
                if winName.hasPrefix("5h") || duration == 18_000_000 {
                    total5hAccounts += cap.accounts
                    used5hAccounts += cap.usedAccounts
                } else if winName.contains("7d") || winName.contains("week") || duration == 604_800_000 {
                    totalWeeklyAccounts += cap.accounts
                    usedWeeklyAccounts += cap.usedAccounts
                }
            }
        }

        let nowMs = now.timeIntervalSince1970 * 1000
        for report in response.reports {
            guard let limits = report.limits else { continue }
            for limit in limits {
                guard let window = limit.window,
                      let resetsAtMs = window.resetsAt,
                      resetsAtMs > nowMs
                else { continue }
                let resetDate = Date(timeIntervalSince1970: resetsAtMs / 1000)
                let winId = (window.id ?? "").lowercased()
                let dur = window.durationMs ?? 0
                if winId.contains("5h") || dur == 18_000_000 {
                    if min5hResetDate == nil || resetDate < min5hResetDate! {
                        min5hResetDate = resetDate
                    }
                } else if winId.contains("week") || winId.contains("7d") || dur == 604_800_000 {
                    if minWeeklyResetDate == nil || resetDate < minWeeklyResetDate! {
                        minWeeklyResetDate = resetDate
                    }
                }
            }
        }

        var raw5hWindow: RateWindow?
        if total5hAccounts > 0 {
            let usedPercent = (used5hAccounts / total5hAccounts) * 100
            raw5hWindow = RateWindow(
                usedPercent: min(100, max(0, usedPercent)),
                windowMinutes: 300,
                resetsAt: min5hResetDate,
                resetDescription: "\(String(format: "%.1f", total5hAccounts - used5hAccounts))/\(Int(total5hAccounts)) accts remaining")
        }

        var rawWeeklyWindow: RateWindow?
        if totalWeeklyAccounts > 0 {
            let usedPercent = (usedWeeklyAccounts / totalWeeklyAccounts) * 100
            rawWeeklyWindow = RateWindow(
                usedPercent: min(100, max(0, usedPercent)),
                windowMinutes: 10080,
                resetsAt: minWeeklyResetDate,
                resetDescription: "\(String(format: "%.1f", totalWeeklyAccounts - usedWeeklyAccounts))/\(Int(totalWeeklyAccounts)) accts remaining")
        }

        let isPrimaryHidden = hiddenItemIDs.contains("metric:primary")
        let isSecondaryHidden = hiddenItemIDs.contains("metric:secondary")

        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?

        if isSecondaryHidden && !isPrimaryHidden {
            // User selected only 5 accounts window
            primaryWindow = raw5hWindow
            secondaryWindow = nil
        } else if isPrimaryHidden && !isSecondaryHidden {
            // User selected only 6 accounts window
            primaryWindow = rawWeeklyWindow
            secondaryWindow = nil
        } else {
            // Both selected or default
            primaryWindow = raw5hWindow
            secondaryWindow = rawWeeklyWindow
        }

        var extraRateWindows: [NamedRateWindow] = []
        for (providerKey, windows) in capacityMap.sorted(by: { $0.key < $1.key }) {
            let shortName = self.shortNameForProvider(providerKey)
            for cap in windows {
                guard cap.accounts > 0 else { continue }
                let pct = min(100, max(0, (cap.usedAccounts / cap.accounts) * 100))
                let id = "omp-\(providerKey)-\(cap.window)"
                let title = "\(shortName) \(cap.window)"
                let winMinutes = (cap.window.lowercased().hasPrefix("5h") || cap.durationMs == 18_000_000)
                    ? 300 : ((cap.window.lowercased().contains("7d") || cap.durationMs == 604_800_000) ? 10080 : nil)
                extraRateWindows.append(NamedRateWindow(
                    id: id,
                    title: title,
                    window: RateWindow(
                        usedPercent: pct,
                        windowMinutes: winMinutes,
                        resetsAt: nil,
                        resetDescription: "\(String(format: "%.1f", cap.remainingAccounts))/\(Int(cap.accounts)) accts")))
            }
        }

        var detailSections: [ProviderDetailSection] = []

        var capacityRows: [ProviderDetailSection.Row] = []
        for (providerKey, windows) in capacityMap.sorted(by: { $0.key < $1.key }) {
            let label = self.displayNameForProvider(providerKey)
            let summaries = windows.map { cap in
                "\(cap.window): \(String(format: "%.1f", cap.remainingAccounts))/\(Int(cap.accounts))"
            }.joined(separator: ", ")
            let primaryCap = windows.first
            let progress = primaryCap.flatMap { cap in
                try? ProviderDetailSection.Row.Progress(used: cap.usedAccounts, total: cap.accounts)
            }
            if let row = self.makeRow(
                id: "cap-\(providerKey)",
                label: label,
                value: summaries,
                progress: progress,
                usageValue: primaryCap?.usedAccounts)
            {
                capacityRows.append(row)
            }
        }
        if let capSection = self.makeSection(title: "Capacity Breakdown", rows: capacityRows) {
            detailSections.append(capSection)
        }

        var accountRows: [ProviderDetailSection.Row] = []
        for report in response.reports {
            let accountID = report.metadata?["email"]
                ?? report.metadata?["accountId"]
                ?? report.metadata?["orgName"]
                ?? report.provider
            let pName = self.shortNameForProvider(report.provider)

            var limitSummaries: [String] = []
            if let limits = report.limits {
                for limit in limits {
                    if let amount = limit.amount, let usedPct = amount.used {
                        let lName = limit.label ?? limit.id
                        limitSummaries.append("\(lName): \(Int(usedPct))%")
                    }
                }
            }
            let summaryText = limitSummaries.isEmpty ? "Connected" : limitSummaries.joined(separator: " · ")
            if let row = self.makeRow(
                id: "acct-\(accountID)",
                label: "[\(pName)] \(accountID)",
                value: summaryText)
            {
                accountRows.append(row)
            }
        }
        if let acctSection = self.makeSection(title: "Connected Accounts (\(accountRows.count))", rows: accountRows) {
            detailSections.append(acctSection)
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .omp,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "omp",
            accountID: "all")

        return UsageSnapshot(
            primary: primaryWindow,
            secondary: secondaryWindow,
            extraRateWindows: extraRateWindows.isEmpty ? nil : extraRateWindows,
            details: detailSections,
            updatedAt: now,
            identity: identity)
    }

    private static func makeSubproviderSnapshot(
        response: OMPUsageResponse,
        target: String,
        hiddenItemIDs: [String],
        now: Date) -> UsageSnapshot
    {
        let matchingReports = response.reports.filter {
            $0.provider.lowercased() == target || $0.provider.lowercased().contains(target)
        }

        let capacityMap = response.capacity ?? [:]
        let matchingCapacity = capacityMap.first {
            $0.key.lowercased() == target || $0.key.lowercased().contains(target)
        }?.value ?? []

        var primary5hCap: OMPCapacityWindow?
        var weeklyCap: OMPCapacityWindow?
        for cap in matchingCapacity {
            let win = cap.window.lowercased()
            if win.hasPrefix("5h") || cap.durationMs == 18_000_000 {
                primary5hCap = cap
            } else if win.contains("7d") || win.contains("week") || cap.durationMs == 604_800_000 {
                weeklyCap = cap
            }
        }

        let nowMs = now.timeIntervalSince1970 * 1000
        var min5hResetDate: Date?
        var minWeeklyResetDate: Date?
        for report in matchingReports {
            for limit in report.limits ?? [] {
                guard let window = limit.window,
                      let resetsAtMs = window.resetsAt,
                      resetsAtMs > nowMs
                else { continue }
                let resetDate = Date(timeIntervalSince1970: resetsAtMs / 1000)
                let winId = (window.id ?? "").lowercased()
                let dur = window.durationMs ?? 0
                if winId.contains("5h") || dur == 18_000_000 {
                    if min5hResetDate == nil || resetDate < min5hResetDate! {
                        min5hResetDate = resetDate
                    }
                } else if winId.contains("week") || winId.contains("7d") || dur == 604_800_000 {
                    if minWeeklyResetDate == nil || resetDate < minWeeklyResetDate! {
                        minWeeklyResetDate = resetDate
                    }
                }
            }
        }

        var rawPrimary: RateWindow?
        if let cap = primary5hCap, cap.accounts > 0 {
            let desc = "\(String(format: "%.1f", cap.remainingAccounts))/\(Int(cap.accounts)) accts remaining"
            rawPrimary = RateWindow(
                usedPercent: min(100, max(0, (cap.usedAccounts / cap.accounts) * 100)),
                windowMinutes: 300,
                resetsAt: min5hResetDate,
                resetDescription: desc)
        } else if let firstLimit = self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "5h") {
            rawPrimary = self.rateWindowFromLimit(firstLimit, defaultMinutes: 300, fallbackReset: min5hResetDate)
        }

        var rawSecondary: RateWindow?
        if let cap = weeklyCap, cap.accounts > 0 {
            let desc = "\(String(format: "%.1f", cap.remainingAccounts))/\(Int(cap.accounts)) accts remaining"
            rawSecondary = RateWindow(
                usedPercent: min(100, max(0, (cap.usedAccounts / cap.accounts) * 100)),
                windowMinutes: 10080,
                resetsAt: minWeeklyResetDate,
                resetDescription: desc)
        } else if let firstLimit = self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "week")
            ?? self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "7d")
            ?? self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "month")
        {
            rawSecondary = self.rateWindowFromLimit(firstLimit, defaultMinutes: 10080, fallbackReset: minWeeklyResetDate)
        }

        let isPrimaryHidden = hiddenItemIDs.contains("metric:primary")
        let isSecondaryHidden = hiddenItemIDs.contains("metric:secondary")

        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?

        if isSecondaryHidden && !isPrimaryHidden {
            primaryWindow = rawPrimary
            secondaryWindow = nil
        } else if isPrimaryHidden && !isSecondaryHidden {
            primaryWindow = rawSecondary
            secondaryWindow = nil
        } else {
            primaryWindow = rawPrimary
            secondaryWindow = rawSecondary
        }

        var extraRateWindows: [NamedRateWindow] = []
        var seenLimitIDs: Set<String> = []
        for report in matchingReports {
            for limit in report.limits ?? [] {
                guard !seenLimitIDs.contains(limit.id) else { continue }
                seenLimitIDs.insert(limit.id)
                guard let amount = limit.amount, let used = amount.used ?? (amount.usedFraction.map { $0 * 100 }) else {
                    continue
                }
                let title = limit.label ?? limit.id
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let winMinutes = limit.window?.durationMs.flatMap { Int($0 / (60 * 1000)) }
                extraRateWindows.append(NamedRateWindow(
                    id: limit.id,
                    title: title,
                    window: RateWindow(
                        usedPercent: min(100, max(0, used)),
                        windowMinutes: winMinutes,
                        resetsAt: resetsAt,
                        resetDescription: limit.status)))
            }
        }

        var detailSections: [ProviderDetailSection] = []

        if !matchingCapacity.isEmpty {
            var capRows: [ProviderDetailSection.Row] = []
            for cap in matchingCapacity {
                let progress = try? ProviderDetailSection.Row.Progress(used: cap.usedAccounts, total: cap.accounts)
                if let row = self.makeRow(
                    id: "cap-\(cap.window)",
                    label: "\(cap.window) Window",
                    value: "\(String(format: "%.1f", cap.remainingAccounts))/\(Int(cap.accounts)) accts remaining",
                    progress: progress,
                    usageValue: cap.usedAccounts)
                {
                    capRows.append(row)
                }
            }
            if let capSection = self.makeSection(title: "\(self.displayNameForProvider(target)) Capacity", rows: capRows) {
                detailSections.append(capSection)
            }
        }

        if !matchingReports.isEmpty {
            var acctRows: [ProviderDetailSection.Row] = []
            for report in matchingReports {
                let accountID = report.metadata?["email"]
                    ?? report.metadata?["accountId"]
                    ?? report.metadata?["orgName"]
                    ?? "Account"
                var summaries: [String] = []
                for limit in report.limits ?? [] {
                    if let amount = limit.amount, let used = amount.used {
                        let lName = limit.label ?? limit.id
                        summaries.append("\(lName): \(Int(used))% (\(limit.status ?? "ok"))")
                    }
                }
                if let row = self.makeRow(
                    id: "acct-\(accountID)",
                    label: accountID,
                    value: summaries.joined(separator: " · "))
                {
                    acctRows.append(row)
                }
            }
            if let acctSection = self.makeSection(title: "Accounts (\(matchingReports.count))", rows: acctRows) {
                detailSections.append(acctSection)
            }
        }

        let firstEmail = matchingReports.first?.metadata?["email"]
        let identity = ProviderIdentitySnapshot(
            providerID: .omp,
            accountEmail: firstEmail,
            accountOrganization: nil,
            loginMethod: "omp",
            accountID: target)

        return UsageSnapshot(
            primary: primaryWindow,
            secondary: secondaryWindow,
            extraRateWindows: extraRateWindows.isEmpty ? nil : extraRateWindows,
            details: detailSections,
            updatedAt: now,
            identity: identity)
    }

    private static func findFirstLimit(matchingReports: [OMPAccountReport], windowPrefix: String) -> OMPLimit? {
        for report in matchingReports {
            for limit in report.limits ?? [] {
                let winId = (limit.window?.id ?? "").lowercased()
                if winId.contains(windowPrefix) {
                    return limit
                }
            }
        }
        return nil
    }

    private static func rateWindowFromLimit(
        _ limit: OMPLimit,
        defaultMinutes: Int?,
        fallbackReset: Date?) -> RateWindow?
    {
        guard let amount = limit.amount,
              let used = amount.used ?? (amount.usedFraction.map { $0 * 100 })
        else { return nil }
        let winMinutes = limit.window?.durationMs.flatMap { Int($0 / (60 * 1000)) } ?? defaultMinutes
        let resetsAt = limit.window?.resetsAt.flatMap { Date(timeIntervalSince1970: $0 / 1000) } ?? fallbackReset
        return RateWindow(
            usedPercent: min(100, max(0, used)),
            windowMinutes: winMinutes,
            resetsAt: resetsAt,
            resetDescription: limit.status)
    }

    private static func shortNameForProvider(_ key: String) -> String {
        switch key.lowercased() {
        case "google-antigravity": return "AGY"
        case "openai-codex": return "Codex"
        case "anthropic": return "Claude"
        case "github-copilot": return "Copilot"
        case "xai-oauth": return "xAI"
        default: return key
        }
    }

    private static func makeRow(
        id: String? = nil,
        label: String,
        value: String,
        secondaryValue: String? = nil,
        progress: ProviderDetailSection.Row.Progress? = nil,
        usageValue: Double? = nil) -> ProviderDetailSection.Row?
    {
        let safeLabel = String(label.prefix(120))
        let safeValue = String(value.prefix(120))
        let safeSecondary = secondaryValue.map { String($0.prefix(120)) }
        return try? ProviderDetailSection.Row(
            id: id.map { String($0.prefix(120)) },
            label: safeLabel,
            value: safeValue,
            secondaryValue: safeSecondary,
            progress: progress,
            usageValue: usageValue)
    }

    private static func makeSection(title: String, rows: [ProviderDetailSection.Row]) -> ProviderDetailSection? {
        guard !rows.isEmpty else { return nil }
        let capped = Array(rows.prefix(ProviderDetailSection.maximumRowsPerSection))
        return try? ProviderDetailSection(title: String(title.prefix(120)), rows: capped)
    }
}
