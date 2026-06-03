# PRD: LSP auto-enable for devbox-managed servers

**Date:** 2026-06-02
**Status:** Final (ready-for-agent)

---

## Problem Statement

Users who manage their toolchain with devbox currently have to duplicate those same LSP servers in mason.nvim for Neovim to recognize and use them. This means:

- **Duplicate binaries.** devbox installs `lua-language-server` via Nix to
  `/nix/store/.../bin/`. mason downloads a second copy to
  `~/.local/share/nvim/mason/bin/`. Same binary, double disk, double network.
- **Version drift.** devbox pins to a Nix revision. mason pins to its own
  registry. They can diverge.
- **Maintenance burden.** Adding a tool means updating two places:
  `devbox.json` and mason config.
- **Lost cross-editor consistency.** VS Code finds the devbox/Nix binary.
  Neovim finds the mason binary. Different versions, different behavior.

Users want devbox.nvim to be a viable **alternative** to mason for LSP server
management — detect what devbox provides on PATH and wire it into Neovim's LSP
client automatically.

---

## Solution

A new `devbox.lsp.servers` module that auto-detects LSP servers on the
devbox-managed PATH and calls `vim.lsp.enable()` for each detected server.

The server map (binary name → lspconfig server name) is auto-generated from
nvim-lspconfig at install time, cached to JSON with content-aware SHA
invalidation, and lazily regenerated when nvim-lspconfig is updated.

**nvim-lspconfig is optional.** Auto-enable is gated behind
`require("lspconfig")` succeeding. If nvim-lspconfig is not installed, the
feature is a silent no-op (logs a warning). No static fallback list — the
feature simply requires nvim-lspconfig to function.

The user adds LSP servers to `devbox.json`, runs `devbox install`, and
devbox.nvim detects and enables them automatically. No mason required.

### Configuration

```lua
require("devbox").setup({
  lsp = {
    auto_enable = true,                    -- opt-in (default: false)
    auto_enable_filter = { "lua_ls", "rust_analyzer" },  -- optional
  }
})
```

---

## User Stories

1. As a devbox user, I want LSP servers from my `devbox.json` to be
   automatically detected and enabled in Neovim, so that I don't need to
   install or configure them via mason.
2. As a devbox user, I want auto-enable to be opt-in (`auto_enable = false`
   by default), so that my existing manual LSP setup is not overridden when
   I upgrade devbox.nvim.
3. As a devbox user, I want to restrict auto-enable to a subset of detected
   servers via `auto_enable_filter`, so that I can use only specific servers
   despite multiple being on PATH.
4. As a devbox user, I want detection to trigger on cache-hit activation
   (instant startup), so that my editing session is not delayed.
5. As a devbox user, I want detection to trigger after the async `devbox
   shellenv` completes, so that newly-resolved servers are enabled even on
   first run.
6. As a devbox user, I want the activation notification to report how many
   LSP servers were enabled (omitted when zero), so that I get immediate
   feedback without noise.
7. As a devbox user, I want auto-enable to be a no-op when devbox is not
   active or when nvim-lspconfig is not installed, so that users without
   nvim-lspconfig see no errors.
8. As a devbox user, I want auto-enable to work alongside the existing
   `_inject_path` mechanism, so that both features coexist.
9. As a devbox user, I want auto-enable to work alongside nvim-lspconfig,
   so that I can still use per-server configuration (settings, on_attach,
   capabilities) as usual.
10. As a devbox user, I want auto-enable to not interfere with any
    mason-managed servers I still use, so that I can transition gradually.
11. As a devbox user, I want `:DevboxActivate` to re-scan and re-enable
    servers, so that I can trigger detection manually without a separate
    command.
12. As a contributor, I want the detection module to be testable in
    isolation with mocked `vim.fn.executable()` and `vim.env.PATH`, so that
    I can add tests without a real devbox environment.
13. As a contributor, I want the module to have no new runtime deps beyond
    nvim-lspconfig being present on the user's system (optional), so that
    the plugin stays lightweight.
14. As a devbox user, I want the server map to include every server
    nvim-lspconfig supports (200+), so that no LSP server is missing out of
    the box.
15. As a developer, I want to register custom binary→name mappings via
    `add_mapping()`, so that I can support servers that don't have a static
    cmd in nvim-lspconfig.
