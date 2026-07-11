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
---@field notify? boolean Notify when a requested jump has no target. Default: false

local defaults = {
  debounce = 200,
  enabled = true,
  notify = false,
}

M.config = vim.deepcopy(defaults)

---@class pint.words.Reference
---@field line integer Zero-based line
---@field character integer Zero-based byte column

---@class pint.words.State
---@field generation integer
---@field refs pint.words.Reference[]
---@field timer? uv.uv_timer_t
---@field request_id? integer
---@field client_id? integer

local enabled = true
---@type table<integer, pint.words.State>
local states = {}

---@param buf integer
---@return pint.words.State
local function state_for(buf)
  if not states[buf] then
    states[buf] = { generation = 0, refs = {} }
  end
  return states[buf]
end

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

---@param state pint.words.State
local function cancel_request(state)
  if not state.request_id or not state.client_id then
    return
  end
  local client = vim.lsp.get_client_by_id(state.client_id)
  if client and type(client.cancel_request) == "function" then
    pcall(client.cancel_request, client, state.request_id)
  end
  state.request_id = nil
  state.client_id = nil
end

---@param buf integer
local function clear_references(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.lsp.util.buf_clear_references, buf)
  end
end

---@param buf integer
---@param remove boolean
local function invalidate(buf, remove)
  local state = states[buf]
  if state then
    state.generation = state.generation + 1
    stop_timer(state.timer)
    state.timer = nil
    cancel_request(state)
    state.refs = {}
  end
  clear_references(buf)
  if remove then
    states[buf] = nil
  end
end

