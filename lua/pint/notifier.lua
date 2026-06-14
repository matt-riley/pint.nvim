-- lua/pint/notifier.lua
-- Floating-window vim.notify implementation with history and id-replacement.
local M = {}

--- Notifier configuration.
---@class pint.notifier.Config
---@field timeout? integer Milliseconds before a notification hides. Default: 2000
---@field history_limit? integer Maximum stored notifications. Default: 200
---@field margin? {top: integer, right: integer, bottom: integer}
---@field border? string Window border. Default: vim.o.winborder or "rounded"
---@field top_down? boolean Stack new notifications at the top. Default: false

---@private
local defaults = {
  timeout = 2000,
  history_limit = 200,
  margin = { top = 0, right = 1, bottom = 1 },
  border = nil,
  top_down = false,
}

M.config = vim.deepcopy(defaults)

---@private
---@class pint.notifier.Item
---@field id string|integer
---@field msg string
---@field level integer
---@field title? string
---@field icon? string
---@field time integer
---@field win? integer
---@field buf? integer
---@field timer? uv.uv_timer_t

---@type pint.notifier.Item[] active notifications, in display order
local active = {}
---@type pint.notifier.Item[]
local history = {}
local next_id = 0
local previous_notify
local notify_wrapper

local level_meta = {
  [vim.log.levels.TRACE] = { hl = "DiagnosticHint", icon = "T", name = "Trace" },
  [vim.log.levels.DEBUG] = { hl = "DiagnosticHint", icon = "D", name = "Debug" },
  [vim.log.levels.INFO] = { hl = "DiagnosticInfo", icon = "I", name = "Info" },
  [vim.log.levels.WARN] = { hl = "DiagnosticWarn", icon = "W", name = "Warn" },
  [vim.log.levels.ERROR] = { hl = "DiagnosticError", icon = "E", name = "Error" },
}

local function meta_for(level)
  return level_meta[level] or level_meta[vim.log.levels.INFO]
end

local function border()
  local b = M.config.border or vim.o.winborder
  return (b == nil or b == "") and "rounded" or b
end

---@private
local function close_item(item)
  if item.timer then
    item.timer:stop()
    if not item.timer:is_closing() then
      item.timer:close()
    end
    item.timer = nil
  end
  if item.win and vim.api.nvim_win_is_valid(item.win) then
    vim.api.nvim_win_close(item.win, true)
  end
  if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
    vim.api.nvim_buf_delete(item.buf, { force = true })
  end
  item.win, item.buf = nil, nil
end

---@private
local function layout()
  local cols = vim.o.columns
  local lines = vim.o.lines
  local m = M.config.margin
  local row = M.config.top_down and m.top or (lines - m.bottom - 2)
  for _, item in ipairs(active) do
    if item.win and vim.api.nvim_win_is_valid(item.win) then
      local height = vim.api.nvim_win_get_height(item.win)
      local width = vim.api.nvim_win_get_width(item.win)
      if not M.config.top_down then
        row = row - height - 2 -- account for border
      end
      vim.api.nvim_win_set_config(item.win, {
        relative = "editor",
        row = math.max(row, 0),
        col = cols - width - m.right - 2,
      })
      if M.config.top_down then
        row = row + height + 2
      end
    end
  end
end

