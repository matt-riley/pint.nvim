-- lua/pint/notifier.lua
-- Floating-window vim.notify implementation with history and id-replacement.
local M = {}

local ui = require("pint.ui")

--- pint.notifier
---
--- Floating-window |vim.notify()| handler with stacking, id-replacement, and history.
---
---@tag pint-notifier

--- Notifier configuration.
---@class pint.notifier.Config
---@field timeout? integer Milliseconds before a notification hides. Default: 2000
---@field margin? {top: integer, right: integer, bottom: integer}
---@field border? string Window border. Default: shared Pint style
---@field top_down? boolean Stack new notifications at the top. Default: false
---@field max_history? integer Maximum history entries to retain. Zero means unlimited. Default: 200
---@field max_width? number|integer Maximum width as a ratio (<= 1) or columns. Default: 0.4
---@field max_height? number|integer Maximum height as a ratio (<= 1) or rows. Default: 0.4

local defaults = {
  timeout = 2000,
  margin = { top = 0, right = 1, bottom = 1 },
  border = nil,
  top_down = false,
  max_history = 200,
  max_width = 0.4,
  max_height = 0.4,
}

M.config = vim.deepcopy(defaults)

---@class pint.notifier.Item
---@field id string|integer
---@field msg string
---@field level integer
---@field title? string
---@field icon? string
---@field time integer
---@field win? integer
---@field buf? integer
---@field timeout_timer? uv.uv_timer_t
---@field animation_timer? uv.uv_timer_t

---@private
---@type pint.notifier.Item[]
local active = {}
---@private
---@type {id?: string|integer, msg:string, level:integer, title?:string, time:integer}[]
local history = {}
local next_id = 0
local original_notify ---@type fun(msg: string, level?: integer, opts?: table)|nil
local notify_wrapper ---@type fun(msg: string, level?: integer, opts?: table)|nil

local level_meta = {
  [vim.log.levels.TRACE] = { hl = "PintHint", icon = "hint", name = "Trace" },
  [vim.log.levels.DEBUG] = { hl = "PintHint", icon = "hint", name = "Debug" },
  [vim.log.levels.INFO] = { hl = "PintInfo", icon = "info", name = "Info" },
  [vim.log.levels.WARN] = { hl = "PintWarn", icon = "warn", name = "Warn" },
  [vim.log.levels.ERROR] = { hl = "PintError", icon = "error", name = "Error" },
}

---@private
local function meta_for(level)
  return level_meta[level] or level_meta[vim.log.levels.INFO]
end

---@private
---@param value number|integer
---@param total integer
---@param minimum integer
---@return integer
local function resolve_size(value, total, minimum)
  local resolved = value <= 1 and math.floor(total * value) or math.floor(value)
  return math.max(resolved, minimum)
end

---@private
---@param timer uv.uv_timer_t?
local function stop_timer(timer)
  if not timer then
    return
  end
  timer:stop()
  if not timer:is_closing() then
    timer:close()
  end
end

---@private
---@param item pint.notifier.Item
local function stop_animation(item)
  stop_timer(item.animation_timer)
  item.animation_timer = nil
end

---@private
---@param item pint.notifier.Item
local function close_item(item)
  stop_timer(item.timeout_timer)
  stop_animation(item)
  item.timeout_timer = nil

  if item.win and vim.api.nvim_win_is_valid(item.win) then
    pcall(vim.api.nvim_win_close, item.win, true)
  end
  if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
    pcall(vim.api.nvim_buf_delete, item.buf, { force = true })
  end
  item.win, item.buf = nil, nil
end

---@private
---@param item pint.notifier.Item
---@param row number
---@param col number
---@param blend integer
local function settle(item, row, col, blend)
  if not (item.win and vim.api.nvim_win_is_valid(item.win)) then
    return
  end

  local current = vim.api.nvim_win_get_config(item.win)
  local opts = ui.clamp_float({
    relative = "editor",
    row = row,
    col = col,
    width = current.width,
    height = current.height,
  })
  pcall(vim.api.nvim_win_set_config, item.win, opts)
  vim.wo[item.win].winblend = blend
end

