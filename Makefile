.PHONY: test lint format format-check docs

MINI_PATH ?= $(shell nvim --headless -c 'for _,p in ipairs(vim.api.nvim_list_runtime_paths()) do if p:match("mini%.nvim") then print(p) vim.cmd("q") end end' -c 'q' 2>&1 | head -1)

test:
	@echo "Running tests..."
	nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run({})" -c "qa"

lint:
	luacheck lua/ plugin/ tests/

format:
	stylua lua/ plugin/ tests/

format-check:
	stylua --check lua/ plugin/ tests/

docs:
	@mkdir -p doc
	nvim --headless -u NONE \
		-c 'lua vim.opt.runtimepath:prepend(vim.fn.getcwd())' \
		-c 'lua if vim.env.MINI_PATH and vim.env.MINI_PATH ~= "" then vim.opt.runtimepath:append(vim.env.MINI_PATH) end' \
		-c 'lua require("mini.doc").setup({})' \
		-c 'lua require("mini.doc").generate({ "lua/pint/init.lua" }, "doc/pint.txt")' \
		-c 'lua local p="doc/pint.txt"; local v=(vim.fn.readfile("VERSION")[1] or ""):gsub("%s+$$",""); local out={}; for _,ln in ipairs(vim.fn.readfile(p)) do if not ln:match("^Version:%s") then out[#out+1]=ln end end; table.insert(out, 4, "Version: " .. v); table.insert(out, 5, ""); vim.fn.writefile(out, p)' \
		-c 'qa'
	@rm -f doc/tags
