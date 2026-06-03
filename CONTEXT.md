# devbox.nvim domain glossary

## LSP management

- **Auto-enable**: feature that detects LSP servers on the devbox-managed PATH and calls `vim.lsp.enable()` for each detected server.
- **Server map**: a table mapping lspconfig server names to their properties (binary name, nix package, etc.). Generated from nvim-lspconfig at install time.
- **Detection**: scanning the PATH for known LSP server binaries via `vim.fn.executable()` after devbox activation.
- **Generator**: an internal function (`_generate()`) that walks nvim-lspconfig's server configurations via `require()` and emits the server map as JSON to `stdpath("cache")/devbox/lsp_servers.json`. Runs lazily on first `detect()` call.
- `add_mapping()`: the extension API for users to register custom or missing binary→server pairs.

## Activation model

- **One-way activation**: once devbox activates, it stays active for the session. No deactivation, no env restore, no `DirChanged` autocmd. Same pattern as direnv.nvim plugins (load on enter, never unload).
