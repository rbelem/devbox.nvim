--[[
scripts/generate_nix_map.lua

Generates lua/devbox/lsp/nix_map.json by querying nix-search for each known
LSP server binary and finding the best-matching nixpkgs attribute.

Usage:
  nvim --headless -c "luafile scripts/generate_nix_map.lua" -c "qa!"

Output: lua/devbox/lsp/nix_map.json (committed to repo)

Format:
  { "lspconfig_name": "nixpkgs_attr_path", ... }
]]

-- [[ Common LSP server binary → lspconfig name ]]
-- This list drives which servers get nix package lookups.
-- It mirrors the same set that devbox.lsp.servers scans at runtime.
-- Add new entries here or via the fallback in add_mapping().
local BINARY_TO_NAME = {
  lua_ls                                           = "lua-language-server",
  ts_ls                                            = "typescript-language-server",
  rust_analyzer                                    = "rust-analyzer",
  jdtls                                            = "jdtls",
  pyright                                          = "pyright-langserver",
  bashls                                           = "bash-language-server",
  vimls                                            = "vim-language-server",
  jsonls                                           = "vscode-json-language-server",
  cssls                                            = "vscode-css-language-server",
  html                                             = "vscode-html-language-server",
  marksman                                         = "marksman",
  yamlls                                           = "yaml-language-server",
  dockerls                                         = "docker-langserver",
  sqlls                                            = "sql-language-server",
  golangci_lint_ls                                 = "golangci-lint-langserver",
  gopls                                            = "gopls",
  clangd                                           = "clangd",
  cmake                                            = "cmake-language-server",
  texlab                                           = "texlab",
  taplo                                            = "taplo",
  eslint                                           = "vscode-eslint-language-server",
  graphql                                          = "graphql-language-service-cli",
  elixirls                                         = "elixir-ls",
  gleam                                            = "gleam",
  ocamlls                                          = "ocaml-language-server",
  spectral                                         = "spectral-language-server",
  helm_ls                                          = "helm_ls",
  terraformls                                      = "terraform-ls",
  tflint                                           = "tflint",
  ansiblels                                        = "ansible-language-server",
  pylsp                                            = "pylsp",
  jedi_language_server                             = "jedi-language-server",
  ruff_lsp                                         = "ruff-lsp",
  svelte                                           = "svelte-language-server",
  tailwindcss                                      = "tailwindcss-language-server",
  emmet_language_server                            = "emmet-language-server",
  vtsls                                            = "typescript-language-server",
  biomedc                                          = "biome",
  nil_ls                                           = "nil",
  nixd                                             = "nixd",
  statix                                           = "statix",
  deadnix                                          = "deadnix",
  basedpyright                                     = "basedpyright-langserver",
  ruff_lsp                                         = "ruff-lsp",
  pylsp                                            = "pylsp",
  zk                                               = "zk",
  prosemd_lsp                                      = "prosemd-lsp",
  vale_ls                                          = "vale-ls",
  tinymist                                         = "tinymist",
  nickel_ls                                        = "nickel-lang-lsp",
  lemminx                                          = "lemminx",
  groovyls                                         = "groovy-language-server",
  kotlin_language_server                           = "kotlin-language-server",
  java_language_server                             = "java-language-server",
  ccls                                             = "ccls",
  csharp_ls                                        = "csharp-ls",
  fsautocomplete                                   = "fsautocomplete",
  rome                                             = "rome",
  ocamllsp                                         = "ocamllsp",
  erlangls                                         = "erlang_ls",
  ghcide                                           = "ghcide",
  haskell_language_server                          = "haskell-language-server",
  pylsp                                            = "pylsp",
  ruff_lsp                                         = "ruff-lsp",
  perlnavigator                                    = "perlnavigator",
  raku_navigator                                   = "raku-navigator",
  phpactor                                         = "phpactor",
  intelephense                                     = "intelephense",
  psalm                                            = "psalm",
  dartls                                           = "dart",
  sourcekit                                        = "sourcekit-lsp",
  r_language_server                                = "r-language-server",
  fortls                                           = "fortls",
  purescriptls                                     = "purescript-language-server",
  reason_ls                                        = "reason-language-server",
  resumed                                          = "resumed",
  solidity                                         = "solidity-ls",
  sieve                                            = "sieve-language-server",
  slint_lsp                                        = "slint-lsp",
  smartyl                                          = "smartyl",
  solargraph                                       = "solargraph",
  solidity_ls                                      = "solidity-ls",
  solidity_ls_nomicfoundation                      = "solidity-language-server",
  sonarlint_ls                                     = "sonarlint-language-server",
  sorbet                                           = "sorbet",
  sourcery                                         = "sourcery",
  spectral                                         = "spectral-language-server",
  sqlls                                            = "sql-language-server",
  sqls                                             = "sqls",
  standardrb                                       = "standardrb",
  statix                                           = "statix",
  steampipe                                        = "steampipe",
  stylelint_lsp                                    = "stylelint-lsp",
  sumneko_lua                                      = "lua-language-server",
  superhtml                                        = "superhtml",
  svlangserver                                     = "svlangserver",
  swift_mesonls                                    = "swift-meson-lsp",
  syft                                             = "syft",
  syntax_tree                                      = "syntax_tree",
  tailwindcss                                      = "tailwindcss-language-server",
  taplo                                            = "taplo",
  teal_ls                                          = "teal-language-server",
  terraformls                                      = "terraform-ls",
  terragrunt                                       = "terragrunt",
  texlab                                           = "texlab",
  tflint                                           = "tflint",
  theme_check                                      = "theme-check",
  thriftlsp                                        = "thriftlsp",
  tilt_analyze                                     = "tilt-analyze",
  tinymist                                         = "tinymist",
  tsserver                                         = "typescript-language-server",
  typos_lsp                                        = "typos-lsp",
  ultrals                                          = "ultra-language-server",
  uncrustify                                       = "uncrustify",
  vala_ls                                          = "vala-language-server",
  vale_ls                                          = "vale-ls",
  verible                                          = "verible",
  veryl_ls                                         = "veryl-ls",
  vimls                                            = "vim-language-server",
  visualforce_ls                                   = "visualforce-language-server",
  vls                                              = "vls",
  vue_language_server                              = "vue-language-server",
  yamlls                                           = "yaml-language-server",
  zk                                               = "zk",
  zls                                              = "zls",
}

