--- Test helpers for devbox.nvim
--- Mock utilities, env management, temp project scaffolding.

local helpers = {}

--- Deep-copy a table.
---@param t table
---@return table
function helpers.deepcopy(t)
  return vim.deepcopy(t)
end

-- ── Environment snapshot ──

local env_backup = {}

--- Snapshot vim.env so tests can restore it.
helpers.take_env_snapshot = function()
  env_backup = vim.deepcopy(vim.env)
end

--- Restore vim.env from snapshot.
helpers.restore_env = function()
  -- Collect keys first to avoid mutation-during-iteration issues
  local keys = {}
  for k, _ in pairs(vim.env) do
    keys[#keys + 1] = k
  end
  for _, k in ipairs(keys) do
    vim.env[k] = nil
  end
  for k, v in pairs(env_backup) do
    vim.env[k] = v
  end
end

-- ── Plugin state reset ──

--- Fully reload the devbox module (clears all in-memory state).
---@param opts? devbox.Config
---@return table The devbox module
function helpers.reload_plugin(opts)
  -- Purge module cache
  package.loaded["devbox"] = nil
  package.loaded["devbox.config"] = nil
  package.loaded["devbox.lsp"] = nil
  package.loaded["devbox.lsp.servers"] = nil
  package.loaded["devbox.init"] = nil

  -- Also clear scripts loaded by plenary (it caches under different keys)
  for k, _ in pairs(package.loaded) do
    if type(k) == "string" and (k:find("^devbox") or k:find("tests.helpers")) then
      package.loaded[k] = nil
    end
  end

  -- Reload and setup
  local devbox = require("devbox")
  -- Sync aliases so require("devbox.init") → same instance
  package.loaded["devbox.init"] = devbox
  devbox.setup(vim.tbl_deep_extend("force", { silent = true }, opts or {}))
  return devbox
end

-- ── Temp dir scaffolding ──

--- Create a temporary project directory with an optional devbox.json.
--- Returns the path. Caller must clean up with os.remove().
---@param with_devbox_json boolean
---@return string tmpdir_path
function helpers.temp_project(with_devbox_json)
  local tmp = os.tmpname():gsub("/tmp/", "")  -- filename only
  local dir = "/tmp/devbox_test_" .. tmp
  vim.fn.mkdir(dir, "p")

  if with_devbox_json then
    vim.fn.writefile(
      vim.split('{"packages":[],"shell":{"scripts":{"test":"echo ok"}}}', "\n"),
      dir .. "/devbox.json"
    )
  end

  return dir
end

--- Recursively remove a directory tree.
---@param dir string
function helpers.rmdir(dir)
  vim.fn.delete(dir, "rf")
end

-- ── Mock devbox shellenv ──

local orig_jobstart

--- Replace vim.fn.jobstart with a mock that calls callbacks synchronously.
---@param output_lines string[] Each element is one line of stdout
---@param exit_code integer
function helpers.mock_jobstart(output_lines, exit_code)
  exit_code = exit_code or 0
  orig_jobstart = vim.fn.jobstart

  vim.fn.jobstart = function(cmd, opts)
    -- Signal shellenv output
    if opts and opts.on_stdout then
      opts.on_stdout(nil, output_lines, nil)
    end
    -- Signal completion
    if opts and opts.on_exit then
      vim.schedule(function()
        opts.on_exit(nil, exit_code)
      end)
    end
    return 1
  end

end

--- Restore original vim.fn.jobstart.
function helpers.restore_jobstart()
  if orig_jobstart then
    vim.fn.jobstart = orig_jobstart
    orig_jobstart = nil
  end
end

-- ── Mock vim.fn.executable ──

local orig_executable
local executable_global_result = nil  -- boolean mode: nil means "use map"
local executable_mock_map = nil       -- table mode: binary→boolean

--- Mock vim.fn.executable with per-binary control.
---@param patterns boolean|table<string,boolean>
---  - true/false: all calls return same value (legacy behavior)
---  - table: map of binary name → boolean (true=executable, false=not)
function helpers.mock_executable(patterns)
  if not orig_executable then
    orig_executable = vim.fn.executable
  end

  if type(patterns) == "table" then
    executable_global_result = nil
    executable_mock_map = patterns
  else
    executable_global_result = patterns and 1 or 0
    executable_mock_map = nil
  end

  vim.fn.executable = function(name)
    if executable_global_result ~= nil then
      return executable_global_result
    end
    if executable_mock_map and name then
      local val = executable_mock_map[name]
      if val ~= nil then
        return val and 1 or 0
      end
    end
    -- Fall through to real executable() for unknown binaries
    return (orig_executable and orig_executable(name)) or 0
  end
end

function helpers.restore_executable()
  if orig_executable then
    vim.fn.executable = orig_executable
    orig_executable = nil
    executable_global_result = nil
    executable_mock_map = nil
  end
end

-- ── Mock vim.lsp.enable ──

local orig_lsp_enable
local lsp_enable_calls = {}

--- Mock vim.lsp.enable to capture calls for assertion.
function helpers.mock_lsp_enable()
  if not orig_lsp_enable then
    orig_lsp_enable = vim.lsp.enable
  end
  lsp_enable_calls = {}
  vim.lsp.enable = function(name)
    lsp_enable_calls[#lsp_enable_calls + 1] = name
  end
end

---@return string[] captured server names
function helpers.get_lsp_enable_calls()
  return lsp_enable_calls
end

function helpers.restore_lsp_enable()
  if orig_lsp_enable then
    vim.lsp.enable = orig_lsp_enable
    orig_lsp_enable = nil
  end
  lsp_enable_calls = {}
end

-- ── Mock vim.api.nvim_get_runtime_file ──

local orig_get_runtime_file

--- Mock nvim_get_runtime_file to return a custom file list for lspconfig.
---@param files string[] list of fake config file paths
function helpers.mock_runtime_files(files)
  if not orig_get_runtime_file then
    orig_get_runtime_file = vim.api.nvim_get_runtime_file
  end
  vim.api.nvim_get_runtime_file = function(pattern, all)
    if type(pattern) == "string" and pattern:find("lspconfig/server_configurations", 1, true) then
      return files
    end
    return orig_get_runtime_file(pattern, all)
  end
end

function helpers.restore_runtime_files()
  if orig_get_runtime_file then
    vim.api.nvim_get_runtime_file = orig_get_runtime_file
    orig_get_runtime_file = nil
  end
end

-- ── Mock lspconfig availability ──

local orig_package_loaded_lspconfig = nil

--- Make pcall(require, "lspconfig") succeed by pre-loading a stub module.
--- Must be called BEFORE fresh() since reload_plugin clears package.loaded.
function helpers.mock_lspconfig()
  orig_package_loaded_lspconfig = nil
  if package.loaded["lspconfig"] then
    orig_package_loaded_lspconfig = package.loaded["lspconfig"]
  end
  package.loaded["lspconfig"] = {}
end

--- Restore original lspconfig module if it existed.
function helpers.restore_lspconfig()
  if orig_package_loaded_lspconfig then
    package.loaded["lspconfig"] = orig_package_loaded_lspconfig
  else
    package.loaded["lspconfig"] = nil
  end
  orig_package_loaded_lspconfig = nil
end

return helpers
