-- lua/pint/dashboard.lua
-- Startup dashboard: header, keyed actions, recent files, custom sections.
local M = {}

local ui = require("pint.ui")

--- pint.dashboard
---
--- Startup dashboard with header, keyed actions, recent files, and custom sections.
---
---@tag pint-dashboard

---@alias pint.dashboard.Seg { [1]: string, hl?: string }

---@class pint.dashboard.Key
---@field icon? string
---@field key string
---@field desc string
---@field action string|fun()
---@field enabled? boolean|fun():boolean
---@field hidden? boolean

---@class pint.dashboard.Item
---@field label string|pint.dashboard.Seg[]
---@field action? string|fun()
---@field icon? string

---@class pint.dashboard.Section
---@field title string
---@field icon? string
---@field items fun(): pint.dashboard.Item[]
---@field gap? integer
---@field padding? integer|{bottom?:integer, top?:integer, [1]?:integer, [2]?:integer}
---@field indent? integer
---@field enabled? boolean|fun():boolean

---@class pint.dashboard.Config
---@field header? string|string[]
---@field keys? pint.dashboard.Key[]
---@field recent? {enabled?:boolean, cwd?:boolean, limit?:integer, filter?:fun(file:string):boolean}|false
---@field sections? pint.dashboard.Section[]
---@field autostart? boolean
---@field width? integer
---@field autokeys? string
---@field footer? fun(): string|pint.dashboard.Seg[]|nil

---@class pint.dashboard.Row
---@field segments pint.dashboard.Seg[]
---@field action? string|fun()
---@field key? string
---@field align? "center"
---@field hidden? boolean

local default_header = {
  "██████╗ ██╗███╗   ██╗████████╗",
  "██╔══██╗██║████╗  ██║╚══██╔══╝",
  "██████╔╝██║██╔██╗ ██║   ██║   ",
  "██╔═══╝ ██║██║╚██╗██║   ██║   ",
  "██║     ██║██║ ╚████║   ██║   ",
  "╚═╝     ╚═╝╚═╝  ╚═══╝   ╚═╝   ",
  ".nvim",
}

local defaults = {
  header = default_header,
  keys = {},
  recent = { enabled = true, cwd = true, limit = 8, filter = nil },
  sections = {},
  autostart = true,
  width = nil,
  autokeys = "1234567890abcdefghijklmnopqrstuvwxyz",
  footer = nil,
}

M.config = vim.deepcopy(defaults)

local namespace = vim.api.nvim_create_namespace("pint.dashboard")
---@private
---@type table<integer, table>
local instances = {}
local global_chrome ---@type {showtabline:integer,laststatus:integer,count:integer}?

local highlight_links = {
  PintDashboardNormal = "Normal",
  PintDashboardCursorLine = "CursorLine",
  PintDashboardHeader = "Title",
  PintDashboardTitle = "Function",
  PintDashboardRule = "NonText",
  PintDashboardIcon = "Special",
  PintDashboardDesc = "Normal",
  PintDashboardKey = "Label",
  PintDashboardItem = "Directory",
  PintDashboardDir = "Comment",
  PintDashboardFile = "Special",
  PintDashboardFooter = "Comment",
  PintDashboardSpecial = "Special",
  PintDashboardEmpty = "Comment",
  PintDashboardError = "DiagnosticError",
}

---@private
local function setup_highlights()
  for name, target in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

---@private
---@param value boolean|fun():boolean|nil
---@return boolean
local function enabled(value)
  if type(value) == "function" then
    local ok, result = pcall(value)
    return ok and result ~= false
  end
  return value ~= false
end

---@private
---@param padding integer|table|nil
---@return integer top, integer bottom
local function section_padding(padding)
  if type(padding) == "number" then
    return 0, padding
  end
  if type(padding) ~= "table" then
    return 1, 0
  end
  if padding.top ~= nil or padding.bottom ~= nil then
    return padding.top or 0, padding.bottom or 0
  end
  return padding[2] or 0, padding[1] or 0
end

