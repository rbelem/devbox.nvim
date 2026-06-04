--[[
scripts/validate_nix_map.lua

CI validation for lua/devbox/lsp/nix_map.json.
Checks JSON structure and detects drift from nvim-lspconfig.

Usage (CI):
  nvim --headless --cmd "set rtp+=." -c "luafile scripts/validate_nix_map.lua" -c "qa!"
  echo $?  # 0 = clean, 1 = issues found

With nvim-lspconfig available:
  nvim --headless --cmd "set rtp+=<lspconfig_path>" --cmd "set rtp+=." \
    -c "luafile scripts/validate_nix_map.lua" -c "qa!"
]]

local project_root = vim.fn.getcwd()
local map_path = project_root .. "/lua/devbox/lsp/nix_map.json"

-- Read and parse nix_map.json
local ok_read, data = pcall(vim.fn.readfile, map_path)
if not ok_read or not data or #data == 0 then
  print("FAIL: could not read " .. map_path)
  os.exit(1)
end

local ok_decode, map = pcall(vim.json.decode, table.concat(data, "\n"))
if not ok_decode or not map then
  print("FAIL: nix_map.json is not valid JSON")
  os.exit(1)
end

-- Validate structure
local errors = {}
local null_count = 0
local array_count = 0

for k, v in pairs(map) do
  if type(k) ~= "string" then
    errors[#errors + 1] = "non-string key: " .. tostring(k)
  end
  if v == vim.NIL then
    null_count = null_count + 1
  elseif type(v) == "table" then
    array_count = array_count + 1
    for _, attr in ipairs(v) do
      if type(attr) ~= "string" then
        errors[#errors + 1] = k .. ": array item is not a string: " .. tostring(attr)
      end
    end
  else
    errors[#errors + 1] = k .. ": invalid value type: " .. type(v)
  end
end

local total = 0
for _ in pairs(map) do total = total + 1 end

if #errors > 0 then
  print("FAIL: " .. #errors .. " structural error(s):")
  for _, e in ipairs(errors) do
    print("  " .. e)
  end
  os.exit(1)
end

print("OK: " .. total .. " entries (" .. null_count .. " null, " .. array_count .. " with nix pkgs)")

-- Discover servers from nvim-lspconfig (if available)
local ok_lsp, _ = pcall(require, "lspconfig")
if not ok_lsp then
  print("INFO: nvim-lspconfig not available, skipping drift detection")
  os.exit(0)
end

-- Try both patterns for compatibility with different Neovim/lspconfig layouts
local config_files = vim.api.nvim_get_runtime_file("lua/lspconfig/configs/*.lua", true)
if #config_files == 0 then
  config_files = vim.api.nvim_get_runtime_file("lspconfig/configs/*.lua", true)
end
if #config_files == 0 then
  config_files = vim.api.nvim_get_runtime_file("lspconfig/server_configurations/*.lua", true)
end
if #config_files == 0 then
  print("INFO: no lspconfig config files found, skipping drift detection")
  os.exit(0)
end

print("INFO: checking " .. #config_files .. " lspconfig config files for drift...")

local discovered = {}
local missing_from_map = {}
for _, filepath in ipairs(config_files) do
  local name = filepath:match("([^/]+)%.lua$")
  if name then
    discovered[#discovered + 1] = name
    if map[name] == nil then
      missing_from_map[#missing_from_map + 1] = name
    end
  end
end

table.sort(discovered)
table.sort(missing_from_map)

print("INFO: " .. #discovered .. " servers in lspconfig, " .. total .. " in nix_map.json")

if #missing_from_map > 0 then
  print("WARN: " .. #missing_from_map .. " server(s) in lspconfig missing from nix_map.json:")
  for _, name in ipairs(missing_from_map) do
    print("  " .. name)
  end
  print("Consider: devbox run generate-nix-map  (requires nix-search)")
  -- Don't fail CI for this — missing entries are informational
end

-- Check for stale entries (in map but not in lspconfig)
local stale = {}
local map_keys = {}
for k, _ in pairs(map) do
  map_keys[k] = true
end
for _, name in ipairs(discovered) do
  map_keys[name] = nil
end
for name, _ in pairs(map_keys) do
  stale[#stale + 1] = name
end

table.sort(stale)
if #stale > 0 then
  print("WARN: " .. #stale .. " server(s) in nix_map.json no longer in lspconfig (stale?):")
  for _, name in ipairs(stale) do
    print("  " .. name)
  end
end

local exit_code = (#missing_from_map > 0 or #stale > 0) and 0 or 0
-- Warnings only, never fail CI for drift — it's informational
os.exit(0)
