# pint.nvim

> A small measure of UI for Neovim: dashboard, notifier, statuscolumn, indent guides, and LSP reference words.

[![Tests](https://github.com/matt-riley/pint.nvim/actions/workflows/tests.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/tests.yml)
[![Lint](https://github.com/matt-riley/pint.nvim/actions/workflows/lint.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/lint.yml)
[![Format](https://github.com/matt-riley/pint.nvim/actions/workflows/format.yml/badge.svg)](https://github.com/matt-riley/pint.nvim/actions/workflows/format.yml)

Deliberately scoped replacement for the parts of larger UI suites I actually use.
Each module is independent and can be disabled.

## Features

- **dashboard** — startup screen with header, keyed actions, recent files, and custom sections
- **notifier** — `vim.notify` handler with stacking floats, id-replacement, and history (`:Pint history`)
- **statuscolumn** — `[sign] [number] [fold/git sign]` layout with git signs split to the right
- **indent** — static indent guides with current-scope highlight, `ii`/`ai` textobjects, `[i`/`]i` jumps
- **words** — LSP `documentHighlight` for the symbol under the cursor with `jump(±1)` cycling

## Requirements

- Neovim 0.13 (nightly)

## Versioning

- Canonical project version is stored in [`VERSION`](VERSION).
- `release-please` updates both `VERSION` and `CHANGELOG.md`.

## Installation

```lua
-- lazy.nvim
{ "matt-riley/pint.nvim", opts = {} }
```

## Configuration

```lua
require("pint").setup({
  dashboard = {
    header = { "my ascii art" },
    keys = {
      { icon = " ", key = "f", desc = "Find File", action = "<leader>sf" },
    },
    recent = { enabled = true, cwd = true, limit = 8 },
    sections = {}, -- { title, icon, items = fun(): {label, action}[] }
    autostart = true,
  },
  notifier = {
    timeout = 2000,
    top_down = false,
    max_history = 200,
  },
  statuscolumn = {}, -- sets vim.o.statuscolumn
  indent = {
    char = "│",
    scope = true,
    textobject = true,
  },
  words = {
    debounce = 200,
  },
  -- any module can be disabled with `module = false`
})
```

### Words keymaps

```lua
vim.keymap.set("n", "]r", function() require("pint.words").jump(1) end, { desc = "Next reference" })
vim.keymap.set("n", "[r", function() require("pint.words").jump(-1) end, { desc = "Prev reference" })
```

## Usage

```vim
:Pint dashboard
:Pint history
:Pint words-enable
:Pint words-disable
```

Section padding accepts either `{ bottom = 2, top = 1 }` or `{ 2, 1 }` (bottom, top).

## Development

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) so `release-please` can version and changelog correctly. Examples: `feat(dashboard): add section icons`, `fix(notifier): dedupe history ids`, `chore(docs): regenerate vim help`.

CI uses [mise](https://mise.jdx.dev/) via the shared [matt-riley-ci](https://github.com/matt-riley/matt-riley-ci) universal workflow. Local setup:

```bash
mise install
mise run install   # clones mini.nvim and installs luacheck on Linux
mise run test
mise run lint
mise run fmt
mise run docs
mise run commits
```

`make` targets still work if you already have Neovim nightly, stylua, and luacheck on your `PATH`.

### Testing

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md):

```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" mise run test
```

### Linting

```bash
mise run lint
```

### Formatting

```bash
mise run fmt       # check only (CI uses this)
make format        # auto-format locally
```

### Documentation (`:help`)

Plugin help is generated from Lua annotations using [mini.doc](https://github.com/nvim-mini/mini.doc):

```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" mise run docs
```

## License

[MIT](LICENSE)
