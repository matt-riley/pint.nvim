-- plugin/pint.lua
-- Auto-loaded by Neovim. Registers the :Pint user command.

vim.api.nvim_create_user_command("Pint", function(cmd)
  local sub = cmd.fargs[1] or "dashboard"
  if sub == "dashboard" then
    require("pint.dashboard").open()
  elseif sub == "history" then
    require("pint.notifier").show_history()
  else
    vim.notify(("Pint: unknown subcommand %q"):format(sub), vim.log.levels.ERROR)
  end
end, {
  desc = "pint.nvim",
  nargs = "?",
  complete = function()
    return { "dashboard", "history" }
  end,
})
