-- lua/pint/dashboard.lua
-- Startup dashboard: header, keyed actions, recent files, custom sections.
local M = {}

--- pint.dashboard
---
--- Startup dashboard with header, keyed actions, recent files, and custom sections.
---
---@tag pint-dashboard

---@class pint.dashboard.Key
---@field icon? string Icon (usually a Nerd Font glyph)
---@field key string Single key that triggers the action
---@field desc string
---@field action string|fun() Keys (starting with "<" or ":") or a function
---@field enabled? boolean|fun():boolean When false, the key row is hidden
---@field hidden? boolean When true, the row is hidden but its keymap is still active

---@class pint.dashboard.Item
---@field label string
---@field action string|fun()

---@class pint.dashboard.Section
---@field title string
---@field icon? string
---@field items fun(): pint.dashboard.Item[]
---@field gap? integer Empty lines between child items
---@field padding? integer|{bottom?:integer, top?:integer, [1]?:integer, [2]?:integer} Padding around the section
---@field indent? integer Spaces to indent child items
---@field enabled? boolean|fun():boolean When false, the section is hidden

--- Dashboard configuration.
---@class pint.dashboard.Config
---@field header? string|string[] ASCII-art header (string is split on newlines)
---@field keys? pint.dashboard.Key[]
---@field recent? {enabled?: boolean, cwd?: boolean, limit?: integer, filter?: fun(file: string): boolean}
---@field sections? pint.dashboard.Section[]
---@field autostart? boolean Open when Neovim starts with no arguments. Default: true
---@field width? integer Maximum content width. Auto-detected when nil.
---@field autokeys? string Sequence of chars for auto-assigned keys (default: 1-9, a-z)

-- Thin segment-based text API. A segment is {str, hl?}.
-- When a row's text is a plain string it renders with vim.hl.range for
-- backward compatibility; when it is a list of segments each segment gets
-- its own extmark so that directory / filename / icon / description /
-- key-bracket can each carry a distinct highlight.

---@alias pint.dashboard.Seg string|{ [1]: string, hl?: string }

---@private
local default_header = {
  "██████╗ ██╗███╗   ██╗████████╗",
  "██╔══██╗██║████╗  ██║╚══██╔══╝",
  "██████╔╝██║██╔██╗ ██║   ██║   ",
  "██╔═══╝ ██║██║╚██╗██║   ██║   ",
  "██║     ██║██║ ╚████║   ██║   ",
  "╚═╝     ╚═╝╚═╝  ╚═══╝   ╚═╝   ",
  ".nvim",
}

---@private
local defaults = {
  header = default_header,
  keys = {},
  recent = { enabled = true, cwd = true, limit = 8, filter = nil },
  sections = {},
  autostart = true,
  width = nil,
  autokeys = "1234567890abcdefghijklmnopqrstuvwxyz",
}

M.config = vim.deepcopy(defaults)

---@private
local NS = vim.api.nvim_create_namespace("pint.dashboard")

---@private
---@param padding integer|{bottom?:integer, top?:integer, [1]?:integer, [2]?:integer}|nil
---@return integer top, integer bottom
local function section_padding(padding)
  local pad_top, pad_bottom = 0, 0
  if type(padding) == "table" then
    if padding.top or padding.bottom then
      pad_top = padding.top or 0
      pad_bottom = padding.bottom or 0
    else
      pad_bottom = padding[1] or 0
      pad_top = padding[2] or 0
    end
  elseif type(padding) == "number" then
    pad_bottom = padding
  end
  return pad_top, pad_bottom
end

