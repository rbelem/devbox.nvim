-- devbox.nvim -- devbox-managed tools inside Neovim
--
-- Detects devbox.json in project roots, runs `devbox shellenv`, injects vars
-- into vim.env. LSP servers inherit PATH and find mvn/java/go without global
-- installs.
--
-- Never blocks startup. Uses disk cache so even the first file open in a new
-- session loads instant (cold ~250ms once, cached ~0.4ms thereafter).
--
-- Activation is one-way: once active, the env stays for the session. There is
-- no deactivation (see ADR 0001 — direnv.nvim precedent). Use `DevboxActivate`
-- to re-activate or switch projects manually.

---@class devbox.Env
---@field vars table<string, string>
---@field project_root string
---@field path string
---@field cached_at? number  vim.loop.now() when cached

local config = require("devbox.config")

local Devbox = {}

-- ── Notification router ──

--- Route a notification based on the configured `notify` mode.
---@param msg string
---@param level number  vim.log.levels.*
---@param opts? { once?: boolean }
local _notify_timer = nil ---@type uv_timer_t?

--- Route a notification based on the configured `notify` mode.
---@param msg string
---@param level number  vim.log.levels.*
---@param opts? { once?: boolean, force?: boolean }  force — notify even in statusline mode (for explicit user commands)
function Devbox._notify(msg, level, opts)
  local mode = config.options.notify or "default"
  if mode == "silent" then
    return
  end

  if mode == "statusline" and not (opts and opts.force) then
    -- statusline() reflects loading/active state instead;
    -- explicit user commands (DevboxStatus etc.) still notify
    return
  end

  if mode == "progress" then
    local hl = ""
    if level == vim.log.levels.WARN or level == vim.log.levels.ERROR then
      hl = "WarningMsg"
    elseif level == vim.log.levels.INFO then
      hl = "MoreMsg"
    end
    pcall(vim.api.nvim_echo, { { msg, hl } }, false, {})

    -- Cancel any pending clear to avoid races
    if _notify_timer then
      _notify_timer:stop()
      _notify_timer:close()
      _notify_timer = nil
    end
    -- Auto-clear info-level messages after 3s
    if level ~= vim.log.levels.WARN and level ~= vim.log.levels.ERROR then
      _notify_timer = vim.defer_fn(function()
        pcall(vim.api.nvim_echo, { { "", "" } }, false, {})
        _notify_timer = nil
      end, 3000)
    end
    return
  end

  -- default mode: use vim.notify / vim.notify_once
  if opts and opts.once then
    vim.notify_once(msg, level)
  else
    vim.notify(msg, level)
  end
end

---@type table<string, devbox.Env>
local env_cache = {}
---@type string?
local active_root = nil
---@type boolean
local did_setup = false
---@type integer  -- bumped on each _async_load; on_exit only clears _loading if gen matches
local _load_gen = 0

local function cache_hash(str)
  return vim.fn.sha256(str):sub(1, 40)
end

--- Path to disk cache file for a project root.
---@param root string
---@return string
local function cache_path(root)
  local hash = cache_hash(root)
  return vim.fn.stdpath("cache") .. "/devbox/" .. hash .. ".json"
end

--- Load env from disk cache if still fresh.
---@param root string
---@return devbox.Env?
local function cache_load(root)
  local path = cache_path(root)
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data or #data == 0 then
    return nil
  end
  local ok_decode, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
  if not ok_decode or not decoded or not decoded.cached_at then
    return nil
  end
  -- check devbox.json mtime
  local mtime = vim.fn.getftime(root .. "/devbox.json")
  if mtime < 0 or mtime ~= decoded.cached_at then
    return nil
  end
  return decoded
end

--- Save env to disk cache.
---@param root string
---@param env devbox.Env
local function cache_save(root, env)
  local dir = vim.fn.stdpath("cache") .. "/devbox"
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  local mtime = vim.fn.getftime(root .. "/devbox.json")
  if mtime < 0 then
    return
  end
  env.cached_at = mtime
  local ok, json = pcall(vim.json.encode, env)
  if ok then
    vim.fn.writefile(vim.split(json, "\n"), cache_path(root))
  end
end

--- Auto-detect and enable LSP servers from the devbox PATH.
--- Only runs when auto_enable is configured and nvim-lspconfig is installed.
---@return integer number of servers enabled
function Devbox._maybe_auto_enable()
  if not config.options.lsp or not config.options.lsp.auto_enable then
    return 0
  end
  local ok, _ = pcall(require, "lspconfig")
  if not ok then
    return 0
  end
  local servers = require("devbox.lsp.servers")
  local filter = config.options.lsp.auto_enable_filter
  local filter_set
  if filter then
    filter_set = {}
    for _, name in ipairs(filter) do
      filter_set[name] = true
    end
  end
  local detected = servers.detect(filter_set)
  servers.enable(detected)
  return #detected
end

