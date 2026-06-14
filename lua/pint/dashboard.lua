-- lua/pint/dashboard.lua
-- Minimal startup dashboard: header, keyed actions, recent files, custom sections.
local M = {}

---@class pint.dashboard.Key
---@field icon? string
---@field key string Single key that triggers the action
---@field desc string
---@field action string|fun() Keys (starting with "<" or ":") or a function

---@class pint.dashboard.Item
---@field label string
---@field action string|fun()

---@class pint.dashboard.Section
---@field title string
---@field icon? string
---@field items fun(): pint.dashboard.Item[]

--- Dashboard configuration.
---@class pint.dashboard.Config
---@field header? string[] ASCII-art header lines
---@field keys? pint.dashboard.Key[]
---@field recent? {enabled?: boolean, cwd?: boolean, limit?: integer, filter?: fun(file: string): boolean}
---@field sections? pint.dashboard.Section[]
---@field autostart? boolean Open when Neovim starts with no arguments. Default: true

---@private
local defaults = {
  header = { "pint.nvim" },
  keys = {},
  recent = { enabled = true, cwd = true, limit = 8, filter = nil },
  sections = {},
  autostart = true,
}

M.config = vim.deepcopy(defaults)

--- Disable dashboard autostart and clear its augroup.
---@tag pint.dashboard.teardown
function M.teardown()
  pcall(vim.api.nvim_del_augroup_by_name, "PintDashboard")
end

---@private
local function recent_files()
  local cfg = M.config.recent
  local cwd = vim.fn.getcwd() .. "/"
  local files = {}
  for _, file in ipairs(vim.v.oldfiles or {}) do
    if vim.fn.filereadable(file) == 1 then
      local keep = not cfg.cwd or file:sub(1, #cwd) == cwd
      if keep and cfg.filter then
        keep = cfg.filter(file)
      end
      if keep then
        table.insert(files, file)
        if #files >= cfg.limit then
          break
        end
      end
    end
  end
  return files
end

---@private
local function run(action)
  if type(action) == "function" then
    return action()
  end
  if action:sub(1, 1) == ":" then
    return vim.cmd(action:sub(2))
  end
  local keys = vim.api.nvim_replace_termcodes(action, true, true, true)
  vim.api.nvim_feedkeys(keys, "tm", true)
end

---@private
local function startup_line()
  local ok, lazy = pcall(require, "lazy")
  if not ok then
    return nil
  end
  local stats = lazy.stats()
  return ("⚡ %d/%d plugins in %.0fms"):format(stats.loaded, stats.count, stats.startuptime)
end

--- Open the dashboard in the current window.
function M.open()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local bo = vim.bo[buf]
  bo.buftype = "nofile"
  bo.bufhidden = "wipe"
  bo.swapfile = false
  bo.filetype = "pint_dashboard"
  local wo = vim.wo[0][0]
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.list = false
  wo.winbar = ""

  ---@type {text: string, hl?: string, action?: string|fun(), key?: string}[]
  local rows = {}
  local function blank()
    table.insert(rows, { text = "" })
  end

  for _, line in ipairs(M.config.header) do
    table.insert(rows, { text = line, hl = "PintDashboardHeader" })
  end
  blank()

  for _, key in ipairs(M.config.keys) do
    table.insert(rows, {
      text = ("%s %s  [%s]"):format(key.icon or "•", key.desc, key.key),
      hl = "PintDashboardKey",
      action = key.action,
      key = key.key,
    })
  end

  local sections = {}
  if M.config.recent.enabled then
    table.insert(sections, {
      title = "Recent files",
      icon = "",
      items = function()
        local items = {}
        for _, file in ipairs(recent_files()) do
          table.insert(items, {
            label = vim.fn.fnamemodify(file, ":~:."),
            action = function()
              vim.cmd.edit(vim.fn.fnameescape(file))
            end,
          })
        end
        return items
      end,
    })
  end
  vim.list_extend(sections, M.config.sections)

  local item_index = 0
  for _, section in ipairs(sections) do
    local items = section.items()
    if #items > 0 then
      blank()
      table.insert(rows, {
        text = ("%s %s"):format(section.icon or "", section.title),
        hl = "PintDashboardTitle",
      })
      for _, item in ipairs(items) do
        item_index = item_index + 1
        local key = item_index <= 9 and tostring(item_index) or nil
        table.insert(rows, {
          text = key and ("  %s  [%d]"):format(item.label, item_index) or ("  %s"):format(item.label),
          hl = "PintDashboardItem",
          action = item.action,
          key = key,
        })
      end
    end
  end

  local footer = startup_line()
  if footer then
    blank()
    table.insert(rows, { text = footer, hl = "PintDashboardFooter" })
  end

  -- center block horizontally and vertically
  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, vim.api.nvim_strwidth(row.text))
  end
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)
  local pad_left = math.max(math.floor((win_width - width) / 2), 0)
  local pad_top = math.max(math.floor((win_height - #rows) / 2), 0)

  local lines = {}
  for _ = 1, pad_top do
    table.insert(lines, "")
  end
  for _, row in ipairs(rows) do
    table.insert(lines, row.text == "" and "" or ((" "):rep(pad_left) .. row.text))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  bo.modifiable = false

  local ns = vim.api.nvim_create_namespace("pint.dashboard")
  for i, row in ipairs(rows) do
    if row.hl and row.text ~= "" then
      vim.hl.range(buf, ns, row.hl, { pad_top + i - 1, 0 }, { pad_top + i - 1, -1 })
    end
    if row.key then
      vim.keymap.set("n", row.key, function()
        run(row.action)
      end, { buffer = buf, nowait = true, desc = row.text })
    end
  end

  local first_action ---@type integer|nil
  for i, row in ipairs(rows) do
    if row.action then
      first_action = first_action or (pad_top + i)
    end
  end
  if first_action then
    vim.api.nvim_win_set_cursor(0, { first_action, pad_left })
  end

  vim.keymap.set("n", "<cr>", function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - pad_top
    local row = rows[lnum]
    if row and row.action then
      run(row.action)
    end
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", "<cmd>quit<cr>", { buffer = buf, nowait = true })
end

--- Configure the dashboard and open it on argument-less startup.
---@tag pint.dashboard.setup
---@param opts? pint.dashboard.Config
function M.setup(opts)
  M.teardown()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  vim.api.nvim_set_hl(0, "PintDashboardHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "PintDashboardKey", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "PintDashboardTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "PintDashboardItem", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PintDashboardFooter", { link = "NonText", default = true })

  if M.config.autostart then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("PintDashboard", { clear = true }),
      once = true,
      callback = function()
        local started_empty = vim.fn.argc() == 0
          and vim.api.nvim_buf_get_name(0) == ""
          and vim.bo.buftype == ""
          and vim.api.nvim_buf_line_count(0) == 1
          and (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or "") == ""
        if started_empty then
          M.open()
        end
      end,
    })
  end
end

return M
