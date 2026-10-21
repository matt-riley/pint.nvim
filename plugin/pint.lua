-- plugin/pint.lua
-- Auto-loaded by Neovim. Registers the :Pint user command.

local subcommands = {
  "dashboard",
  "history",
  "dismiss",
  "dismiss-all",
  "restore",
  "words-enable",
  "words-disable",
  "scroll-enable",
  "scroll-disable",
  "scroll-toggle",
}

vim.api.nvim_create_user_command("Pint", function(cmd)
  local sub = cmd.fargs[1] or "dashboard"

  if sub == "dashboard" then
    require("pint.dashboard").open()
  elseif sub == "history" then
    require("pint.notifier").show_history()
  elseif sub == "dismiss" then
    require("pint.notifier").dismiss()
  elseif sub == "dismiss-all" then
    require("pint.notifier").dismiss_all()
  elseif sub == "restore" then
    require("pint").restore()
  elseif sub == "words-enable" then
    require("pint.words").enable()
  elseif sub == "words-disable" then
    require("pint.words").disable()
  elseif sub == "scroll-enable" then
    require("pint.scroll").enable()
  elseif sub == "scroll-disable" then
    require("pint.scroll").disable()
  elseif sub == "scroll-toggle" then
    require("pint.scroll").toggle()
  else
    vim.notify(("Pint: unknown subcommand %q"):format(sub), vim.log.levels.ERROR)
  end
end, {
  desc = "pint.nvim",
  nargs = "?",
  complete = function()
    return subcommands
  end,
})