---@private
---@param root string
---@param file string
---@return boolean
local function path_inside(root, file)
  local separator = package.config:sub(1, 1)
  local normalized_root = vim.fs.normalize(root):gsub(separator .. "+$", "")
  local normalized_file = vim.fs.normalize(file)
  return normalized_file == normalized_root
    or normalized_file:sub(1, #normalized_root + 1) == normalized_root .. separator
end

---@private
---@return string[]
local function recent_files()
  local config = M.config.recent
  if type(config) ~= "table" or config.enabled == false then
    return {}
  end

  local cwd = config.cwd and vim.fs.normalize(vim.fn.getcwd()) or nil
  local files = {}
  for _, file in ipairs(vim.v.oldfiles or {}) do
    local normalized = vim.fs.normalize(file)
    local keep = vim.fn.filereadable(normalized) == 1
    if keep and cwd then
      keep = path_inside(cwd, normalized)
    end
    if keep and config.filter then
      local ok, result = pcall(config.filter, normalized)
      keep = ok and result ~= false
    end
    if keep then
      files[#files + 1] = normalized
      if #files >= (config.limit or 8) then
        break
      end
    end
  end
  return files
end

---@private
---@param action string|fun()
local function run(action)
  if type(action) == "function" then
    action()
  elseif action:sub(1, 1) == ":" then
    vim.cmd(action:sub(2))
  else
    local keys = vim.api.nvim_replace_termcodes(action, true, true, true)
    vim.api.nvim_feedkeys(keys, "tm", true)
  end
end

---@private
---@param file string
---@return string icon, string highlight
local function file_icon(file)
  local mini_icons = rawget(_G, "MiniIcons")
  local get_icon = type(mini_icons) == "table" and rawget(mini_icons, "get") or nil
  if type(get_icon) == "function" then
    local icon, highlight = get_icon("file", file)
    if icon then
      return icon, highlight or "PintDashboardIcon"
    end
  end

  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local name = vim.fs.basename(file)
    local extension = vim.fn.fnamemodify(file, ":e")
    local icon, highlight = devicons.get_icon(name, extension, { default = true })
    if icon then
      return icon, highlight or "PintDashboardIcon"
    end
  end

  return ui.icon("file", "·"), "PintDashboardIcon"
end

---@private
---@param text string
---@param width integer
---@return string
local function tail(text, width)
  if width <= 0 then
    return ""
  end
  if vim.api.nvim_strwidth(text) <= width then
    return text
  end

  local chars = {}
  local index = 0
  while true do
    local char = vim.fn.strcharpart(text, index, 1)
    if char == "" then
      break
    end
    chars[#chars + 1] = char
    index = index + 1
  end

  local result = ""
  for current = #chars, 1, -1 do
    local candidate = chars[current] .. result
    if vim.api.nvim_strwidth(candidate) + 1 > width then
      break
    end
    result = candidate
  end
  return "…" .. result
end

---@private
---@param file string
---@param width integer
---@param relative boolean
---@return pint.dashboard.Seg[]
local function path_segments(file, width, relative)
  local display = relative and vim.fn.fnamemodify(file, ":.:") or vim.fn.fnamemodify(file, ":~")
  if vim.api.nvim_strwidth(display) > width then
    display = vim.fn.pathshorten(display)
  end
  if vim.api.nvim_strwidth(display) > width then
    display = tail(display, width)
  end

  local directory = vim.fs.dirname(display)
  local name = vim.fs.basename(display)
  if directory and directory ~= "." and directory ~= name then
    return {
      { directory .. "/", hl = "PintDashboardDir" },
      { name, hl = "PintDashboardFile" },
    }
  end
  return { { display, hl = "PintDashboardFile" } }
end

---@private
---@param segments pint.dashboard.Seg[]
---@return integer
local function segments_width(segments)
  local width = 0
  for _, segment in ipairs(segments) do
    width = width + vim.api.nvim_strwidth(segment[1])
  end
  return width
end

---@private
---@param segments pint.dashboard.Seg[]
---@param width integer
---@return pint.dashboard.Seg[]
local function fit_segments(segments, width)
  local result = {}
  local remaining = math.max(width, 0)
  for _, segment in ipairs(segments) do
    if remaining <= 0 then
      break
    end
    local text = segment[1]
    if vim.api.nvim_strwidth(text) > remaining then
      text = ui.truncate(text, remaining)
    end
    result[#result + 1] = { text, hl = segment.hl }
    remaining = remaining - vim.api.nvim_strwidth(text)
  end
  return result
end

---@private
---@param segments pint.dashboard.Seg[]
---@param key string
---@param width integer
---@return pint.dashboard.Seg[]
local function with_key(segments, key, width)
  local label = "[" .. key .. "]"
  local label_width = vim.api.nvim_strwidth(label)
  local content = fit_segments(segments, math.max(width - label_width - 1, 1))
  local gap = math.max(width - segments_width(content) - label_width, 1)
  content[#content + 1] = { string.rep(" ", gap), hl = "PintDashboardDesc" }
  content[#content + 1] = { label, hl = "PintDashboardKey" }
  return content
end

---@private
---@return string
local function next_autokey(sequence, used, state)
  while state.index <= #sequence do
    local key = sequence:sub(state.index, state.index)
    state.index = state.index + 1
    if not used[key] then
      used[key] = true
      return key
    end
  end
  return ""
end

---@private
---@param rows pint.dashboard.Row[]
local function blank(rows)
  rows[#rows + 1] = { segments = {} }
end

---@private
---@param rows pint.dashboard.Row[]
---@param section pint.dashboard.Section
---@param max_width integer
---@param used table<string,boolean>
---@param autokeys string
---@param auto_state {index:integer}
local function add_section(rows, section, max_width, used, autokeys, auto_state)
  if not enabled(section.enabled) then
    return
  end

  local top, bottom = section_padding(section.padding)
  for _ = 1, top do
    blank(rows)
  end

  rows[#rows + 1] = {
    segments = {
      { section.icon or ui.icon("dashboard", "◆"), hl = "PintDashboardIcon" },
      { "  " .. section.title, hl = "PintDashboardTitle" },
    },
  }
  rows[#rows + 1] = {
    segments = { { string.rep("─", math.min(max_width, 24)), hl = "PintDashboardRule" } },
  }

  local ok, items = pcall(section.items)
  if not ok then
    rows[#rows + 1] = {
      segments = fit_segments({ { "  " .. tostring(items), hl = "PintDashboardError" } }, max_width),
    }
  else
    items = type(items) == "table" and items or {}
    if #items == 0 then
      rows[#rows + 1] = { segments = { { "  No items", hl = "PintDashboardEmpty" } } }
    end

    local indent = string.rep(" ", section.indent ~= nil and section.indent or 2)
    for item_index, item in ipairs(items) do
      local segments = { { indent, hl = "PintDashboardItem" } }
      if item.icon then
        segments[#segments + 1] = { item.icon .. "  ", hl = "PintDashboardIcon" }
      end
      if type(item.label) == "table" then
        for _, segment in ipairs(item.label) do
          segments[#segments + 1] = { segment[1], hl = segment.hl or "PintDashboardItem" }
        end
      else
        segments[#segments + 1] = { tostring(item.label), hl = "PintDashboardItem" }
      end

      local key = item.action and next_autokey(autokeys, used, auto_state) or ""
      if key ~= "" then
        segments = with_key(segments, key, max_width)
      else
        segments = fit_segments(segments, max_width)
      end
      rows[#rows + 1] = { segments = segments, action = item.action, key = key ~= "" and key or nil }

      if item_index < #items then
        for _ = 1, section.gap or 0 do
          blank(rows)
        end
      end
    end
  end

  for _ = 1, bottom do
    blank(rows)
  end
end

---@private
---@param win integer
---@return pint.dashboard.Row[] rows, pint.dashboard.Seg[]? footer
local function build_rows(win)
  local win_width = math.max(vim.api.nvim_win_get_width(win), 1)
  local max_width = math.max(math.min(M.config.width or (win_width - 2), win_width), 1)
  local rows = {}
  local used = {}
  local autokeys = (M.config.autokeys or defaults.autokeys):gsub("[hjklq]", "")
  local auto_state = { index = 1 }

  local header = M.config.header
  if type(header) == "string" then
    header = vim.split(header, "\n", { plain = true })
  elseif type(header) ~= "table" then
    header = {}
  end
  for _, line in ipairs(header) do
    rows[#rows + 1] = {
      segments = fit_segments({ { line, hl = "PintDashboardHeader" } }, max_width),
      align = "center",
    }
  end
  if #header > 0 then
    blank(rows)
    blank(rows)
  end

  for _, key in ipairs(M.config.keys or {}) do
    if enabled(key.enabled) then
      used[key.key] = true
      local segments = {
        { key.icon or ui.icon("dashboard", "◆"), hl = "PintDashboardIcon" },
        { "  " .. key.desc, hl = "PintDashboardDesc" },
      }
      rows[#rows + 1] = {
        segments = key.hidden and {} or with_key(segments, key.key, max_width),
        action = key.action,
        key = key.key,
        hidden = key.hidden,
      }
    end
  end

  local sections = {}
  if type(M.config.recent) == "table" and M.config.recent.enabled ~= false then
    sections[#sections + 1] = {
      title = "Recent files",
      icon = ui.icon("file", "·"),
      items = function()
        local items = {}
        local files = recent_files()
        if #files == 0 then
          return items
        end
        local relative = M.config.recent.cwd == true
        local path_width = math.max(max_width - 8, 8)
        for _, file in ipairs(files) do
          local icon, highlight = file_icon(file)
          local label = { { icon .. "  ", hl = highlight } }
          vim.list_extend(label, path_segments(file, path_width, relative))
          items[#items + 1] = {
            label = label,
            action = function()
              vim.cmd.edit(vim.fn.fnameescape(file))
            end,
          }
        end
        return items
      end,
    }
  end
  vim.list_extend(sections, M.config.sections or {})

  for _, section in ipairs(sections) do
    add_section(rows, section, max_width, used, autokeys, auto_state)
  end

  local footer
  if M.config.footer then
    local ok, value = pcall(M.config.footer)
    if ok and value then
      if type(value) == "string" then
        footer = { { value, hl = "PintDashboardFooter" } }
      elseif type(value) == "table" then
        footer = fit_segments(value, max_width)
      end
    elseif not ok then
      footer = { { tostring(value), hl = "PintDashboardError" } }
    end
  end

  return rows, footer
end

---@private
---@param segments pint.dashboard.Seg[]
---@param left integer
---@return string line, {col:integer,end_col:integer,hl:string}[] marks
local function render_segments(segments, left)
  local parts = { string.rep(" ", math.max(left, 0)) }
  local marks = {}
  local column = math.max(left, 0)
  for _, segment in ipairs(segments) do
    parts[#parts + 1] = segment[1]
    if segment.hl and segment[1] ~= "" then
      marks[#marks + 1] = {
        col = column,
        end_col = column + #segment[1],
        hl = segment.hl,
      }
    end
    column = column + #segment[1]
  end
  return table.concat(parts), marks
end

---@private
---@param buf integer
---@param win integer
---@param rows pint.dashboard.Row[]
---@param footer? pint.dashboard.Seg[]
---@return table context
local function paint(buf, win, rows, footer)
  local win_width = math.max(vim.api.nvim_win_get_width(win), 1)
  local win_height = math.max(vim.api.nvim_win_get_height(win), 1)
  local max_width = math.max(math.min(M.config.width or (win_width - 2), win_width), 1)
  local content_width = 1
  for _, row in ipairs(rows) do
    if not row.hidden then
      content_width = math.max(content_width, math.min(segments_width(row.segments), max_width))
    end
  end

  local visible_rows = 0
  for _, row in ipairs(rows) do
    if not row.hidden then
      visible_rows = visible_rows + 1
    end
  end
  local footer_count = footer and 1 or 0
  local pad_top = math.max(math.floor((win_height - visible_rows - footer_count - 1) / 2), 0)
  local line_count = math.max(win_height, pad_top + visible_rows + footer_count + 1, 1)
  local output = {}
  for _ = 1, line_count do
    output[#output + 1] = ""
  end

  local pending = {}
  local actions = {}
  local row_number = pad_top + 1
  local base_left = math.max(math.floor((win_width - content_width) / 2), 0)

  for _, row in ipairs(rows) do
    if not row.hidden then
      local fitted = fit_segments(row.segments, max_width)
      local width = segments_width(fitted)
      local left = row.align == "center" and math.max(math.floor((win_width - width) / 2), 0) or base_left
      local line, marks = render_segments(fitted, left)
      output[row_number] = line
      for _, mark in ipairs(marks) do
        pending[#pending + 1] = {
          row = row_number - 1,
          col = mark.col,
          end_col = mark.end_col,
          hl = mark.hl,
        }
      end
      if row.action then
        actions[#actions + 1] = { lnum = row_number, action = row.action, key = row.key }
      end
      row_number = row_number + 1
    elseif row.action then
      actions[#actions + 1] = { lnum = nil, action = row.action, key = row.key }
    end
  end

  if footer then
    local fitted = fit_segments(footer, max_width)
    local width = segments_width(fitted)
    local footer_line = math.max(win_height, row_number)
    if footer_line > #output then
      output[footer_line] = ""
    end
    local line, marks = render_segments(fitted, math.max(math.floor((win_width - width) / 2), 0))
    output[footer_line] = line
    for _, mark in ipairs(marks) do
      pending[#pending + 1] = {
        row = footer_line - 1,
        col = mark.col,
        end_col = mark.end_col,
        hl = mark.hl,
      }
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for _, mark in ipairs(pending) do
    vim.api.nvim_buf_set_extmark(buf, namespace, mark.row, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
      priority = 1,
    })
  end
  vim.bo[buf].modifiable = false

  return {
    actions = actions,
    action_by_line = vim.iter(actions):fold({}, function(result, action)
      if action.lnum then
        result[action.lnum] = action.action
      end
      return result
    end),
    left = base_left,
  }
end

---@private
local function acquire_global_chrome()
  if not global_chrome then
    global_chrome = {
      showtabline = vim.o.showtabline,
      laststatus = vim.o.laststatus,
      count = 0,
    }
  end
  global_chrome.count = global_chrome.count + 1
  vim.o.showtabline = 0
  vim.o.laststatus = 0
end

---@private
local function release_global_chrome()
  if not global_chrome then
    return
  end
  global_chrome.count = math.max(global_chrome.count - 1, 0)
  if global_chrome.count > 0 then
    return
  end
  if vim.o.showtabline == 0 then
    vim.o.showtabline = global_chrome.showtabline
  end
  if vim.o.laststatus == 0 then
    vim.o.laststatus = global_chrome.laststatus
  end
  global_chrome = nil
end

---@private
---@param instance table
local function restore_instance(instance)
  if instance.restored then
    return
  end
  instance.restored = true
  release_global_chrome()
  pcall(vim.api.nvim_del_augroup_by_name, instance.group_name)

  if vim.api.nvim_win_is_valid(instance.win) then
    local options = vim.wo[instance.win]
    for name, value in pairs(instance.window_options) do
      pcall(function()
        options[name] = value
      end)
    end
  end
  instances[instance.buf] = nil
end

---@private
---@param instance table
local function clear_action_maps(instance)
  for key in pairs(instance.action_maps) do
    local mapping = vim.fn.maparg(key, "n", false, true)
    if not vim.tbl_isempty(mapping) and mapping.desc == "pint: dashboard action" then
      pcall(vim.keymap.del, "n", key, { buffer = instance.buf })
    end
  end
  instance.action_maps = {}
end

---@private
---@param instance table
local function bind_action_maps(instance)
  clear_action_maps(instance)
  for _, action in ipairs(instance.context.actions) do
    if action.key and action.key ~= "" then
      instance.action_maps[action.key] = true
      vim.keymap.set("n", action.key, function()
        restore_instance(instance)
        run(action.action)
      end, { buffer = instance.buf, nowait = true, desc = "pint: dashboard action" })
    end
  end
end

---@private
---@param instance table
local function refresh_instance(instance)
  if not vim.api.nvim_buf_is_valid(instance.buf) or not vim.api.nvim_win_is_valid(instance.win) then
    return
  end
  local rows, footer = build_rows(instance.win)
  instance.context = paint(instance.buf, instance.win, rows, footer)
  bind_action_maps(instance)

  local current = vim.api.nvim_win_get_cursor(instance.win)[1]
  local target = instance.context.actions[1] and instance.context.actions[1].lnum or 1
  for _, action in ipairs(instance.context.actions) do
    if action.lnum and math.abs(action.lnum - current) < math.abs(target - current) then
      target = action.lnum
    end
  end
  vim.api.nvim_win_set_cursor(instance.win, { math.max(target or 1, 1), instance.context.left })
end

--- Open the dashboard in the current window.
function M.open()
  setup_highlights()
  local win = vim.api.nvim_get_current_win()
  local window_options = {}
  for _, name in ipairs({
    "number",
    "relativenumber",
    "signcolumn",
    "statuscolumn",
    "statusline",
    "winbar",
    "foldcolumn",
    "foldmethod",
    "cursorline",
    "cursorlineopt",
    "cursorcolumn",
    "winhighlight",
    "list",
    "spell",
    "wrap",
    "colorcolumn",
    "sidescrolloff",
  }) do
    window_options[name] = vim.wo[win][name]
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].filetype = "pint_dashboard"

  local options = vim.wo[win]
  options.number = false
  options.relativenumber = false
  options.signcolumn = "no"
  options.statuscolumn = ""
  options.statusline = ""
  options.winbar = ""
  options.foldcolumn = "0"
  options.foldmethod = "manual"
  options.cursorline = true
  options.cursorlineopt = "line"
  options.cursorcolumn = false
  options.list = false
  options.spell = false
  options.wrap = false
  options.colorcolumn = ""
  options.sidescrolloff = 0
  options.winhighlight = "Normal:PintDashboardNormal,CursorLine:PintDashboardCursorLine"

  acquire_global_chrome()

  local instance = {
    buf = buf,
    win = win,
    group_name = "PintDashboard:" .. buf,
    window_options = window_options,
    action_maps = {},
    context = { actions = {}, action_by_line = {}, left = 0 },
    restored = false,
  }
  instances[buf] = instance
  local group = vim.api.nvim_create_augroup(instance.group_name, { clear = true })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      restore_instance(instance)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = vim.schedule_wrap(function()
      refresh_instance(instance)
    end),
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      local current = vim.api.nvim_win_get_cursor(win)[1]
      if instance.context.action_by_line[current] then
        return
      end
      local target
      local distance
      for _, action in ipairs(instance.context.actions) do
        if action.lnum then
          local candidate = math.abs(action.lnum - current)
          if not distance or candidate < distance then
            target, distance = action.lnum, candidate
          end
        end
      end
      if target then
        vim.api.nvim_win_set_cursor(win, { target, instance.context.left })
      end
    end,
  })

  vim.keymap.set("n", "<CR>", function()
    local action = instance.context.action_by_line[vim.api.nvim_win_get_cursor(win)[1]]
    if action then
      restore_instance(instance)
      run(action)
    end
  end, { buffer = buf, nowait = true, desc = "pint: activate dashboard item" })
  vim.keymap.set("n", "q", function()
    restore_instance(instance)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, { buffer = buf, nowait = true, desc = "pint: close dashboard" })

  refresh_instance(instance)
end

--- Disable dashboard autostart and close active dashboard buffers.
function M.restore()
  pcall(vim.api.nvim_del_augroup_by_name, "PintDashboard")
  local buffers = vim.tbl_keys(instances)
  for _, buf in ipairs(buffers) do
    local instance = instances[buf]
    if instance then
      restore_instance(instance)
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
end

--- Configure the dashboard and open it on argument-less startup.
---@param opts? pint.dashboard.Config
function M.setup(opts)
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  setup_highlights()

  if not M.config.autostart then
    return
  end

  local group = vim.api.nvim_create_augroup("PintDashboard", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      if vim.fn.argc() > 0 or vim.api.nvim_buf_get_name(0) ~= "" or vim.bo.modified then
        return
      end
      local uis = vim.api.nvim_list_uis()
      if #uis == 0 or (uis[1].stdout_tty and not uis[1].stdin_tty) then
        return
      end
      local windows = 0
      for _, candidate in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(candidate).relative == "" then
          windows = windows + 1
        end
      end
      if windows ~= 1 then
        return
      end
      local first = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
      if vim.api.nvim_buf_line_count(0) > 1 or first ~= "" then
        return
      end
      M.open()
    end,
  })
end

M._test = {
  path_inside = path_inside,
  refresh = function(buf)
    if instances[buf] then
      refresh_instance(instances[buf])
    end
  end,
  instance_count = function()
    return vim.tbl_count(instances)
  end,
}

return M
