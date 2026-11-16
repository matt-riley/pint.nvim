-- Generate doc/pint.txt and doc/tags.
--
-- Every module exposes its API through a table named `M`, so mini.doc's default
-- tag inference produces the same tag for e.g. `require('pint.words').disable`
-- and `require('pint.scroll').disable`. `:helptags` then fails with
-- E154: Duplicate tag. Qualify inferred tags and signatures with the module path
-- so that each help tag names the module it belongs to.
local files = {
  "lua/pint/init.lua",
  "lua/pint/ui.lua",
  "lua/pint/dashboard.lua",
  "lua/pint/notifier.lua",
  "lua/pint/statuscolumn.lua",
  "lua/pint/indent.lua",
  "lua/pint/words.lua",
  "lua/pint/scroll.lua",
}

local output = "doc/pint.txt"

-- Module path used in help tags, keyed by file name where it differs.
local module_names = { init = "pint" }

if vim.env.MINI_PATH ~= nil and vim.env.MINI_PATH ~= "" then
  vim.opt.runtimepath:append(vim.env.MINI_PATH)
end

local MiniDoc = require("mini.doc")

local infer_header = MiniDoc.default_hooks.block_pre

MiniDoc.setup({
  hooks = {
    block_pre = function(block)
      infer_header(block)

      local module = (block.parent.info.path or ""):match("lua/pint/([%w_]+)%.lua$")
      if module == nil then
        return
      end
      module = module_names[module] or ("pint." .. module)

      for _, section in ipairs(block) do
        if type(section) == "table" and section.type == "section" then
          local id = section.info.id
          if id == "@tag" or id == "@signature" then
            section[1] = section[1]:gsub("^M%.", module .. ".")
          end
        end
      end
    end,
  },
})

MiniDoc.generate(files, output)

-- Keep the version in the generated file in sync with VERSION.
local version = (vim.fn.readfile("VERSION")[1] or ""):gsub("%s+$", "")
local lines = {}
for _, line in ipairs(vim.fn.readfile(output)) do
  if not line:match("^Version:%s") then
    lines[#lines + 1] = line
  end
end
table.insert(lines, 4, "Version: " .. version)
table.insert(lines, 5, "")
vim.fn.writefile(lines, output)

-- mini.doc already runs :helptags, do it again so that duplicate tags fail the
-- build instead of only printing a warning.
vim.cmd("helptags " .. vim.fn.fnamemodify(output, ":h"))
