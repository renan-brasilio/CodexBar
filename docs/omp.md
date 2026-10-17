---
summary: "OMP provider notes: combined AI coding provider limits, subprovider selection, and multi-account capacity aggregation."
read_when:
  - Configuring or debugging the OMP provider
  - Working with combined limits across providers (Antigravity, Codex, Claude, Copilot, xAI Grok)
  - Selecting subproviders in OMP settings or via CLI
---

# OMP provider

CodexBar can read AI limits and aggregated provider capacity from OMP (`omp usage --json`), including multi-account Google Antigravity quotas, OpenAI Codex limits, Anthropic Claude, GitHub Copilot, and xAI Grok.

## Subproviders

In Settings → Providers → OMP, choose which limits to display:
- **Combined (All Limits)**: Combines 5-hour and weekly capacity across all connected accounts and providers.
- **Google Antigravity (agy)**: Shows Antigravity's combined 5-hour and 7-day capacity across all signed-in Google accounts, plus shared 3p Claude/GPT and Gemini limits.
- **OpenAI Codex**: Shows Codex 5-hour and weekly limits.
- **Anthropic Claude**: Shows Claude quota limits.
- **GitHub Copilot**: Shows Copilot requests and completions.
- **xAI Grok**: Shows GrokBot and SuperGrok credits.
- **Custom Subprovider**: Filters by any custom provider key reported by OMP.

## CLI Usage

Fetch usage from OMP via CodexBar CLI:
```bash
codexbar usage --provider omp
```

Override subprovider via environment:
```bash
OMP_SUBPROVIDER=agy codexbar usage --provider omp
OMP_SUBPROVIDER=codex codexbar usage --provider omp
```
