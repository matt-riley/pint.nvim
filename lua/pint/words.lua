-- lua/pint/words.lua
-- Highlight LSP references for the symbol under the cursor and jump between them.
local M = {}

--- Words configuration.
---@class pint.words.Config
---@field debounce? integer Milliseconds of cursor rest before highlighting. Default: 200
---@field enabled? boolean Start enabled. Default: true

---@private
local defaults = {
  debounce = 200,
  enabled = true,
}

M.config = vim.deepcopy(defaults)

local enabled = true
local timer ---@type uv.uv_timer_t|nil

---@private
local function supported(buf)
  return #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentHighlight" }) > 0
end

---@private
local function clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.lsp.buf.clear_references(buf)
  end
end

---@private
local function highlight()
  local buf = vim.api.nvim_get_current_buf()
  if not (enabled and supported(buf)) then
    return
  end
  vim.lsp.buf.document_highlight()
end

--- Is the words module currently enabled?
---@return boolean
function M.is_enabled()
  return enabled
end

--- Enable reference highlighting.
function M.enable()
  enabled = true
  highlight()
end

--- Disable reference highlighting and clear existing highlights.
function M.disable()
  enabled = false
  clear(vim.api.nvim_get_current_buf())
end

---@private
---Collect reference ranges in the current buffer, sorted by position.
---@param cb fun(ranges: {line: integer, character: integer}[])
local function references(cb)
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentHighlight" })[1]
  if not client then
    return cb({})
  end
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  client:request("textDocument/documentHighlight", params, function(err, result)
    if err or not result then
      return cb({})
    end
    local starts = {}
    for _, ref in ipairs(result) do
      table.insert(starts, ref.range.start)
    end
    table.sort(starts, function(a, b)
      if a.line == b.line then
        return a.character < b.character
      end
      return a.line < b.line
    end)
    cb(starts)
  end, buf)
end

--- Jump to a reference of the symbol under the cursor.
---@param count integer 1 for next, -1 for previous
---@param cycle? boolean Wrap around at the ends. Default: true
function M.jump(count, cycle)
  if cycle == nil then
    cycle = true
  end
  references(function(starts)
    if #starts == 0 then
      return
    end
    local cur = vim.api.nvim_win_get_cursor(0)
    local line, col = cur[1] - 1, cur[2]
    local current = 1
    for i, pos in ipairs(starts) do
      if pos.line < line or (pos.line == line and pos.character <= col) then
        current = i
      end
    end
    local target = current + count
    if cycle then
      target = ((target - 1) % #starts) + 1
    elseif target < 1 or target > #starts then
      return
    end
    local pos = starts[target]
    vim.api.nvim_win_set_cursor(0, { pos.line + 1, pos.character })
  end)
end

--- Set up autocmds for automatic reference highlighting.
---@param opts? pint.words.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  enabled = M.config.enabled

  local group = vim.api.nvim_create_augroup("PintWords", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = function(ev)
      clear(ev.buf)
      if not enabled then
        return
      end
      timer = timer or vim.uv.new_timer()
      timer:start(M.config.debounce, 0, vim.schedule_wrap(highlight))
    end,
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(ev)
      clear(ev.buf)
    end,
  })
end

return M
