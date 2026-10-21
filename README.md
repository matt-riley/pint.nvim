# pint.nvim

> A small measure of polished UI for Neovim: dashboard, notifications, statuscolumn, indent guides, smooth scrolling, and LSP reference words.

[![Tests](https://github.com/matt-riley/pint.nvim/actions/workflows/tests.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/tests.yml)
[![Lint](https://github.com/matt-riley/pint.nvim/actions/workflows/lint.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/lint.yml)
[![Format](https://github.com/matt-riley/pint.nvim/actions/workflows/format.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/format.yml)
[![Typecheck](https://github.com/matt-riley/pint.nvim/actions/workflows/typecheck.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/typecheck.yml)

Pint is a deliberately scoped, dependency-free replacement for the parts of larger UI suites its author actually uses. Each module is independent, reload-safe, and can be disabled without leaving mappings, timers, windows, handlers, or global options behind.

## Features

- **dashboard** — responsive startup screen with keyed actions, recent files, custom sections, empty/error states, and an optional footer
- **notifier** — polished `vim.notify` floats with stacking, replacement by ID, bounded history, dismissal controls, and subtle optional transitions
- **statuscolumn** — compact diagnostic/sign, number, and fold/Git layout with correct absolute, relative, and hybrid numbers
- **indent** — static guides with an active-scope highlight, `ii`/`ai` text objects, and `[i`/`]i` navigation
- **words** — encoding-safe LSP `documentHighlight` with stale-response protection and reference navigation
- **scroll** — smooth motion for half-page, page, and `zz`/`zt`/`zb` that finishes on the builtin view and cursor (on by default)

Pint targets the six features above. It is not trying to become a picker, terminal, Git client, file explorer, or general component framework. Vibes are not an architecture.

## Requirements

- Neovim 0.13/nightly

Optional integrations are detected only when already installed:

- `mini.icons`
- `nvim-web-devicons`

Neither is required.

## Installation

```lua
-- lazy.nvim
{
  "matt-riley/pint.nvim",
  opts = {},
}
```

Pint does not depend on Lazy and works with any package manager or native package loading.

## Configuration

```lua
require("pint").setup({
  style = {
    border = nil, -- 'winborder', then "rounded"
    icons = true,
    animation = {
      enabled = true,
      duration = 120,
      fps = 30,
    },
  },

  dashboard = {
    header = { "my ascii art" },
    keys = {
      { icon = " ", key = "f", desc = "Find File", action = "<leader>sf" },
    },
    recent = { enabled = true, cwd = true, limit = 8 },
    sections = {
      -- {
      --   title = "Sessions",
      --   icon = "S",
      --   items = function()
      --     return { { label = "Current project", action = ":SessionLoad" } }
      --   end,
      -- },
    },
    footer = function()
      -- Pint intentionally knows nothing about Lazy. Add manager-specific
      -- statistics here when useful.
      local ok, lazy = pcall(require, "lazy")
      if not ok then
        return nil
      end
      local stats = lazy.stats()
      return {
        { "⚡ ", hl = "PintDashboardFooter" },
        { string.format("%d/%d plugins · %.0fms", stats.loaded, stats.count, stats.startuptime), hl = "PintDashboardSpecial" },
      }
    end,
    autostart = true,
  },

  notifier = {
    timeout = 2000,
    top_down = false,
    max_history = 200, -- 0 means unlimited
    max_width = 0.4,
    max_height = 0.4,
  },

  statuscolumn = {
    sign_width = 2,
    right_width = 2,
    separator = " ",
    folds = {
      open = false,
      git_hl = false,
      precedence = "git", -- or "fold"
    },
  },

  indent = {
    char = "│",
    scope_char = "│",
    scope = true,
    textobject = true,
  },

  words = {
    debounce = 200,
    enabled = true,
    notify = false,
  },

  scroll = {
    duration = 200,
    easing = "ease-out-quad", -- "linear", "ease-out-quad", or function(t) -> number
    max_lines = 10000,
    override = false, -- set true to replace existing global scroll mappings
  },

  -- Any module can be disabled with `module = false`.
})
```

All Pint highlight groups link to standard Neovim groups by default. Colorschemes remain in control, and users can override any `Pint*` highlight normally.

### Words keymaps

```lua
vim.keymap.set("n", "]r", function()
  require("pint.words").jump(1)
end, { desc = "Next reference" })

vim.keymap.set("n", "[r", function()
  require("pint.words").jump(-1)
end, { desc = "Previous reference" })
```

### Scroll

Smooth scrolling is on when you call `require("pint").setup()` with no `scroll` options. Turn it off with `scroll = { enabled = false }`, `scroll = false` (skip the module entirely), or `:Pint scroll-disable`.

It maps normal-mode `<C-d>`, `<C-u>`, `<C-f>`, `<C-b>`, `zz`, `zt`, and `zb` when those keys do not already have a global mapping. Set `override = true` to replace an existing global mapping; Pint puts that mapping back when scrolling is disabled. Buffer-local mappings stay in place and keep priority. Mouse-wheel scrolling is unchanged. Counts and the `'scroll'` option behave like the builtin commands, and an animation that runs to the end lands on the same view and cursor.

A key pressed during the animation cancels it. That key acts on the in-between line, and Pint does not jump to the planned target. Jumps longer than 100 buffer lines interpolate the topline, then finish on the builtin view.

Animation is skipped while a macro is recording or playing, when another key is already queued, when the scroll key was produced by a different mapping, when the window changes mid-motion, and in buffers longer than `max_lines`.

## Commands

```vim
:Pint dashboard
:Pint history
:Pint dismiss
:Pint dismiss-all
:Pint words-enable
:Pint words-disable
:Pint scroll-enable
:Pint scroll-disable
:Pint scroll-toggle
:Pint restore
```

`:Pint restore` disables every Pint module and releases state Pint still owns. Calling `setup()` again is safe; Pint restores the previous configuration before applying the new one.

Section padding accepts either `{ bottom = 2, top = 1 }` or `{ 2, 1 }` in bottom/top order.

## Development

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) so `release-please` can version and generate the changelog.

CI uses [mise](https://mise.jdx.dev/) through the shared [matt-riley-ci](https://github.com/matt-riley/matt-riley-ci) workflows.

```bash
mise install
mise run install   # clones mini.nvim and installs luacheck on Linux
mise run test
mise run lint
mise run fmt
mise run docs
mise run commits
```

`make` targets also work when Neovim nightly, StyLua, Luacheck, and mini.nvim are available locally.

### Tests

```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" mise run test
```

The suite includes the original compatibility coverage plus focused lifecycle, Unicode, stale-request, rendering, and ownership regressions for each module.

### Formatting and linting

```bash
mise run fmt       # check only
make format        # write formatting changes
mise run lint
```

### Documentation

Help is generated from Lua annotations using `mini.doc`:

```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" mise run docs
```

Then use `:help pint` inside Neovim.

## Versioning

- Canonical project version is stored in [`VERSION`](VERSION).
- `release-please` updates `VERSION` and `CHANGELOG.md`.

## License

[MIT](LICENSE)
