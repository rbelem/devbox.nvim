--- devbox.lsp.servers — detect devbox-managed LSP servers and enable them.
---
--- Maintains a map of LSP server binary names → lspconfig server names.
--- The map is auto-generated from nvim-lspconfig's server configurations,
--- cached to JSON with content-aware SHA invalidation. User custom mappings
--- can be added via add_mapping() and override generated entries.
---
--- Usage:
---   local s = require("devbox.lsp.servers")
---   local names = s.detect()      -- scan PATH
---   s.enable(names)               -- call vim.lsp.enable() for each

local M = {}

---@type table<string, {binary: string}>?
M._generated_map = nil

---@type table<string, {binary: string}>
M._user_map = {}

--- Nix package map: lspconfig name → nixpkgs attribute path.
--- Loaded from the checked-in nix_map.json at startup.
---@type table<string, string>
M._nix_map = {}

-- Load the nix package map on module init
do
  local nix_path = vim.fn.stdpath("cache") .. "/devbox/nix_map.json"
  local ok, data = pcall(vim.fn.readfile, nix_path)
  if ok and data and #data > 0 then
    local ok_decode, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
    if ok_decode and decoded then
      M._nix_map = decoded
    end
  end
  -- Also try the project-relative path (for repo-checked-in version)
  local project_path = vim.fn.getcwd() .. "/lua/devbox/lsp/nix_map.json"
  if project_path ~= nix_path then
    local ok2, data2 = pcall(vim.fn.readfile, project_path)
    if ok2 and data2 and #data2 > 0 then
      local ok_decode2, decoded2 = pcall(vim.json.decode, table.concat(data2, "\n"))
    if ok_decode2 and decoded2 then
      for k, v in pairs(decoded2) do
        if not M._nix_map[k] and v ~= vim.NIL then
          -- If the value is an array, take the best (first) element
          if type(v) == "table" and #v > 0 then
            M._nix_map[k] = v[1]
          else
            M._nix_map[k] = v
          end
        end
      end
    end
    end
  end
end

---@return string
local function _cache_path()
  return vim.fn.stdpath("cache") .. "/devbox/lsp_servers.json"
end

--- Compute SHA256 of nvim-lspconfig server config file contents.
---@return string?, string? sha, err
local function _compute_sha()
  local files = vim.api.nvim_get_runtime_file("lspconfig/server_configurations/*.lua", true)
  if #files == 0 then
    return nil, "no nvim-lspconfig config files found"
  end
  table.sort(files)
  local parts = {}
  for _, f in ipairs(files) do
    local ok, data = pcall(vim.fn.readfile, f)
    if ok and data then
      parts[#parts + 1] = table.concat(data, "\n")
    end
  end
  return vim.fn.sha256(table.concat(parts)), nil
end

--- Generate server map from nvim-lspconfig, writes JSON cache.
---@param sha? string pre-computed SHA256 of lspconfig files (avoids re-reading)
---@return boolean true if generation succeeded
function M._generate(sha)
  local files = vim.api.nvim_get_runtime_file("lspconfig/server_configurations/*.lua", true)
  if #files == 0 then
    return false
  end
  table.sort(files)

  -- Compute SHA from file contents if not provided
  if not sha then
    local sha_parts = {}
    for _, f in ipairs(files) do
      local ok, data = pcall(vim.fn.readfile, f)
      if ok and data then
        sha_parts[#sha_parts + 1] = table.concat(data, "\n")
      end
    end
    sha = vim.fn.sha256(table.concat(sha_parts))
  end

  -- Extract binary→name map
  ---@type table<string, {binary: string}>
  local map = {}
  for _, filepath in ipairs(files) do
    local name = filepath:match("([^/]+)%.lua$")
    if not name then
      goto continue
    end

    local ok_r, config = pcall(require, "lspconfig.server_configurations." .. name)
    if ok_r and config and config.default_config then
      local cmd = config.default_config.cmd
      if type(cmd) == "table" and #cmd > 0 and type(cmd[1]) == "string" then
        map[name] = { binary = cmd[1] }
      elseif type(cmd) == "function" then
        local ok_fn, result = pcall(cmd)
        if ok_fn and type(result) == "table" and #result > 0 and type(result[1]) == "string" then
          map[name] = { binary = result[1] }
        end
      end
    end

    ::continue::
  end

  -- Write JSON cache (with embedded SHA for invalidation)
  local out = vim.deepcopy(map)
  out._sha = sha
  local ok_json, json = pcall(vim.json.encode, out)
  if ok_json then
    local dir = vim.fn.stdpath("cache") .. "/devbox"
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
    vim.fn.writefile(vim.split(json, "\n"), _cache_path())
  end

  -- In-memory map without the SHA field
  M._generated_map = map
  return true
end

--- Load generated map from JSON cache, regenerate if stale.
---@return boolean true if map is available
local function _load_or_generate()
  if M._generated_map then
    return true
  end

  local ok, data = pcall(vim.fn.readfile, _cache_path())
  if ok and data and #data > 0 then
    local ok_decode, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
    if ok_decode and decoded then
      local cached_sha = decoded._sha
      local current_sha, _ = _compute_sha()
      if current_sha and current_sha == cached_sha then
        decoded._sha = nil
        M._generated_map = decoded
        return true
      end
      -- Cache stale, regenerate with pre-computed SHA to avoid re-reading files
      return M._generate(current_sha)
    end
  end

  -- No valid cache — regenerate (no SHA available, _generate will compute it)
  return M._generate()
end

--- Detect which LSP servers are available on PATH.
--- Merges the generated map with any user-added mappings (user wins).
---@param filter? table<string, true> if provided, only returns servers in this set
---@return string[] lspconfig server names that are executable
function M.detect(filter)
  _load_or_generate()

  local map = vim.tbl_extend("force", M._generated_map or {}, M._user_map)
  -- Enrich with nix package names from the checked-in map
  for name, entry in pairs(map) do
    if type(entry) == "table" and not entry.nix then
      entry.nix = M._nix_map[name]
    end
  end
  local detected = {}
  for name, entry in pairs(map) do
    if type(entry) == "table" and entry.binary then
      if (not filter or filter[name]) and vim.fn.executable(entry.binary) == 1 then
        detected[#detected + 1] = name
      end
    end
  end
  return detected
end

--- Enable a list of LSP servers via vim.lsp.enable().
--- vim.lsp.enable() is idempotent and safe for unknown server names.
---@param names string[]
function M.enable(names)
  for _, name in ipairs(names) do
    pcall(vim.lsp.enable, name)
  end
end

--- Register custom binary→lspconfig name mappings.
--- User entries override generated entries on collision.
--- Accepts both a single pair and a table of pairs.
---@param ... string|table if two strings: (binary, name). If table: {[binary]=name, ...}
function M.add_mapping(...)
  local args = { ... }
  if type(args[1]) == "table" then
    -- Table form: { [binary] = name, ... }
    for binary, name in pairs(args[1]) do
      if type(binary) == "string" and type(name) == "string" then
        M._user_map[name] = { binary = binary }
      end
    end
  elseif type(args[1]) == "string" and type(args[2]) == "string" then
    -- Single pair form: (binary, name)
    M._user_map[args[2]] = { binary = args[1] }
  end
end

return M
