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

    private struct LimitEntry {
        let emailShort: String
        let fullEmail: String
        let used: Double
        let remaining: Double
        let resetsAt: Date?
        let windowId: String
    }

    private static func makeCombinedSnapshot(
        response: OMPUsageResponse,
        hiddenItemIDs: [String],
        now: Date) -> UsageSnapshot
    {
        let nowMs = now.timeIntervalSince1970 * 1000

        // 1. Collect Antigravity account limits
        let agyReports = response.reports.filter { $0.provider == "google-antigravity" }

        var agyGroups: [String: [LimitEntry]] = [
            "gemini-5h": [],
            "gemini-weekly": [],
            "3p-5h": [],
            "3p-weekly": [],
        ]

        for report in agyReports {
            let email = report.metadata?["email"] ?? report.metadata?["accountId"] ?? "account"
            let emailShort = email.components(separatedBy: "@").first ?? email
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

                let used = limit.amount?.used ?? (limit.amount?.usedFraction.map { $0 * 100 } ?? 0)
                let rem = limit.amount?.remaining ?? (limit.amount?.remainingFraction.map { $0 * 100 } ?? (100 - used))
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }

                agyGroups[groupKey]?.append(LimitEntry(
                    emailShort: emailShort,
                    fullEmail: email,
                    used: min(100, max(0, used.isFinite ? used : 0)),
                    remaining: min(100, max(0, rem.isFinite ? rem : 100)),
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
                if limit.id.contains("chat") {
                    let used = (limit.amount?.used ?? 0) >= (limit.amount?.limit ?? 1) ? 100.0 : 0.0
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-copilot-\(reportIndex)-chat",
                        title: "Chat Requests",
                        window: RateWindow(usedPercent: used, windowMinutes: 43200, resetsAt: resetsAt, resetDescription: nil)))
                } else if limit.id.contains("completions") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-copilot-\(reportIndex)-completions",
                        title: "Completions",
                        window: RateWindow(usedPercent: 0, windowMinutes: 43200, resetsAt: resetsAt, resetDescription: nil)))
                }
            }
        }

        let codexReports = response.reports.filter { $0.provider == "openai-codex" }
        for (reportIndex, report) in codexReports.enumerated() {
            for limit in report.limits ?? [] {
                let rawUsed = limit.amount?.used ?? (limit.amount?.usedFraction.map { $0 * 100 } ?? 0)
                let used = min(100, max(0, rawUsed.isFinite ? rawUsed : 0))
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let winId = (limit.window?.id ?? "").lowercased()
                if winId.contains("5h") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-codex-\(reportIndex)-5h",
                        title: "Codex 5h",
                        window: RateWindow(usedPercent: used, windowMinutes: 300, resetsAt: resetsAt, resetDescription: nil)))
                } else if winId.contains("7d") || winId.contains("week") {
                    extraRateWindows.append(NamedRateWindow(
                        id: "omp-codex-\(reportIndex)-7d",
                        title: "Codex 7d",
                        window: RateWindow(usedPercent: used, windowMinutes: 10080, resetsAt: resetsAt, resetDescription: nil)))
                }
            }
        }

        let xaiReports = response.reports.filter { $0.provider == "xai-oauth" }
        for (reportIndex, report) in xaiReports.enumerated() {
            for limit in report.limits ?? [] {
                let rawUsed = limit.amount?.used ?? 0
                let used = min(100, max(0, rawUsed.isFinite ? rawUsed : 0))
                let resetsAt = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                extraRateWindows.append(NamedRateWindow(
                    id: "omp-xai-\(reportIndex)-7d",
                    title: "xAI Grok",
                    window: RateWindow(usedPercent: used, windowMinutes: 10080, resetsAt: resetsAt, resetDescription: nil)))
            }
        }

        // 3. Top Primary and Secondary Windows - Dynamically aggregated across accounts
        let agy5hCount = agyGroups["gemini-5h"]?.count ?? 0
        let agy5hUsedSum = agyGroups["gemini-5h"]?.map(\.used).reduce(0, +) ?? 0

        var codex5hCount = 0
        var codex5hUsedSum: Double = 0
        for report in codexReports {
            if let lim = report.limits?.first(where: { ($0.window?.id ?? "").contains("5h") }) {
                codex5hCount += 1
                let u = lim.amount?.used ?? 0
                codex5hUsedSum += u.isFinite ? u : 0
            }
        }

        let total5hCount = Double(agy5hCount + codex5hCount)
        let total5hUsedSum = agy5hUsedSum + codex5hUsedSum
        let combined5hUsedPercent = total5hCount > 0 ? min(100, max(0, total5hUsedSum / total5hCount)) : 0
        let min5hReset = (agyGroups["gemini-5h"]?.compactMap(\.resetsAt) ?? []).min()

        let raw5hWindow = RateWindow(
            usedPercent: combined5hUsedPercent,
            windowMinutes: 300,
            resetsAt: min5hReset,
            resetDescription: nil)

        // Weekly Window dynamically aggregated across Antigravity, Codex, and xAI
        let agyWeeklyCount = agyGroups["3p-weekly"]?.count ?? agyGroups["gemini-weekly"]?.count ?? 0
        let agyWeeklyUsedSum = agyGroups["3p-weekly"]?.map(\.used).reduce(0, +)
            ?? agyGroups["gemini-weekly"]?.map(\.used).reduce(0, +) ?? 0

        var codexWeeklyCount = 0
        var codexWeeklyUsedSum: Double = 0
        for report in codexReports {
            if let lim = report.limits?.first(where: { ($0.window?.id ?? "").contains("7d") || ($0.window?.id ?? "").contains("week") }) {
                codexWeeklyCount += 1
                let u = lim.amount?.used ?? 0
                codexWeeklyUsedSum += u.isFinite ? u : 0
            }
        }

        var xaiWeeklyCount = 0
        var xaiWeeklyUsedSum: Double = 0
        for report in xaiReports {
            if let lim = report.limits?.first {
                xaiWeeklyCount += 1
                let u = lim.amount?.used ?? 0
                xaiWeeklyUsedSum += u.isFinite ? u : 0
            }
        }

        let totalWeeklyCount = Double(agyWeeklyCount + codexWeeklyCount + xaiWeeklyCount)
        let totalWeeklyUsedSum = agyWeeklyUsedSum + codexWeeklyUsedSum + xaiWeeklyUsedSum
        let combinedWeeklyUsedPercent = totalWeeklyCount > 0 ? min(100, max(0, totalWeeklyUsedSum / totalWeeklyCount)) : 0
        let minWeeklyReset = (agyGroups["3p-weekly"]?.compactMap(\.resetsAt) ?? []).min()
            ?? (agyGroups["gemini-weekly"]?.compactMap(\.resetsAt) ?? []).min()

        let rawWeeklyWindow = RateWindow(
            usedPercent: combinedWeeklyUsedPercent,
            windowMinutes: 10080,
            resetsAt: minWeeklyReset,
            resetDescription: nil)

        let isPrimaryHidden = hiddenItemIDs.contains("metric:primary")
        let isSecondaryHidden = hiddenItemIDs.contains("metric:secondary")

        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?

        if isSecondaryHidden && !isPrimaryHidden {
            primaryWindow = raw5hWindow
            secondaryWindow = nil
        } else if isPrimaryHidden && !isSecondaryHidden {
            primaryWindow = rawWeeklyWindow
            secondaryWindow = nil
        } else {
            primaryWindow = raw5hWindow
            secondaryWindow = rawWeeklyWindow
        }

        // 4. Detail sections grouped by Provider & Limit
        var detailSections: [ProviderDetailSection] = []

        // Section: Google Antigravity
        var agyRows: [ProviderDetailSection.Row] = []
        if let entries = agyGroups["gemini-5h"], !entries.isEmpty {
            let avgRem = entries.map(\.remaining).reduce(0, +) / Double(entries.count)
            let avgUsed = 100 - avgRem
            let resetDesc = entries.compactMap(\.resetsAt).min().map { UsageFormatter.resetDescription(from: $0) }
            let breakdown = entries.map { "\($0.emailShort): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
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
            let breakdown = entries.map { "\($0.emailShort): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
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
            let breakdown = entries.map { "\($0.emailShort): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
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
            let breakdown = entries.map { "\($0.emailShort): \(self.safePercentInt(from: $0.remaining))%" }.joined(separator: " · ")
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

        let agyTitle = agyReports.count > 0 ? "Google Antigravity (\(agyReports.count) accounts)" : "Google Antigravity"
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
                let used = limit.amount?.used ?? 0
                let limitVal = limit.amount?.limit ?? 0
                let limitText = limitVal > 0 ? "\(Int(used))/\(Int(limitVal))" : "\(Int(used))"

                if limit.id.contains("chat") {
                    let isExhausted = limit.status?.lowercased() == "exhausted" || (limitVal > 0 && used >= limitVal)
                    let usedPercent = isExhausted ? 100.0 : min(100, max(0, limitVal > 0 ? (used / limitVal) * 100 : 0))
                    let remPercent = max(0, 100 - usedPercent)
                    let progress = try? ProviderDetailSection.Row.Progress(used: usedPercent, total: 100)
                    if let row = self.makeRow(
                        id: "copilot-chat",
                        label: limit.label ?? "Chat Requests",
                        value: "\(self.safePercentInt(from: remPercent))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                        secondaryValue: "\(accountID) · \(limitText) requests" + (isExhausted ? " (exhausted)" : ""),
                        progress: progress,
                        usageValue: usedPercent)
                    {
                        copilotRows.append(row)
                    }
                } else if limit.id.contains("completions") {
                    let usedPercent = limitVal > 0 ? (used / limitVal) * 100 : 0
                    let remPercent = max(0, 100 - usedPercent)
                    let progress = try? ProviderDetailSection.Row.Progress(used: min(100, max(0, usedPercent)), total: 100)
                    if let row = self.makeRow(
                        id: "copilot-completions",
                        label: limit.label ?? "Completions",
                        value: "\(self.safePercentInt(from: remPercent))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                        secondaryValue: "\(accountID) · \(limitText) requests",
                        progress: progress,
                        usageValue: usedPercent)
                    {
                        copilotRows.append(row)
                    }
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
                let used = limit.amount?.used ?? 0
                let rem = max(0, 100 - used)
                let resets = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let resetDesc = resets.map { UsageFormatter.resetDescription(from: $0) }
                let winName = limit.label ?? limit.id
                let progress = try? ProviderDetailSection.Row.Progress(used: max(0.1, used), total: 100)
                if let row = self.makeRow(
                    id: "codex-\(winName)",
                    label: winName,
                    value: "\(self.safePercentInt(from: rem))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                    secondaryValue: "\(email)\(plan)",
                    progress: progress,
                    usageValue: used)
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
                let used = limit.amount?.used ?? 0
                let rem = max(0, 100 - used)
                let resets = limit.window?.resetsAt.flatMap { $0 > nowMs ? Date(timeIntervalSince1970: $0 / 1000) : nil }
                let resetDesc = resets.map { UsageFormatter.resetDescription(from: $0) }
                let lName = limit.label ?? "Weekly Credits"
                let progress = try? ProviderDetailSection.Row.Progress(used: max(0.1, used), total: 100)
                if let row = self.makeRow(
                    id: "xai-\(lName)",
                    label: lName,
                    value: "\(self.safePercentInt(from: rem))% left" + (resetDesc.map { " (\($0))" } ?? ""),
                    secondaryValue: email,
                    progress: progress,
                    usageValue: used)
                {
                    xaiRows.append(row)
                }
            }
        }
        if let xaiSection = self.makeSection(title: "xAI Grok", rows: xaiRows) {
            detailSections.append(xaiSection)
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

        var rawPrimary: RateWindow?
        if let cap = primary5hCap, cap.accounts > 0 {
            rawPrimary = RateWindow(
                usedPercent: min(100, max(0, (cap.usedAccounts / cap.accounts) * 100)),
                windowMinutes: 300,
                resetsAt: min5hResetDate,
                resetDescription: nil)
        } else if let firstLimit = self.findFirstLimit(matchingReports: matchingReports, windowPrefix: "5h") {
            rawPrimary = self.rateWindowFromLimit(firstLimit, defaultMinutes: 300, fallbackReset: min5hResetDate)
        }

        var rawSecondary: RateWindow?
        if let cap = weeklyCap, cap.accounts > 0 {
            rawSecondary = RateWindow(
                usedPercent: min(100, max(0, (cap.usedAccounts / cap.accounts) * 100)),
                windowMinutes: 10080,
                resetsAt: minWeeklyResetDate,
                resetDescription: nil)
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
        for (reportIndex, report) in matchingReports.enumerated() {
            for limit in report.limits ?? [] {
                let scopedID = "\(limit.id)-\(reportIndex)"
                guard !seenLimitIDs.contains(scopedID) else { continue }
                seenLimitIDs.insert(scopedID)
                guard let amount = limit.amount, let used = amount.used ?? (amount.usedFraction.map { $0 * 100 }) else {
                    continue
                }
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
                        usedPercent: min(100, max(0, used.isFinite ? used : 0)),
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
                    if let amount = limit.amount, let used = amount.used {
                        let lName = limit.label ?? limit.id
                        summaries.append("\(lName): \(self.safePercentInt(from: max(0, 100 - used)))% left")
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
            if let acctSection = self.makeSection(title: "\(self.displayNameForProvider(target)) Accounts (\(matchingReports.count))", rows: acctRows) {
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
        let winMinutes = limit.window?.durationMs.flatMap { dur -> Int? in
            guard dur.isFinite, dur > 0, dur < Double(Int.max) * 60_000 else { return nil }
            return Int(dur / (60 * 1000))
        } ?? defaultMinutes
        let resetsAt = limit.window?.resetsAt.flatMap { Date(timeIntervalSince1970: $0 / 1000) } ?? fallbackReset
        return RateWindow(
            usedPercent: min(100, max(0, used.isFinite ? used : 0)),
            windowMinutes: winMinutes,
            resetsAt: resetsAt,
            resetDescription: nil)
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