16. As a developer, I want the server map to be auto-regenerated when
    nvim-lspconfig is updated (SHA cache invalidation), so that new servers
    are automatically discovered without manual intervention.

---

## Implementation Decisions

### Modules

**New: `lua/devbox/lsp/servers.lua`** (~120 lines)

The core deep module. Contains:

- **Generated map** (`table<string, {binary: string}>`): produced by internal
  `_generate()` from nvim-lspconfig configs, cached to JSON file.
- **User map** (`table<string, {binary: string}>`): populated via
  `add_mapping()`.
- **`detect(filter?)`** (`string[]`): merges generated + user maps (user wins
  on collision), checks `vim.fn.executable(binary)` for each entry, returns
  lspconfig server names. If `filter` is provided, only returns servers in
  that list. Benchmarked at ~5ms for 200 entries.
- **`enable(server_names)`**: calls `vim.lsp.enable(name)` for each entry.
  `vim.lsp.enable()` is idempotent and safe for unknown servers (no-op).
- **`add_mapping(binary, name)` or `add_mapping({[binary]=name, ...})`**:
  registers custom entries in the user map. User entries override generated
  entries on collision.
- **`_generate()`**: walks nvim-lspconfig's server configurations via
  `nvim_get_runtime_file`, `require()` each config, extracts `default_config.cmd[1]`,
  pcalls dynamic `cmd` functions. Writes JSON + embedded content SHA to
  `stdpath("cache")/devbox/lsp_servers.json`.
- **SHA cache check**: SHA256 of config file *contents* (not just filenames).
  Detects renames, binary changes, adds, and removes. On mismatch,
  regenerates.

**Modified: `lua/devbox/config.lua`** (+3 fields)

```lua
---@field auto_enable? boolean           -- default false
---@field auto_enable_filter? string[]   -- optional include-list
```

**Modified: `lua/devbox/init.lua`** (~15 lines added, ~30 lines removed)

Changes to activation flow:

- **Removed:** `DevboxDeactivate` command entirely. Deactivation is not
  supported — once devbox activates, it stays active for the session.
- **Removed:** `Devbox.deactivate()` function. No snapshot/restore
  machinery. No env_set_keys tracking.
- **Removed:** `DirChanged` autocmd. Buffer events (`BufReadPost`,
  `BufNewFile`) handle project detection. `deactivate()` + `activate()`
  on `DirChanged` was a common source of bugs (LSP server state after
  deactivation).
- **Removed:** Env snapshot (`env_snapshot` table) and restore logic in
  `_apply_env()`. Activation is one-way and idempotent.
- **Added:** `_maybe_auto_enable()` helper called after `_apply_env()` in
  both the cache-hit path and the async `on_exit` path. Only runs when
  `config.options.lsp.auto_enable` is true AND `pccall(require,
  "lspconfig")` succeeds.
- **Added:** Server count appended to activation notification when ≥1
  (`[devbox] activated projetX (42 vars, 3 LSP servers)`).

### Architectural decisions

- **nvim-lspconfig is optional.** Gated behind `pcall(require, "lspconfig")`
  at detect-time. If not installed, `_maybe_auto_enable()` is a no-op and
  logs a single `vim.notify` warning at `vim.log.levels.INFO`. No static
  fallback list — the feature simply requires nvim-lspconfig to function.
- **Detection by `vim.fn.executable()` on PATH.** After devbox activation,
  `vim.env.PATH` already contains devbox-managed paths. No manual PATH
  parsing needed. Benchmarked at ~5ms for 200 entries.
- **Server map cached as JSON.** `vim.json.encode`/`decode` for
  serialization. `_sha` field embedded in JSON for cache invalidation.
- **SHA invalidation on file contents.** SHA256 of concatenated file
  contents (not just filenames). Catches binary renames, content edits,
  adds, and removes.
- **Generator uses `require()` then `pcall()`.** Static `cmd` tables read
  directly via `config.default_config.cmd[1]`. Dynamic `cmd` functions
  called inside `pcall()` with no arguments. Multi-element cmd arrays
  (e.g., `{"node", "server.js"}`) use only `cmd[1]` — if `cmd[1]` is a
  common binary name (`node`, `python3`, etc.), it's detected and can be
  filtered out by the user via `auto_enable_filter`.