---@private
local function recent_files()
  local cfg = M.config.recent
  local cwd = cfg.cwd and vim.fs.normalize(vim.fn.getcwd()) or nil
  local files = {}
  for _, file in ipairs(vim.v.oldfiles or {}) do
    if vim.fn.filereadable(file) == 1 then
      local keep = not cfg.cwd or vim.fs.normalize(file):sub(1, #cwd) == cwd
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

---@param text string
---@return string[]
---@private
local function strchars(text)
  local chars = {} ---@type string[]
  local i = 0
  while true do
    local ch = vim.fn.strcharpart(text, i, 1)
    if ch == "" then
      break
    end
    chars[#chars + 1] = ch
    i = i + 1
  end
  return chars
end

--- Truncate `text` to at most `max_w` display cells.
---@param text string
---@param max_w integer
---@return string
---@private
local function truncate_strwidth(text, max_w)
  if text == "" or max_w <= 0 then
    return ""
  end
  if vim.api.nvim_strwidth(text) <= max_w then
    return text
  end
  if max_w == 1 then
    return "…"
  end
  local ellipsis = "…"
  local limit = max_w - vim.api.nvim_strwidth(ellipsis)
  if limit <= 0 then
    return ellipsis
  end
  local out = ""
  local width = 0
  for _, ch in ipairs(strchars(text)) do
    local cw = vim.api.nvim_strwidth(ch)
    if width + cw > limit then
      return out .. ellipsis
    end
    out = out .. ch
    width = width + cw
  end
  return out
end

--- Keep the tail of `text` within `max_w` display cells.
---@param text string
---@param max_w integer
---@return string
---@private
local function truncate_strwidth_tail(text, max_w)
  if text == "" or max_w <= 0 then
    return ""
  end
  if vim.api.nvim_strwidth(text) <= max_w then
    return text
  end
  local chars = strchars(text)
  local out = ""
  local width = 0
  for i = #chars, 1, -1 do
    local cw = vim.api.nvim_strwidth(chars[i])
    if width + cw > max_w then
      break
    end
    out = chars[i] .. out
    width = width + cw
  end
  if out == "" then
    return truncate_strwidth(text, max_w)
  end
  if width < vim.api.nvim_strwidth(text) then
    local ell = "…"
    if vim.api.nvim_strwidth(ell) + width <= max_w then
      out = ell .. out
    end
  end
  return out
end

--- Icon and highlight for a file path (mini.icons, devicons, then fallback).
---@param file string
---@return string icon
---@return string hl
---@private
local function file_icon(file)
  if _G.MiniIcons ~= nil then
    local icon, hl = _G.MiniIcons.get("file", file)
    if icon then
      return icon, hl or "PintDashboardIcon"
    end
  end
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local name = vim.fn.fnamemodify(file, ":t")
    local ext = vim.fn.fnamemodify(file, ":e")
    local icon, hl = devicons.get_icon(name, ext, { default = true })
    if icon then
      return icon, hl or "PintDashboardIcon"
    end
  end
  local ft = vim.filetype.match({ filename = file })
  if ft and ft ~= "" and _G.MiniIcons ~= nil then
    local icon, hl = _G.MiniIcons.get("filetype", ft)
    if icon then
      return icon, hl or "PintDashboardIcon"
    end
  end
  return "󰈔", "PintDashboardIcon"
end

--- Available display width for a recent-file path segment.
---@param win integer
---@param max_width integer
---@param indent integer
---@return integer
---@private
local function recent_path_budget(win, max_width, indent)
  local win_w = math.max(vim.api.nvim_win_get_width(win) - 2, 1)
  local budget = math.min(max_width, win_w)
  local overhead = indent + 3 + 5
  return math.max(budget - overhead, 12)
end

--- Split a file path into {dir/, filename} segments.
--- Long paths are shortened with pathshorten then display-width truncation.
---@param file string
---@param max_width integer
---@return pint.dashboard.Seg[]
---@private
local function format_path(file, max_width, relative)
  if not max_width or max_width <= 0 then
    max_width = 20
  end
  local fname = relative and vim.fn.fnamemodify(file, ":.:") or vim.fn.fnamemodify(file, ":~")
  if vim.api.nvim_strwidth(fname) > max_width then
    fname = vim.fn.pathshorten(fname)
  end
  if vim.api.nvim_strwidth(fname) <= max_width then
    local dir, name = vim.fs.dirname(fname), vim.fs.basename(fname)
    if dir ~= name then
      return { { dir .. "/", hl = "PintDashboardDir" }, { name, hl = "PintDashboardFile" } }
    end
    return { { fname, hl = "PintDashboardFile" } }
  end

  local dir, name = vim.fs.dirname(fname), vim.fs.basename(fname)
  local name_w = vim.api.nvim_strwidth(name)
  local middle = "/…/"
  local middle_w = vim.api.nvim_strwidth(middle)
  if dir == name or name_w + middle_w >= max_width then
    return { { truncate_strwidth(name, max_width), hl = "PintDashboardFile" } }
  end
  local dir_budget = max_width - name_w - middle_w
  local short_dir = truncate_strwidth_tail(dir, dir_budget)
  return {
    { short_dir .. middle, hl = "PintDashboardDir" },
    { name, hl = "PintDashboardFile" },
  }
end

--- Build recent-file row segments with icon and truncated path.
---@param file string
---@param path_budget integer
---@return pint.dashboard.Seg[]
---@private
local function recent_file_segments(file, path_budget, relative)
  local icon, icon_hl = file_icon(file)
  local segs = {
    { icon, hl = icon_hl },
    { " ", hl = nil },
  }
  vim.list_extend(segs, format_path(file, path_budget, relative))
  return segs
end

--- Sum the strwidth of an array of segments.
---@param segs pint.dashboard.Seg[]
---@return integer
---@private
local function segs_width(segs)
  return vim.iter(segs):fold(0, function(w, s)
    return w + vim.api.nvim_strwidth(s[1])
  end)
end

--- Right-align a `[key]` suffix inside a fixed content width.
---@param segs pint.dashboard.Seg[]
---@param key string
---@param total_width integer
---@private
local function append_aligned_key(segs, key, total_width)
  local label = "[" .. key .. "]"
  local gap = total_width - segs_width(segs) - vim.api.nvim_strwidth(label)
  if gap < 1 then
    gap = 1
  end
  table.insert(segs, { string.rep(" ", gap) })
  table.insert(segs, { label, hl = "PintDashboardKey" })
end

--- Insert aligned key suffixes for all keyed rows.
---@param rows pint.dashboard.Row[]
---@private
local function align_row_keys(rows)
  local keyed_width = vim.iter(rows):fold(0, function(w, row)
    if row.key and type(row.text) == "table" then
      return math.max(w, segs_width(row.text))
    end
    return w
  end)
  if keyed_width == 0 then
    return
  end
  local max_key_w = vim.iter(rows):fold(0, function(w, row)
    if row.key then
      return math.max(w, vim.api.nvim_strwidth("[" .. row.key .. "]"))
    end
    return w
  end)
  local total_width = keyed_width + 1 + max_key_w
  for _, row in ipairs(rows) do
    if row.key and type(row.text) == "table" then
      append_aligned_key(row.text, row.key, total_width)
    end
  end
end

--- Build the line string and collect extmark positions for segments.
--- Extmarks must be applied *after* the line is set in the buffer.
---@param segs pint.dashboard.Seg[]
---@param col_start integer column where the segments begin
---@return string line
---@return {row:integer, col:integer, hl:string, end_col:integer}[]
---@private
local function build_segs_line(segs, col_start)
  local parts = {}
  local marks = {}
  local col = col_start
  for _, s in ipairs(segs) do
    local str, hl = s[1], s.hl
    table.insert(parts, str)
    if hl then
      marks[#marks + 1] = { col = col, hl = hl, end_col = col + #str }
    end
    col = col + #str
  end
  return (" "):rep(col_start) .. table.concat(parts, ""), marks
end

--- Find the next row that has an action, starting from `lnum` and
--- searching in direction `dir` (+1 forward, -1 backward).
---@param rows pint.dashboard.Row[]
---@param lnum integer
---@param dir integer
---@return integer|nil
---@private
local function nearest_action(rows, lnum, dir)
  local start = dir == 1 and lnum or lnum - 1
  local stop = dir == 1 and #rows or 1
  for i = start, stop, dir do
    if rows[i] and rows[i].action then
      return i
    end
  end
  return nil
end

---@class pint.dashboard.Row
---@field text string|pint.dashboard.Seg[]
---@field action? string|fun()
---@field key? string
---@field align? "center"
---@field footer? boolean

---@private
---@return pint.dashboard.Row[] body
---@return pint.dashboard.Row[] footer
local function build_rows(win)
  local max_width = M.config.width or (vim.api.nvim_win_get_width(win) - 2)
  local autokeys = M.config.autokeys:gsub("[hjklq]", "") ---@type string
  local used_keys = {} ---@type table<string, boolean>
  ---@type pint.dashboard.Row[]
  local rows = {}

  local function blank()
    table.insert(rows, { text = "" })
  end

  local header_lines = type(M.config.header) == "string" and vim.split(M.config.header, "\n", { plain = true })
    or M.config.header
  for _, line in ipairs(header_lines) do
    table.insert(rows, { text = { { line, hl = "PintDashboardHeader" } }, align = "center" })
  end
  blank()
  blank()

  for _, k in ipairs(M.config.keys) do
    local kenabled = k.enabled
    if type(kenabled) == "function" then
      kenabled = kenabled()
    end
    if kenabled ~= false then
      if not k.hidden then
        table.insert(rows, {
          text = {
            { k.icon or "󰌑", hl = "PintDashboardIcon" },
            { "  " .. k.desc, hl = "PintDashboardDesc" },
          },
          action = k.action,
          key = k.key,
        })
      else
        table.insert(rows, { text = "", action = k.action, key = k.key })
      end
    end
    if k.key then
      used_keys[k.key] = true
    end
  end

  local sections = {}
  if M.config.recent.enabled then
    table.insert(sections, {
      title = "Recent files",
      icon = "󰋚 ",
      items = function()
        local items = {}
        local path_budget = recent_path_budget(win, max_width, 2)
        local relative = M.config.recent.cwd
        for _, file in ipairs(recent_files()) do
          items[#items + 1] = {
            label = recent_file_segments(file, path_budget, relative),
            action = function()
              vim.cmd.edit(vim.fn.fnameescape(file))
            end,
          }
        end
        return items
      end,
    })
  end
  vim.list_extend(sections, M.config.sections)

  local autokey_idx = 1
  for _, section in ipairs(sections) do
    local senabled = section.enabled
    if type(senabled) == "function" then
      senabled = senabled()
    end
    if senabled ~= false then
      local items = section.items()
      if #items > 0 then
        local pad_top, pad_bottom = section_padding(section.padding)
        if pad_top == 0 and section.padding == nil then
          pad_top = 1
        end
        for _ = 1, pad_top do
          blank()
        end

        table.insert(rows, {
          text = {
            { section.icon or "󰉋 ", hl = "PintDashboardIcon" },
            { section.title, hl = "PintDashboardTitle" },
          },
        })
        table.insert(rows, {
          text = { { string.rep("─", 24), hl = "PintDashboardRule" } },
        })

        local indent = (" "):rep(section.indent ~= nil and section.indent or 2)
        for itemidx, item in ipairs(items) do
          local akey = nil
          while autokey_idx <= #autokeys and used_keys[autokeys:sub(autokey_idx, autokey_idx)] do
            autokey_idx = autokey_idx + 1
          end
          if autokey_idx <= #autokeys then
            akey = autokeys:sub(autokey_idx, autokey_idx)
            autokey_idx = autokey_idx + 1
          end

          local item_text ---@type pint.dashboard.Seg[]
          if type(item.label) == "string" then
            local label = vim.fn.fnamemodify(item.label, ":~:.")
            item_text = { { indent .. label, hl = "PintDashboardItem" } }
          else
            ---@diagnostic disable-next-line: assign-type-mismatch
            item_text = { { indent, hl = "PintDashboardItem" } }
            vim.list_extend(item_text, item.label)
            for _, seg in ipairs(item_text) do
              if not seg.hl then
                seg.hl = "PintDashboardItem"
              end
            end
          end
          table.insert(rows, {
            text = item_text,
            action = item.action,
            key = akey,
          })

          local gap = section.gap or 0
          if gap > 0 and itemidx < #items then
            for _ = 1, gap do
              blank()
            end
          end
        end

        for _ = 1, pad_bottom do
          blank()
        end
      end
    end
  end

  align_row_keys(rows)

  local footer = {} ---@type pint.dashboard.Row[]
  local ok, lazy = pcall(require, "lazy")
  if ok then
    local stats = lazy.stats()
    table.insert(footer, {
      footer = true,
      align = "center",
      text = {
        { "󱐋 ", hl = "PintDashboardFooter" },
        { stats.loaded .. "/" .. stats.count, hl = "PintDashboardSpecial" },
        { " plugins loaded in ", hl = "PintDashboardFooter" },
        { ("%.0fms"):format(stats.startuptime), hl = "PintDashboardSpecial" },
      },
    })
  end

  return rows, footer
end

---@private
---@param body pint.dashboard.Row[]
---@param footer pint.dashboard.Row[]
---@return integer pad_left
---@return integer pad_top
---@return integer footer_start
local function paint_dashboard(buf, win, body, footer)
  local max_width = M.config.width or (vim.api.nvim_win_get_width(win) - 2)
  local content_width = vim.iter(body):fold(0, function(w, row)
    if row.align == "center" then
      return w
    end
    local rw = type(row.text) == "string" and vim.api.nvim_strwidth(row.text) or segs_width(row.text)
    return math.max(w, rw)
  end)
  content_width = math.min(content_width, max_width)

  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  local pad_left = math.max(math.floor((win_width - content_width) / 2), 0)
  local footer_gap = #footer > 0 and 1 or 0
  local pad_top = math.max(math.floor((win_height - footer_gap - #footer - #body) / 2), 1)
  local footer_start = win_height - #footer

  vim.bo[buf].modifiable = true
  local lines = {} ---@type string[]
  for _ = 1, win_height do
    lines[#lines + 1] = ""
  end
  local pending_marks = {} ---@type {lnum:integer, col:integer, hl:string, end_col:integer}[]

  local function row_pad_left(row)
    if row.align == "center" then
      local rw = type(row.text) == "string" and vim.api.nvim_strwidth(row.text) or segs_width(row.text)
      return math.max(math.floor((win_width - rw) / 2), 0)
    end
    return pad_left
  end

  local function paint_row(row, lnum)
    if type(row.text) == "string" then
      lines[lnum + 1] = row.text == "" and "" or ((" "):rep(row_pad_left(row)) .. row.text)
      return
    end
    local left = row_pad_left(row)
    local rendered, marks = build_segs_line(row.text, left)
    lines[lnum + 1] = rendered
    for _, m in ipairs(marks) do
      pending_marks[#pending_marks + 1] = { lnum = lnum, col = m.col, hl = m.hl, end_col = m.end_col }
    end
  end

  for i, row in ipairs(body) do
    paint_row(row, pad_top + i - 1)
  end
  for i, row in ipairs(footer) do
    paint_row(row, footer_start + i - 1)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, m in ipairs(pending_marks) do
    vim.api.nvim_buf_set_extmark(buf, NS, m.lnum, m.col, {
      hl_group = m.hl,
      end_col = m.end_col,
      priority = 1,
    })
  end
  vim.bo[buf].modifiable = false

  return pad_left, pad_top, footer_start
end

--- Open the dashboard in the current window.
function M.open()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Buffer hygiene
  local bo = vim.bo[buf]
  bo.buftype = "nofile"
  bo.bufhidden = "wipe"
  bo.buflisted = false
  bo.swapfile = false
  bo.undofile = false
  bo.filetype = "pint_dashboard"

  -- Window hygiene
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = true
  wo.cursorlineopt = "line"
  wo.cursorcolumn = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.foldmethod = "manual"
  wo.statuscolumn = ""
  wo.statusline = ""
  wo.list = false
  wo.spell = false
  wo.wrap = false
  wo.colorcolumn = ""
  wo.winbar = ""
  wo.sidescrolloff = 0
  -- Override Normal so the dashboard background stays consistent regardless
  -- of colorscheme / float background differences.
  pcall(
    vim.api.nvim_set_option_value,
    "winhighlight",
    "Normal:PintDashboardNormal,NormalFloat:PintDashboardNormal,CursorLine:PintDashboardCursorLine",
    { win = win }
  )

  -- Suppress tabline / statusline for a cleaner startup look.
  local saved = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus }
  if vim.o.showtabline ~= 0 then
    vim.o.showtabline = 0
  end
  if vim.o.laststatus ~= 0 then
    vim.o.laststatus = 0
  end
  -- Store saved state on the buffer so restore_chrome can be idempotent.
  vim.b[buf].pint_dashboard_chrome = saved
  local function restore_chrome()
    local s = vim.b[buf].pint_dashboard_chrome
    if not s then
      return
    end
    vim.b[buf].pint_dashboard_chrome = nil
    if vim.o.showtabline == 0 and s.showtabline ~= 0 then
      vim.o.showtabline = s.showtabline
    end
    if vim.o.laststatus == 0 and s.laststatus ~= 0 then
      vim.o.laststatus = s.laststatus
    end
  end
  -- Called directly (not scheduled) — safe because we only touch global options.
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = restore_chrome,
  })

  local augroup = vim.api.nvim_create_augroup("pint_dashboard_win", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function(ev)
      if ev.buf ~= buf then
        restore_chrome()
        vim.api.nvim_del_augroup_by_id(augroup)
      end
    end,
  })

  ---@type {body: pint.dashboard.Row[], footer: pint.dashboard.Row[], pad_left: integer, pad_top: integer, footer_start: integer}
  local ctx = { body = {}, footer = {}, pad_left = 0, pad_top = 0, footer_start = 0 }

  local function bind_row_keys()
    for _, row in ipairs(ctx.body) do
      if row.key then
        vim.keymap.set("n", row.key, function()
          run(row.action)
        end, { buffer = buf, nowait = true, desc = "pint: dashboard action" })
      end
    end
  end

  local function refresh()
    local cursor = vim.api.nvim_win_get_cursor(win)
    ctx.body, ctx.footer = build_rows(win)
    ctx.pad_left, ctx.pad_top, ctx.footer_start = paint_dashboard(buf, win, ctx.body, ctx.footer)
    bind_row_keys()
    local row_idx = math.min(cursor[1], ctx.footer_start - 1)
    vim.api.nvim_win_set_cursor(win, { row_idx, ctx.pad_left })
  end

  ctx.body, ctx.footer = build_rows(win)
  ctx.pad_left, ctx.pad_top, ctx.footer_start = paint_dashboard(buf, win, ctx.body, ctx.footer)

  -- Keymaps and action tracking
  local action_rows = vim
    .iter(ipairs(ctx.body))
    :filter(function(_, row)
      return row.action ~= nil
    end)
    :map(function(i, _)
      return ctx.pad_top + i
    end)
    :totable()
  bind_row_keys()

  -- Set initial cursor on the first actionable row
  if #action_rows > 0 then
    vim.api.nvim_win_set_cursor(win, { action_rows[1], ctx.pad_left })
  else
    vim.api.nvim_win_set_cursor(win, { ctx.pad_top + 1, ctx.pad_left })
  end

  -- <CR> activates the row under the cursor
  vim.keymap.set("n", "<cr>", function()
    local lnum = vim.api.nvim_win_get_cursor(win)[1] - ctx.pad_top
    local row = ctx.body[lnum]
    if row and row.action then
      restore_chrome()
      run(row.action)
    end
  end, { buffer = buf, nowait = true, desc = "pint: activate dashboard item" })

  vim.keymap.set("n", "q", function()
    restore_chrome()
    vim.cmd.quit()
  end, { buffer = buf, nowait = true, desc = "pint: close dashboard" })

  -- Snap cursor to nearest actionable row on movement
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    group = augroup,
    callback = function()
      local lnum = vim.api.nvim_win_get_cursor(win)[1] - ctx.pad_top
      if lnum > #ctx.body then
        local target = nearest_action(ctx.body, #ctx.body, -1)
        if target then
          vim.api.nvim_win_set_cursor(win, { ctx.pad_top + target, ctx.pad_left })
        end
        return
      end
      local row = ctx.body[lnum]
      if not row or not row.action then
        local target = nearest_action(ctx.body, lnum, 1) or nearest_action(ctx.body, lnum, -1)
        if target then
          vim.api.nvim_win_set_cursor(win, { ctx.pad_top + target, ctx.pad_left })
        end
      end
    end,
  })

  -- Re-render on resize without recreating the buffer
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = augroup,
    callback = vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      refresh()
    end),
  })
