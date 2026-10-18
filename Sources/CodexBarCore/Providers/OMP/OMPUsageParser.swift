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
        do {
            let response = try JSONDecoder().decode(OMPUsageResponse.self, from: data)
            return self.makeSnapshot(response: response, subprovider: subprovider, hiddenItemIDs: hiddenItemIDs, now: now)
        } catch let error as DecodingError {
            throw OMPUsageError.parseFailed("Malformed OMP usage JSON payload: \(error.localizedDescription)")
        }
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
            return self.makeSubproviderSnapshot(response: response, target: normalized, now: now)
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
    // Provider-specific by design: This maps OMP subproviders to short display names.
    private static func shortNameForProvider(_ key: String) -> String {
        let k = key.lowercased()
        if k.contains("antigravity") || k.contains("agy") { return "AGY" }
        if k.contains("codex") { return "Codex" }
        if k.contains("copilot") { return "Copilot" }
        if k.contains("xai") || k.contains("grok") { return "Grok" }
        if k.contains("anthropic") || k.contains("claude") { return "Claude" }
        return key
    }

    // Provider-specific by design: This checks whether a subprovider's metrics or sections are hidden.
    private static func isProviderActive(
        key: String,
        hiddenSet: Set<String>) -> Bool
    {
        let k = key.lowercased()
        if k.contains("antigravity") || k.contains("agy") {
            let agyMetrics = ["omp-agy-gemini-5h", "omp-agy-gemini-7d", "omp-agy-3p-5h", "omp-agy-3p-7d"]
            return !hiddenSet.contains("detailSection:Google Antigravity") &&
                !hiddenSet.contains("detailSection:Google Antigravity Accounts") &&
                !agyMetrics.allSatisfy { hiddenSet.contains("metric:\($0)") }
        }
        if k.contains("codex") {
            let codexMetrics = ["omp-codex-0-5h", "omp-codex-0-7d"]
            return !hiddenSet.contains("detailSection:OpenAI Codex") &&
                !hiddenSet.contains("detailSection:OpenAI Codex Accounts") &&
                !codexMetrics.allSatisfy { hiddenSet.contains("metric:\($0)") }
        }
        if k.contains("copilot") {
            let copilotMetrics = ["omp-copilot-0-chat", "omp-copilot-0-completions"]
            return !hiddenSet.contains("detailSection:GitHub Copilot") &&
                !hiddenSet.contains("detailSection:GitHub Copilot Accounts") &&
                !copilotMetrics.allSatisfy { hiddenSet.contains("metric:\($0)") }
        }
        if k.contains("xai") || k.contains("grok") {
            let hasHiddenXAI = hiddenSet.contains("detailSection:xAI Grok") ||
                hiddenSet.contains("detailSection:xAI Grok Accounts") ||
                hiddenSet.contains("metric:omp-xai-0-7d") ||
                hiddenSet.contains { $0.hasPrefix("metric:omp-xai-") }
            return !hasHiddenXAI
        }
        if k.contains("anthropic") || k.contains("claude") {
            return !hiddenSet.contains("detailSection:Anthropic Claude") &&
                !hiddenSet.contains("detailSection:Anthropic Claude Accounts")
        }
        return true
    }


    public static func normalizeAmount(_ limit: OMPLimit) -> (usedPercent: Double, remainingPercent: Double, summaryText: String)? {
        guard let amount = limit.amount else {
            return nil
        }

        let usedPercent: Double
        let remPercent: Double

        if let frac = amount.usedFraction, frac.isFinite {
            usedPercent = min(100, max(0, frac * 100))
            remPercent = max(0, 100 - usedPercent)
        } else if let remFrac = amount.remainingFraction, remFrac.isFinite {
            remPercent = min(100, max(0, remFrac * 100))
            usedPercent = max(0, 100 - remPercent)
        } else if let rawUsed = amount.used, rawUsed.isFinite, let limitVal = amount.limit, limitVal > 0 {
            usedPercent = min(100, max(0, (rawUsed / limitVal) * 100))
            remPercent = max(0, 100 - usedPercent)
        } else if let rawRem = amount.remaining, rawRem.isFinite, let limitVal = amount.limit, limitVal > 0 {
            remPercent = min(100, max(0, (rawRem / limitVal) * 100))
            usedPercent = max(0, 100 - remPercent)
        } else if let rawUsed = amount.used, rawUsed.isFinite {
            usedPercent = min(100, max(0, rawUsed))
            remPercent = max(0, 100 - usedPercent)
        } else if let rawRem = amount.remaining, rawRem.isFinite {
            remPercent = min(100, max(0, rawRem))
            usedPercent = max(0, 100 - remPercent)
        } else {
            return nil
        }

        let summary: String = if let limitVal = amount.limit, limitVal > 0, (amount.unit ?? "").lowercased().contains("request"), let used = amount.used {
            "\(Int(used))/\(Int(limitVal)) requests"
        } else if let rem = amount.remaining, rem.isFinite, (amount.unit ?? "").lowercased() == "percent" || amount.limit == nil || amount.limit == 100 {
            "\(self.safePercentInt(from: rem))% left"
        } else {
            "\(self.safePercentInt(from: remPercent))% left"
        }

        return (usedPercent, remPercent, summary)
    }

    private struct LimitEntry {
        let fullEmail: String
        let used: Double
        let remaining: Double
        let resetsAt: Date?
        let windowId: String
    }

    private static func makeCombinedSnapshot(
        response: OMPUsageResponse,
        hiddenItemIDs: [String] = [],
        now: Date) -> UsageSnapshot
    {
        let nowMs = now.timeIntervalSince1970 * 1000

        // 1. Group Antigravity account limits
        let agyReports = response.reports.filter { $0.provider == "google-antigravity" }
        var agyGroups: [String: [LimitEntry]] = [
            "gemini-5h": [],
            "gemini-weekly": [],
            "3p-5h": [],
            "3p-weekly": [],
        ]

        for report in agyReports {
            let email = report.metadata?["email"] ?? report.metadata?["accountId"] ?? "account"
            var seenGroupsForAccount = Set<String>()
            for limit in report.limits ?? [] {
                let winId = (limit.window?.id ?? "").lowercased()
                let lid = limit.id.lowercased()

                // Provider-specific by design: This groups Antigravity quota families by model and window duration.
                let groupKey: String? = if lid.contains("gemini") && winId.contains("5h") {
                    "gemini-5h"
                } else if lid.contains("gemini") && (winId.contains("week") || winId.contains("7d")) {
                    "gemini-weekly"
                } else if (lid.contains("3p") || lid.contains("shared") || lid.contains("anthropic") || lid.contains("openai")) && winId.contains("5h") {
                    "3p-5h"
                } else if (lid.contains("3p") || lid.contains("shared") || lid.contains("anthropic") || lid.contains("openai")) && (winId.contains("week") || winId.contains("7d")) {
                    "3p-weekly"
                } else {
                    nil
                }

                guard let groupKey, !seenGroupsForAccount.contains(groupKey) else { continue }
                seenGroupsForAccount.insert(groupKey)

                guard let norm = self.normalizeAmount(limit) else { continue }
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }

                agyGroups[groupKey]?.append(LimitEntry(
                    fullEmail: email,
                    used: norm.usedPercent,
                    remaining: norm.remainingPercent,
                    resetsAt: resetsAt,
                    windowId: winId))
            }
        }

        // 2. Extra Rate Windows
        var extraRateWindows: [NamedRateWindow] = []

        if let entries = agyGroups["gemini-5h"], !entries.isEmpty {
            let avgUsed = entries.map(\.used).reduce(0, +) / Double(entries.count)
            let reset = entries.compactMap(\.resetsAt).min()
            extraRateWindows.append(NamedRateWindow(
                id: "omp-agy-gemini-5h",
                title: "Gemini 5h",
                window: RateWindow(usedPercent: avgUsed, windowMinutes: 300, resetsAt: reset, resetDescription: nil)))
        }

        if let entries = agyGroups["gemini-weekly"], !entries.isEmpty {
            let avgUsed = entries.map(\.used).reduce(0, +) / Double(entries.count)
            let reset = entries.compactMap(\.resetsAt).min()
            extraRateWindows.append(NamedRateWindow(
                id: "omp-agy-gemini-7d",
                title: "Gemini 7d",
                window: RateWindow(usedPercent: avgUsed, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)))
        }

        if let entries = agyGroups["3p-5h"], !entries.isEmpty {
            let avgUsed = entries.map(\.used).reduce(0, +) / Double(entries.count)
            let reset = entries.compactMap(\.resetsAt).min()
            extraRateWindows.append(NamedRateWindow(
                id: "omp-agy-3p-5h",
                title: "Claude & GPT (shared) 5h",
                window: RateWindow(usedPercent: avgUsed, windowMinutes: 300, resetsAt: reset, resetDescription: nil)))
        }

        if let entries = agyGroups["3p-weekly"], !entries.isEmpty {
            let avgUsed = entries.map(\.used).reduce(0, +) / Double(entries.count)
            let reset = entries.compactMap(\.resetsAt).min()
            extraRateWindows.append(NamedRateWindow(
                id: "omp-agy-3p-7d",
                title: "Claude & GPT (shared) 7d",
                window: RateWindow(usedPercent: avgUsed, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)))
        }

        let copilotReports = response.reports.filter { $0.provider == "github-copilot" }
        for (reportIndex, report) in copilotReports.enumerated() {
            for limit in report.limits ?? [] {
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                guard let norm = self.normalizeAmount(limit) else { continue }
                if limit.id.contains("chat") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-copilot-\(reportIndex)-chat",
                        title: "Chat Requests",
                        window: RateWindow(usedPercent: norm.usedPercent, windowMinutes: 43200, resetsAt: resetsAt, resetDescription: nil)))
                } else if limit.id.contains("completions") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-copilot-\(reportIndex)-completions",
                        title: "Completions",
                        window: RateWindow(usedPercent: norm.usedPercent, windowMinutes: 43200, resetsAt: resetsAt, resetDescription: nil)))
                }
            }
        }

        let codexReports = response.reports.filter { $0.provider == "openai-codex" }
        for (reportIndex, report) in codexReports.enumerated() {
            for limit in report.limits ?? [] {
                guard let norm = self.normalizeAmount(limit) else { continue }
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let winId = (limit.window?.id ?? "").lowercased()
                if winId.contains("5h") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-codex-\(reportIndex)-5h",
                        title: "Codex 5h",
                        window: RateWindow(usedPercent: norm.usedPercent, windowMinutes: 300, resetsAt: resetsAt, resetDescription: nil)))
                } else if winId.contains("7d") || winId.contains("week") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-codex-\(reportIndex)-7d",
                        title: "Codex 7d",
                        window: RateWindow(usedPercent: norm.usedPercent, windowMinutes: 10080, resetsAt: resetsAt, resetDescription: nil)))
                }
            }
        }

        let xaiReports = response.reports.filter { $0.provider == "xai-oauth" }
        for (reportIndex, report) in xaiReports.enumerated() {
            for limit in report.limits ?? [] {
                guard let norm = self.normalizeAmount(limit) else { continue }
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let lName = limit.label ?? "xAI Grok"
                let winId = (limit.window?.id ?? "").lowercased()
                let winMinutes = limit.window?.durationMs.flatMap { dur -> Int? in
                    guard dur.isFinite, dur > 0, dur < Double(Int.max) * 60_000 else { return nil }
                    return Int(dur / (60 * 1000))
                } ?? (winId.contains("5h") ? 300 : (winId.contains("month") ? 43200 : 10080))
                extraRateWindows.append(NamedRateWindow(
                    id: "omp-xai-\(reportIndex)-\(limit.id)",
                    title: lName,
                    window: RateWindow(
                        usedPercent: norm.usedPercent,
                        windowMinutes: winMinutes,
                        resetsAt: resetsAt,
                        resetDescription: nil)))
            }
        }

        let anthropicReports = response.reports.filter { $0.provider == "anthropic" }
        for (reportIndex, report) in anthropicReports.enumerated() {
            for limit in report.limits ?? [] {
                guard let norm = self.normalizeAmount(limit) else { continue }
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let lName = limit.label ?? "Claude Quota"
                let winId = (limit.window?.id ?? "").lowercased()
                let winMinutes = limit.window?.durationMs.flatMap { dur -> Int? in
                    guard dur.isFinite, dur > 0, dur < Double(Int.max) * 60_000 else { return nil }
                    return Int(dur / (60 * 1000))
                } ?? (winId.contains("week") || winId.contains("7d") ? 10080 : (winId.contains("month") ? 43200 : 300))
                extraRateWindows.append(NamedRateWindow(
                    id: "omp-anthropic-\(reportIndex)-\(limit.id)",
                    title: lName,
                    window: RateWindow(usedPercent: norm.usedPercent, windowMinutes: winMinutes, resetsAt: resetsAt, resetDescription: nil)))
            }
        }

        // 3. Compute Aggregate 5h and Weekly Windows using response.capacity totals
        let hiddenSet = Set(hiddenItemIDs)
        var total5hCapacityAccounts: Double = 0
        var used5hCapacityAccounts: Double = 0
        var totalWeeklyCapacityAccounts: Double = 0
        var usedWeeklyCapacityAccounts: Double = 0

        var contributing5hProviders: [String: Int] = [:]
        var contributingWeeklyProviders: [String: Int] = [:]

        for (providerKey, windows) in response.capacity ?? [:] {
            guard self.isProviderActive(key: providerKey, hiddenSet: hiddenSet) else { continue }

            for cap in windows {
                let winName = cap.window.lowercased()
                let dur = cap.durationMs ?? 0
                let accts = Int(cap.accounts)
                if winName.hasPrefix("5h") || dur == 18_000_000 {
                    total5hCapacityAccounts += cap.accounts
                    used5hCapacityAccounts += cap.usedAccounts
                    let normKey = self.shortNameForProvider(providerKey)
                    contributing5hProviders[normKey] = max(contributing5hProviders[normKey] ?? 0, accts)
                } else if winName.contains("7d") || winName.contains("week") || dur == 604_800_000 {
                    totalWeeklyCapacityAccounts += cap.accounts
                    usedWeeklyCapacityAccounts += cap.usedAccounts
                    let normKey = self.shortNameForProvider(providerKey)
                    contributingWeeklyProviders[normKey] = max(contributingWeeklyProviders[normKey] ?? 0, accts)
                }
            }
        }

        // Earliest resets across ALL contributing active providers
        var min5hResetDate: Date?
        var minWeeklyResetDate: Date?

        for report in response.reports {
            guard self.isProviderActive(key: report.provider, hiddenSet: hiddenSet) else { continue }
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

        func makeSummaryLabel(providers: [String: Int], fallback: String) -> String {
            guard !providers.isEmpty else { return fallback }
            let order = ["AGY", "Codex", "Copilot", "Grok", "Claude"]
            var parts: [String] = []
            for name in order {
                if let count = providers[name], count > 0 {
                    parts.append("\(count) \(name)")
                }
            }
            for (name, count) in providers where !order.contains(name) && count > 0 {
                parts.append("\(count) \(name)")
            }
            return parts.isEmpty ? fallback : parts.joined(separator: " + ")
        }

        let summary5h = makeSummaryLabel(providers: contributing5hProviders, fallback: "5-Hour")
        let summaryWeekly = makeSummaryLabel(providers: contributingWeeklyProviders, fallback: "Weekly")

        // Construct 5h aggregate window only when contributing quota exists
        var primaryWindow: RateWindow?
        if total5hCapacityAccounts > 0 {
            let usedPercent = min(100, max(0, (used5hCapacityAccounts / total5hCapacityAccounts) * 100))
            primaryWindow = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: min5hResetDate,
                resetDescription: summary5h)
        }

        var secondaryWindow: RateWindow?
        if totalWeeklyCapacityAccounts > 0 {
            let usedPercent = min(100, max(0, (usedWeeklyCapacityAccounts / totalWeeklyCapacityAccounts) * 100))
            secondaryWindow = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 10080,
                resetsAt: minWeeklyResetDate,
                resetDescription: summaryWeekly)
        }

        // 4. Detail sections grouped by Provider & Limit
        var detailSections: [ProviderDetailSection] = []

        // Section: Google Antigravity
        var agyRows: [ProviderDetailSection.Row] = []
        if let entries = agyGroups["gemini-5h"], !entries.isEmpty {
            let avgRem = entries.map(\.remaining).reduce(0, +) / Double(entries.count)
            let avgUsed = 100 - avgRem
            let resetDesc = entries.compactMap(\.resetsAt).min().map { UsageFormatter.resetDescription(from: $0) }
            let breakdown = entries.map { "\($0.fullEmail): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
            let progress = try? ProviderDetailSection.Row.Progress(used: avgUsed, total: 100)
            if let row = self.makeRow(
                id: "agy-gemini-5h",
                label: "Gemini 5h",
                value: "\(self.safePercentInt(from: avgRem))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                secondaryValue: breakdown,
                progress: progress,
                usageValue: avgUsed)
            {
                agyRows.append(row)
            }
        }

        if let entries = agyGroups["gemini-weekly"], !entries.isEmpty {
            let avgRem = entries.map(\.remaining).reduce(0, +) / Double(entries.count)
            let avgUsed = 100 - avgRem
            let resetDesc = entries.compactMap(\.resetsAt).min().map { UsageFormatter.resetDescription(from: $0) }
            let breakdown = entries.map { "\($0.fullEmail): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
            let progress = try? ProviderDetailSection.Row.Progress(used: avgUsed, total: 100)
            if let row = self.makeRow(
                id: "agy-gemini-7d",
                label: "Gemini 7d",
                value: "\(self.safePercentInt(from: avgRem))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                secondaryValue: breakdown,
                progress: progress,
                usageValue: avgUsed)
            {
                agyRows.append(row)
            }
        }

        if let entries = agyGroups["3p-5h"], !entries.isEmpty {
            let avgRem = entries.map(\.remaining).reduce(0, +) / Double(entries.count)
            let avgUsed = 100 - avgRem
            let breakdown = entries.map { "\($0.fullEmail): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
            let progress = try? ProviderDetailSection.Row.Progress(used: avgUsed, total: 100)
            if let row = self.makeRow(
                id: "agy-3p-5h",
                label: "Claude & GPT (shared) 5h",
                value: "\(self.safePercentInt(from: avgRem))% left",
                secondaryValue: breakdown,
                progress: progress,
                usageValue: avgUsed)
            {
                agyRows.append(row)
            }
        }

        if let entries = agyGroups["3p-weekly"], !entries.isEmpty {
            let avgRem = entries.map(\.remaining).reduce(0, +) / Double(entries.count)
            let avgUsed = 100 - avgRem
            let resetDesc = entries.compactMap(\.resetsAt).min().map { UsageFormatter.resetDescription(from: $0) }
            let breakdown = entries.map { "\($0.fullEmail): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
            let progress = try? ProviderDetailSection.Row.Progress(used: avgUsed, total: 100)
            if let row = self.makeRow(
                id: "agy-3p-7d",
                label: "Claude & GPT (shared) 7d",
                value: "\(self.safePercentInt(from: avgRem))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                secondaryValue: breakdown,
                progress: progress,
                usageValue: avgUsed)
            {
                agyRows.append(row)
            }
        }

        let agyCapCount = response.capacity?["google-antigravity"]?.first.map { Int($0.accounts) } ?? 0
        let agyWithoutUsageCount = response.accountsWithoutUsage?.filter { $0.provider == "google-antigravity" }.count ?? 0
        let totalAgyAccounts = max(agyReports.count + agyWithoutUsageCount, agyCapCount)
        if totalAgyAccounts > 0, let countRow = self.makeRow(id: "agy-account-count", label: "Connected Accounts", value: "\(totalAgyAccounts)") {
            agyRows.insert(countRow, at: 0)
        }
        let agyTitle = "Google Antigravity"
        if let agySection = self.makeSection(title: agyTitle, rows: agyRows) {
            detailSections.append(agySection)
        }

        // Section: GitHub Copilot
        var copilotRows: [ProviderDetailSection.Row] = []
        for report in copilotReports {
            let accountID = report.metadata?["accountId"] ?? "account"
            for limit in report.limits ?? [] {
                let resets = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let resetDesc = resets.map { UsageFormatter.resetDescription(from: $0) }
                guard let norm = self.normalizeAmount(limit) else { continue }
                let isExhausted = limit.status?.lowercased() == "exhausted" || norm.usedPercent >= 100
                let progress = try? ProviderDetailSection.Row.Progress(used: norm.usedPercent, total: 100)

                let label = limit.label ?? (limit.id.contains("chat") ? "Chat Requests" : "Completions")
                if let row = self.makeRow(
                    id: "copilot-\(limit.id)",
                    label: label,
                    value: "\(self.safePercentInt(from: norm.remainingPercent))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                    secondaryValue: "\(accountID) · \(norm.summaryText)" + (isExhausted ? " (exhausted)" : ""),
                    progress: progress,
                    usageValue: norm.usedPercent)
                {
                    copilotRows.append(row)
                }
            }
        }
        if let copilotSection = self.makeSection(title: "GitHub Copilot", rows: copilotRows) {
            detailSections.append(copilotSection)
        }

        // Section: OpenAI Codex
        var codexRows: [ProviderDetailSection.Row] = []
        for report in codexReports {
            let email = report.metadata?["email"] ?? report.metadata?["accountId"] ?? "account"
            let plan = report.metadata?["planType"].map { " (\($0))" } ?? ""
            for limit in report.limits ?? [] {
                guard let norm = self.normalizeAmount(limit) else { continue }
                let resets = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let resetDesc = resets.map { UsageFormatter.resetDescription(from: $0) }
                let winName = limit.label ?? limit.id
                let progress = try? ProviderDetailSection.Row.Progress(used: max(0.1, norm.usedPercent), total: 100)
                if let row = self.makeRow(
                    id: "codex-\(winName)",
                    label: winName,
                    value: "\(self.safePercentInt(from: norm.remainingPercent))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                    secondaryValue: "\(email)\(plan)",
                    progress: progress,
                    usageValue: norm.usedPercent)
                {
                    codexRows.append(row)
                }
            }
        }
        if let codexSection = self.makeSection(title: "OpenAI Codex", rows: codexRows) {
            detailSections.append(codexSection)
        }

        // Section: xAI Grok
        var xaiRows: [ProviderDetailSection.Row] = []
        for report in xaiReports {
            let email = report.metadata?["email"] ?? report.metadata?["accountId"] ?? "account"
            for limit in report.limits ?? [] {
                guard let norm = self.normalizeAmount(limit) else { continue }
                let resets = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let resetDesc = resets.map { UsageFormatter.resetDescription(from: $0) }
                let lName = limit.label ?? "Weekly Credits"
                let progress = try? ProviderDetailSection.Row.Progress(used: max(0.1, norm.usedPercent), total: 100)
                if let row = self.makeRow(
                    id: "xai-\(limit.id)",
                    label: lName,
                    value: "\(self.safePercentInt(from: norm.remainingPercent))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                    secondaryValue: email,
                    progress: progress,
                    usageValue: norm.usedPercent)
                {
                    xaiRows.append(row)
                }
            }
        }
        if let xaiSection = self.makeSection(title: "xAI Grok", rows: xaiRows) {
            detailSections.append(xaiSection)
        }

        // Section: Anthropic Claude
        var anthropicRows: [ProviderDetailSection.Row] = []
        for report in anthropicReports {
            let email = report.metadata?["email"] ?? report.metadata?["accountId"] ?? "account"
            for limit in report.limits ?? [] {
                guard let norm = self.normalizeAmount(limit) else { continue }
                let resets = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let resetDesc = resets.map { UsageFormatter.resetDescription(from: $0) }
                let lName = limit.label ?? limit.id
                let progress = try? ProviderDetailSection.Row.Progress(used: max(0.1, norm.usedPercent), total: 100)
                if let row = self.makeRow(
                    id: "anthropic-\(limit.id)",
                    label: lName,
                    value: "\(self.safePercentInt(from: norm.remainingPercent))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                    secondaryValue: email,
                    progress: progress,
                    usageValue: norm.usedPercent)
                {
                    anthropicRows.append(row)
                }
            }
        }
        if let anthropicSection = self.makeSection(title: "Anthropic Claude", rows: anthropicRows) {
            detailSections.append(anthropicSection)
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
        now: Date) -> UsageSnapshot
    {
        let matchingReports = response.reports.filter {
            $0.provider.lowercased() == target
        }

        let capacityMap = response.capacity ?? [:]
        let matchingCapacity = capacityMap.first {
            $0.key.lowercased() == target
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

        let providerShort = self.shortNameForProvider(target)
        let subproviderAccounts = Int(primary5hCap?.accounts ?? weeklyCap?.accounts ?? Double(matchingReports.count))
        let subproviderSummary = subproviderAccounts > 0 ? "\(subproviderAccounts) \(providerShort)" : providerShort

        var primaryWindow: RateWindow?
        if let cap = primary5hCap, cap.accounts > 0 {
            primaryWindow = RateWindow(
                usedPercent: min(100, max(0, (cap.usedAccounts / cap.accounts) * 100)),
                windowMinutes: 300,
                resetsAt: min5hResetDate,
                resetDescription: "\(subproviderSummary) (5h)")
        } else if let firstLimit = self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "5h") {
            primaryWindow = self.rateWindowFromLimit(firstLimit, defaultMinutes: 300, fallbackReset: min5hResetDate, resetDesc: "\(subproviderSummary) (5h)")
        }

        var secondaryWindow: RateWindow?
        if let cap = weeklyCap, cap.accounts > 0 {
            secondaryWindow = RateWindow(
                usedPercent: min(100, max(0, (cap.usedAccounts / cap.accounts) * 100)),
                windowMinutes: 10080,
                resetsAt: minWeeklyResetDate,
                resetDescription: "\(subproviderSummary) (Weekly)")
        } else if let firstLimit = self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "week")
            ?? self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "7d")
        {
            secondaryWindow = self.rateWindowFromLimit(firstLimit, defaultMinutes: 10080, fallbackReset: minWeeklyResetDate, resetDesc: "\(subproviderSummary) (Weekly)")
        } else if let firstLimit = self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "month") {
            secondaryWindow = self.rateWindowFromLimit(firstLimit, defaultMinutes: 43200, fallbackReset: minWeeklyResetDate, resetDesc: "\(subproviderSummary) (Monthly)")
        }

        var extraRateWindows: [NamedRateWindow] = []
        var seenLimitIDs: Set<String> = []
        for (reportIndex, report) in matchingReports.enumerated() {
            for limit in report.limits ?? [] {
                let scopedID = "\(limit.id)-\(reportIndex)"
                guard !seenLimitIDs.contains(scopedID) else { continue }
                seenLimitIDs.insert(scopedID)
                guard let norm = self.normalizeAmount(limit) else { continue }
                let title = limit.label ?? limit.id
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let winMinutes = limit.window?.durationMs.flatMap { dur -> Int? in
                    guard dur.isFinite, dur > 0, dur < Double(Int.max) * 60_000 else { return nil }
                    return Int(dur / (60 * 1000))
                }
                extraRateWindows.append(NamedRateWindow(
                    id: scopedID,
                    title: title,
                    window: RateWindow(
                        usedPercent: norm.usedPercent,
                        windowMinutes: winMinutes,
                        resetsAt: resetsAt,
                        resetDescription: nil)))
            }
        }

        var detailSections: [ProviderDetailSection] = []

        if !matchingReports.isEmpty {
            var acctRows: [ProviderDetailSection.Row] = []
            for report in matchingReports {
                let accountID = report.metadata?["email"]
                    ?? report.metadata?["accountId"]
                    ?? "account"
                var summaries: [String] = []
                for limit in report.limits ?? [] {
                    guard let norm = self.normalizeAmount(limit) else { continue }
                    let lName = limit.label ?? limit.id
                    summaries.append("\(lName): \(self.safePercentInt(from: norm.remainingPercent))% left")
                }
                if let row = self.makeRow(
                    id: "acct-\(accountID)",
                    label: accountID,
                    value: summaries.joined(separator: " · "))
                {
                    acctRows.append(row)
                }
            }
            let providerCapAccounts = response.capacity?[target]?.first.map { Int($0.accounts) }
                ?? (target == "agy" ? response.capacity?["google-antigravity"]?.first.map { Int($0.accounts) } : nil)
                ?? 0
            let withoutUsageCount = response.accountsWithoutUsage?.filter {
                $0.provider.lowercased() == target || (target == "agy" && $0.provider == "google-antigravity")
            }.count ?? 0
            let totalAccounts = max(matchingReports.count + withoutUsageCount, providerCapAccounts)
            if totalAccounts > matchingReports.count, let countRow = self.makeRow(id: "sub-account-count", label: "Connected Accounts", value: "\(totalAccounts)") {
                acctRows.insert(countRow, at: 0)
            }
            let sectionTitle = "\(self.displayNameForProvider(target)) Accounts"
            if let acctSection = self.makeSection(title: sectionTitle, rows: acctRows) {
                detailSections.append(acctSection)
            }
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .omp,
            accountEmail: nil,
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
        fallbackReset: Date?,
        resetDesc: String? = nil) -> RateWindow?
    {
        guard let norm = self.normalizeAmount(limit) else { return nil }
        let winId = (limit.window?.id ?? "").lowercased()
        let inferredMinutes: Int? = if winId.contains("month") {
            43200
        } else if winId.contains("week") || winId.contains("7d") {
            10080
        } else if winId.contains("5h") {
            300
        } else {
            defaultMinutes
        }
        let winMinutes = limit.window?.durationMs.flatMap { dur -> Int? in
            guard dur.isFinite, dur > 0, dur < Double(Int.max) * 60_000 else { return nil }
            return Int(dur / (60 * 1000))
        } ?? inferredMinutes
        let resetsAt = limit.window?.resetsAt.flatMap { Date(timeIntervalSince1970: $0 / 1000) } ?? fallbackReset
        return RateWindow(
            usedPercent: norm.usedPercent,
            windowMinutes: winMinutes,
            resetsAt: resetsAt,
            resetDescription: resetDesc)
    }
    private static func safePercentInt(from value: Double) -> Int {
        guard value.isFinite, !value.isNaN else { return 0 }
        return Int(min(100, max(0, value.rounded())))
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
