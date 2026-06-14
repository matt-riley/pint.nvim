-- lua/pint/init.lua
local M = {}

--- pint.nvim
---
--- A small measure of UI: dashboard, notifier, statuscolumn, indent guides,
--- and LSP reference words. Scoped to exactly what one config needs.
---
---@tag pint

--- Plugin configuration.
---@class pint.Config
---@field dashboard? pint.dashboard.Config|false
---@field notifier? pint.notifier.Config|false
---@field statuscolumn? pint.statuscolumn.Config|false
---@field indent? pint.indent.Config|false
---@field words? pint.words.Config|false

---@private
local defaults = {
  dashboard = {},
  notifier = {},
  statuscolumn = {},
  indent = {},
  words = {},
}

---@private
---@type pint.Config
M.config = vim.deepcopy(defaults)

local modules = { "notifier", "statuscolumn", "indent", "words", "dashboard" }
local teardown_modules = { "dashboard", "words", "indent", "statuscolumn", "notifier" }

---@private
local function safe_teardown(name)
  local ok, mod = pcall(require, "pint." .. name)
  if ok and type(mod.teardown) == "function" then
    mod.teardown()
  end
end

--- Configure and enable the plugin's modules.
---
--- Pass `false` for any module to disable it.
---
---@param opts? pint.Config User configuration options
function M.setup(opts)
  opts = opts or {}
  for _, name in ipairs(teardown_modules) do
    safe_teardown(name)
  end
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for _, name in ipairs(modules) do
    if M.config[name] ~= false then
      require("pint." .. name).setup(M.config[name])
    end
  end
end

return M
