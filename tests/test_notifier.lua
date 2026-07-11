local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

local notifier = require("pint.notifier")
local ui = require("pint.ui")

local function setup(opts)
  ui.setup({ animation = { enabled = false } })
  notifier.setup(vim.tbl_deep_extend("force", { timeout = 0 }, opts or {}))
end

T["restore only replaces vim.notify while Pint owns it"] = function()
  local original = vim.notify
  setup()

  local replacement = function() end
  vim.notify = replacement
  notifier.restore()

  MiniTest.expect.equality(vim.notify, replacement)
  vim.notify = original
end

T["dismiss_all closes every active notification"] = function()
  setup()
  notifier.notify("one")
  notifier.notify("two")

  MiniTest.expect.equality(notifier._test.active_count(), 2)
  notifier.dismiss_all()
  MiniTest.expect.equality(notifier._test.active_count(), 0)
end

T["dismiss without an id removes the newest notification"] = function()
  setup()
  notifier.notify("one")
  notifier.notify("two")

  notifier.dismiss()

  MiniTest.expect.equality(notifier._test.active_count(), 1)
  MiniTest.expect.equality(notifier._test.active_messages(), { "one" })
end

T["replacement by id reuses the active notification and history entry"] = function()
  setup({ max_history = 10 })
  notifier.notify("starting", vim.log.levels.INFO, { id = "job", title = "Build" })
  notifier.notify("finished", vim.log.levels.INFO, { id = "job", title = "Build" })

  MiniTest.expect.equality(notifier._test.active_count(), 1)
  MiniTest.expect.equality(notifier._test.active_messages(), { "finished" })
  MiniTest.expect.equality(notifier._test.history_messages(), { "finished" })
end

T["max_history zero keeps unlimited history"] = function()
  setup({ max_history = 0 })
  notifier.notify("one")
  notifier.notify("two")
  notifier.notify("three")

  MiniTest.expect.equality(notifier._test.history_messages(), { "one", "two", "three" })
end

T["restore closes notifications and removes the resize group"] = function()
  setup()
  notifier.notify("one")
  notifier.restore()

  MiniTest.expect.equality(notifier._test.active_count(), 0)
  local ok = pcall(vim.api.nvim_get_autocmds, { group = "PintNotifier" })
  MiniTest.expect.equality(ok, false)
end

return T
