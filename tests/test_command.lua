local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

T["Pint restore calls the public restore API"] = function()
  local pint = require("pint")
  local called = false
  local original = pint.restore
  pint.restore = function()
    called = true
  end

  vim.cmd("Pint restore")

  pint.restore = original
  MiniTest.expect.equality(called, true)
end

T["Pint dismiss delegates to notifier"] = function()
  local notifier = require("pint.notifier")
  local called = false
  local original = notifier.dismiss
  notifier.dismiss = function()
    called = true
  end

  vim.cmd("Pint dismiss")

  notifier.dismiss = original
  MiniTest.expect.equality(called, true)
end

T["Pint dismiss-all delegates to notifier"] = function()
  local notifier = require("pint.notifier")
  local called = false
  local original = notifier.dismiss_all
  notifier.dismiss_all = function()
    called = true
  end

  vim.cmd("Pint dismiss-all")

  notifier.dismiss_all = original
  MiniTest.expect.equality(called, true)
end

return T