---@param opts? devbox.Config
function Devbox.setup(opts)
  if did_setup then
    return
  end
  did_setup = true

  config.setup(opts)

  if config.options.auto_activate then
    local grp = vim.api.nvim_create_augroup("devbox_nvim", { clear = true })

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
      group = grp,
      desc = "[devbox] activate",
      callback = function(args)
        if Devbox.is_active() or Devbox.is_loading() then
          return
        end
        local buf_dir = vim.fn.expand(("#%d:p:h"):format(args.buf))
        Devbox.activate(buf_dir)
      end,
    })

    vim.api.nvim_create_autocmd("VimEnter", {
      group = grp,
      desc = "[devbox] activate on startup",
      callback = function()
        if Devbox.is_active() or Devbox.is_loading() then
          return
        end
        -- If no file was opened, try current working directory
        Devbox.activate()
      end,
    })

    vim.api.nvim_create_autocmd("DirChanged", {
      group = grp,
      desc = "[devbox] re-check",
      callback = function()
        Devbox.activate()
      end,
    })

    -- If VimEnter already passed (lazy load), activate immediately
    if vim.v.vim_did_enter == 1 then
      Devbox.activate()
    end
  end

  if config.options.lsp and config.options.lsp.inject_env then
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("devbox_nvim_lsp", { clear = true }),
      desc = "[devbox] inject PATH into LSP client",
      callback = function(args)
        if not Devbox.is_active() then
          return
        end
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client then
          Devbox._inject_path(client)
        end
      end,
    })
  end

  vim.api.nvim_create_user_command("DevboxActivate", function()
    if not Devbox.available() then
      Devbox._notify("[devbox] devbox binary not found", vim.log.levels.WARN, { force = true })
    elseif not Devbox.activate() then
      Devbox._notify("[devbox] no devbox.json found", vim.log.levels.INFO, { force = true })
    end
  end, { desc = "[devbox] activate devbox env" })

  vim.api.nvim_create_user_command("DevboxStatus", function()
    if Devbox.is_loading() then
      Devbox._notify("[devbox] loading env...", vim.log.levels.INFO, { force = true })
    elseif Devbox.is_active() then
      Devbox._notify("[devbox] active: " .. (Devbox.get_active_root() or "?"), vim.log.levels.INFO, { force = true })
    else
      Devbox._notify("[devbox] inactive", vim.log.levels.INFO, { force = true })
    end
  end, { desc = "[devbox] show status" })

  vim.api.nvim_create_user_command("DevboxClearCache", function()
    Devbox.clear_cache()
    Devbox._notify("[devbox] cache cleared", vim.log.levels.INFO, { force = true })
  end, { desc = "[devbox] clear env cache" })
end

