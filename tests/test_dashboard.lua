local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

local dashboard = require("pint.dashboard")

local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function contains(text)
  for _, line in ipairs(lines()) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end

T["cwd containment does not match a sibling with the same prefix"] = function()
  MiniTest.expect.equality(dashboard._test.path_inside("/tmp/foo", "/tmp/foo/file.lua"), true)
  MiniTest.expect.equality(dashboard._test.path_inside("/tmp/foo", "/tmp/foobar/file.lua"), false)
end

T["restore removes the autostart group"] = function()
  dashboard.setup({ autostart = true })
  dashboard.restore()

  local ok = pcall(vim.api.nvim_get_autocmds, { group = "PintDashboard" })
  MiniTest.expect.equality(ok, false)
end

T["section callback errors render a contained error row"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    sections = {
      {
        title = "Broken",
        items = function()
          error("pub is closed")
        end,
      },
    },
  })

  local ok = pcall(dashboard.open)
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(contains("pub is closed"), true)
end

T["empty sections render a polished empty state"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    sections = {
      {
        title = "Nothing here",
        items = function()
          return {}
        end,
      },
    },
  })

  dashboard.open()
  MiniTest.expect.equality(contains("No items"), true)
end

T["footer callback is opt-in and centred"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    footer = function()
      return "Pint is ready"
    end,
  })

  dashboard.open()
  MiniTest.expect.equality(contains("Pint is ready"), true)
end

T["refresh removes obsolete action mappings"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    keys = {
      { key = "x", desc = "Temporary", action = ":echo x" },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  MiniTest.expect.equality(vim.fn.maparg("x", "n", false, true).buffer, 1)

  dashboard.config.keys = {}
  dashboard._test.refresh(buf)

  MiniTest.expect.equality(vim.fn.maparg("x", "n", false, true).lhs or "", "")
end

return T
