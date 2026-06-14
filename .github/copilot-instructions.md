# Copilot CLI Instructions for pint.nvim

This file helps Copilot CLI sessions work effectively in pint.nvim.

## Project Summary

**pint.nvim** is a focused Neovim plugin providing UI components: a startup dashboard, notification system with history, statuscolumn layout, indent guides with textobjects, and LSP reference highlighting. Each module is independently configurable and togglable via `pint.setup()`.

## High-Level Architecture

The plugin is structured as **independent modules** under `lua/pint/`:

- **init.lua** — Plugin entry point. Merges config, calls each module's `setup()` function.
- **dashboard.lua** — Startup screen with ASCII header, keyed actions, recent files list, custom sections.
- **notifier.lua** — Replaces `vim.notify()` with stacking floats, ID-based replacement, history.
- **statuscolumn.lua** — Configures statuscolumn layout: signs, line numbers, fold/git indicators.
- **indent.lua** — Static indent guides with current-scope highlight, `ii`/`ai` textobjects, `[i`/`]i` jumps.
- **words.lua** — LSP `documentHighlight` handler for symbol under cursor with jump cycling.

**plugin/pint.lua** auto-loads and registers the `:Pint` user command (dashboard, history, words-enable, words-disable).

### Module Pattern

Each module exports:
- A `config` table (merged from defaults in init.lua)
- A `setup(opts)` function
- Optionally a `restore()` function to revert when disabled
- Private namespace for state and helpers

## Build, Test, Lint, and Documentation

All commands use `mise run` (or equivalent `make` targets if you have tools on PATH):

```bash
mise install              # One-time: fetch Neovim (nightly) and stylua
mise run install          # One-time: clone mini.nvim v0.17.0 to .ci/mini.nvim
mise run test             # Run mini.test suite
mise run lint             # Run luacheck over lua/, plugin/, tests/
mise run fmt              # Check formatting (CI check)
make format               # Auto-format locally with stylua
mise run docs             # Regenerate doc/pint.txt from Lua annotations
mise run commits          # Validate commit message formatting (Conventional Commits)
```

### Testing

Tests live in `tests/test_pint.lua` using [mini.test](https://github.com/echasnovski/mini.nvim). The environment is set up by `tests/minimal_init.lua`.

Run a single test by pattern if needed:
```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run({ select = 'test name pattern' })" -c "qa"
```

### Documentation Generation

Help text is generated from LuaCAT annotations in module files. When you add or change public APIs:

```bash
mise run docs
```

This regenerates `doc/pint.txt`, injects the VERSION file version string, and runs helptags.

## Code Style & Conventions

- **Lua annotations**: Use [LuaCAT](https://github.com/LuaCAT/LuaCAT) for public APIs.
  - Top-level doc comment (`---`) describing the module.
  - `@tag` annotations (e.g., `@tag pint-dashboard`).
  - Type annotations for classes (e.g., `@class pint.dashboard.Config`).
  - Function doc comments with `@param`, `@return`, `@private`.
- **Formatting**: stylua with default settings (enforced in CI via `mise run fmt`).
- **Linting**: luacheck (run locally before commit).
- **Comments**: Minimal. Write self-documenting code. Use comments only for non-obvious WHYs (workarounds, constraints, invariants).
- **Module state**: Use `local` tables (not globals). Private helpers in namespace tables.
- **Naming**: Align with modules and commands: `pint.dashboard`, `pint.notifier`, `:Pint history`, `:Pint words-enable`.

## Commit Message Guidelines

Commits must follow [Conventional Commits](https://www.conventionalcommits.org/). Scopes are module names: `dashboard`, `notifier`, `statuscolumn`, `indent`, `words`, plus `docs`, `ci`, `chore`.

Examples:
- `feat(dashboard): add section icons`
- `fix(notifier): dedupe history ids`
- `docs(words): clarify jump keymaps`
- `chore(deps): pin mini.nvim v0.17.0`

The CI enforces this via `scripts/lint-commits.sh`.

## Versioning & Releases

- Canonical version lives in `VERSION` file.
- [release-please](https://github.com/googleapis/release-please) auto-generates release PRs that update both `VERSION` and `CHANGELOG.md`.
- Conventional Commits drive changelog categorization.

## Key Files

- `lua/pint/init.lua` — Plugin entry and module orchestration
- `plugin/pint.lua` — `:Pint` command registration (auto-loaded)
- `tests/test_pint.lua` — mini.test suite
- `tests/minimal_init.lua` — Test environment setup
- `.mise.toml` — Task definitions and tool versions
- `Makefile` — Local development (use if you have tools on PATH)
- `VERSION` — Canonical version string (read by release-please)
- `CHANGELOG.md` — Release notes (auto-updated)

## CI Workflow

GitHub Actions workflows (in `.github/workflows/`) delegate to shared [matt-riley-ci](https://github.com/matt-riley/matt-riley-ci) universal workflow:

- `tests.yml` → `mise run test`
- `lint.yml` → `mise run lint`
- `format.yml` → `mise run fmt`
- `docs.yml` → `mise run docs`
- `commits.yml` → `mise run commits`

## Target Environment

- **Neovim 0.13 (nightly)** — Only target nightly; verify headless test runs and that `doc/pint.txt` reflects your code changes.

## Additional Context

For more detailed architecture and code patterns, see [CLAUDE.md](../CLAUDE.md) and [AGENTS.md](../AGENTS.md).