--- Walk up the directory tree looking for devbox.json
---@param dir? string Starting directory (defaults to current buffer's dir)
---@return string? Absolute project root path, or nil
function Devbox.find_root(dir)
  dir = dir or vim.fn.expand("%:p:h")
  if dir == "" then
    dir = vim.fn.getcwd()
  end
  local root
  if vim.fs.root then
    root = vim.fs.root(dir, "devbox.json")
  end
  if not root then
    local f = vim.fn.findfile("devbox.json", dir .. ";")
    if f ~= "" then
      root = vim.fn.fnamemodify(f --[[@as string]], ":p:h")
    end
  end
  return root
end

---@return boolean
function Devbox.available()
  if Devbox._available ~= nil then
    return Devbox._available
  end
  Devbox._available = vim.fn.executable(config.options.devbox_path) == 1
  return Devbox._available
end

---@return boolean
function Devbox.is_loading()
  return Devbox._loading == true
end

--- Activate devbox env for the current buffer's project.
--- Tries disk cache first, falls back to async devbox shellenv.
--- Never blocks.
---@param dir? string
---@return boolean true if env was applied (from cache), false otherwise
function Devbox.activate(dir)
  if not Devbox.available() then
    return false
  end

  dir = dir or vim.fn.expand("%:p:h")
  local root = Devbox.find_root(dir)
  if not root then
    return false
  end

  -- in-memory cache hit
  if env_cache[root] then
    active_root = root
    Devbox._apply_env(env_cache[root])
    return true
  end

  -- disk cache hit
  local disk = cache_load(root)
  if disk then
    env_cache[root] = disk
    active_root = root
    Devbox._apply_env(disk)
    -- refresh in background
    Devbox._async_load(root)
    return true
  end

  -- no cache: async load
  Devbox._async_load(root)
  return false
end

---@return string?
function Devbox.get_active_root()
  return active_root
end

---@return boolean
function Devbox.is_active()
  return active_root ~= nil
end

--- Devbox PATH string (empty if inactive).
---@return string
function Devbox.get_path()
  local env = active_root and env_cache[active_root]
  return (env and env.path) or ""
end

--- Status string for use in statusline plugins (lualine, etc.).
--- Returns a short label (or empty when inactive) so users can drop it
--- directly into a lualine section.
---@return string
function Devbox.statusline()
  if Devbox.is_loading() then
    return "Devbox..."
  end
  if Devbox.is_active() then
    return "Devbox"
  end
  return ""
end

--- Clear the env cache (memory + disk).
---@param project_root? string nil clears all
function Devbox.clear_cache(project_root)
  if project_root then
    env_cache[project_root] = nil
    local ok, _ = pcall(vim.fn.delete, cache_path(project_root))
    if ok then end
  else
    env_cache = {}
    local dir = vim.fn.stdpath("cache") .. "/devbox"
    pcall(vim.fn.delete, dir, "rf")
  end
end

---@async
---@param root string
function Devbox._async_load(root)
  _load_gen = _load_gen + 1
  local gen = _load_gen
  Devbox._loading = true

  local chunks = {}
  local finished = false

  local job_id = vim.fn.jobstart({ config.options.devbox_path, "shellenv" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      chunks = data
    end,
    on_exit = vim.schedule_wrap(function(_, exit_code)
      if finished then
        return
      end
      finished = true

      if exit_code ~= 0 then
        if gen == _load_gen then
          Devbox._loading = false
        end
        Devbox._notify("[devbox] shellenv failed (exit " .. exit_code .. ")", vim.log.levels.WARN)
        return
      end

      local raw = table.concat(chunks, "\n")
      local parsed = Devbox._parse_shellenv(raw)
      ---@type devbox.Env
      local env = {
        vars = parsed.vars,
        project_root = root,
        path = parsed.vars["PATH"] or "",
      }

      env_cache[root] = env
      cache_save(root, env)

      if gen == _load_gen then
        Devbox._loading = false
        active_root = root
        Devbox._apply_env(env)
      end
    end),
  })
  if job_id and job_id > 0 then
    vim.defer_fn(function()
      if not finished then
        vim.fn.jobstop(job_id)
        finished = true
        if gen == _load_gen then
          Devbox._loading = false
        end
        Devbox._notify("[devbox] shellenv timed out", vim.log.levels.WARN)
      end
    end, 30000)
  end
end

--- Check if all components of a devbox PATH are already present in the client PATH.
--- The devbox PATH may be multi-component (e.g. "/devbox/bin:/nix/store/xxx/bin").
--- Returns true only when every component of `dp` exists as a component in `cur`.
---@param cur string  colon-separated client PATH
---@param dp string  colon-separated devbox PATH (may have multiple entries)
---@return boolean
local function devbox_path_already_present(cur, dp)
  local cur_set = {}
  for p in cur:gmatch("[^:]+") do
    cur_set[p] = true
  end
  for p in dp:gmatch("[^:]+") do
    if not cur_set[p] then
      return false
    end
  end
  return true
end

--- Prepend devbox PATH to an LSP client's cmd_env.
---@param client table|nil
function Devbox._inject_path(client)
  if not client or not client.config then
    return
  end
  local dp = Devbox.get_path()
  if dp == "" then
    return
  end
  client.config.cmd_env = client.config.cmd_env or {}
  local cur = client.config.cmd_env.PATH or vim.env.PATH or ""
  if not devbox_path_already_present(cur, dp) then
    client.config.cmd_env.PATH = dp .. ":" .. cur
  end
end

--- Parse `export KEY=VALUE` lines from `devbox shellenv` output.
---@param raw string
---@return { vars: table<string,string> }
function Devbox._parse_shellenv(raw)
  local vars = {}
  for line in raw:gmatch("([^\n]+)") do
    local key, val = line:match("^export%s+([%a_][%w_]*)%s*=%s*(.*)$")
    if key and val then
      val = val:gsub('^"?(.-)"?%s*;?$', "%1")
      val = val:gsub('\\"', '"')
      val = val:gsub("\\\\", "\\")
      if not Devbox._is_excluded(key) then
        vars[key] = val
      end
    end
  end
  return { vars = vars }
end

---@param key string
---@return boolean
function Devbox._is_excluded(key)
  local excludes = config.options.exclude_env
  if not excludes then
    return false
  end
  for _, p in ipairs(excludes) do
    if key:find(p) then
      return true
    end
  end
  return false
end

--- Apply a parsed devbox env to vim.env, then auto-enable LSP servers.
---@param env devbox.Env
function Devbox._apply_env(env)
  for k, v in pairs(env.vars) do
    if not Devbox._is_excluded(k) then
      vim.env[k] = v
    end
  end
  local lsp_count = Devbox._maybe_auto_enable()
  local name = vim.fn.fnamemodify(env.project_root, ":t")
  local msg = "[devbox] " .. name
  if lsp_count > 0 then
    msg = msg .. " (" .. lsp_count .. " LSP)"
  end
  Devbox._notify(msg, vim.log.levels.INFO, { once = true })
end

return Devbox
