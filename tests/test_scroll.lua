local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      require("tests.helpers").reset()
      if vim.fn.reg_recording() ~= "" then
        vim.cmd("normal! q")
      end
      vim.o.lines = 32
      vim.o.columns = 80
      vim.o.more = false
      vim.wo.wrap = false
      vim.wo.smoothscroll = false
      vim.wo.scrolloff = 0
      vim.wo.sidescrolloff = 0
      vim.wo.foldmethod = "manual"
      vim.wo.foldenable = true
      pcall(vim.cmd, "silent! normal! zE")
      for _ = 1, 32 do
        if vim.fn.getcharstr(1) == "" then
          break
        end
        vim.fn.getcharstr(0)
      end
    end,
  },
})

local scroll = require("pint.scroll")

local function fill(count, width)
  local lines = {}
  for index = 1, count do
    lines[index] = ("line %03d %s"):format(index, string.rep("x", width or 12))
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local function place(line, col)
  vim.wo.scroll = math.floor(vim.api.nvim_win_get_height(0) / 2)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd("keepjumps normal! zt")
  if col and col > 0 then
    vim.api.nvim_win_set_cursor(0, { line, col })
  end
end

local function native(lhs, count)
  local prefix = count and count > 0 and tostring(count) or ""
  local keys = vim.api.nvim_replace_termcodes(prefix .. lhs, true, false, true)
  vim.cmd.normal({ bang = true, args = { keys } })
end

local function expect_view(expected)
  local actual = vim.fn.winsaveview()
  local fields = { "lnum", "col", "coladd", "curswant", "topline", "topfill", "leftcol", "skipcol" }
  for _, field in ipairs(fields) do
    MiniTest.expect.equality(actual[field], expected[field], field)
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], expected.lnum, "cursor line")
  MiniTest.expect.equality(cursor[2], expected.col, "cursor col")
end

local function settle()
  local guard = 0
  while scroll._test.animating() do
    guard = guard + 1
    MiniTest.expect.equality(guard <= 80, true, "animation should finish")
    scroll._test.advance()
  end
  MiniTest.expect.equality(scroll._test.last_error(), nil)
  MiniTest.expect.equality(scroll._test.animating(), false, "animation should finish")
end

local function finish_like_native(lhs, count, prepare)
  prepare()
  native(lhs, count)
  local expected = vim.fn.winsaveview()
  local expected_scroll = vim.wo.scroll

  prepare()
  scroll.scroll(lhs, { count = count or 0 })
  settle()
  expect_view(expected)
  MiniTest.expect.equality(vim.wo.scroll, expected_scroll, "scroll option")
end

local motions = {
  { "half-page down", "<C-d>", 1, 2, nil },
  { "half-page up", "<C-u>", 90, 2, nil },
  { "page down", "<C-f>", 1, 1, nil },
  { "page up", "<C-b>", 100, 1, nil },
  { "center line", "zz", 60, 2, nil },
  { "top line", "zt", 60, 2, nil },
  { "bottom line", "zb", 40, 2, nil },
  { "counted half-page", "<C-d>", 1, 0, 4 },
  { "counted center", "zz", 1, 0, 50 },
}

for _, spec in ipairs(motions) do
  local label, lhs, line, col, count = spec[1], spec[2], spec[3], spec[4], spec[5]
  T[label .. " finishes on the native view and cursor"] = function()
    scroll.setup({ enabled = true, duration = 60, easing = "ease-out-quad" })
    fill(140)
    finish_like_native(lhs, count, function()
      place(line, col)
    end)
  end
end

T["linear easing finishes on the native view"] = function()
  scroll.setup({ enabled = true, duration = 60, easing = "linear" })
  fill(140)
  finish_like_native("<C-f>", nil, function()
    place(1, 3)
  end)
end

T["custom easing is used while scrolling"] = function()
  local seen = false
  scroll.setup({
    enabled = true,
    duration = 70,
    easing = function(t)
      seen = true
      return t
    end,
  })
  fill(140)
  place(1, 0)
  scroll.scroll("<C-f>")
  settle()
  MiniTest.expect.equality(seen, true)
end

T["ease-out-quad leaves the start faster than linear"] = function()
  scroll.setup({ enabled = false, easing = "ease-out-quad" })
  MiniTest.expect.equality(scroll._test.ease(0), 0)
  MiniTest.expect.equality(scroll._test.ease(1), 1)
  MiniTest.expect.equality(scroll._test.ease(0.5) > 0.5, true)
  scroll.setup({ enabled = false, easing = "linear" })
  MiniTest.expect.equality(scroll._test.ease(0.25), 0.25)
end

T["the scroll option is honored"] = function()
  scroll.setup({ enabled = true, duration = 60 })
  fill(140)
  finish_like_native("<C-d>", nil, function()
    place(10, 0)
    vim.wo.scroll = 3
  end)
end

T["scrolloff does not change the final view"] = function()
  scroll.setup({ enabled = true, duration = 70 })
  fill(140)
  finish_like_native("<C-d>", nil, function()
    vim.wo.scrolloff = 4
    place(30, 2)
  end)
  MiniTest.expect.equality(vim.wo.scrolloff, 4)
