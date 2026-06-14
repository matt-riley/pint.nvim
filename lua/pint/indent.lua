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
---@field hl? string Guide highlight group. Default: "PintIndent"
---@field scope_hl? string Current-scope guide highlight. Default: "PintIndentScope"
---@field scope? boolean Highlight the current scope's guide. Default: true
---@field textobject? boolean Map ii/ai and [i/]i. Default: true
---@field exclude_filetypes? string[] Filetypes to skip

---@private
local defaults = {
  char = "│",
  hl = "PintIndent",
  scope_hl = "PintIndentScope",
  scope = true,
  textobject = true,
  exclude_filetypes = { "help", "qf", "minifiles", "pint_dashboard", "fzf", "lazy", "mason" },
}

M.config = vim.deepcopy(defaults)

local ns = vim.api.nvim_create_namespace("pint.indent")

---@private
---Effective indent of a line, looking through blanks to the next non-blank.
---@return integer
local function line_indent(buf, lnum, last)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
  if line ~= "" then
    return vim.fn.indent(lnum)
  end
  local next_nonblank = vim.fn.nextnonblank(lnum)
  local prev_nonblank = vim.fn.prevnonblank(lnum)
  if next_nonblank == 0 or prev_nonblank == 0 or next_nonblank > last then
    return 0
  end
  return math.min(vim.fn.indent(next_nonblank), vim.fn.indent(prev_nonblank))
end

---@private
---Scope around the cursor: lines whose indent >= the cursor line's level.
---@return integer top, integer bottom, integer indent
local function scope_range(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)[1]
  local last = vim.api.nvim_buf_line_count(buf)
  local indent = line_indent(buf, cursor, last)
  -- a block opener owns the deeper scope below it
  if cursor < last then
    local below = line_indent(buf, cursor + 1, last)
    if below > indent then
      indent = below
    end
  end
  if indent == 0 then
    return 0, 0, 0
  end
  local top, bottom = cursor, cursor
  while top > 1 and line_indent(buf, top - 1, last) >= indent do
    top = top - 1
  end
  while bottom < last and line_indent(buf, bottom + 1, last) >= indent do
    bottom = bottom + 1
  end
  return top, bottom, indent
end

---@private
---@type table<integer, {top: integer, bottom: integer, indent: integer}>
local scopes = {}

---@private
local function on_win(_, win, buf, _)
  if vim.tbl_contains(M.config.exclude_filetypes, vim.bo[buf].filetype) or vim.bo[buf].buftype ~= "" then
    return false
  end
  if M.config.scope and vim.api.nvim_get_current_win() == win then
    local top, bottom, indent = scope_range(win)
    scopes[win] = { top = top, bottom = bottom, indent = indent }
  end
end

---@private
local function on_line(_, win, buf, row)
  local lnum = row + 1
  local last = vim.api.nvim_buf_line_count(buf)
  local indent = line_indent(buf, lnum, last)
  if indent == 0 then
    return
  end
  local sw = vim.bo[buf].shiftwidth
  if sw == 0 then
    sw = vim.bo[buf].tabstop
  end
  local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
  local scope = scopes[win]
  for col = 0, indent - 1, sw do
    local hl = M.config.hl
    if scope and M.config.scope and col == scope.indent - sw and lnum >= scope.top and lnum <= scope.bottom then
      hl = M.config.scope_hl
    end
    if col >= leftcol then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = { { M.config.char, hl } },
        virt_text_pos = "overlay",
        virt_text_win_col = col - leftcol,
        hl_mode = "combine",
        ephemeral = true,
        priority = 1,
      })
    end
  end
end

--- Select or operate on the current indent scope.
---@param outer boolean Include the line above (and trailing line for `ai`)
---@private
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
---@private
function M.jump(bottom)
  local top, bot = scope_range(vim.api.nvim_get_current_win())
  if top == 0 then
    return
  end
  local target = bottom and bot or top
  vim.api.nvim_win_set_cursor(0, { target, vim.fn.indent(target) })
end

--- Enable indent guides.
---@param opts? pint.indent.Config
---@private
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  vim.api.nvim_set_hl(0, "PintIndent", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "PintIndentScope", { link = "Special", default = true })

  vim.api.nvim_set_decoration_provider(ns, {
    on_win = on_win,
    on_line = on_line,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      scopes[tonumber(ev.match)] = nil
    end,
  })

  if M.config.textobject then
    for _, mode in ipairs({ "o", "x" }) do
      vim.keymap.set(mode, "ii", function()
        M.textobject(false)
      end, { desc = "inner scope" })
      vim.keymap.set(mode, "ai", function()
        M.textobject(true)
      end, { desc = "outer scope" })
    end
    vim.keymap.set("n", "[i", function()
      M.jump(false)
    end, { desc = "Prev scope edge" })
    vim.keymap.set("n", "]i", function()
      M.jump(true)
    end, { desc = "Next scope edge" })
  end
end

return M
