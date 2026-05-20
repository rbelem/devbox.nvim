---@class devbox.Config
---@field auto_activate boolean
---@field update_env boolean
---@field strategy string  -- "async" (default) | "sync"
---@field silent boolean
---@field devbox_path string
---@field lsp? { inject_env: boolean }
---@field exclude_env? string[]

local M = {}

---@type devbox.Config
M.defaults = {
  auto_activate = true,
  update_env = true,
  strategy = "async",
  silent = false,
  devbox_path = "devbox",
  lsp = { inject_env = true },
  exclude_env = {
    "^ATUIN_",
    "^BLE_",
    "_PREEXEC_",
    "^BASH_",
    "^SHELL",
    "^TERM",
    "^LS_COLORS",
    "^HIST",
    "^PROMPT",
  },
}

---@type devbox.Config
M.options = {}

---@param opts? devbox.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
