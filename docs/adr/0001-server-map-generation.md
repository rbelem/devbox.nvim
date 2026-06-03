# ADR 0001: Auto-generate server map from nvim-lspconfig

**Status:** Accepted
**Date:** 2026-06-02

## Context

devbox.nvim's auto-enable feature needs a mapping from LSP server binary names
(e.g., `lua-language-server`) to lspconfig server names (e.g., `lua_ls`). There
are ~200 known LSP servers in nvim-lspconfig. The mapping must be maintained
somehow.

## Options considered

### Option A: Curated static list (~40 servers)

Ship a hand-maintained Lua table in the plugin repo. Users extend via
`add_mapping()` for anything not covered.

- Pro: no runtime deps on nvim-lspconfig
- Pro: zero startup cost
- Con: drifts from nvim-lspconfig over time — new servers aren't auto-detected
- Con: user must manually add any server outside the curated 40
- Con: ongoing maintenance burden for plugin maintainers

### Option B: Auto-generated from nvim-lspconfig (chosen)

A generator script walks nvim-lspconfig's server configurations at install time,
extracts `default_config.cmd[1]` for each server, and produces a JSON cache
file. The cache is invalidated when nvim-lspconfig's file *contents* change
(SHA of concatenated file contents). Generation runs lazily on first `detect()` call.

- Pro: always covers every server nvim-lspconfig knows about
- Pro: no upstream maintenance burden — the generator adapts automatically
- Pro: cache makes startup fast on subsequent loads
- Pro: nvim-lspconfig is optional — feature is gated behind `pcall(require)`
- Con: ~50-300ms generation cost on cache miss (first run or nvim-lspconfig update)
- Con: generator complexity (walk config files, pcall dynamic cmds, SHA check)

### Option C: Load-time in-memory generation

Same as Option B but regenerate on every Neovim start instead of caching.

- Pro: never stale
- Con: requires requiring 200+ config files on every startup = unacceptable latency

## Decision

Adopt Option B (auto-generated from nvim-lspconfig, cached to JSON).

## Consequences

- nvim-lspconfig is optional — feature disabled gracefully if not installed
- First detect() in a fresh session (or after nvim-lspconfig update) pays ~50-300ms
- Subsequent detects are ~0.1ms (JSON parse from cache)
- Users with exotic or custom servers extend via `add_mapping()`
- The generator handles dynamic `cmd` functions via `pcall`; failures are logged
  and the server is skipped
- Cache invalidation uses SHA of file contents, not filenames — catches
  content edits, binary renames, adds, and removes
- CI must install nvim-lspconfig for generator tests
