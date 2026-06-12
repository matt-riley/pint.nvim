local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local pint = require("pint")

local setup_set = MiniTest.new_set()

setup_set["setup() enables all modules by default"] = function()
  pint.setup()
  MiniTest.expect.equality(type(pint.config.dashboard), "table")
  MiniTest.expect.equality(type(pint.config.notifier), "table")
  MiniTest.expect.equality(type(pint.config.statuscolumn), "table")
  MiniTest.expect.equality(type(pint.config.indent), "table")
  MiniTest.expect.equality(type(pint.config.words), "table")
end

setup_set["setup() allows disabling a module"] = function()
  pint.setup({ dashboard = false })
  MiniTest.expect.equality(pint.config.dashboard, false)
end

setup_set["setup() merges module options"] = function()
  pint.setup({ notifier = { timeout = 5000 } })
  MiniTest.expect.equality(require("pint.notifier").config.timeout, 5000)
end

T["setup"] = setup_set

local notifier_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      pint.setup({ dashboard = { autostart = false } })
    end,
  },
})

notifier_set["notify() replaces vim.notify and records history"] = function()
  vim.notify("hello from test", vim.log.levels.INFO, { title = "Test" })
  local found = false
  -- history is rendered, not exported; assert via show_history buffer
  require("pint.notifier").show_history()
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find("hello from test", 1, true) then
      found = true
    end
  end
  vim.cmd.close()
  MiniTest.expect.equality(found, true)
end

T["notifier"] = notifier_set

local statuscolumn_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      pint.setup({ dashboard = { autostart = false } })
    end,
  },
})

statuscolumn_set["setup() installs the statuscolumn expression"] = function()
  MiniTest.expect.equality(vim.o.statuscolumn, "%!v:lua.require'pint.statuscolumn'.get()")
end

T["statuscolumn"] = statuscolumn_set

return T
