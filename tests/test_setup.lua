local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

local pint = require("pint")

T["restore is idempotent"] = function()
  pint.setup({ dashboard = { autostart = false } })
  pint.restore()
  local ok = pcall(pint.restore)
  MiniTest.expect.equality(ok, true)
end

T["disabling modules restores owned global state"] = function()
  local original_notify = vim.notify
  local original_statuscolumn = vim.o.statuscolumn

  pint.setup({
    dashboard = false,
    notifier = {},
    statuscolumn = {},
    indent = false,
    words = false,
  })

  pint.setup({
    dashboard = false,
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
  })

  MiniTest.expect.equality(vim.notify, original_notify)
  MiniTest.expect.equality(vim.o.statuscolumn, original_statuscolumn)
end

T["repeated setup does not wrap vim.notify repeatedly"] = function()
  local original_notify = vim.notify

  pint.setup({
    dashboard = false,
    notifier = {},
    statuscolumn = false,
    indent = false,
    words = false,
  })
  local first_wrapper = vim.notify

  pint.setup({
    dashboard = false,
    notifier = {},
    statuscolumn = false,
    indent = false,
    words = false,
  })
  local second_wrapper = vim.notify

  MiniTest.expect.equality(first_wrapper ~= original_notify, true)
  MiniTest.expect.equality(second_wrapper ~= original_notify, true)

  pint.restore()
  MiniTest.expect.equality(vim.notify, original_notify)
end

return T
