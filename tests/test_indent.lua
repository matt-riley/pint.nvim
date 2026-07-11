local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })

local indent = require("pint.indent")

T["restore removes Pint mappings"] = function()
  indent.setup()
  MiniTest.expect.equality(vim.fn.maparg("[i", "n") ~= "", true)

  indent.restore()

  MiniTest.expect.equality(vim.fn.maparg("[i", "n"), "")
  MiniTest.expect.equality(vim.fn.maparg("ii", "x"), "")
end

T["restore reinstates a mapping replaced by Pint"] = function()
  vim.keymap.set("n", "[i", "<cmd>let g:pint_original_map = 1<cr>", { desc = "original mapping" })
  indent.setup()
  indent.restore()

  local restored = vim.fn.maparg("[i", "n", false, true)
  MiniTest.expect.equality(restored.desc, "original mapping")
end

T["restore leaves a mapping installed after Pint alone"] = function()
  indent.setup()
  vim.keymap.set("n", "[i", "<cmd>let g:pint_later_map = 1<cr>", { desc = "later mapping" })
  indent.restore()

  local current = vim.fn.maparg("[i", "n", false, true)
  MiniTest.expect.equality(current.desc, "later mapping")
end

T["first_nonblank_byte handles tabs and multibyte text"] = function()
  MiniTest.expect.equality(indent._test.first_nonblank_byte("\t  λvalue"), 3)
end

T["jump lands on the first nonblank byte"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "if true then",
    "\t  print('hello')",
    "end",
  })
  vim.bo.shiftwidth = 2
  vim.bo.tabstop = 4
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  indent.jump(false)

  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[2], 3)
end

return T
