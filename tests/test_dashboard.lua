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

local function content_width()
  local width = 0
  for _, line in ipairs(lines()) do
    width = math.max(width, vim.api.nvim_strwidth(vim.trim(line)))
  end
  return width
end

T["content is sized to its widest line, not the window"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    keys = { { key = "f", desc = "Find File", action = ":echo 1" } },
  })

  dashboard.open()
  local window_width = vim.api.nvim_win_get_width(0)
  MiniTest.expect.equality(window_width > 48, true)
  MiniTest.expect.equality(content_width(), 48)
end

T["width option fixes the content width"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    width = 60,
    keys = { { key = "f", desc = "Find File", action = ":echo 1" } },
  })

  dashboard.open()
  MiniTest.expect.equality(content_width(), 60)
end

T["key hints share one right aligned column"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = false,
    keys = {
      { key = "f", desc = "Find File", action = ":echo 1" },
      { key = "g", desc = "Live Grep", action = ":echo 2" },
    },
  })

  dashboard.open()
  local columns = {}
  for _, line in ipairs(lines()) do
    local col = line:find("%[%a%]")
    if col then
      table.insert(columns, col)
    end
  end
  MiniTest.expect.equality(#columns, 2)
  MiniTest.expect.equality(columns[1], columns[2])
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
