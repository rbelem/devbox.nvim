# devbox.nvim

[![Discord](https://img.shields.io/discord/903306922852245526?style=flat-square&label=devbox&logo=discord&logoColor=white&color=5865F2)](https://discord.gg/jetify)
[![License](https://img.shields.io/github/license/rbelem/devbox.nvim?style=flat-square&color=blue)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D%200.10-57A143?style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Latest release](https://img.shields.io/github/v/release/rbelem/devbox.nvim?style=flat-square&color=orange&sort=semver)](https://github.com/rbelem/devbox.nvim/releases)
[![Built with Devbox](https://www.jetify.com/img/devbox/shield_galaxy.svg)](https://www.jetify.com/devbox/docs/contributor-quickstart/)

Seamless [Devbox](https://www.jetify.com/devbox/) environment integration for
Neovim.

Open any file inside a Devbox project — the plugin detects `devbox.json`,
resolves the environment, and injects variables into `vim.env` so LSP servers,
formatters, linters, and tools find the right binaries without global installs.
No manual `devbox shell` needed.

Never blocks startup. Disk cache makes repeat opens instant; async
`devbox shellenv` resolves the first time in the background.

---

## Features

- **Auto-activation** — Detects `devbox.json` on `BufReadPost`/`BufNewFile`;
  re-activates on `DirChanged`
- **Disk cache** — First resolve per project is async (~250ms); subsequent
  opens load from disk (~0.4ms)
- **LSP integration** — `LspAttach` auto‑injects devbox `PATH` into LSP client
  environments
- **Smart env filtering** — Skips shell-specific variables (`ATUIN_`, `BASH_`,
  `HIST`, `PROMPT`, `SHELL`, `TERM`, etc.)
- **Env snapshot** — Captures pre‑activation state; `deactivate()` restores it
  fully
- **Commands** — `DevboxActivate`, `DevboxDeactivate`, `DevboxStatus`,
  `DevboxClearCache`

## Requirements

- Neovim >= **0.10** (uses `vim.fs.root`)
- [Devbox](https://www.jetify.com/devbox/docs/installing-devbox/) installed on
  `$PATH`
- A project with `devbox.json`

## Installation

**lazy.nvim** (recommended):

```lua
{
  "rbelem/devbox.nvim",
  opts = {}, -- uses defaults below
}
```

**vim.pack** (Neovim 0.12+):

```lua
vim.pack.add {
  src = "https://github.com/rbelem/devbox.nvim",
}
require("devbox").setup({})
```

**Manual** (any plugin manager):

```lua
require("devbox").setup({})
```

## Configuration

`devbox.nvim` works out of the box with no configuration. Override only
what you need:

```lua
require("devbox").setup({
  silent = true,         -- suppress activation/deactivation notifications
  auto_activate = false, -- manual :DevboxActivate only
})
```

Full defaults:

```lua
{
  auto_activate  = true,            -- auto-activate on buffer open
  silent         = false,           -- suppress notifications
  devbox_path    = "devbox",        -- path to devbox binary
  lsp            = { inject_env = true },
  exclude_env    = {
    "^ATUIN_",                      -- shell-specific vars (Lua patterns)
    "^BLE_",
    "_PREEXEC_",
    "^BASH_",
    "^SHELL",
    "^TERM",
    "^LS_COLORS",
    "^HIST",
    "^PROMPT",
  },
}
```

## Commands

| Command | Description |
| --- | --- |
| `:DevboxActivate` | Activate devbox env for current project |
| `:DevboxDeactivate` | Restore `vim.env` to pre‑activation state |
| `:DevboxStatus` | Show activation state (active, loading, inactive) |
| `:DevboxClearCache` | Clear both in‑memory and disk caches |

## How It Works

1. Open a file inside a project with `devbox.json`
2. Walk up the tree to find the project root
3. **Cache lookup** — determines the path through one of:
   - **In-memory hit** — env already resolved this session: instant
   - **Disk hit** — load from disk, auto-refresh in background: ~0.4ms
   - **Miss** — run `devbox shellenv` async via `jobstart`: ~250ms
4. Parse `export KEY=VALUE` lines, filter excluded vars, write to `vim.env`
5. `LspAttach` hook injects devbox `PATH` into LSP clients
6. `:DevboxDeactivate` restores `vim.env` from the pre-activation snapshot

Cache is invalidated automatically when `devbox.json` mtime changes.

## Advanced Usage

### LSP Module

By default, devbox.nvim injects `PATH` into LSP clients automatically via
`LspAttach` when the env is active. No configuration needed.

If you need explicit control (e.g. merging env vars for a specific server),
the `devbox.lsp` module provides `make_lsp_env()`:

```lua
local devbox_lsp = require("devbox.lsp")

-- Option A: before_init (Neovim 0.11+)
vim.lsp.config("jdtls", {
  before_init = function(params, cfg)
    local env = devbox_lsp.make_lsp_env()
    if env then
      cfg.cmd_env = env
    end
  end,
})

-- Option B: LspAttach autocmd (Neovim 0.10)
-- Note: make_lsp_env() replaces PATH entirely with the devbox-resolved
-- value (which already includes system paths). The automatic LspAttach
-- hook used by the plugin prepends devbox PATH to the existing value
-- instead — no difference in practice since devbox shellenv includes
-- the full system PATH.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      local env = devbox_lsp.make_lsp_env()
      if env then
        client.config.cmd_env = env
      end
    end
  end,
})
```

## FAQ

**Q: Does this replace `devbox shell`?**
No. It injects env variables into Neovim's process so tools inside the editor
find devbox-managed binaries. You still use `devbox shell` in your terminal for
interactive work.

**Q: What happens if `devbox` binary is not installed?**
Auto-activation silently skips. Running `:DevboxActivate` manually shows
a warning (`devbox binary not found`).

**Q: Can I use this without auto-activation?**
Yes. Set `auto_activate = false` and call `:DevboxActivate` manually.

## Contributing

Contributions welcome! Open an issue or pull request on
[GitHub](https://github.com/rbelem/devbox.nvim).

## License

Apache 2.0. See [LICENSE](LICENSE).
