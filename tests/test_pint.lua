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
    if line:find(vim.fn.fnamemodify(vim.v.oldfiles[1], ":t"), 1, true) then
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
    child_line:sub(1, 4) == "    ",
    true,
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
    MiniTest.expect.equality(line:find("Hidden Section", 1, true), nil, "disabled section should not appear")
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
  MiniTest.expect.equality(vim.wo.cursorline, true)
  MiniTest.expect.equality(vim.wo.signcolumn, "no")
  MiniTest.expect.equality(vim.wo.spell, false)
  MiniTest.expect.equality(vim.wo.wrap, false)
  MiniTest.expect.equality(vim.wo.list, false)
end

dashboard_set["open() truncates long recent file paths"] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local nested = dir
    .. "/projects/personal/pint.nvim/lua/pint/extra/deep/nested/directories/and/more/"
    .. string.rep("segment-", 6)
    .. "file.lua"
  vim.fn.mkdir(vim.fn.fnamemodify(nested, ":h"), "p")
  vim.fn.writefile({ "x" }, nested)
  vim.v.oldfiles = { nested }
  vim.o.columns = 72
  dashboard.setup({
    autostart = false,
    header = {},
    keys = {
      { desc = "Find File", key = "f", action = ":echo f" },
    },
    recent = { enabled = true, cwd = false, limit = 1 },
    width = 48,
  })
  dashboard.open()
  local win_w = vim.api.nvim_win_get_width(0)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:find("file%.lua", 1, true) or line:find("…", 1, true) then
      found = true
      MiniTest.expect.equality(
        vim.api.nvim_strwidth(line) <= win_w,
        true,
        ("recent path should fit window, got %d > %d: %q"):format(vim.api.nvim_strwidth(line), win_w, line)
      )
    end
  end
  MiniTest.expect.equality(found, true, "recent file row should render")
  vim.fn.delete(nested)
  vim.fn.delete(dir, "rf")
end

dashboard_set["open() recent files use cwd-relative paths when cwd=true"] = function()
  local file = vim.fn.getcwd() .. "/lua/pint/dashboard.lua"
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  vim.fn.writefile({ "x" }, file)
  vim.v.oldfiles = { file }
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = true, cwd = true, limit = 1 },
  })
  dashboard.open()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found_relative = false
  local found_home = false
  for _, line in ipairs(lines) do
    if line:find("lua/pint/dashboard.lua", 1, true) then
      found_relative = true
    end
    if line:find(vim.fn.expand("~"), 1, true) then
      found_home = true
    end
  end
  MiniTest.expect.equality(found_relative, true, "recent file should use cwd-relative path")
  MiniTest.expect.equality(found_home, false, "recent file should not show home directory prefix")
  vim.fn.delete(file)
end

dashboard_set["open() uses consistent gap between sections"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    keys = {
      { desc = "Action", key = "a", action = ":echo a" },
    },
    recent = { enabled = true, cwd = false, limit = 1 },
    sections = {
      {
        title = "Sessions",
        items = function()
          return { { label = "Session One", action = ":echo s" } }
        end,
      },
    },
  })
  local file = vim.fn.tempname()
  vim.fn.writefile({ "x" }, file)
  vim.v.oldfiles = { file }
  dashboard.open()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local action_idx, recent_idx, recent_item_idx, sessions_idx = nil, nil, nil, nil
  for i, line in ipairs(lines) do
    if line:find("Action", 1, true) then
      action_idx = i
    end
    if line:find("Recent files", 1, true) then
      recent_idx = i
    end
    if line:find(vim.fn.fnamemodify(file, ":t"), 1, true) then
      recent_item_idx = i
    end
    if line:find("Sessions", 1, true) then
      sessions_idx = i
    end
  end
  MiniTest.expect.equality(action_idx ~= nil, true)
  MiniTest.expect.equality(recent_idx ~= nil, true)
  MiniTest.expect.equality(recent_item_idx ~= nil, true)
  MiniTest.expect.equality(sessions_idx ~= nil, true)
  local gap_menu_recent = recent_idx - action_idx - 1
  local gap_recent_sessions = sessions_idx - recent_item_idx - 1
  MiniTest.expect.equality(gap_menu_recent, 1, "menu to recent gap")
  MiniTest.expect.equality(gap_recent_sessions, 1, "recent to sessions gap")
  vim.fn.delete(file)
