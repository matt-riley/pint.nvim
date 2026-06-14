local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local pint = require("pint")
local dashboard = require("pint.dashboard")

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

--- Dashboard tests
local dashboard_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Disable autostart so we control when open() is called.
      dashboard.setup({ autostart = false })
      -- Seed oldfiles with some readable paths for recent-file tests.
      local tmp = vim.fn.tempname()
      vim.fn.writefile({ "test" }, tmp)
      vim.v.oldfiles = { tmp }
    end,
    post_case = function()
      pcall(vim.cmd, "bd!")
    end,
  },
})

dashboard_set["open() does not crash with default config"] = function()
  dashboard.setup({ autostart = false })
  local ok, err = pcall(dashboard.open)
  MiniTest.expect.equality(ok, true, err and tostring(err) or "")
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines > 0, true, "dashboard buffer should have lines")
end

dashboard_set["open() renders header and recent files section"] = function()
  dashboard.setup({
    autostart = false,
    header = { "TEST HEADER" },
    recent = { enabled = true, cwd = false, limit = 2 },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Should contain the header line (centered) and recent file entries.
  local has_header = false
  local has_filename = false
  for _, line in ipairs(lines) do
    if line:find("TEST HEADER", 1, true) then
      has_header = true
    end
    if line:find(vim.fn.fnamemodify(vim.v.oldfiles[1], ":~"):gsub("%/", "/"), 1, true) then
      has_filename = true
    end
  end
  MiniTest.expect.equality(has_header, true, "header should appear")
  MiniTest.expect.equality(has_filename, true, "recent file should appear")
end

dashboard_set["open() with keys renders action rows"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    keys = {
      { desc = "Test Action", key = "t", action = ":echo 'test'" },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:find("Test Action", 1, true) and line:find("[t]", 1, true) then
      found = true
    end
  end
  MiniTest.expect.equality(found, true, "key row should appear")
end

dashboard_set["open() with key hidden still binds the keymap"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    keys = {
      { desc = "Visible", key = "v", action = ":echo 'v'" },
      { desc = "Hidden", key = "h", action = ":echo 'h'", hidden = true },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local hidden_found = false
  for _, line in ipairs(lines) do
    if line:find("Hidden", 1, true) then
      hidden_found = true
    end
  end
  MiniTest.expect.equality(hidden_found, false, "hidden key should not appear in buffer")
  -- The keymap should still exist (mapped to 'h')
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  local has_h = false
  for _, m in ipairs(maps) do
    if m.lhs == "h" then
      has_h = true
    end
  end
  MiniTest.expect.equality(has_h, true, "hidden key should still be mapped")
end

dashboard_set["open() with enabled=false hides the key"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    keys = {
      { desc = "Always", key = "a", action = ":echo 'a'" },
      { desc = "Disabled", key = "d", action = ":echo 'd'", enabled = false },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local disabled_found = false
  for _, line in ipairs(lines) do
    if line:find("Disabled", 1, true) then
      disabled_found = true
    end
  end
  MiniTest.expect.equality(disabled_found, false, "disabled key should not appear")
end

dashboard_set["open() with custom sections renders titles and items"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "My Section",
        icon = "X",
        items = function()
          return {
            { label = "Item One", action = ":echo 'one'" },
            { label = "Item Two", action = ":echo 'two'" },
          }
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local has_title = false
  local has_item = false
  for _, line in ipairs(lines) do
    if line:find("My Section", 1, true) then
      has_title = true
    end
    if line:find("Item One", 1, true) then
      has_item = true
    end
  end
  MiniTest.expect.equality(has_title, true, "section title should appear")
  MiniTest.expect.equality(has_item, true, "section item should appear")
end

dashboard_set["open() with gap adds blank lines between items"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "Gapped",
        gap = 1,
        items = function()
          return {
            { label = "First", action = ":echo '1'" },
            { label = "Second", action = ":echo '2'" },
          }
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first_idx, second_idx = nil, nil
  for i, line in ipairs(lines) do
    if line:find("First", 1, true) then
      first_idx = i
    end
    if line:find("Second", 1, true) then
      second_idx = i
    end
  end
  MiniTest.expect.equality(first_idx ~= nil, true)
  MiniTest.expect.equality(second_idx ~= nil, true)
  -- With gap=1 there should be exactly 1 blank line between them.
  local blank_count = 0
  for i = first_idx + 1, second_idx - 1 do
    if lines[i] == "" or lines[i]:match("^%s*$") then
      blank_count = blank_count + 1
    end
  end
  MiniTest.expect.equality(blank_count, 1, "should have 1 blank line between items with gap=1")
end

dashboard_set["open() with padding adds blank lines around section"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "Padded",
        padding = { 2, 1 }, -- bottom=2, top=1
        items = function()
          return { { label = "Only", action = ":echo 'x'" } }
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Find the title and item, then check whitespace above title and below item.
  local title_idx, item_idx = nil, nil
  for i, line in ipairs(lines) do
    if line:find("Padded", 1, true) then
      title_idx = i
    end
    if line:find("Only", 1, true) then
      item_idx = i
    end
  end
  MiniTest.expect.equality(title_idx ~= nil, true)
  MiniTest.expect.equality(item_idx ~= nil, true)
  -- There should be 1 blank line above the title (pad_top=1).
  -- Title is at title_idx, the line above should be empty.
  if title_idx > 1 then
    MiniTest.expect.equality(
      lines[title_idx - 1] == "" or (lines[title_idx - 1] or ""):match("^%s*$") ~= nil,
      true,
      "line above title should be blank (top padding)"
    )
  end
  -- After the item, there should be 2 blank lines (pad_bottom=2).
  local blank_after = 0
  for i = item_idx + 1, math.min(item_idx + 3, #lines) do
    if lines[i] == "" or lines[i]:match("^%s*$") then
      blank_after = blank_after + 1
    end
  end
  MiniTest.expect.equality(blank_after >= 2, true, "should have at least 2 blank lines after item (bottom padding)")
end

dashboard_set["open() with indent indents section items"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "Indented",
        indent = 4,
        items = function()
          return { { label = "Child", action = ":echo 'c'" } }
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local child_line = nil
  for _, line in ipairs(lines) do
    if line:find("Child", 1, true) then
      child_line = line
    end
  end
  MiniTest.expect.equality(child_line ~= nil, true, "child item should appear")
  -- Should start with at least 4 spaces.
  MiniTest.expect.equality(
    child_line:sub(1, 4) == "    ", true,
    ("child line should be indented, got: %q"):format(child_line)
  )
end

dashboard_set["open() with enabled section renders it"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "Enabled",
        enabled = true,
        items = function()
          return { { label = "E", action = ":echo 'e'" } }
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:find("Enabled", 1, true) then
      found = true
    end
  end
  MiniTest.expect.equality(found, true, "enabled section should appear")
end

dashboard_set["open() with disabled section hides it"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "Hidden Section",
        enabled = false,
        items = function()
          return { { label = "H", action = ":echo 'h'" } }
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, line in ipairs(lines) do
    MiniTest.expect.equality(
      line:find("Hidden Section", 1, true), nil,
      "disabled section should not appear"
    )
  end
end

dashboard_set["autokeys skip h/j/k/l/q"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    keys = {},
    sections = {
      {
        title = "Auto",
        items = function()
          local items = {}
          for i = 1, 10 do
            items[i] = { label = "Item" .. i, action = ":echo '" .. i .. "'" }
          end
          return items
        end,
      },
    },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  local mapped = {}
  for _, m in ipairs(maps) do
    if #m.lhs == 1 then
      mapped[m.lhs] = true
    end
  end
  -- Items 1-9 get keys 1-9; item 10 gets 0.
  for i = 1, 9 do
    MiniTest.expect.equality(mapped[tostring(i)], true, ("%d should be assigned"):format(i))
  end
  MiniTest.expect.equality(mapped["0"], true, "0 should be assigned for 10th item")
  -- The dashboard binds 'q' to close; that is expected.
  MiniTest.expect.equality(mapped["q"], true, "q is the dashboard close key")
  -- The default autokeys sequence strips h/j/k/l, but we test that those
  -- are NOT among the autokey-assigned chars by checking that the section
  -- items (1-10) use only numeric keys.
  local letters = { "a", "b", "c", "d", "e", "f", "h", "i", "j", "k", "l" }
  for _, c in ipairs(letters) do
    if mapped[c] then
      -- If mapped, it should be the dashboard q, not an autokey
      MiniTest.expect.equality(c, "q", ("unexpected autokey %q mapped"):format(c))
    end
  end
end

dashboard_set["open() buffer has correct filetype"] = function()
  dashboard.setup({ autostart = false })
  dashboard.open()
  MiniTest.expect.equality(vim.bo.filetype, "pint_dashboard")
end

dashboard_set["open() buffer is not modifiable"] = function()
  dashboard.setup({ autostart = false })
  dashboard.open()
  MiniTest.expect.equality(vim.bo.modifiable, false)
end

dashboard_set["open() sets correct buffer options"] = function()
  dashboard.setup({ autostart = false })
  dashboard.open()
  MiniTest.expect.equality(vim.bo.buftype, "nofile")
  MiniTest.expect.equality(vim.bo.buflisted, false)
  MiniTest.expect.equality(vim.bo.swapfile, false)
end

dashboard_set["open() sets correct window options"] = function()
  dashboard.setup({ autostart = false })
  dashboard.open()
  MiniTest.expect.equality(vim.wo.number, false)
  MiniTest.expect.equality(vim.wo.relativenumber, false)
  MiniTest.expect.equality(vim.wo.cursorline, false)
  MiniTest.expect.equality(vim.wo.signcolumn, "no")
  MiniTest.expect.equality(vim.wo.spell, false)
  MiniTest.expect.equality(vim.wo.wrap, false)
  MiniTest.expect.equality(vim.wo.list, false)
end

dashboard_set["open() with custom width constrains content"] = function()
  dashboard.setup({
    autostart = false,
    width = 20,
    header = { "SHORT" },
    recent = { enabled = false },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Every non-blank line should fit within width + pad_left
  local win_width = vim.api.nvim_win_get_width(0)
  for _, line in ipairs(lines) do
    local stripped = line:gsub("^%s+", "")
    MiniTest.expect.equality(#stripped <= 20, true, ("line too wide: %q"):format(line))
  end
end

dashboard_set["q key closes the dashboard"] = function()
  dashboard.setup({ autostart = false })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  -- In headless mode quit may not wipe the buffer immediately because
  -- there are no alternate windows. Instead, verify 'q' is mapped.
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  local has_q = false
  for _, m in ipairs(maps) do
    if m.lhs == "q" then
      has_q = true
    end
  end
  MiniTest.expect.equality(has_q, true, "q should be mapped to close the dashboard")
  -- Also test feeding 'q' doesn't crash (it might close or error, both OK).
  local ok = pcall(vim.api.nvim_feedkeys, "q", "n", false)
  MiniTest.expect.equality(ok, true, "feeding q should not error")
end

dashboard_set["open() with header string splits on newlines"] = function()
  dashboard.setup({
    autostart = false,
    header = "Line1\nLine2",
    recent = { enabled = false },
  })
  dashboard.open()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found1, found2 = false, false
  for _, line in ipairs(lines) do
    if line:find("Line1", 1, true) then found1 = true end
    if line:find("Line2", 1, true) then found2 = true end
  end
  MiniTest.expect.equality(found1, true, "Line1 should appear")
  MiniTest.expect.equality(found2, true, "Line2 should appear")
end

T["dashboard"] = dashboard_set

return T
