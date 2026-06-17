---@class devbox.LspModule
local M = {}

--- Build an env table suitable for passing to an LSP client's `before_init`.
--- Merges current vim.env with the devbox-resolved PATH.
--- Returns nil if no devbox env is active.
---@return table<string,string>?
function M.make_lsp_env()
  local devbox = require("devbox")
  if not devbox.is_active() then
    return nil
  end

  local env = vim.deepcopy(vim.env)
  setmetatable(env, nil)  -- strip proxy metatable so mutations don't leak
  local devbox_path = devbox.get_path()
  if devbox_path ~= "" then
    local cur = env["PATH"] or ""
    env["PATH"] = devbox_path .. ":" .. cur
  end
  local root = devbox.get_active_root()
  if root then
    env["DEVBOX_PROJECT_ROOT"] = root
  end
  return env
end

return M
