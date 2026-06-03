--[[
scripts/generate_nix_map.lua

Generates lua/devbox/lsp/nix_map.json by querying nix-search for each known
LSP server binary and finding the best-matching nixpkgs attribute.

Discovers ALL servers from nvim-lspconfig. Servers without a matching nix
package get a null entry so we know which ones need a nix flake built.

Usage:
  nvim --headless --cmd "set rtp+=~/.local/share/nvim/lazy/nvim-lspconfig" \
    -c "luafile scripts/generate_nix_map.lua" -c "qa!"

Output: lua/devbox/lsp/nix_map.json (committed to repo)

Format:
  { "lspconfig_name": "nixpkgs_attr_path_or_null", ... }
]]

-- [[ Discover all servers from nvim-lspconfig ]]
local function discover_servers()
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    print("ERROR: nvim-lspconfig not installed -- run with rtp+=nvim-lspconfig")
    return {}
  end

  local info = debug.getinfo(lspconfig.util.root_pattern, "S")
  local src_path = info and info.source
  if not src_path then
    print("ERROR: could not find lspconfig install path")
    return {}
  end

  -- source is "@<path>/lua/lspconfig/util.lua"
  local install_dir = src_path:match("^@(.*/)lua/lspconfig/util%.lua$")
  if not install_dir then
    print("ERROR: could not parse lspconfig path: " .. (src_path or "nil"))
    return {}
  end

  local configs_glob = install_dir .. "lua/lspconfig/configs/*.lua"
  local config_files = vim.fn.glob(configs_glob, false, true)
  if type(config_files) == "string" then
    config_files = { config_files }
  end
  if #config_files == 0 then
    print("ERROR: no config files found at " .. configs_glob)
    return {}
  end

  local servers = {}
  local loaded = 0
  local failed = 0
  for _, filepath in ipairs(config_files) do
    local name = filepath:match("([^/]+)%.lua$")
    if name then
      local ok_r, config = pcall(require, "lspconfig.configs." .. name)
      if ok_r and config and config.default_config then
        local cmd = config.default_config.cmd
        if cmd then
          local binary
          if type(cmd) == "table" and #cmd > 0 and type(cmd[1]) == "string" then
            binary = cmd[1]
          elseif type(cmd) == "function" then
            local ok_fn, result = pcall(cmd)
            if ok_fn and type(result) == "table" and #result > 0 and type(result[1]) == "string" then
              binary = result[1]
            end
          end
          if binary then
            servers[name] = binary
            loaded = loaded + 1
          else
            failed = failed + 1
          end
        else
          failed = failed + 1
        end
      else
        failed = failed + 1
      end
    end
  end
  print("discovered " .. loaded .. " servers with binaries, " .. failed .. " skipped")
  return servers
end

-- [[ Nix-search for a single binary ]]
-- Returns a list of all valid nixpkgs attribute paths, sorted by score (best first).
local function resolve_nix_attrs(binary)
  local escaped = binary:gsub("'", "'\\''")
  local cmd = "nix-search --program " .. escaped .. " --json --max-results 5"
  local handle = io.popen(cmd, "r")
  if not handle then
    return nil
  end
  local output = handle:read("*a")
  handle:close()
  if not output or output == "" then
    return nil
  end

  local scored = {}

  for line in output:gmatch("[^\n]+") do
    local ok_j, result = pcall(vim.json.decode, line)
    if ok_j and result and result.package_attr_name then
      local attr = result.package_attr_name

      -- Verify this package provides our binary
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
      local score = 0
      score = score + 100  -- base for valid result
      if attr == binary then
        score = score + 100  -- exact attribute name match
      end
      if result.package_attr_set == "No package set" then
        score = score + 50  -- top-level package
      end
      if not attr:match("_[0-9]+$") then
        score = score + 10  -- no version suffix
        if not attr:match("_") then
          score = score + 5  -- simple name, no underscore
        end
      end

      scored[#scored + 1] = { attr = attr, score = score }
    end
    ::continue::
  end

  if #scored == 0 then
    return nil
  end

  -- Sort by score descending
  table.sort(scored, function(a, b) return a.score > b.score end)

  -- Return just the attr names in order
  local attrs = {}
  for _, s in ipairs(scored) do
    attrs[#attrs + 1] = s.attr
  end
  return attrs
end

-- [[ MAIN ]]--

-- Discover servers
local servers = discover_servers()
if not servers or next(servers) == nil then
  print("aborting: no servers discovered")
  return
end

-- Deduplicate binary names
local binary_set = {}
local binary_list = {}
for _, binary in pairs(servers) do
  if not binary_set[binary] then
    binary_set[binary] = true
    binary_list[#binary_list + 1] = binary
  end
end

print("resolving " .. #binary_list .. " unique binaries...")

-- Resolve each unique binary (returns list of attrs, best first)
local binary_to_attrs = {}
local success_count = 0
local fail_count = 0
for _, binary in ipairs(binary_list) do
  local attrs = resolve_nix_attrs(binary)
  if attrs then
    binary_to_attrs[binary] = attrs
    success_count = success_count + 1
  else
    binary_to_attrs[binary] = nil
    fail_count = fail_count + 1
  end
end

local total_candidates = 0
for _, attrs in pairs(binary_to_attrs) do
  if attrs then
    total_candidates = total_candidates + #attrs
  end
end

print("resolved: " .. success_count .. " found, " .. fail_count .. " not found ("
  .. total_candidates .. " total candidates)")

-- Build results: lspconfig name → list of nix attrs (null for not found)
local NULL = {}
local results = {}
local found_count = 0
local missing_count = 0
for name, binary in pairs(servers) do
  if binary_to_attrs[binary] then
    results[name] = binary_to_attrs[binary]
    found_count = found_count + 1
  else
    results[name] = NULL
    missing_count = missing_count + 1
  end
end

-- Write to project path (committed) — pretty-printed with nulls
local project_path = vim.fn.getcwd() .. "/lua/devbox/lsp/nix_map.json"
local keys = {}
for k, _ in pairs(results) do
  keys[#keys + 1] = k
end
table.sort(keys)

local parts = { "{" }
for i, k in ipairs(keys) do
  local sep = (i < #keys) and "," or ""
  local val = results[k]
  if val == NULL then
    parts[#parts + 1] = string.format('  %q: null%s', k, sep)
  elseif type(val) == "table" then
    -- Array of packages
    local items = {}
    for _, attr in ipairs(val) do
      items[#items + 1] = string.format("%q", attr)
    end
    parts[#parts + 1] = string.format('  %q: [%s]%s', k, table.concat(items, ", "), sep)
  else
    parts[#parts + 1] = string.format('  %q: %q%s', k, val, sep)
  end
end
parts[#parts + 1] = "}"
vim.fn.writefile(parts, project_path)

-- Save non-null entries to cache for runtime loading
local cache_path = vim.fn.stdpath("cache") .. "/devbox/nix_map.json"
local cache_data = {}
for k, v in pairs(results) do
  if v ~= NULL then
    if type(v) == "table" then
      -- Only store the best (first) result in cache
      cache_data[k] = v[1]
    else
      cache_data[k] = v
    end
  end
end
local ok_json, json = pcall(vim.json.encode, cache_data)
if ok_json then
  vim.fn.writefile(vim.split(json, "\n"), cache_path)
end

print("done: " .. found_count .. " found, " .. missing_count .. " missing (null), "
  .. #binary_list .. " unique binaries, " .. #keys .. " total servers")