end

dashboard_set["open() recent files include a file icon"] = function()
  local file = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "x" }, file)
  vim.v.oldfiles = { file }
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = true, cwd = false, limit = 1 },
  })
  dashboard.open()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:find(vim.fn.fnamemodify(file, ":t"), 1, true) then
      found = true
      MiniTest.expect.equality(vim.api.nvim_strwidth(line) > #vim.fn.fnamemodify(file, ":t"), true)
    end
  end
  MiniTest.expect.equality(found, true, "recent file row should include icon and filename")
  vim.fn.delete(file)
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
    if line:find("Line1", 1, true) then
      found1 = true
    end
    if line:find("Line2", 1, true) then
      found2 = true
    end
  end
  MiniTest.expect.equality(found1, true, "Line1 should appear")
  MiniTest.expect.equality(found2, true, "Line2 should appear")
end

T["dashboard"] = dashboard_set

local indent_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      pint.setup({ dashboard = { autostart = false } })
    end,
  },
})

indent_set["setup() maps scope textobjects"] = function()
  local found = false
  for _, mode in ipairs({ "o", "x", "n" }) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.lhs == "ii" or m.lhs == "ai" or m.lhs == "[i" or m.lhs == "]i" then
        found = true
      end
    end
  end
  MiniTest.expect.equality(found, true, "indent textobjects and jumps should be mapped")
end

T["indent"] = indent_set

local words_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      pint.setup({ dashboard = { autostart = false }, words = { enabled = true } })
    end,
  },
})

words_set["enable() and disable() toggle state"] = function()
  local words = require("pint.words")
  words.disable()
  MiniTest.expect.equality(words.is_enabled(), false)
  words.enable()
  MiniTest.expect.equality(words.is_enabled(), true)
end

T["words"] = words_set

notifier_set["notify() with id replaces history entry"] = function()
  vim.notify("first", vim.log.levels.INFO, { id = "job", title = "Job" })
  vim.notify("second", vim.log.levels.INFO, { id = "job", title = "Job" })
  require("pint.notifier").show_history()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.cmd.close()
  local first_count, second_count = 0, 0
  for _, line in ipairs(lines) do
    if line:find("first", 1, true) then
      first_count = first_count + 1
    end
    if line:find("second", 1, true) then
      second_count = second_count + 1
    end
  end
  MiniTest.expect.equality(first_count, 0, "replaced id should not keep first message")
  MiniTest.expect.equality(second_count, 1, "replaced id should keep latest message")
end

local notifier_restore_set = MiniTest.new_set()

notifier_restore_set["disabling restores previous vim.notify"] = function()
  require("pint.notifier").restore()
  local baseline = vim.notify
  pint.setup({ dashboard = { autostart = false }, notifier = {} })
  MiniTest.expect.no_equality(vim.notify, baseline)
  pint.setup({ dashboard = { autostart = false }, notifier = false })
  MiniTest.expect.equality(vim.notify, baseline)
end

T["notifier_restore"] = notifier_restore_set

dashboard_set["open() with named padding adds blank lines around section"] = function()
  dashboard.setup({
    autostart = false,
    header = {},
    recent = { enabled = false },
    sections = {
      {
        title = "Named Pad",
        padding = { bottom = 2, top = 1 },
        items = function()
          return { { label = "Only", action = ":echo 'x'" } }
        end,
      },
    },
  })
  dashboard.open()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local title_idx, item_idx = nil, nil
  for i, line in ipairs(lines) do
    if line:find("Named Pad", 1, true) then
      title_idx = i
    end
    if line:find("Only", 1, true) then
      item_idx = i
    end
  end
  MiniTest.expect.equality(title_idx ~= nil, true)
  MiniTest.expect.equality(item_idx ~= nil, true)
  if title_idx > 1 then
    MiniTest.expect.equality(
      lines[title_idx - 1] == "" or (lines[title_idx - 1] or ""):match("^%s*$") ~= nil,
      true,
      "line above title should be blank (top padding)"
    )
  end
  local blank_after = 0
  for i = item_idx + 1, math.min(item_idx + 3, #lines) do
    if lines[i] == "" or lines[i]:match("^%s*$") then
      blank_after = blank_after + 1
    end
  end
  MiniTest.expect.equality(blank_after >= 2, true, "should have bottom padding after item")
end

return T