---@private
---@param item pint.notifier.Item
---@param row number
---@param col number
---@param closing? boolean
---@param on_complete? fun()
local function transition(item, row, col, closing, on_complete)
  if not (item.win and vim.api.nvim_win_is_valid(item.win)) then
    if on_complete then
      on_complete()
    end
    return
  end

  stop_animation(item)
  local animation = ui.config.animation or {}
  if animation.enabled == false or (animation.duration or 0) <= 0 then
    settle(item, row, col, closing and 100 or 0)
    if on_complete then
      on_complete()
    end
    return
  end

  local current = vim.api.nvim_win_get_config(item.win)
  local start_row = tonumber(current.row) or row
  local start_col = tonumber(current.col) or col
  local start_blend = vim.wo[item.win].winblend
  local end_blend = closing and 100 or 0
  local fps = math.max(animation.fps or 30, 1)
  local duration = math.max(animation.duration or 120, 1)
  local frames = math.max(math.floor(duration / (1000 / fps)), 1)
  local interval = math.max(math.floor(duration / frames), 1)
  local frame = 0

  item.animation_timer = vim.uv.new_timer()
  item.animation_timer:start(0, interval, function()
    frame = frame + 1
    local progress = math.min(frame / frames, 1)
    vim.schedule(function()
      if not (item.win and vim.api.nvim_win_is_valid(item.win)) then
        stop_animation(item)
        return
      end
      settle(
        item,
        start_row + (row - start_row) * progress,
        start_col + (col - start_col) * progress,
        math.floor(start_blend + (end_blend - start_blend) * progress)
      )
      if progress >= 1 then
        stop_animation(item)
        if on_complete then
          on_complete()
        end
      end
    end)
  end)
end

---@private
local function layout(immediate)
  local margin = M.config.margin
  local row = M.config.top_down and margin.top or (vim.o.lines - margin.bottom - 2)

  for _, item in ipairs(active) do
    if item.win and vim.api.nvim_win_is_valid(item.win) then
      local height = vim.api.nvim_win_get_height(item.win)
      local width = vim.api.nvim_win_get_width(item.win)
      if not M.config.top_down then
        row = row - height - 2
      end
      local target_row = math.max(row, margin.top)
      local target_col = math.max(vim.o.columns - width - margin.right - 2, 0)
      if immediate then
        stop_animation(item)
        settle(item, target_row, target_col, 0)
      else
        transition(item, target_row, target_col)
      end
      if M.config.top_down then
        row = row + height + 2
      end
    end
  end
end

