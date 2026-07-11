local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

local words = require("pint.words")

T["position conversion honours UTF-16 offsets"] = function()
  local byte = words._test.byte_column("a😀b", "utf-16", 3)
  MiniTest.expect.equality(byte, 5)
end

T["next jump before the first reference selects the first reference"] = function()
  local refs = {
    { line = 1, character = 2 },
    { line = 3, character = 4 },
  }
  MiniTest.expect.equality(words._test.target(refs, 0, 0, 1, false), refs[1])
end

T["previous jump after the final reference selects the final reference"] = function()
  local refs = {
    { line = 1, character = 2 },
    { line = 3, character = 4 },
  }
  MiniTest.expect.equality(words._test.target(refs, 9, 0, -1, false), refs[2])
end

T["cycling wraps at both ends"] = function()
  local refs = {
    { line = 1, character = 2 },
    { line = 3, character = 4 },
  }
  MiniTest.expect.equality(words._test.target(refs, 9, 0, 1, true), refs[1])
  MiniTest.expect.equality(words._test.target(refs, 0, 0, -1, true), refs[2])
end

T["a response is stale after the buffer changes"] = function()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha" })

  local handler
  local client = {
    id = 42,
    offset_encoding = "utf-16",
    request = function(_, _, _, callback)
      handler = callback
      return true, 7
    end,
    cancel_request = function() end,
  }

  local original_get_clients = vim.lsp.get_clients
  local original_get_client = vim.lsp.get_client_by_id
  local original_highlight = vim.lsp.util.buf_highlight_references
  vim.lsp.get_clients = function()
    return { client }
  end
  vim.lsp.get_client_by_id = function()
    return client
  end

  local highlighted = false
  vim.lsp.util.buf_highlight_references = function()
    highlighted = true
  end

  words.setup({ debounce = 0 })
  words._test.refresh(buf, win)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "changed" })
  handler(nil, {
    {
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 1 },
      },
    },
  })
  vim.wait(100)

  words.restore()
  vim.lsp.get_clients = original_get_clients
  vim.lsp.get_client_by_id = original_get_client
  vim.lsp.util.buf_highlight_references = original_highlight

  MiniTest.expect.equality(highlighted, false)
end

T["restore clears tracked state"] = function()
  words.setup({ debounce = 50 })
  words._test.schedule(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
  words.restore()
  MiniTest.expect.equality(words._test.state_count(), 0)
end

return T