-- [[ Deduplicate by binary name (many lspconfig names share the same binary) ]]
local binary_set = {}
local binary_list = {}
for _, binary in pairs(BINARY_TO_NAME) do
  if not binary_set[binary] then
    binary_set[binary] = true
    binary_list[#binary_list + 1] = binary
  end
end

-- [[ Nix-search wrapper ]]
-- Returns the best nixpkgs attribute path for a given binary, or nil.
local function resolve_nix_attr(binary)
  local cmd = { "nix-search", "--program", binary, "--json", "--max-results", "5" }
  local handle = io.popen(vim.fn.shellescape(table.concat(cmd, " ")):gsub("'", ""), "r")
  if not handle then
    return nil
  end
  local output = handle:read("*a")
  handle:close()
  if not output or output == "" then
    return nil
  end

  -- Parse each line (nix-search outputs one JSON object per result)
  local best = nil
  local best_score = -1

  for line in output:gmatch("[^\n]+") do
    local ok, result = pcall(vim.json.decode, line)
    if ok and result and result.package_attr_name then
      local attr = result.package_attr_name
      local match_binary = false
      if result.package_programs then
        for _, prog in ipairs(result.package_programs) do
          if prog == binary then
            match_binary = true
            break
          end
        end
      end
      if not match_binary then
        goto continue
      end

      -- Score: higher is better
      -- +100: exact attribute name matches binary name (top-level package)
      -- +50:  attribute set is "No package set" (not in an overlay)
      -- +10:  no version suffix (no _NN at end)
      -- +5:   no suffix at all
      -- -10:  has version suffix
      local score = 0
      if attr == binary then
        score = score + 100
      end
      if result.package_attr_set == "No package set" then
        score = score + 50
      end
      if not attr:match("_[0-9]+$") then
        score = score + 10
        if not attr:match("_") then
          score = score + 5
        end
      else
        score = score - 10
      end

      if score > best_score then
        best = attr
        best_score = score
      end
    end
    ::continue::
  end

  return best
end

-- [[ Main ]]--

local out_dir = vim.fn.stdpath("cache") .. "/devbox"
if vim.fn.isdirectory(out_dir) == 0 then
  vim.fn.mkdir(out_dir, "p")
end

local results = {}
local success_count = 0
local fail_count = 0

-- Build reverse map: binary → lspconfig names
-- (same binary can map to multiple lspconfig names)
local binary_to_configs = {}
for name, binary in pairs(BINARY_TO_NAME) do
  binary_to_configs[binary] = binary_to_configs[binary] or {}
  table.insert(binary_to_configs[binary], name)
end

-- Also load any existing nix_map.json to keep old entries
local existing_map = {}
local existing_path = vim.fn.stdpath("cache") .. "/devbox/nix_map.json"
local ok, data = pcall(vim.fn.readfile, existing_path)
if ok and data and #data > 0 then
  local ok_decode, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
  if ok_decode and decoded then
    existing_map = decoded
  end
end

for _, binary in ipairs(binary_list) do
  local attr = resolve_nix_attr(binary)
  if attr then
    local config_names = binary_to_configs[binary]
    for _, name in ipairs(config_names) do
      results[name] = attr
    end
    success_count = success_count + 1
    vim.notify(string.format("[nix] %s → %s", binary, attr), vim.log.levels.INFO)
  else
    -- Fall back to existing mapping if available
    for _, name in ipairs(binary_to_configs[binary]) do
      if existing_map[name] then
        results[name] = existing_map[name]
      end
    end
    fail_count = fail_count + 1
    vim.notify(string.format("[nix] %s → NOT FOUND", binary), vim.log.levels.WARN)
  end
end

-- Write to project path (committed)
local project_path = vim.fn.getcwd() .. "/lua/devbox/lsp/nix_map.json"

-- Pretty-print with sorted keys for human readability
local keys = {}
for k, _ in pairs(results) do
  keys[#keys + 1] = k
end
table.sort(keys)

local parts = { "{" }
for i, k in ipairs(keys) do
  local sep = (i < #keys) and "," or ""
  parts[#parts + 1] = string.format('  %q: %q%s', k, results[k], sep)
end
parts[#parts + 1] = "}"
vim.fn.writefile(parts, project_path)

-- Also save to cache for future incremental runs
local cache_path = vim.fn.stdpath("cache") .. "/devbox/nix_map.json"
local ok_json, json = pcall(vim.json.encode, results)
if ok_json then
  vim.fn.writefile(vim.split(json, "\n"), cache_path)
end

vim.notify(
  string.format("[nix] done: %d found, %d not found, %d total entries",
    success_count, fail_count, #keys),
  vim.log.levels.INFO
)