---@private
---@param text string
---@param max_width integer
---@param max_height integer
---@return string[]
local function message_lines(text, max_width, max_height)
  local lines = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    lines[#lines + 1] = ui.truncate(line, max_width)
    if #lines >= max_height then
      break
    end
  end
  if #lines == 0 then
    lines = { "" }
  end
  return lines
end

---@private
---@param item pint.notifier.Item
local function render(item)
  local meta = meta_for(item.level)
  local max_width = resolve_size(M.config.max_width, vim.o.columns, 16)
  local max_height = resolve_size(M.config.max_height, vim.o.lines, 1)
  local icon = item.icon or ui.icon(meta.icon, meta.name:sub(1, 1))
  local title = item.title and (" %s %s "):format(icon, item.title) or nil
  local lines = message_lines(item.msg, max_width - 2, max_height)

  local width = title and vim.api.nvim_strwidth(title) or 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.api.nvim_strwidth(line))
  end
  width = math.max(width + 2, math.min(16, math.max(vim.o.columns - 2, 1)))

  if not (item.buf and vim.api.nvim_buf_is_valid(item.buf)) then
    item.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[item.buf].buftype = "nofile"
    vim.bo[item.buf].bufhidden = "wipe"
  end

  vim.bo[item.buf].modifiable = true
  vim.api.nvim_buf_set_lines(item.buf, 0, -1, false, lines)
  vim.bo[item.buf].modifiable = false

  local opts = ui.clamp_float({
    relative = "editor",
    row = 0,
    col = vim.o.columns,
    width = width,
    height = math.max(#lines, 1),
    style = "minimal",
    focusable = false,
    border = ui.border(M.config.border),
    title = title,
    title_pos = title and "left" or nil,
    zindex = 100,
    noautocmd = true,
  })

  if item.win and vim.api.nvim_win_is_valid(item.win) then
    vim.api.nvim_win_set_config(item.win, opts)
  else
    item.win = vim.api.nvim_open_win(item.buf, false, opts)
    vim.wo[item.win].winblend = ui.config.animation.enabled == false and 0 or 100
  end

  local winhighlight = ("NormalFloat:PintNormal,FloatBorder:%s,FloatTitle:%s"):format(meta.hl, meta.hl)
  vim.wo[item.win].winhighlight = winhighlight
  vim.wo[item.win].wrap = false
end

---@private
---@param entry {id?:string|integer,msg:string,level:integer,title?:string,time:integer}
local function record_history(entry)
  if entry.id then
    for index = #history, 1, -1 do
      if history[index].id == entry.id then
        history[index] = entry
        return
      end
    end
  end

  history[#history + 1] = entry
  local limit = M.config.max_history
  while limit and limit > 0 and #history > limit do
    table.remove(history, 1)
  end
end

---@param id? string|integer
function M.dismiss(id)
  local index
  if id == nil then
    index = 1
  else
    for current, item in ipairs(active) do
      if item.id == id then
        index = current
        break
      end
    end
  end

  if not index then
    return false
  end

  local item = table.remove(active, index)
  stop_timer(item.timeout_timer)
  item.timeout_timer = nil
  local width = item.win and vim.api.nvim_win_is_valid(item.win) and vim.api.nvim_win_get_width(item.win) or 0
  transition(item, 0, vim.o.columns + width, true, function()
    close_item(item)
  end)
  layout()
  return true
end

function M.dismiss_all()
  local items = active
  active = {}
  for _, item in ipairs(items) do
    close_item(item)
  end
  layout(true)
end

--- Show a notification. Signature matches |vim.notify()|.
---@param msg string
---@param level? integer
---@param opts? {title?:string, icon?:string, id?:string|integer, timeout?:integer}
function M.notify(msg, level, opts)
  if vim.in_fast_event() then
    vim.schedule(function()
      M.notify(msg, level, opts)
    end)
    return
  end

  opts = opts or {}
  level = level or vim.log.levels.INFO
  msg = tostring(msg)

  ---@type pint.notifier.Item|nil
  local item
  if opts.id ~= nil then
    for _, candidate in ipairs(active) do
      if candidate.id == opts.id then
        item = candidate
        break
      end
    end
  end

  if not item then
    next_id = next_id + 1
    item = { id = opts.id or next_id, msg = msg, level = level, time = os.time() }
    table.insert(active, 1, item)
  end

  item.msg = msg
  item.level = level
  item.title = opts.title
  item.icon = opts.icon
  item.time = os.time()

  record_history({
    id = opts.id,
    msg = msg,
    level = level,
    title = opts.title,
    time = item.time,
  })

  render(item)
  layout()

  stop_timer(item.timeout_timer)
  item.timeout_timer = nil
  local timeout = opts.timeout
  if timeout == nil then
    timeout = M.config.timeout
  end
  if timeout and timeout > 0 then
    item.timeout_timer = vim.uv.new_timer()
    item.timeout_timer:start(timeout, 0, function()
      vim.schedule(function()
        M.dismiss(item.id)
      end)
    end)
  end
end

--- Show notification history in a floating window.
function M.show_history()
  local lines = {}
  for _, item in ipairs(history) do
    local meta = meta_for(item.level)
    local icon = ui.icon(meta.icon, meta.name:sub(1, 1))
    local stamp = os.date("%H:%M:%S", item.time)
    local title = item.title and (" · " .. item.title) or ""
    local prefix = ("%s  %s%s  "):format(stamp, icon, title)
    local message = vim.split(item.msg, "\n", { plain = true })
    for index, line in ipairs(message) do
      lines[#lines + 1] = index == 1 and (prefix .. line) or (string.rep(" ", #prefix) .. line)
    end
    lines[#lines + 1] = ""
  end

  if #lines == 0 then
    lines = { "No notifications yet" }
  elseif lines[#lines] == "" then
    table.remove(lines)
  end

  local width = resolve_size(0.65, vim.o.columns, 20)
  local height = math.min(resolve_size(0.6, vim.o.lines, 3), math.max(#lines, 1))
  local opts = ui.clamp_float({
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = ui.border(M.config.border),
    title = " Notification history ",
    title_pos = "center",
  })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.wo[win].winhighlight = "NormalFloat:PintNormal,FloatBorder:PintBorder,FloatTitle:PintTitle"
  vim.wo[win].wrap = false
  vim.api.nvim_win_set_cursor(win, { math.min(#lines, height), 0 })
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, "<cmd>close<cr>", { buffer = buf, nowait = true })
  end
end

--- Restore the previous |vim.notify()| handler and close Pint notifications.
function M.restore()
  M.dismiss_all()
  pcall(vim.api.nvim_del_augroup_by_name, "PintNotifier")

  if notify_wrapper and vim.notify == notify_wrapper and original_notify then
    vim.notify = original_notify
  end

  notify_wrapper = nil
  original_notify = nil
  history = {}
  next_id = 0
end

--- Install Pint as the |vim.notify()| handler.
---@param opts? pint.notifier.Config
function M.setup(opts)
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  original_notify = vim.notify
  notify_wrapper = function(msg, level, notify_opts)
    M.notify(msg, level, notify_opts)
  end
  vim.notify = notify_wrapper

  local group = vim.api.nvim_create_augroup("PintNotifier", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      layout(true)
    end,
  })
end

M._test = {
  active_count = function()
    return #active
  end,
  active_messages = function()
    return vim.tbl_map(function(item)
      return item.msg
    end, active)
  end,
  history_messages = function()
    return vim.tbl_map(function(item)
      return item.msg
    end, history)
  end,
}

return M
