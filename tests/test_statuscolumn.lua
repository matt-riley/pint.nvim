local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

local statuscolumn = require("pint.statuscolumn")

T["restore returns the previous statuscolumn while Pint owns it"] = function()
  vim.o.statuscolumn = "previous"
  statuscolumn.setup()
  statuscolumn.restore()
  MiniTest.expect.equality(vim.o.statuscolumn, "previous")
end

T["restore does not overwrite a later statuscolumn owner"] = function()
  statuscolumn.setup()
  vim.o.statuscolumn = "later"
  statuscolumn.restore()
  MiniTest.expect.equality(vim.o.statuscolumn, "later")
end

T["fit clips double-width signs to the slot"] = function()
  local value = statuscolumn._test.fit("界界", 2)
  MiniTest.expect.equality(vim.api.nvim_strwidth(value), 2)
end

T["number text handles absolute relative and hybrid modes"] = function()
  MiniTest.expect.equality(statuscolumn._test.number_text(8, 3, false, true), "3")
  MiniTest.expect.equality(statuscolumn._test.number_text(8, 0, true, true), "8")
  MiniTest.expect.equality(statuscolumn._test.number_text(8, 3, true, false), "8")
  MiniTest.expect.equality(statuscolumn._test.number_text(8, 3, false, false), "")
end

T["virtual and wrapped rows do not render line content"] = function()
  MiniTest.expect.equality(statuscolumn._test.renderable(1), false)
  MiniTest.expect.equality(statuscolumn._test.renderable(-1), false)
  MiniTest.expect.equality(statuscolumn._test.renderable(0), true)
end

T["get tolerates an invalid statusline window"] = function()
  statuscolumn.setup()
  local original = vim.g.statusline_winid
  vim.g.statusline_winid = -1
  local ok, value = pcall(statuscolumn.get)
  vim.g.statusline_winid = original

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(value, "")
end

return T
