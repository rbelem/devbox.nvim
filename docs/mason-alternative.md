# devbox.nvim as a mason alternative

**Date:** 2026-06-02

## The idea

[mason.nvim](https://github.com/mason-org/mason.nvim) manages LSP servers,
formatters, and linters by downloading them to `~/.local/share/nvim/mason/bin/`.
devbox.nvim could fill the same niche — but instead of downloading binaries,
it relies on devbox/Nix to provide them.

The user adds LSP servers to `devbox.json`, devbox installs them via Nix, and
devbox.nvim **detects what's on PATH and auto-enables them**.

---

## What mason does (for comparison)

| Feature | mason approach |
|---|---|
| **Install servers** | Downloads tarballs/zips to `Mason/bin/` from GitHub releases, npm, PyPI, cargo, etc. |
| **Registry** | Hardcoded map of server name → download source |
| **Enable servers** | Via mason-lspconfig: `vim.lsp.config()` + `vim.lsp.enable()` |
| **UI** | `:Mason` TUI — browse, install, update, remove |
| **Formatters/linters** | Same download+register mechanism |
| **Version management** | Pins to a specific release, but user must manually update |

## What devbox provides (for comparison)

| Feature | devbox approach |
|---|---|
| **Install servers** | Adds package name to `devbox.json`, Nix resolves + installs |
| **Version management** | Via `devbox.json` inputs/flakes — lockfile, reproducible |
| **PATH injection** | `devbox shellenv` → exports PATH with nix-store paths |
| **Project scope** | Per-project `devbox.json`, not global |

## What devbox.nvim could add

A minimal **auto-enable** module: scan the devbox-injected PATH for known LSP
servers, then call `vim.lsp.enable()` for each one found.

No download logic needed — devbox/Nix handles that. No registry of download
sources needed — just a **static map** of binary names → lspconfig server names.

---

## Proposed module: `devbox.lsp.servers`

### Detection approach

After devbox activation resolves PATH, walk a known list:

```lua
-- Known LSP server binaries → nvim-lspconfig server name
local server_map = {
  ["lua-language-server"]           = "lua_ls",
  ["typescript-language-server"]    = "ts_ls",
  ["rust-analyzer"]                 = "rust_analyzer",
  ["vscode-json-language-server"]   = "jsonls",
  ["vscode-css-language-server"]    = "cssls",
  ["vscode-html-language-server"]   = "html",
  ["vscode-markdown-language-server"] = "marksman",  -- or "markdown_oxide"
  ["jdtls"]                         = "jdtls",
  ["bash-language-server"]          = "bashls",
  ["pyright-langserver"]            = "pyright",
  -- etc.
}
```

For each entry, check `vim.fn.executable(binary)` against the devbox PATH.
If found, call `vim.lsp.enable(server_name)`.

### Configuration

```lua
require("devbox").setup({
  lsp = {
    auto_enable = true,                    -- enable detected servers (default: false)
    auto_enable_filter = { "lua_ls", "rust_analyzer" },  -- only these (optional)
  }
})
```

### What users need

1. Add LSP servers to their project's `devbox.json`:
   ```json
   {
     "packages": [
       "lua-language-server",
       "rust-analyzer",
       "nodePackages.typescript-language-server"
     ]
   }
   ```
2. Run `devbox install`
3. Have `nvim-lspconfig` installed (for the server configs)
4. devbox.nvim detects and enables them automatically

---

## Comparison with mason

| Aspect | mason | devbox.nvim + devbox |
|---|---|---|
| **Server install** | `:MasonInstall lua-language-server` | `devbox add lua-language-server` |
| **Server source** | GitHub releases / npm / etc | Nixpkgs |
| **Version pinning** | Pinned to a mason registry version | Nix lockfile (`devbox.lock`) |
| **Editor IDE experience** | Out-of-box — all in Neovim | Cross-editor — tools work in VS Code too |
| **No internet install** | No (downloads tarballs) | No (Nix builds/downloads) |
| **Offline after install** | Yes | Yes (Nix store is persisted) |
| **Binary location** | `~/.local/share/nvim/mason/bin/` | `/nix/store/.../bin/` |
| **LSP config** | mason-lspconfig → `vim.lsp.config()` | nvim-lspconfig → `vim.lsp.enable()` |
| **UI for browsing** | `:Mason` TUI | `devbox search` (CLI) |
| **Auto-enable** | Yes (mason-lspconfig) | Proposed (devbox.lsp.servers) |
| **Per-project isolation** | No (all servers in one mason dir) | Yes (devbox.json is per-project) |

### Where devbox.nvim wins

- **No duplication.** If the team already uses devbox for the build toolchain,
  the same Nix packages provide LSP servers. mason downloads a separate copy.
- **Cross-editor consistency.** VS Code + Neovim use the same Nix-provided
  servers from the same `devbox.json`.
- **Reproducible.** `devbox.lock` pins exact versions. `devbox install` on CI
  or a new machine gets the same servers.
- **One source of truth.** Tools in `devbox.json` are the source; there's no
  separate mason state to keep in sync.

### Where mason still wins

- **Familiarity.** Users already know `:MasonInstall`.
- **UI.** The `:Mason` TUI is polished — browsing, updating, removing.
- **Simplicity.** `:MasonInstall lua-language-server` is one command.
  `devbox add` + `devbox install` is two (and requires Nix).

---

## Rough scope estimate

A minimal auto-enable module:

| Component | Lines | Complexity |
|---|---|---|
| Server binary → name map | ~40 lines | Low (static list) |
| Detection + enable logic | ~30 lines | Low (executable + vim.lsp.enable) |
| Config options | ~5 lines | Trivial |
| **Total** | **~75 lines** | **Low** |

This is an order of magnitude simpler than mason itself (which has installers,
registries, UI, package sources, etc.) because devbox handles the hard part.

---

## Open questions

1. **How to build the server map?** Auto-generate from nvim-lspconfig's server
   list, or maintain a curated subset?

2. **Should it also handle formatters/linters?** (e.g. stylua, prettier, eslint)
   Those don't need LSP enable — they're just on PATH. Maybe not needed.

3. **What about servers that need extra config?** (e.g., jdtls needs workspace
   folders, rust-analyzer needs cargo.toml) — nvim-lspconfig already handles
   these. `vim.lsp.enable()` uses nvim-lspconfig's defaults.

4. **Should auto-enable be opt-in or opt-out?** Default `false` (
   `lsp.auto_enable = false`) to avoid surprising users who manage servers
   manually. They opt in when they want this behavior.

5. **How does this interact with `lsp.inject_env`?** It supersedes it for
   server resolution — if devbox provides the servers on PATH, the `_inject_path`
   mechanism is less critical.