---@private
local function render(item)
  local m = meta_for(item.level)
  local lines = vim.split(item.msg, "\n", { plain = true })
  local title = item.title and (" %s %s "):format(item.icon or m.icon, item.title) or nil

  local width = title and vim.api.nvim_strwidth(title) or 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.api.nvim_strwidth(l))
  end
  width = math.min(math.max(width + 2, 16), math.floor(vim.o.columns * 0.4))

  if not (item.buf and vim.api.nvim_buf_is_valid(item.buf)) then
    item.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[item.buf].buftype = "nofile"
    vim.bo[item.buf].bufhidden = "wipe"
  end
  vim.bo[item.buf].modifiable = true
  vim.api.nvim_buf_set_lines(item.buf, 0, -1, false, lines)
  vim.bo[item.buf].modifiable = false

  local win_opts = {
    relative = "editor",
    row = 0,
    col = vim.o.columns,
    width = width,
    height = math.max(#lines, 1),
    style = "minimal",
    focusable = false,
    border = border(),
    title = title,
    title_pos = title and "left" or nil,
    zindex = 100,
    noautocmd = true,
  }
  if item.win and vim.api.nvim_win_is_valid(item.win) then
    vim.api.nvim_win_set_config(item.win, win_opts)
  else
    item.win = vim.api.nvim_open_win(item.buf, false, win_opts)
  end
  local wo = vim.wo[item.win]
  wo.winhighlight = ("NormalFloat:NormalFloat,FloatBorder:%s,FloatTitle:%s"):format(m.hl, m.hl)
  wo.wrap = false
  wo.winblend = 0
end

---@private
local function dismiss(id)
  for i, item in ipairs(active) do
    if item.id == id then
      close_item(item)
      table.remove(active, i)
      break
    end
  end
  layout()
end

--- Show a notification. Signature matches |vim.notify()|.
---@param msg string
---@param level? integer
---@param opts? {title?: string, icon?: string, id?: string|integer, timeout?: integer}
function M.notify(msg, level, opts)
  opts = opts or {}
  level = level or vim.log.levels.INFO

  ---@type pint.notifier.Item|nil
  local item
  if opts.id then
    for _, it in ipairs(active) do
      if it.id == opts.id then
        item = it
        break
      end
    end
  end
  if not item then
    next_id = next_id + 1
    item = { id = opts.id or next_id, time = os.time() }
    table.insert(active, 1, item)
  end
  item.msg = msg
  item.level = level
  item.title = opts.title
  item.icon = opts.icon
  item.time = os.time()
  table.insert(history, { msg = msg, level = level, title = opts.title, time = item.time })
  local limit = M.config.history_limit
  if limit and limit > 0 then
    while #history > limit do
      table.remove(history, 1)
    end
  end

  render(item)
  layout()

  if item.timer then
    item.timer:stop()
  else
    item.timer = vim.uv.new_timer()
  end
  local timeout = opts.timeout or M.config.timeout
  if timeout and timeout > 0 then
    item.timer:start(timeout, 0, function()
      vim.schedule(function()
        dismiss(item.id)
      end)
    end)
  end
end

--- Show notification history in a floating window.
function M.show_history()
  local lines = {}
  for _, item in ipairs(history) do
    local m = meta_for(item.level)
    local stamp = os.date("%H:%M:%S", item.time)
    local prefix = ("%s %s %s"):format(stamp, m.icon, item.title and ("[" .. item.title .. "] ") or "")
    for i, l in ipairs(vim.split(item.msg, "\n", { plain = true })) do
      table.insert(lines, i == 1 and (prefix .. l) or ((" "):rep(vim.api.nvim_strwidth(prefix)) .. l))
    end
  end
  if #lines == 0 then
    lines = { "No notifications" }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = border(),
    title = " Notification history ",
    title_pos = "center",
  })
  vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
  vim.api.nvim_win_set_cursor(win, { #lines, 0 })
  for _, lhs in ipairs({ "q", "<esc>" }) do
    vim.keymap.set("n", lhs, "<cmd>close<cr>", { buffer = buf, nowait = true })
  end
end

--- Restore the original `vim.notify` and clear notifications.
---@tag pint.notifier.teardown
function M.teardown()
  for _, item in ipairs(active) do
    close_item(item)
  end
  active = {}
  history = {}
  next_id = 0
  if notify_wrapper and vim.notify == notify_wrapper and previous_notify then
    vim.notify = previous_notify
  end
  notify_wrapper = nil
  previous_notify = nil
  pcall(vim.api.nvim_del_augroup_by_name, "PintNotifier")
end

--- Install pint as the vim.notify handler.
---@tag pint.notifier.setup
---@param opts? pint.notifier.Config
function M.setup(opts)
  M.teardown()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  previous_notify = vim.notify
  notify_wrapper = function(msg, level, o)
    M.notify(msg, level, o)
  end
  vim.notify = notify_wrapper
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("PintNotifier", { clear = true }),
    callback = layout,
  })
end

return M
