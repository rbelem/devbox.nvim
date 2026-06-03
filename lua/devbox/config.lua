---@class devbox.Config
---@field auto_activate boolean
---@field silent boolean
---@field devbox_path string
---@field lsp? { inject_env: boolean, auto_enable?: boolean, auto_enable_filter?: string[] }
---@field exclude_env? string[]

local M = {}

---@type devbox.Config
M.defaults = {
  auto_activate = true,
  silent = false,
  devbox_path = "devbox",
  lsp = { inject_env = true, auto_enable = false },
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
