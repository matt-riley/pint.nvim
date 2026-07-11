-- lua/pint/indent.lua
-- Static indent guides with current-scope highlight, plus indent-scope
-- textobjects (ii/ai) and edge jumps ([i/]i).
local M = {}

--- pint.indent
---
--- Static indent guides with current-scope highlight, textobjects, and jumps.
---
---@tag pint-indent

--- Indent configuration.
---@class pint.indent.Config
---@field char? string Guide character. Default: "│"
---@field scope_char? string Current-scope guide character. Default: same as `char`
---@field hl? string Guide highlight group. Default: "PintIndent"
---@field scope_hl? string Current-scope guide highlight. Default: "PintIndentScope"
---@field scope? boolean Highlight the current scope's guide. Default: true
---@field textobject? boolean Map ii/ai and [i/]i. Default: true
---@field exclude_filetypes? string[] Filetypes to skip

local defaults = {
  char = "│",
  scope_char = nil,
  hl = "PintIndent",
  scope_hl = "PintIndentScope",
  scope = true,
  textobject = true,
  exclude_filetypes = { "help", "qf", "minifiles", "pint_dashboard", "fzf", "lazy", "mason" },
}

M.config = vim.deepcopy(defaults)

local namespace = vim.api.nvim_create_namespace("pint.indent")
local enabled = false
---@type table<integer, {top:integer,bottom:integer,indent:integer}>
local scopes = {}
---@type table<integer, {lines:string[], indents:table<integer,integer>}>
local redraw = {}
---@type {mode:string,lhs:string,desc:string,previous:table?}[]
local installed_maps = {}

---@param buf integer
---@param line string
---@return integer
local function indent_width(buf, line)
  local whitespace = line:match("^[ \t]*") or ""
  if whitespace == "" then
    return 0
  end

  local tabstop = vim.bo[buf].tabstop
  local width = 0
  for index = 1, #whitespace do
    if whitespace:byte(index) == 9 then
      width = width + (tabstop - (width % tabstop))
    else
      width = width + 1
    end
  end
  return width
end

---@param line string
---@return integer
local function first_nonblank_byte(line)
  local start = line:find("%S")
  return start and (start - 1) or 0
end

---@param buf integer
---@return {lines:string[], indents:table<integer,integer>}
local function context_for(buf)
  if not redraw[buf] then
    redraw[buf] = {
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
      indents = {},
    }
  end
  return redraw[buf]
end

---@param ctx {lines:string[], indents:table<integer,integer>}
---@param from integer
---@param to integer
---@param step integer
---@return integer
local function nonblank(ctx, from, to, step)
  for lnum = from, to, step do
    local line = ctx.lines[lnum] or ""
    if line:find("%S") then
      return lnum
    end
  end
  return 0
end

---@param buf integer
---@param ctx {lines:string[], indents:table<integer,integer>}
---@param lnum integer
---@return integer
local function line_indent(buf, ctx, lnum)
  if ctx.indents[lnum] ~= nil then
    return ctx.indents[lnum]
  end

  local line = ctx.lines[lnum] or ""
  local value
  if line:find("%S") then
    value = indent_width(buf, line)
  else
    local last = #ctx.lines
    local next_line = nonblank(ctx, lnum, last, 1)
    local previous_line = nonblank(ctx, lnum, 1, -1)
    if next_line == 0 or previous_line == 0 then
      value = 0
    else
      value = math.min(indent_width(buf, ctx.lines[next_line] or ""), indent_width(buf, ctx.lines[previous_line] or ""))
    end
  end

  ctx.indents[lnum] = value
  return value
end

---@param win integer
---@param ctx? {lines:string[], indents:table<integer,integer>}
---@return integer top, integer bottom, integer indent
local function scope_range(win, ctx)
  if not vim.api.nvim_win_is_valid(win) then
    return 0, 0, 0
  end

  local buf = vim.api.nvim_win_get_buf(win)
  ctx = ctx or {
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    indents = {},
  }
  local cursor = vim.api.nvim_win_get_cursor(win)[1]
  local last = #ctx.lines
  local indent = line_indent(buf, ctx, cursor)

  if cursor < last then
    local below = line_indent(buf, ctx, cursor + 1)
    if below > indent then
      indent = below
    end
  end
  if indent == 0 then
    return 0, 0, 0
  end

  local top, bottom = cursor, cursor
  while top > 1 and line_indent(buf, ctx, top - 1) >= indent do
    top = top - 1
  end
  while bottom < last and line_indent(buf, ctx, bottom + 1) >= indent do
    bottom = bottom + 1
  end
  return top, bottom, indent
end

---@param buf integer
---@return boolean
local function excluded(buf)
  return vim.bo[buf].buftype ~= "" or vim.tbl_contains(M.config.exclude_filetypes, vim.bo[buf].filetype)
end

local function on_start()
  redraw = {}
  return enabled
end

local function on_win(_, win, buf)
  if not enabled or excluded(buf) then
    scopes[win] = nil
    return false
  end

  if M.config.scope and vim.api.nvim_get_current_win() == win then
    local top, bottom, indent = scope_range(win, context_for(buf))
    scopes[win] = { top = top, bottom = bottom, indent = indent }
  else
    scopes[win] = nil
  end
  return true
end

