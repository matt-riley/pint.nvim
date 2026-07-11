local M = {}

function M.reset()
  local ok, pint = pcall(require, "pint")
  if ok and type(pint.restore) == "function" then
    pint.restore()
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  vim.cmd.enew({ bang = true })
  vim.o.statuscolumn = ""
end

return M