end

--- Configure the dashboard and open it on argument-less startup.
---@param opts? pint.dashboard.Config
---@private
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  -- Highlight groups — all default=true so users can override them.
  local hls = {
    PintDashboardNormal = { link = "Normal", default = true },
    PintDashboardCursorLine = { link = "CursorLine", default = true },
    PintDashboardHeader = { link = "Title", default = true },
    PintDashboardTitle = { link = "Function", default = true },
    PintDashboardRule = { link = "NonText", default = true },
    PintDashboardIcon = { link = "Special", default = true },
    PintDashboardDesc = { link = "Normal", default = true },
    PintDashboardKey = { link = "Label", default = true },
    PintDashboardItem = { link = "Directory", default = true },
    PintDashboardDir = { link = "NonText", default = true },
    PintDashboardFile = { link = "Special", default = true },
    PintDashboardFooter = { link = "Comment", default = true },
    PintDashboardSpecial = { link = "Special", default = true },
  }
  for name, hl in pairs(hls) do
    vim.api.nvim_set_hl(0, name, hl)
  end

  if M.config.autostart then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("PintDashboard", { clear = true }),
      once = true,
      callback = function()
        -- More thorough startup-empty check (inspired by snacks).
        if vim.fn.argc() > 0 then
          return
        end
        if vim.api.nvim_buf_get_name(0) ~= "" then
          return
        end
        if vim.bo.modified then
          return
        end
        -- Check for headless or piped stdin
        local uis = vim.api.nvim_list_uis()
        if #uis == 0 then
          return
        end
        if uis[1].stdout_tty and not uis[1].stdin_tty then
          return
        end
        -- Only one non-floating window
        local normal_wins = vim
          .iter(vim.api.nvim_list_wins())
          :filter(function(w)
            return vim.api.nvim_win_get_config(w).relative == ""
          end)
          :totable()
        if #normal_wins ~= 1 then
          return
        end
        -- Buffer should be empty
        if vim.api.nvim_buf_line_count(0) > 1 or #(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or "") > 0 then
          return
        end
        M.open()
      end,
    })
  end
end

return M