end

T["folds finish on the native view and cursor"] = function()
  scroll.setup({ enabled = true, duration = 70 })
  fill(140)
  vim.cmd("10,30fold")
  finish_like_native("<C-d>", nil, function()
    place(1, 0)
  end)
  finish_like_native("zz", nil, function()
    place(20, 0)
  end)
end

T["wrapped smoothscroll lines finish on the native view"] = function()
  scroll.setup({ enabled = true, duration = 80 })
  fill(40, 180)
  vim.wo.wrap = true
  vim.wo.smoothscroll = true
  finish_like_native("<C-d>", nil, function()
    place(3, 0)
    vim.cmd.normal({
      bang = true,
      args = { vim.api.nvim_replace_termcodes("<C-e>", true, false, true) },
      mods = { keepjumps = true },
    })
  end)
end

T["a second scroll retargets and finishes where two native commands land"] = function()
  scroll.setup({ enabled = true, duration = 400, easing = "linear" })
  fill(180)
  place(1, 0)
  native("<C-d>")
  native("<C-d>")
  local expected = vim.fn.winsaveview()
  local expected_scroll = vim.wo.scroll

  place(1, 0)
  scroll.scroll("<C-d>")
  MiniTest.expect.equality(scroll._test.animating(), true)
  local guard = 0
  while vim.fn.winsaveview().topline <= 1 and scroll._test.animating() do
    guard = guard + 1
    MiniTest.expect.equality(guard <= 80, true, "first scroll should move before the next one")
    scroll._test.advance()
  end
  MiniTest.expect.equality(vim.fn.winsaveview().topline > 1, true, "first scroll should move before the next one")
  local mid = vim.fn.winsaveview().topline
  scroll.scroll("<C-d>")
  MiniTest.expect.equality(vim.fn.winsaveview().topline >= mid, true)
  MiniTest.expect.equality(scroll._test.animating(), true)
  settle()
  expect_view(expected)
  MiniTest.expect.equality(vim.wo.scroll, expected_scroll)
end

T["disabled scrolling leaves the builtin commands in place"] = function()
  scroll.setup({ enabled = false, duration = 400 })
  MiniTest.expect.equality(scroll.is_enabled(), false)
  MiniTest.expect.equality(vim.fn.maparg("<C-d>", "n"), "")
  MiniTest.expect.equality(vim.fn.maparg("zz", "n"), "")

  fill(80)
  place(1, 0)
  native("<C-d>")
  local expected = vim.fn.winsaveview()

  place(1, 0)
  scroll.scroll("<C-d>")
  MiniTest.expect.equality(scroll._test.animating(), false)
  expect_view(expected)

  place(1, 0)
  local before = vim.fn.winsaveview().topline
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-d>", true, false, true), "x", false)
  MiniTest.expect.equality(vim.fn.winsaveview().topline > before, true)
end