local function on_range(_, win, buf, first, last)
  if not enabled or excluded(buf) then
    return
  end

  local ctx = context_for(buf)
  local shiftwidth = vim.bo[buf].shiftwidth
  if shiftwidth == 0 then
    shiftwidth = vim.bo[buf].tabstop
  end
  if shiftwidth <= 0 then
    return
  end

  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local leftcol = view.leftcol or 0
  local scope = scopes[win]
  local final = math.min(last, #ctx.lines)

  for row = first, final - 1 do
    local lnum = row + 1
    local indent = line_indent(buf, ctx, lnum)
    if indent > 0 then
      for col = 0, indent - 1, shiftwidth do
        if col >= leftcol then
          local is_scope = scope
            and M.config.scope
            and col == scope.indent - shiftwidth
            and lnum >= scope.top
            and lnum <= scope.bottom
          local char = is_scope and (M.config.scope_char or M.config.char) or M.config.char
          local highlight = is_scope and M.config.scope_hl or M.config.hl
          vim.api.nvim_buf_set_extmark(buf, namespace, row, 0, {
            virt_text = { { char, highlight } },
            virt_text_pos = "overlay",
            virt_text_win_col = col - leftcol,
            hl_mode = "combine",
            ephemeral = true,
            priority = 1,
          })
        end
      end
    end
  end
end

---@param mode string
---@param lhs string
---@param rhs string|function
---@param desc string
local function install_map(mode, lhs, rhs, desc)
  local existing = vim.fn.maparg(lhs, mode, false, true)
  ---@type table?
  local previous = vim.tbl_isempty(existing) and nil or existing

  local installed_desc = "pint: " .. desc
  vim.keymap.set(mode, lhs, rhs, { desc = installed_desc })
  installed_maps[#installed_maps + 1] = {
    mode = mode,
    lhs = lhs,
    desc = installed_desc,
    previous = previous,
  }
end

---@param mapping table
local function restore_mapping(mapping)
  local current = vim.fn.maparg(mapping.lhs, mapping.mode, false, true)
  if vim.tbl_isempty(current) or current.desc ~= mapping.desc then
    return
  end

  pcall(vim.keymap.del, mapping.mode, mapping.lhs)
  local previous = mapping.previous
  if not previous then
    return
  end

  local opts = {
    desc = previous.desc ~= "" and previous.desc or nil,
    expr = previous.expr == 1,
    nowait = previous.nowait == 1,
    remap = previous.noremap ~= 1,
    script = previous.script == 1,
    silent = previous.silent == 1,
  }
  local rhs = previous.callback or previous.rhs or ""
  vim.keymap.set(mapping.mode, mapping.lhs, rhs, opts)
end

--- Select or operate on the current indent scope.
---@param outer boolean Include the line above and trailing line for `ai`
function M.textobject(outer)
  local top, bottom = scope_range(vim.api.nvim_get_current_win())
  if top == 0 then
    return
  end
  if outer then
    top = math.max(top - 1, 1)
    bottom = math.min(bottom + 1, vim.api.nvim_buf_line_count(0))
  end

  vim.cmd("normal! " .. (vim.fn.mode():match("[vV]") and "" or "V"))
  vim.api.nvim_win_set_cursor(0, { top, 0 })
  vim.cmd("normal! o")
  vim.api.nvim_win_set_cursor(0, { bottom, 0 })
  if vim.fn.mode() == "v" then
    vim.cmd("normal! V")
  end
end

--- Jump to the top or bottom edge of the current indent scope.
---@param bottom boolean Jump to the bottom edge instead of the top
function M.jump(bottom)
  local top, lower = scope_range(vim.api.nvim_get_current_win())
  if top == 0 then
    return
  end

  local target = bottom and lower or top
  local line = vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { target, first_nonblank_byte(line) })
end

--- Disable indent guides and restore mappings Pint still owns.
function M.restore()
  enabled = false
  scopes = {}
  redraw = {}
  pcall(vim.api.nvim_del_augroup_by_name, "PintIndent")

  for index = #installed_maps, 1, -1 do
    restore_mapping(installed_maps[index])
  end
  installed_maps = {}

  vim.api.nvim_set_decoration_provider(namespace, {
    on_start = function()
      return false
    end,
  })
  pcall(vim.cmd.redraw)
end

--- Enable indent guides.
---@param opts? pint.indent.Config
function M.setup(opts)
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  enabled = true

  vim.api.nvim_set_hl(0, "PintIndent", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "PintIndentScope", { link = "Special", default = true })

  vim.api.nvim_set_decoration_provider(namespace, {
    on_start = on_start,
    on_win = on_win,
    on_range = on_range,
  })

  local group = vim.api.nvim_create_augroup("PintIndent", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      scopes[tonumber(event.match)] = nil
    end,
  })

  if M.config.textobject then
    for _, mode in ipairs({ "o", "x" }) do
      install_map(mode, "ii", function()
        M.textobject(false)
      end, "inner scope")
      install_map(mode, "ai", function()
        M.textobject(true)
      end, "outer scope")
    end
    install_map("n", "[i", function()
      M.jump(false)
    end, "previous scope edge")
    install_map("n", "]i", function()
      M.jump(true)
    end, "next scope edge")
  end
end

M._test = {
  first_nonblank_byte = first_nonblank_byte,
  indent_width = indent_width,
}

return M
