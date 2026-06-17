# devbox.nvim — agent guide

Tiny Neovim plugin: detects `devbox.json`, runs `devbox shellenv` async,
injects vars into `vim.env` so LSP/tools find devbox-managed binaries.

**This repo is a devbox project.** All work should happen inside
a devbox shell or via `devbox run` to ensure the correct toolchain
(markdownlint-cli). Do not rely on globally installed tools.
Run `devbox shell` before working, or prefix commands with `devbox run`.

## Structure

```
lua/devbox/
  init.lua   — all core logic (entry point, env resolution, cache, commands)
  config.lua — defaults + opts merge
  lsp.lua    — make_lsp_env() for explicit LSP client config
```

Entry point: `require("devbox").setup(opts)`.

## Key architecture

- **Never blocks startup.** `activate()` returns immediately even on cache miss — spawns `vim.fn.jobstart("devbox shellenv", ...)` in background.
- **Two-tier cache:** in-memory table + disk files at `stdpath("cache")/devbox/<cache_hash(project_root)>.json`. Invalidated when `devbox.json` mtime changes.
- **One-way activation:** once active, env stays for the session. No deactivation (see ADR 0001 — direnv.nvim precedent).
- **LSP injection:** `LspAttach` autocmd prepends devbox PATH into `client.config.cmd_env`. Only works for future attaches.
- **Shell env parser:** naive `export KEY=VALUE` regex — no bash evaluation. Excluded vars filtered by prefix patterns.
- **Tests use plenary.nvim test harness.** Run with `devbox run test`. Run a single file: `devbox run test-file FILE=tests/test_init_spec.lua`.
- **CI runs on push/PR** via `.github/workflows/ci.yml` — tests on Neovim stable + nightly, plus markdownlint.

## Commands (registered by setup)

| Command | Action |
|---|---|
| `DevboxActivate` | Manual activation for current dir |
| `DevboxStatus` | Show active/loading/inactive |
| `DevboxClearCache` | Clear in-memory + disk cache |

## Config quirks

- `strategy` field was removed — the plugin is always async. No blocking strategy is offered.
- `lsp.inject_env = true` is the default — disable if user manages LSP env manually.
- `exclude_env` defaults filter shell-specific vars (`ATUIN_`, `BASH_`, `HIST`, `PROMPT`, etc.). Extend by listing more Lua patterns.

## Common agent mistakes to avoid

- **Don't add test infrastructure** without asking — repo has none and that's intentional.
- **Don't refactor `_async_load` to be sync** — the whole design is async-first.
- **`_inject_path` doesn't re-inject** — only prepends if devbox PATH not already present.
- **Cache key is SHA256 truncated to 40 chars** — not collision-safe but fine for cache filenames.
- **`vim.fs.root` is Neovim ≥0.10** — fallback to `vim.fn.findfile` handles older versions.