- **Map value is a record `{binary: string}`.** Extensible with future
  fields (e.g., `nix: "lua-language-server"`). The record wrapper has no
  runtime cost over a flat string.
- **Merged at detect() time.** `vim.tbl_extend("force", generated_map,
  user_map)`. User entries override generated entries on collision.
- **Auto-generation runs lazily on first `detect()` call.** ~50-300ms on
  cache miss, ~0.1ms on cache hit.
- **No deactivation.** Once devbox activates, it stays active for the
  session. No `DevboxDeactivate` command, no env restore, no DirChanged
  autocmd. This eliminates the LSP server state problem identified during
  review (servers remain enabled after deactivation, producing errors).
- **Coexists with `_inject_path`.** Both features run independently.
  Auto-enable handles server discovery; `_inject_path` handles PATH
  injection for servers that need it.
- **`DevboxActivate` doubles as manual re-scan.** No separate
  `DevboxEnableServers` command needed.

### File and cache locations

```
Generated map (cache):
  stdpath("cache")/devbox/lsp_servers.json

Module location:
  lua/devbox/lsp/servers.lua
```

### Activation flow (post-changes)

```
Devbox.activate(dir)
  ├─ in-mem cache hit: _apply_env(env) → _maybe_auto_enable() → return true
  ├─ disk cache hit:   _apply_env(env) → _async_load() (bg refresh) → _maybe_auto_enable() → return true
  └─ miss:             _async_load(root) → ... → on_exit: _apply_env(env) → _maybe_auto_enable()
```

`_maybe_auto_enable()`:
```
1. config.options.lsp.auto_enable == true?
   → NO:  return
   → YES: continue
2. pcall(require, "lspconfig") succeeds?
   → NO:  log warning once, return
   → YES: continue
3. servers.detect(config.options.lsp.auto_enable_filter)
4. servers.enable(detected)
5. Append server count to activation notification
```

---

## Testing Decisions

### Test philosophy

Test external behavior, not implementation details. The key question for
each test: "does the LSP server get enabled or not?"

### Modules to test

**`devbox.lsp.servers`** — the core logic:
- `detect()` returns correct servers given a mocked `executable`
- `detect()` returns empty when no servers are executable
- `enable()` calls `vim.lsp.enable()` for each detected name
- `enable()` handles duplicate calls (idempotent)
- `detect(filter)` respects include-list filter
- `add_mapping()` adds entries that `detect()` picks up
- `add_mapping()` overrides generated entries on collision
- Server map entries map the right binary names to lspconfig names
  (spot-check a representative sample)
- `_generate()` produces a valid JSON file with expected structure
  (requires nvim-lspconfig installed)
- SHA cache invalidation regenerates on content change

**Integration with activation** (in `test_init_spec.lua`):
- Activation with `auto_enable = true` triggers detect + enable
- Activation with `auto_enable = false` does not
- Activation without nvim-lspconfig is a silent no-op

### Test files

- `tests/test_lsp_servers_spec.lua` — new file, unit tests for
  `devbox.lsp.servers`
- `tests/test_init_spec.lua` — extend with auto-enable activation tests

### Prior art

`tests/test_lsp_spec.lua` demonstrates the mocking pattern:
- `helper.mock_executable(result)` to control `vim.fn.executable()`
- `helper.mock_jobstart(output_lines, exit_code)` to simulate devbox env
- `helper.reload_plugin(opts)` to set config options fresh per test

### New mock infrastructure needed

- **Per-binary `mock_executable()`**: current mock is a single boolean for
  all calls. Need map `{binary → 1/0}`.
- **Mock for `vim.lsp.enable()`**: capture calls for assertion.
- **Mock for `nvim_get_runtime_file()`**: return synthetic file list for
  generator tests.
- **Reload plugin update**: `reload_plugin()` must clear
  `package.loaded["devbox.lsp.servers"]`.

### CI changes

Add nvim-lspconfig installation to the CI workflow:

```yaml
env:
  PLENARY_DIR: /tmp/plenary.nvim
  LSPCONFIG_DIR: /tmp/nvim-lspconfig

steps:
  - name: Install nvim-lspconfig
    run: git clone --depth=1 --filter=blob:none \
      https://github.com/neovim/nvim-lspconfig.git $LSPCONFIG_DIR

  - name: Run tests
    run: nvim --headless \
      --cmd "set rtp+=$PLENARY_DIR" \
      --cmd "set rtp+=$LSPCONFIG_DIR" \
      --cmd "set rtp+=." \
      -c "lua require('plenary.test_harness').test_directory('tests/', {minimal_init = 'tests/init.lua', sequential = true})" \
      -c "qa!"
```

---

## Out of Scope

- **Formatter/linter management.** Prettier, eslint, stylua, etc. are just
  binaries on PATH — they don't need `vim.lsp.enable()`. Already available
  for conform.nvim/null-ls if devbox provides them.
- **Download/install/update UI.** devbox (the CLI) handles package
  management. No `:Mason`-like TUI.
- **Nix package → lspconfig name mapping.** A future step. V1 only needs
  binary → name for detection.
- **Per-server configuration overrides.** nvim-lspconfig handles settings,
  on_attach, capabilities, root_markers. This module only enables; it
  doesn't configure.
- **Neovim <0.10 compatibility.** `vim.lsp.enable()` requires Neovim 0.10+.
- **Cross-project server conflict resolution.** If two projects provide
  different versions of the same binary on PATH, the last-activated PATH
  wins (standard PATH semantics).
- **Deactivation.** No `DevboxDeactivate` command, no env restore, no
  DirChanged autocmd. Devbox activation is one-way. The old env stays when
  the user leaves the project — same pattern as direnv.nvim plugins.
- **Standalone generation script.** The generator is embedded in
  `devbox.lsp.servers._generate()` and runs lazily. No `scripts/` file.
- **`DevboxEnableServers` command.** `DevboxActivate` already triggers
  detection+enable.
- **Static server map fallback.** If nvim-lspconfig is not installed, the
  feature is disabled. No hand-maintained fallback list.

---

## Further Notes

### Comparison with mason

| Aspect | mason | devbox.nvim + devbox |
|---|---|---|
| **Server install** | `:MasonInstall lua-language-server` | `devbox add lua-language-server` |
| **Server source** | GitHub releases / npm / PyPI / cargo | Nixpkgs |
| **Version pinning** | mason registry version | Nix lockfile (`devbox.lock`) |
| **Binary location** | `~/.local/share/nvim/mason/bin/` | `/nix/store/.../bin/` |
| **Auto-enable** | mason-lspconfig → `vim.lsp.config()` + `vim.lsp.enable()` | devbox.lsp.servers → `detect()` + `vim.lsp.enable()` |
| **Server coverage** | ~200 servers (mason registry) | ~200 servers (from nvim-lspconfig) |
| **Per-project isolation** | No (global mason dir) | Yes (per-project `devbox.json`) |

### Migration path for existing mason users

1. Add desired LSP server packages to `devbox.json`
2. Run `devbox install`
3. Ensure nvim-lspconfig is installed (already required by most setups)
4. Set `lsp.auto_enable = true` in devbox.nvim config
5. Remove `mason` and `mason-lspconfig` from Neovim config (or keep for
   non-devbox projects)

### Why opt-in?

`auto_enable = false` by default avoids surprising users who manage their
LSP servers manually.

### Why no deactivation?

Following the precedent set by direnv.nvim plugins: environment loads on
enter, never explicitly unloads. devbox activation is one-way for the
session. The old env stays when the user leaves the project — harmless and
avoids the LSP server state problem.

### Relationship with `_inject_path`

Both features coexist independently:
- Auto-enable handles server discovery (which servers to run)
- `_inject_path` handles PATH injection (which binary version wins)
- When auto-enable is active and devbox provides all needed servers,
  `_inject_path` becomes redundant but remains harmless
- Users mixing devbox and mason servers benefit from both running

### Performance

Benchmarked: 200 `vim.fn.executable()` calls = ~5ms. Well below human
perception threshold. No per-project scoping optimization needed.

### Architecture references

- ADR 0001: Server map generation strategy
- `lua/devbox/init.lua` — activation flow, `_inject_path`
- `lua/devbox/lsp.lua` — `make_lsp_env()` (standalone helper)
- `lua/devbox/config.lua` — defaults and options merge
