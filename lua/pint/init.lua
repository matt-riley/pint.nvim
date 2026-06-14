-- lua/pint/init.lua
local M = {}

--- pint.nvim
---
--- A small measure of UI: dashboard, notifier, statuscolumn, indent guides,
--- and LSP reference words. Scoped to exactly what one config needs.
---
--- Modules ~
--- - |pint-dashboard|: `require("pint.dashboard").open()`
--- - |pint-notifier|: `:Pint history`, `require("pint.notifier").show_history()`
--- - |pint-statuscolumn|: sets `'statuscolumn'` globally
--- - |pint-indent|: indent guides with `ii`/`ai` and `[i`/`]i`
--- - |pint-words|: LSP reference highlights with `require("pint.words").jump()`
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

--- Configure and enable the plugin's modules.
---
--- Pass `false` for any module to disable it.
---
---@param opts? pint.Config User configuration options
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for _, name in ipairs(modules) do
    local mod = require("pint." .. name)
    if M.config[name] ~= false then
      mod.setup(M.config[name])
    elseif mod.restore then
      mod.restore()
    end
  end
end

return M
