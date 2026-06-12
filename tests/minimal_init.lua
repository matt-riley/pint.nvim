vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function add_mini()
  local paths = {}
  if vim.env.MINI_PATH and vim.env.MINI_PATH ~= "" then
    table.insert(paths, vim.env.MINI_PATH)
  end

  local data_dir = vim.fn.stdpath("data")
  table.insert(paths, data_dir .. "/site/pack/packer/start/mini.nvim")
  table.insert(paths, data_dir .. "/site/pack/lazy/start/mini.nvim")

  for _, path in ipairs(paths) do
    if vim.loop.fs_stat(path) then
      vim.opt.runtimepath:append(path)
      return
    end
  end

  error("mini.nvim not found. Set MINI_PATH or install mini.nvim.")
end

add_mini()

local minitest = require("mini.test")
minitest.setup({
  execute = {
    reporter = minitest.gen_reporter.stdout(),
  },
})
