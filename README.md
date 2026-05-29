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
  `HIST`, `PROMPT`, etc.)
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
  { src = "https://github.com/rbelem/devbox.nvim" },
}
```

**Manual** (any plugin manager):

```lua
require("devbox").setup({})
```

## Configuration

`devbox.nvim` works out of the box with no configuration. Commonly changed
options:

```lua
require("devbox").setup({
  silent = false,    -- set to true to suppress notifications
  devbox_path = "devbox", -- custom path to devbox binary
})
```

Full defaults:

```lua
{
  auto_activate  = true,            -- auto-activate on buffer open
  update_env     = true,            -- set vim.env from devbox shellenv
  strategy       = "async",         -- "async" (default) | "sync"
  silent         = false,           -- suppress notifications
  devbox_path    = "devbox",        -- path to devbox binary
  lsp            = { inject_env = true },
  exclude_env    = {
    "^ATUIN_",                      -- shell history
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

1. You open a file inside a project that has `devbox.json`
2. `devbox.nvim` walks up the directory tree to find the project root
3. **Cache hit**: loads cached env from disk — instant
4. **Cache miss**: runs `devbox shellenv` asynchronously via `jobstart`
5. Parses `export KEY=VALUE` lines, skips excluded vars, writes to `vim.env`
6. LSP clients inherit the updated `PATH` via `LspAttach` hook

Deactivation restores `vim.env` to the snapshot taken at activation.

## Advanced Usage

### LSP Module

The `devbox.lsp` module provides `make_lsp_env()` for explicit LSP client
configuration:

```lua
local devbox_lsp = require("devbox.lsp")
vim.lsp.config("jdtls", {
  before_init = function(params, config)
    config.env = devbox_lsp.make_lsp_env()
  end,
})
```

### Sync Strategy

If you prefer blocking resolution (e.g., on `VimEnter`), set
`strategy = "sync"`. Note that sync runs synchronously via `vim.fn.system` —
consider async unless you have a specific reason.

## FAQ

**Q: Does this replace `devbox shell`?**
No. It injects env variables into Neovim's process so tools inside the editor
find devbox-managed binaries. You still use `devbox shell` in your terminal for
interactive work.

**Q: What happens if `devbox` binary is not installed?**
The plugin silently skips activation (shows a warning unless `silent = true`).

**Q: Can I use this without auto-activation?**
Yes. Set `auto_activate = false` and call `:DevboxActivate` manually.

## Contributing

Contributions welcome! Open an issue or pull request on
[GitHub](https://github.com/rbelem/devbox.nvim).

## License

Apache 2.0. See [LICENSE](LICENSE).