T["setup leaves scrolling off until it is enabled"] = function()
  require("pint").setup({
    dashboard = false,
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(scroll.is_enabled(), false)
  MiniTest.expect.equality(vim.fn.maparg("<C-d>", "n"), "")
  MiniTest.expect.equality(scroll.config.enabled, false)
end

T["commands and toggle enable and disable scrolling"] = function()
  scroll.setup({ enabled = false })
  scroll.toggle()
  MiniTest.expect.equality(scroll.is_enabled(), true)
  MiniTest.expect.equality(vim.fn.maparg("zz", "n") ~= "", true)

  vim.cmd("Pint scroll-toggle")
  MiniTest.expect.equality(scroll.is_enabled(), false)
  MiniTest.expect.equality(vim.fn.maparg("zz", "n"), "")

  vim.cmd("Pint scroll-enable")
  MiniTest.expect.equality(scroll.is_enabled(), true)
  vim.cmd("Pint scroll-disable")
  MiniTest.expect.equality(scroll.is_enabled(), false)
end

T["restore puts a replaced mapping back"] = function()
  vim.keymap.set("n", "<C-d>", "j", { desc = "original mapping" })
  scroll.setup({ enabled = true })
  local during = vim.fn.maparg("<C-d>", "n", false, true)
  MiniTest.expect.equality(during.desc:find("pint", 1, true) ~= nil, true)

  scroll.restore()
  local restored = vim.fn.maparg("<C-d>", "n", false, true)
  MiniTest.expect.equality(restored.desc, "original mapping")
end

T["restore leaves a mapping installed after Pint"] = function()
  scroll.setup({ enabled = true })
  vim.keymap.set("n", "<C-d>", "j", { desc = "later mapping" })
  scroll.restore()
  local current = vim.fn.maparg("<C-d>", "n", false, true)
  MiniTest.expect.equality(current.desc, "later mapping")
end

T["buffer-local mappings keep priority"] = function()
  vim.keymap.set("n", "<C-d>", function()
    vim.g.pint_scroll_local = (vim.g.pint_scroll_local or 0) + 1
  end, { buffer = true, desc = "local down" })
  scroll.setup({ enabled = true, duration = 400 })
  vim.g.pint_scroll_local = 0
  local during = vim.fn.maparg("<C-d>", "n", false, true)
  MiniTest.expect.equality(during.buffer, 1)
  MiniTest.expect.equality(during.desc, "local down")

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-d>", true, false, true), "x", false)
  MiniTest.expect.equality(vim.g.pint_scroll_local, 1)
  MiniTest.expect.equality(scroll._test.animating(), false)

  scroll.restore()
  local after = vim.fn.maparg("<C-d>", "n", false, true)
  MiniTest.expect.equality(after.buffer, 1)
  MiniTest.expect.equality(after.desc, "local down")
end

T["macros scroll immediately to the native view"] = function()
  scroll.setup({ enabled = true, duration = 400 })
  fill(100)
  place(1, 0)
  native("<C-d>")
  local expected = vim.fn.winsaveview()

  place(1, 0)
  vim.fn.setreg("a", vim.api.nvim_replace_termcodes("<C-d>", true, false, true))
  vim.cmd("normal! @a")
  MiniTest.expect.equality(scroll._test.animating(), false)
  expect_view(expected)
end

T["recording scrolls immediately"] = function()
  scroll.setup({ enabled = true, duration = 400 })
  fill(100)
  place(1, 0)
  native("<C-d>")
  local expected = vim.fn.winsaveview()

  place(1, 0)
  vim.cmd("normal! qa")
  MiniTest.expect.equality(vim.fn.reg_recording(), "a")
  scroll.scroll("<C-d>")
  MiniTest.expect.equality(scroll._test.animating(), false)
  expect_view(expected)
  vim.cmd("normal! q")
end

T["very large buffers scroll immediately"] = function()
  scroll.setup({ enabled = true, duration = 400, max_lines = 30 })
  fill(50)
  place(1, 0)
  native("<C-d>")
  local expected = vim.fn.winsaveview()

  place(1, 0)
  scroll.scroll("<C-d>")
  MiniTest.expect.equality(scroll._test.animating(), false)
  expect_view(expected)
end

T["queued keys skip animation and still land on the native view"] = function()
  scroll.setup({ enabled = true, duration = 400 })
  fill(160)
  place(1, 0)
  native("<C-d>")
  native("<C-d>")
  local expected = vim.fn.winsaveview()
  local before = scroll._test.skipped()

  place(1, 0)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-d><C-d>", true, false, true), "xt", false)
  MiniTest.expect.equality(scroll._test.skipped() > before, true)
  settle()
  expect_view(expected)
end

T["a remapped scroll key runs the builtin command immediately"] = function()
  scroll.setup({ enabled = true, duration = 400 })
  fill(100)
  vim.keymap.set("n", "<leader>d", "<C-d>", { remap = true, desc = "leader page" })
  place(1, 0)
  native("<C-d>")
  local expected = vim.fn.winsaveview()

  place(1, 0)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>d", true, false, true), "xt", false)
  MiniTest.expect.equality(scroll._test.animating(), false)
  expect_view(expected)
end

T["the mapped key itself animates"] = function()
  scroll.setup({ enabled = true, duration = 200 })
  fill(140)
  place(1, 0)
  native("<C-d>")
  local expected = vim.fn.winsaveview()

  place(1, 0)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-d>", true, false, true), "xt", false)
  MiniTest.expect.equality(scroll._test.animating(), true)
  MiniTest.expect.equality(vim.fn.winsaveview().topline < expected.topline, true)
  settle()
  expect_view(expected)
end

T["leaving the window stops the animation and restores scrolloff"] = function()
  scroll.setup({ enabled = true, duration = 400 })
  fill(160)
  vim.wo.scrolloff = 6
  place(1, 0)
  local win = vim.api.nvim_get_current_win()
  scroll.scroll("<C-f>")
  MiniTest.expect.equality(scroll._test.animating(), true)
  vim.cmd("new")
  MiniTest.expect.equality(scroll._test.animating(), false)
  MiniTest.expect.equality(scroll._test.last_error(), nil)
  MiniTest.expect.equality(vim.wo[win].scrolloff, 6)
end

T["disabling mid-animation lands on the native view"] = function()
  scroll.setup({ enabled = true, duration = 400 })
  fill(140)
  local function prepare()
    vim.wo.scrolloff = 3
    place(1, 1)
  end
  prepare()
  native("<C-f>")
  local expected = vim.fn.winsaveview()

  prepare()
  scroll.scroll("<C-f>")
  MiniTest.expect.equality(scroll._test.animating(), true)
  scroll.disable()
  MiniTest.expect.equality(scroll._test.animating(), false)
  MiniTest.expect.equality(vim.wo.scrolloff, 3)
  expect_view(expected)
end

T["scroll = false removes scrolling installed earlier"] = function()
  scroll.setup({ enabled = true })
  MiniTest.expect.equality(vim.fn.maparg("<C-u>", "n") ~= "", true)
  require("pint").setup({
    dashboard = false,
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
    scroll = false,
  })
  MiniTest.expect.equality(vim.fn.maparg("<C-u>", "n"), "")
  MiniTest.expect.equality(scroll.is_enabled(), false)
end

return T
