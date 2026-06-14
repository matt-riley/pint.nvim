local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local pint = require("pint")

local function reset()
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
  })
end

local setup_set = MiniTest.new_set()

setup_set["setup() enables all modules by default"] = function()
  reset()
  pint.setup({
    dashboard = { autostart = false },
  })
  MiniTest.expect.equality(type(pint.config.dashboard), "table")
  MiniTest.expect.equality(type(pint.config.notifier), "table")
  MiniTest.expect.equality(type(pint.config.statuscolumn), "table")
  MiniTest.expect.equality(type(pint.config.indent), "table")
  MiniTest.expect.equality(type(pint.config.words), "table")
end

setup_set["setup() allows disabling a module"] = function()
  reset()
  pint.setup({ dashboard = false })
  MiniTest.expect.equality(pint.config.dashboard, false)
end

setup_set["setup() merges module options"] = function()
  reset()
  pint.setup({ dashboard = { autostart = false }, notifier = { timeout = 5000 } })
  MiniTest.expect.equality(require("pint.notifier").config.timeout, 5000)
end

setup_set["setup() restores vim.notify when notifier is disabled"] = function()
  reset()
  local original_notify = vim.notify
  pint.setup({
    dashboard = { autostart = false },
    notifier = {},
    statuscolumn = false,
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(vim.notify ~= original_notify, true)
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(vim.notify, original_notify)
end

setup_set["setup() restores 'statuscolumn' when disabled"] = function()
  reset()
  local original = vim.o.statuscolumn
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = {},
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(vim.o.statuscolumn, "%!v:lua.require'pint.statuscolumn'.get()")
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(vim.o.statuscolumn, original)
end

setup_set["setup() removes indent maps when disabled"] = function()
  reset()
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = false,
    indent = {},
    words = false,
  })
  MiniTest.expect.equality(vim.fn.mapcheck("[i", "n") ~= "", true)
  MiniTest.expect.equality(vim.fn.mapcheck("ii", "x") ~= "", true)
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = false,
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(vim.fn.mapcheck("[i", "n"), "")
  MiniTest.expect.equality(vim.fn.mapcheck("ii", "x"), "")
end

T["setup"] = setup_set

local notifier_set = MiniTest.new_set({
  hooks = {
    pre_case = reset,
  },
})

notifier_set["notify() replaces vim.notify and records history"] = function()
  pint.setup({
    dashboard = { autostart = false },
    notifier = {},
    statuscolumn = false,
    indent = false,
    words = false,
  })
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

notifier_set["history_limit trims old notifications"] = function()
  pint.setup({
    dashboard = { autostart = false },
    notifier = { timeout = 0, history_limit = 2 },
    statuscolumn = false,
    indent = false,
    words = false,
  })
  vim.notify("first kept?", vim.log.levels.INFO)
  vim.notify("second kept?", vim.log.levels.INFO)
  vim.notify("third kept?", vim.log.levels.INFO)
  require("pint.notifier").show_history()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local first, second, third = false, false, false
  for _, line in ipairs(lines) do
    first = first or line:find("first kept?", 1, true) ~= nil
    second = second or line:find("second kept?", 1, true) ~= nil
    third = third or line:find("third kept?", 1, true) ~= nil
  end
  vim.cmd.close()
  MiniTest.expect.equality(first, false)
  MiniTest.expect.equality(second, true)
  MiniTest.expect.equality(third, true)
end

T["notifier"] = notifier_set

local statuscolumn_set = MiniTest.new_set({
  hooks = {
    pre_case = reset,
  },
})

statuscolumn_set["setup() installs the statuscolumn expression"] = function()
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = {},
    indent = false,
    words = false,
  })
  MiniTest.expect.equality(vim.o.statuscolumn, "%!v:lua.require'pint.statuscolumn'.get()")
end

statuscolumn_set["statuscolumn formatting tolerates wide signs"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two" })
  pint.setup({
    dashboard = { autostart = false },
    notifier = false,
    statuscolumn = { folds = { open = true, git_hl = true } },
    indent = false,
    words = false,
  })
  local original_get_extmarks = vim.api.nvim_buf_get_extmarks
  vim.api.nvim_buf_get_extmarks = function(...)
    local buf = select(1, ...)
    if buf ~= bufnr then
      return original_get_extmarks(...)
    end
    return {
      { 1, 0, 0, { sign_text = "界界", sign_hl_group = "ErrorMsg", sign_name = "PintWideSign", priority = 20 } },
    }
  end
  local ok, result = pcall(vim.api.nvim_eval_statusline, vim.o.statuscolumn, {
    winid = vim.api.nvim_get_current_win(),
    maxwidth = 80,
    use_statuscol_lnum = 1,
    fillchar = " ",
  })
  vim.api.nvim_buf_set_extmarks = original_get_extmarks
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(type(result.str), "string")
end

T["statuscolumn"] = statuscolumn_set

local words_set = MiniTest.new_set({
  hooks = {
    pre_case = reset,
  },
})

words_set["jump() moves the original window after async highlight returns"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "alpha", "beta", "gamma" })
  local original_win = vim.api.nvim_get_current_win()
  vim.cmd.vsplit()
  local other_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(other_win, bufnr)
  vim.api.nvim_win_set_cursor(original_win, { 1, 0 })
  vim.api.nvim_win_set_cursor(other_win, { 1, 0 })
  vim.api.nvim_set_current_win(original_win)

  local original_get_clients = vim.lsp.get_clients
  vim.lsp.get_clients = function()
    return {
      {
        offset_encoding = "utf-8",
        request = function(_, _, _, callback)
          vim.api.nvim_set_current_win(other_win)
          callback(nil, {
            { range = { start = { line = 0, character = 0 } } },
            { range = { start = { line = 1, character = 0 } } },
          })
        end,
      },
    }
  end

  local words = require("pint.words")
  words.jump(1)

  vim.lsp.get_clients = original_get_clients
  local original_cursor = vim.api.nvim_win_get_cursor(original_win)
  local other_cursor = vim.api.nvim_win_get_cursor(other_win)
  MiniTest.expect.equality(original_cursor[1], 2)
  MiniTest.expect.equality(other_cursor[1], 1)
end

T["words"] = words_set

return T