---@param line string
---@param encoding string
---@param character integer
---@return integer
local function byte_column(line, encoding, character)
  local ok, value = pcall(vim.str_byteindex, line, encoding, character, false)
  if ok then
    return value
  end
  if encoding == "utf-8" then
    return math.min(character, #line)
  end
  local fallback_ok, fallback = pcall(vim.str_byteindex, line, character)
  return fallback_ok and fallback or math.min(character, #line)
end

---@param buf integer
---@param result table[]?
---@param encoding string
---@return pint.words.Reference[]
local function references_from_result(buf, result, encoding)
  local refs = {}
  for _, reference in ipairs(result or {}) do
    local start = reference.range and reference.range.start
    if start then
      local line = vim.api.nvim_buf_get_lines(buf, start.line, start.line + 1, false)[1] or ""
      refs[#refs + 1] = {
        line = start.line,
        character = byte_column(line, encoding, start.character),
      }
    end
  end
  table.sort(refs, function(left, right)
    if left.line == right.line then
      return left.character < right.character
    end
    return left.line < right.line
  end)
  return refs
end

---@param refs pint.words.Reference[]
---@param line integer
---@param col integer
---@param count integer
---@param cycle boolean
---@return pint.words.Reference?
local function target(refs, line, col, count, cycle)
  if #refs == 0 or count == 0 then
    return nil
  end

  local index
  if count > 0 then
    for current, reference in ipairs(refs) do
      if reference.line > line or (reference.line == line and reference.character > col) then
        index = current
        break
      end
    end
    index = (index or (#refs + 1)) + count - 1
  else
    for current = #refs, 1, -1 do
      local reference = refs[current]
      if reference.line < line or (reference.line == line and reference.character < col) then
        index = current
        break
      end
    end
    index = (index or 0) + count + 1
  end

  if cycle then
    index = ((index - 1) % #refs) + 1
  elseif index < 1 or index > #refs then
    return nil
  end
  return refs[index]
end

---@param buf integer
---@return table?
local function highlight_client(buf)
  return vim.lsp.get_clients({
    bufnr = buf,
    method = "textDocument/documentHighlight",
  })[1]
end

---@param buf integer
---@param win integer
---@param callback? fun(refs:pint.words.Reference[])
local function refresh(buf, win, callback)
  if not enabled or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    if callback then
      callback({})
    end
    return
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    if callback then
      callback({})
    end
    return
  end

  local state = state_for(buf)
  state.generation = state.generation + 1
  local generation = state.generation
  stop_timer(state.timer)
  state.timer = nil
  cancel_request(state)

  local client = highlight_client(buf)
  if not client then
    invalidate(buf, false)
    if callback then
      callback({})
    end
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local encoding = client.offset_encoding or "utf-16"
  local params = vim.lsp.util.make_position_params(win, encoding)

  local success, request_id = client:request("textDocument/documentHighlight", params, function(err, result)
    vim.schedule(function()
      local current = states[buf]
      if not current or current.generation ~= generation or not enabled then
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= changedtick then
        return
      end
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
        return
      end
      if not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor) then
        return
      end

      current.request_id = nil
      current.client_id = nil
      if err or not result then
        current.refs = {}
        clear_references(buf)
        if callback then
          callback({})
        end
        return
      end

      pcall(vim.lsp.util.buf_highlight_references, buf, result, encoding)
      current.refs = references_from_result(buf, result, encoding)
      if callback then
        callback(current.refs)
      end
    end)
  end, buf)

  if success then
    state.request_id = request_id
    state.client_id = client.id
  elseif callback then
    callback({})
  end
end

---@param buf integer
---@param win integer
local function schedule(buf, win)
  if not enabled or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local state = state_for(buf)
  state.generation = state.generation + 1
  stop_timer(state.timer)
  cancel_request(state)
  state.refs = {}
  clear_references(buf)

  state.timer = vim.uv.new_timer()
  state.timer:start(M.config.debounce, 0, function()
    vim.schedule(function()
      local current = states[buf]
      if not current then
        return
      end
      stop_timer(current.timer)
      current.timer = nil
      refresh(buf, win)
    end)
  end)
end

--- Is the words module currently enabled?
---@return boolean
function M.is_enabled()
  return enabled
end

--- Enable reference highlighting.
function M.enable()
  enabled = true
  local win = vim.api.nvim_get_current_win()
  schedule(vim.api.nvim_win_get_buf(win), win)
end

--- Disable reference highlighting and clear tracked references.
function M.disable()
  enabled = false
  local buffers = vim.tbl_keys(states)
  for _, buf in ipairs(buffers) do
    invalidate(buf, true)
  end
end

---@param refs pint.words.Reference[]
---@param count integer
---@param cycle boolean
---@param win integer
---@return boolean
local function jump_to(refs, count, cycle, win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local reference = target(refs, cursor[1] - 1, cursor[2], count, cycle)
  if not reference then
    return false
  end
  vim.api.nvim_win_set_cursor(win, { reference.line + 1, reference.character })
  return true
end

--- Jump to a reference of the symbol under the cursor.
---@param count integer 1 for next, -1 for previous
---@param cycle? boolean Wrap around at the ends. Default: true
function M.jump(count, cycle)
  if cycle == nil then
    cycle = true
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local state = states[buf]
  if state and #state.refs > 0 then
    if not jump_to(state.refs, count, cycle, win) and M.config.notify then
      vim.notify("Pint: no further references", vim.log.levels.INFO)
    end
    return
  end

  refresh(buf, win, function(refs)
    if not jump_to(refs, count, cycle, win) and M.config.notify then
      vim.notify("Pint: no references", vim.log.levels.INFO)
    end
  end)
end

--- Disable automatic highlighting and release all tracked state.
function M.restore()
  enabled = false
  pcall(vim.api.nvim_del_augroup_by_name, "PintWords")
  local buffers = vim.tbl_keys(states)
  for _, buf in ipairs(buffers) do
    invalidate(buf, true)
  end
  states = {}
end

--- Set up autocmds for automatic reference highlighting.
---@param opts? pint.words.Config
function M.setup(opts)
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  enabled = M.config.enabled

  local group = vim.api.nvim_create_augroup("PintWords", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = function(event)
      local buf = event.buf ~= 0 and event.buf or vim.api.nvim_get_current_buf()
      local win = vim.fn.bufwinid(buf)
      if win > 0 then
        schedule(buf, win)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "LspDetach", "BufWipeout" }, {
    group = group,
    callback = function(event)
      invalidate(event.buf, true)
    end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(event)
      if enabled then
        local win = vim.fn.bufwinid(event.buf)
        if win > 0 then
          schedule(event.buf, win)
        end
      end
    end,
  })
end

M._test = {
  byte_column = byte_column,
  target = target,
  refresh = refresh,
  schedule = schedule,
  state_count = function()
    return vim.tbl_count(states)
  end,
}

return M
