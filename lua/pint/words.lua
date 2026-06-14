-- lua/pint/words.lua
-- Highlight LSP references for the symbol under the cursor and jump between them.
local M = {}

--- pint.words
---
--- LSP `documentHighlight` for the symbol under the cursor with reference jumping.
---
---@tag pint-words

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
local ns = vim.api.nvim_create_namespace("pint.words")

---@type table<integer, {line: integer, character: integer}[]>
local refs_cache = {}

local HL = {
  [1] = "LspReferenceText",
  [2] = "LspReferenceRead",
  [3] = "LspReferenceWrite",
}

---@private
local function supported(buf)
  return #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentHighlight" }) > 0
end

---@private
local function clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    refs_cache[buf] = nil
  end
end

---@private
---@return {line: integer, character: integer}[]
local function sorted_starts(result)
  local starts = {}
  for _, ref in ipairs(result or {}) do
    table.insert(starts, ref.range.start)
  end
  table.sort(starts, function(a, b)
    if a.line == b.line then
      return a.character < b.character
    end
    return a.line < b.line
  end)
  return starts
end

---@private
local function apply_highlights(buf, result)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not result then
    refs_cache[buf] = {}
    return
  end
  for _, ref in ipairs(result) do
    local range = ref.range
    local hl = HL[ref.kind] or HL[1]
    vim.hl.range(buf, ns, hl, range.start.line, range.start.character, range["end"].line, range["end"].character)
  end
  refs_cache[buf] = sorted_starts(result)
end

---@private
---@param cb? fun(refs: {line: integer, character: integer}[])
local function refresh(buf, cb)
  if not supported(buf) then
    clear(buf)
    if cb then
      cb({})
    end
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win <= 0 then
    win = vim.api.nvim_get_current_win()
  end
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentHighlight" })[1]
  if not client then
    clear(buf)
    if cb then
      cb({})
    end
    return
  end
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  client:request("textDocument/documentHighlight", params, function(err, result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if err then
        clear(buf)
        if cb then
          cb({})
        end
        return
      end
      apply_highlights(buf, result)
      if cb then
        cb(refs_cache[buf] or {})
      end
    end)
  end, buf)
end

---@private
local function highlight()
  local buf = vim.api.nvim_get_current_buf()
  if not (enabled and supported(buf)) then
    return
  end
  refresh(buf)
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
---@param starts {line: integer, character: integer}[]
---@param count integer
---@param cycle boolean
local function jump_to(starts, count, cycle)
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
end

--- Jump to a reference of the symbol under the cursor.
---@param count integer 1 for next, -1 for previous
---@param cycle? boolean Wrap around at the ends. Default: true
function M.jump(count, cycle)
  if cycle == nil then
    cycle = true
  end
  local buf = vim.api.nvim_get_current_buf()
  local cached = refs_cache[buf]
  if cached and #cached > 0 then
    jump_to(cached, count, cycle)
    return
  end
  refresh(buf, function(starts)
    jump_to(starts, count, cycle)
  end)
end

--- Set up autocmds for automatic reference highlighting.
---@param opts? pint.words.Config
---@private
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
