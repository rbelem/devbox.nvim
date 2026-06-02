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

function helpers.mock_executable(result)
  orig_executable = vim.fn.executable
  vim.fn.executable = function()
    return result and 1 or 0
  end
end

function helpers.restore_executable()
  if orig_executable then
    vim.fn.executable = orig_executable
    orig_executable = nil
  end
end

return helpers
