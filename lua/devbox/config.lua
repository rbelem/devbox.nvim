---@class devbox.Config
---@field auto_activate boolean
---@field notify "default"|"statusline"|"progress"|"silent"
---@field devbox_path string
---@field lsp? { inject_env: boolean, auto_enable?: boolean, auto_enable_filter?: string[] }
---@field exclude_env? string[]

local M = {}

---@type devbox.Config
M.defaults = {
  auto_activate = true,
  notify = "default",
  devbox_path = "devbox",
  lsp = { inject_env = true, auto_enable = true },
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

local VALID_NOTIFY = { ["default"] = true, ["statusline"] = true, ["progress"] = true, ["silent"] = true }

---@param opts? devbox.Config
function M.setup(opts)
  opts = opts or {}

  -- Backward compat: `silent = true` → `notify = "silent"`
  if opts.silent ~= nil then
    if opts.silent and opts.notify == nil then
      opts.notify = "silent"
    end
    opts.silent = nil
  end

  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts)

  -- Validate lsp option is a table (common mistake: passing true/false)
  if M.options.lsp ~= nil and type(M.options.lsp) ~= "table" then
    vim.notify(
      "[devbox] invalid 'lsp' option, expected a table, got " .. type(M.options.lsp),
      vim.log.levels.WARN
    )
    M.options.lsp = nil
  end

  -- Validate notify value
  if not VALID_NOTIFY[M.options.notify] then
    vim.notify(
      "[devbox] invalid notify option '" .. tostring(M.options.notify) .. "', falling back to 'default'",
      vim.log.levels.WARN
    )
    M.options.notify = "default"
  end
end

return M
