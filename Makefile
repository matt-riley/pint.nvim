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
	nvim --headless -u NONE -l scripts/docs.lua
