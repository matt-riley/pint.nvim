# Repository Guidelines

## Project Structure & Module Organization
This is a Neovim plugin. Source lives in `lua/pint/`, split by feature:
`init.lua` wires setup, while `dashboard.lua`, `notifier.lua`, `statuscolumn.lua`,
`indent.lua`, and `words.lua` each own one module. `plugin/pint.lua` registers
the `:Pint` command, and `ftplugin/pint_dashboard.lua` applies dashboard-specific
buffer settings. Tests are in `tests/`, generated help is in `doc/`, and helper
scripts live in `scripts/`.

## Build, Test, and Development Commands
Use `mise install` once to fetch pinned tools, then `mise run install` to clone
`mini.nvim` into `.ci/mini.nvim`.

```bash
mise run test    # run the mini.test suite
mise run lint    # luacheck over lua/, plugin/, tests/
mise run fmt     # check formatting with stylua
make format      # rewrite files with stylua
mise run docs    # regenerate doc/pint.txt and helptags
mise run commits # validate commit subjects
```

## Coding Style & Naming Conventions
Use Lua with `stylua` defaults and `luacheck` cleanliness. Prefer `local`
module state, small private helper functions, and LuaDoc annotations for any
API that feeds generated docs. Keep names aligned with modules and commands:
`pint.dashboard`, `pint.notifier`, `:Pint history`, `:Pint words-enable`.

## Testing Guidelines
Tests use `mini.test` in `tests/test_pint.lua`, with `tests/minimal_init.lua`
providing a minimal Neovim runtime. Add focused cases near the affected module
and name them as behavior statements, e.g. `open() renders header and recent
files section`. Run the suite with `MINI_PATH="$(pwd)/.ci/mini.nvim" mise run test`.

## Commit & Pull Request Guidelines
Commit messages must follow Conventional Commits because `scripts/lint-commits.sh`
enforces them. Use scopes that match the plugin area, such as `dashboard`,
`notifier`, `statuscolumn`, `indent`, `words`, `docs`, `ci`, or `chore`.
Pull requests should summarize behavior changes, mention test coverage, and note
any doc regeneration (`mise run docs`) when help text changes.

## Configuration Notes
This project targets Neovim 0.13 nightly. If you change runtime behavior, verify
it still works headlessly and that `doc/pint.txt` stays in sync with the Lua
annotations.
