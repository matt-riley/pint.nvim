# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**pint.nvim** is a Neovim plugin providing focused UI components: a startup dashboard, notification system with history, status column layout, indent guides with textobjects, and LSP reference highlighting. Each module is independently togglable via `pint.setup()`.

## Architecture

The plugin is structured as independent modules under `lua/pint/`:

- **init.lua**: Plugin entry point. Defines `pint.setup(opts)` which merges config, initializes modules, and calls each module's `setup()` function. Some modules define a `restore()` function to clean up when disabled.
- **dashboard.lua**: Startup screen with ASCII header, keyed actions, recent files list, and custom sections. Uses a segment-based rendering system for flexible highlighting.
- **notifier.lua**: Replaces `vim.notify()` with floating-window notifications that stack, support ID-based replacement, and maintain a history.
- **statuscolumn.lua**: Configures the statuscolumn layout (signs, line numbers, fold/git indicators).
- **indent.lua**: Static indent guides with current-scope highlighting, `ii`/`ai` textobjects, and `[i`/`]i` jump motions.
- **words.lua**: LSP `documentHighlight` handler that highlights the symbol under the cursor and provides jump functions.

**plugin/pint.lua** auto-loads and registers the `:Pint` user command (dispatches to dashboard, history, words-enable, words-disable).

### Module API Pattern

Each module follows a consistent pattern:
- Exports a `config` table (deep-merged from defaults in `init.lua`)
- Exports a `setup(opts)` function that merges config and initializes the module
- May export a `restore()` function to revert changes when the module is disabled
- Uses a private namespace for state and helper functions

## Development

### Prerequisites & Setup

Tools are managed via [mise](https://mise.jdx.dev/):

```bash
mise install        # installs Neovim (nightly) and stylua
mise run install    # clones mini.nvim v0.17.0 to .ci/ and installs luacheck
```

Or use `make` directly if you already have Neovim nightly, stylua, and luacheck on PATH.

### Common Commands

```bash
mise run test       # run tests with mini.test
mise run lint       # lint with luacheck
mise run fmt        # check formatting (stylua --check)
make format         # auto-format with stylua (local-only)
mise run docs       # regenerate doc/pint.txt from Lua annotations
mise run commits    # validate commit message formatting
```

### Testing

Tests use [mini.test](https://github.com/echasnovski/mini.nvim) and live in `tests/test_pint.lua`. The test suite requires mini.nvim cloned to `.ci/mini.nvim`:

```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run({})" -c "qa"
```

`minimal_init.lua` sets up a minimal Neovim environment with pint's plugin/ directory loaded.

### Commits & Versioning

Commits must follow [Conventional Commits](https://www.conventionalcommits.org/) (e.g., `feat(dashboard): add section icons`, `fix(notifier): dedupe history`). Scopes are the module names: `dashboard`, `notifier`, `statuscolumn`, `indent`, `words`, plus `docs`, `ci`, `chore` for repo-level changes. The CI enforces this with `scripts/lint-commits.sh`.

Versioning is managed by [release-please](https://github.com/googleapis/release-please), which reads the VERSION file and updates CHANGELOG.md.

### Documentation

Help documentation is generated from Lua annotations in the module files. Each module should include:
- A top-level doc comment (`---`) describing the module
- `@tag` annotations (e.g., `@tag pint-dashboard`)
- Type annotations for classes (e.g., `@class pint.dashboard.Config`)
- Function doc comments with `@param`, `@return`, `@private` as needed

Generation:
```bash
mise run docs   # regenerates doc/pint.txt and runs helptags
```

The VERSION file is injected into the generated doc during build; the doc command handles this automatically.

## Code Style

- **Lua annotations**: Use [LuaCAT](https://github.com/LuaCAT/LuaCAT) annotations for type hints and documentation (required for mini.doc generation).
- **Formatting**: stylua with default settings (enforced in CI).
- **Linting**: luacheck (run locally before commit).
- **Comments**: Minimal; write self-documenting code. One short line only if the WHY is non-obvious (a workaround, hidden constraint, subtle invariant).
- **Module state**: Use `local` tables (not globals) for state. Use private namespace tables for internal functions.

## Key Files

- `lua/pint/init.lua` — Plugin setup and module orchestration
- `plugin/pint.lua` — Command registration (auto-loaded by Neovim)
- `tests/test_pint.lua` — Test suite using mini.test
- `tests/minimal_init.lua` — Test environment setup
- `Makefile` — Local development shortcuts
- `.mise.toml` — Task definitions and tool versions
- `VERSION` — Canonical project version (read by release-please)
- `CHANGELOG.md` — Release notes (auto-updated by release-please)

## CI

GitHub Actions workflows (in `.github/workflows/`) use a shared [matt-riley-ci](https://github.com/matt-riley/matt-riley-ci) workflow. Local equivalents:
- `tests.yml` → `mise run test`
- `lint.yml` → `mise run lint`
- `format.yml` → `mise run fmt`
- `docs.yml` → `mise run docs`
- `commits.yml` → `mise run commits`
