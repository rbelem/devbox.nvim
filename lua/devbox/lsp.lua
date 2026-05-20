---@class devbox.LspModule
local M = {}

function M.setup()
  -- Currently handled via vim.env injection in init.lua
  -- This module exists for future explicit client config
end

--- Build an env table suitable for passing to an LSP client's `before_init`.
--- Merges current vim.env with the devbox-resolved PATH.
--- Returns nil if no devbox env is active.
---@return table<string,string>?
function M.make_lsp_env()
  local devbox = require("devbox.init")
  if not devbox.is_active() then
    return nil
  end

  local env = vim.deepcopy(vim.env)
  local devbox_path = devbox.get_path()
  if devbox_path ~= "" then
    env["PATH"] = devbox_path
  end
  local root = devbox.get_active_root()
  if root then
    env["DEVBOX_PROJECT_ROOT"] = root
  end
  return env
end

return M
