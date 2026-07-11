local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local ui = require("pint.ui")

T["clamp_float keeps a float inside the editor"] = function()
  local value = ui.clamp_float({
    row = -5,
    col = 9999,
    width = 9999,
    height = 9999,
  })

  MiniTest.expect.equality(value.row >= 0, true)
  MiniTest.expect.equality(value.col >= 0, true)
  MiniTest.expect.equality(value.width <= math.max(vim.o.columns - 2, 1), true)
  MiniTest.expect.equality(value.height <= math.max(vim.o.lines - 2, 1), true)
end

T["truncate preserves display width"] = function()
  local value = ui.truncate("hello界", 5)
  MiniTest.expect.equality(vim.api.nvim_strwidth(value) <= 5, true)
end

T["border falls back to rounded"] = function()
  local original = vim.o.winborder
  vim.o.winborder = ""
  ui.setup({ border = nil })
  MiniTest.expect.equality(ui.border(), "rounded")
  vim.o.winborder = original
end

return T
