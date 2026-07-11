# Pint Hardening and Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pint's five existing UI modules safely reloadable and visibly polished while remaining dependency-free and focused.

**Architecture:** Add one small internal `pint.ui` module for shared display primitives and styling. Give every feature module an idempotent `setup(opts)` / `restore()` lifecycle, keep state local to each module, and use native Neovim APIs for rendering, LSP positions, timers, and option restoration.

**Tech Stack:** Lua, Neovim nightly/0.13 APIs, MiniTest, StyLua, Luacheck, LuaLS, GitHub Actions via `matt-riley-ci`.

## Global Constraints

- Pint remains dependency-free and targets Neovim nightly.
- No picker, terminal, Git UI, file explorer, scrolling engine, or generic component system.
- All highlight groups link to standard editor groups with `default = true`; no hardcoded colours.
- Animation is limited to notifier float position/blend transitions and is globally disableable.
- Existing public behaviour remains compatible except documented correctness fixes and the dashboard footer becoming opt-in.
- Every task follows red/green/refactor and commits independently.

---

## File map

- Create `lua/pint/ui.lua`: private display helpers, style configuration, dimensions, borders, icon fallbacks, highlight links, display-width text handling.
- Modify `lua/pint/init.lua`: top-level style configuration, reverse-order restore, public `restore()`.
- Modify `plugin/pint.lua`: command dispatch and completion for restore/dismiss actions.
- Modify `lua/pint/dashboard.lua`: lifecycle, footer callback, responsive layout, safe sections and keymaps.
- Modify `lua/pint/notifier.lua`: ownership-safe restore, dimensions, dismiss APIs, subtle transitions.
- Modify `lua/pint/statuscolumn.lua`: lifecycle, number semantics, sign clipping and configurable layout.
- Modify `lua/pint/indent.lua`: lifecycle, mapping ownership, `on_range`, redraw cache and cursor columns.
- Modify `lua/pint/words.lua`: per-buffer request state, stale-response protection, encoding-safe jumps.
- Split `tests/test_pint.lua` into focused test files and keep `tests/minimal_init.lua` as the runner bootstrap.
- Create `.luarc.json` and `.github/workflows/typecheck.yml`.
- Modify `README.md`, `Makefile`, and generated `doc/pint.txt`.

---

### Task 1: Split tests and establish lifecycle regressions

**Files:**
- Create: `tests/helpers.lua`
- Create: `tests/test_setup.lua`
- Create: `tests/test_command.lua`
- Modify: `tests/test_pint.lua`

**Interfaces:**
- Produces `require("tests.helpers").reset()` to restore Pint modules, close test windows, clear test buffers, and reset global options between cases.
- Establishes the lifecycle contract later tasks must satisfy: `pint.restore()` and module `restore()` functions are idempotent.

- [ ] **Step 1: Create the shared reset helper**

```lua
local M = {}

function M.reset()
  local ok, pint = pcall(require, "pint")
  if ok and type(pint.restore) == "function" then
    pint.restore()
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.cmd.enew({ bang = true })
  vim.o.statuscolumn = ""
end

return M
```

- [ ] **Step 2: Write failing setup lifecycle tests**

```lua
local MiniTest = require("mini.test")
local T = MiniTest.new_set({ hooks = { pre_case = require("tests.helpers").reset } })
local pint = require("pint")

T["restore is idempotent"] = function()
  pint.setup({ dashboard = { autostart = false } })
  pint.restore()
  local ok = pcall(pint.restore)
  MiniTest.expect.equality(ok, true)
end

T["disabling modules restores owned state"] = function()
  local original_notify = vim.notify
  local original_statuscolumn = vim.o.statuscolumn
  pint.setup({ dashboard = false, notifier = {}, statuscolumn = {}, indent = false, words = false })
  pint.setup({ dashboard = false, notifier = false, statuscolumn = false, indent = false, words = false })
  MiniTest.expect.equality(vim.notify, original_notify)
  MiniTest.expect.equality(vim.o.statuscolumn, original_statuscolumn)
end

return T
```

- [ ] **Step 3: Write failing command tests**

```lua
local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["Pint restore calls the public restore API"] = function()
  local pint = require("pint")
  local called = false
  local original = pint.restore
  pint.restore = function() called = true end
  vim.cmd("Pint restore")
  pint.restore = original
  MiniTest.expect.equality(called, true)
end

return T
```

- [ ] **Step 4: Run tests and confirm lifecycle failures**

Run: `MINI_PATH="$(pwd)/.ci/mini.nvim" make test`

Expected: FAIL because `pint.restore()` and `:Pint restore` do not exist and disabled modules leave state behind.

- [ ] **Step 5: Remove the migrated cases from `tests/test_pint.lua` without changing dashboard/notifier behaviour tests**

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "test: define Pint lifecycle contract"
```

---

### Task 2: Add private shared UI and top-level lifecycle

**Files:**
- Create: `lua/pint/ui.lua`
- Modify: `lua/pint/init.lua`
- Modify: `plugin/pint.lua`
- Test: `tests/test_setup.lua`
- Test: `tests/test_command.lua`

**Interfaces:**
- Produces `pint.ui.setup(style)`, `pint.ui.border(value)`, `pint.ui.clamp_float(opts)`, `pint.ui.truncate(text, width)`, `pint.ui.icon(kind, fallback)`.
- Produces public `require("pint").restore()`.

- [ ] **Step 1: Add failing UI helper tests**

```lua
local ui = require("pint.ui")

T["clamp_float keeps a float inside the editor"] = function()
  local value = ui.clamp_float({ row = -5, col = 9999, width = 9999, height = 9999 })
  MiniTest.expect.equality(value.row >= 0, true)
  MiniTest.expect.equality(value.col >= 0, true)
  MiniTest.expect.equality(value.width <= vim.o.columns - 2, true)
  MiniTest.expect.equality(value.height <= vim.o.lines - 2, true)
end

T["truncate preserves display width"] = function()
  MiniTest.expect.equality(vim.api.nvim_strwidth(ui.truncate("hello界", 5)) <= 5, true)
end
```

- [ ] **Step 2: Run the focused test and confirm `pint.ui` is missing**

Run: `MINI_PATH="$(pwd)/.ci/mini.nvim" nvim --headless -u tests/minimal_init.lua -c 'lua MiniTest.run_file("tests/test_setup.lua")' -c qa`

Expected: FAIL with module `pint.ui` not found.

- [ ] **Step 3: Implement `lua/pint/ui.lua`**

```lua
local M = {}

local defaults = {
  border = nil,
  icons = true,
  animation = { enabled = true, duration = 120, fps = 30 },
}

M.config = vim.deepcopy(defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local links = {
    PintNormal = "NormalFloat",
    PintBorder = "FloatBorder",
    PintTitle = "FloatTitle",
    PintMuted = "Comment",
    PintAccent = "Special",
    PintError = "DiagnosticError",
    PintWarn = "DiagnosticWarn",
    PintInfo = "DiagnosticInfo",
    PintHint = "DiagnosticHint",
  }
  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

function M.border(value)
  local border = value or M.config.border or vim.o.winborder
  return border == nil or border == "" and "rounded" or border
end

function M.clamp_float(opts)
  local max_width = math.max(vim.o.columns - 2, 1)
  local max_height = math.max(vim.o.lines - 2, 1)
  local width = math.min(math.max(opts.width or 1, 1), max_width)
  local height = math.min(math.max(opts.height or 1, 1), max_height)
  return vim.tbl_extend("force", opts, {
    width = width,
    height = height,
    row = math.min(math.max(opts.row or 0, 0), math.max(vim.o.lines - height - 2, 0)),
    col = math.min(math.max(opts.col or 0, 0), math.max(vim.o.columns - width - 2, 0)),
  })
end
```

Implement `truncate()` by iterating Unicode characters and measuring `nvim_strwidth`; implement `icon()` with configured fallbacks only.

- [ ] **Step 4: Implement reverse-order restore in `pint/init.lua`**

```lua
local modules = { "notifier", "statuscolumn", "indent", "words", "dashboard" }

function M.restore()
  for i = #modules, 1, -1 do
    local ok, mod = pcall(require, "pint." .. modules[i])
    if ok and type(mod.restore) == "function" then
      mod.restore()
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  require("pint.ui").setup(M.config.style)
  for _, name in ipairs(modules) do
    if M.config[name] ~= false then
      require("pint." .. name).setup(M.config[name])
    end
  end
end
```

- [ ] **Step 5: Extend `:Pint` dispatch**

Add `restore`, `dismiss`, and `dismiss-all`, delegating to `pint.restore()` and notifier APIs. Keep unknown-command errors concise.

- [ ] **Step 6: Run focused and full tests**

Run: `MINI_PATH="$(pwd)/.ci/mini.nvim" make test`

Expected: lifecycle and command tests still fail only for module-specific restore functions not yet implemented; UI helper tests pass.

- [ ] **Step 7: Commit**

```bash
git add lua/pint/ui.lua lua/pint/init.lua plugin/pint.lua tests/
git commit -m "feat: add shared Pint lifecycle and styling"
```

---

### Task 3: Harden and polish notifier

**Files:**
- Modify: `lua/pint/notifier.lua`
- Create: `tests/test_notifier.lua`

**Interfaces:**
- Produces `pint.notifier.restore()`, `dismiss(id?)`, `dismiss_all()`.
- Consumes `pint.ui.border()`, `clamp_float()`, style animation options and shared highlights.

- [ ] **Step 1: Write failing notifier lifecycle and dimension tests**

Cover:

```lua
T["restore only replaces vim.notify while Pint owns it"] = function()
  local original = vim.notify
  notifier.setup({ timeout = 0 })
  local replacement = function() end
  vim.notify = replacement
  notifier.restore()
  MiniTest.expect.equality(vim.notify, replacement)
  vim.notify = original
end

T["dismiss_all closes active notifications"] = function()
  notifier.setup({ timeout = 0 })
  notifier.notify("one")
  notifier.notify("two")
  notifier.dismiss_all()
  MiniTest.expect.equality(notifier.active_count(), 0)
end
```

Also test tiny `columns`/`lines`, ID replacement, `max_history`, fast-event deferral, and animation cancellation.

- [ ] **Step 2: Run focused tests and confirm missing APIs / layout failures**

Run: `MINI_PATH="$(pwd)/.ci/mini.nvim" nvim --headless -u tests/minimal_init.lua -c 'lua MiniTest.run_file("tests/test_notifier.lua")' -c qa`

- [ ] **Step 3: Refactor notifier state and ownership**

Use one `notify_wrapper` closure, retain `original_notify`, and restore it only when `vim.notify == notify_wrapper`. Close timers before buffers/windows, remove augroups, and clear active state.

- [ ] **Step 4: Add bounded rendering and polished highlights**

Use `ui.clamp_float()` for all floats. Wrap message text to the chosen width before setting buffer lines. Apply severity-specific title/border highlights through `PintInfo`, `PintWarn`, `PintError`, and `PintHint` links.

- [ ] **Step 5: Add restrained animation**

Implement an internal transition that interpolates `row`, `col`, and `winblend` on a `vim.uv` timer using `style.animation.duration` and `fps`. Every item owns at most one animation timer; replacement, resize, dismiss, and restore stop it. When animation is disabled, settle immediately.

- [ ] **Step 6: Implement dismiss APIs and history polish**

`dismiss(nil)` removes the newest active item; `dismiss(id)` removes the matching item; `dismiss_all()` removes all. History uses a bounded centred float, severity icons, timestamp/title spacing, and `q`/`<Esc>` close maps.

- [ ] **Step 7: Run notifier tests and full suite**

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lua/pint/notifier.lua tests/test_notifier.lua tests/test_pint.lua
git commit -m "feat(notifier): harden lifecycle and polish floats"
```

---

### Task 4: Harden and polish statuscolumn

**Files:**
- Modify: `lua/pint/statuscolumn.lua`
- Create: `tests/test_statuscolumn.lua`

**Interfaces:**
- Produces `pint.statuscolumn.restore()` and pure helpers exported under `M._test` for number/sign formatting tests.

- [ ] **Step 1: Write failing tests**

Test restoration, invalid `vim.g.statusline_winid`, wide signs (`"界界"` in a two-cell slot), absolute/relative/hybrid numbering, wrapped rows (`vim.v.virtnum ~= 0`), and explicit fold/Git precedence.

- [ ] **Step 2: Run focused tests and confirm current failures**

- [ ] **Step 3: Implement lifecycle ownership**

Store `previous_statuscolumn`, an `expression` constant, and `active`. `restore()` clears caches/augroup/provider activity and restores the prior option only when the global value still equals Pint's expression.

- [ ] **Step 4: Implement safe display-width clipping**

```lua
local function fit(text, width)
  local out = ""
  for i = 0, vim.fn.strchars(text) - 1 do
    local candidate = out .. vim.fn.strcharpart(text, i, 1)
    if vim.api.nvim_strwidth(candidate) > width then break end
    out = candidate
  end
  return out .. string.rep(" ", math.max(width - vim.api.nvim_strwidth(out), 0))
end
```

- [ ] **Step 5: Implement correct number semantics**

Use `vim.v.lnum`, `vim.v.relnum`, `vim.v.virtnum`, and window `number`/`relativenumber` options. Hybrid mode shows absolute number on the cursor line and relative numbers elsewhere. Wrapped/virtual rows render blank number and sign slots.

- [ ] **Step 6: Add configurable slot widths/separators**

Extend config with `sign_width`, `right_width`, and `separator`, defaulting to the current compact shape. Keep one sign-cache enumeration per redraw.

- [ ] **Step 7: Run tests and commit**

```bash
git add lua/pint/statuscolumn.lua tests/test_statuscolumn.lua tests/test_pint.lua
git commit -m "fix(statuscolumn): restore state and render safely"
```

---

### Task 5: Harden and polish indent guides

**Files:**
- Modify: `lua/pint/indent.lua`
- Create: `tests/test_indent.lua`

**Interfaces:**
- Produces `pint.indent.restore()` and private redraw cache helpers.

- [ ] **Step 1: Write failing tests**

Test enable/disable cycles, restoration of replaced mappings, split-window tab indentation, horizontal scrolling, blank-line scope ranges, and jumps landing on the first nonblank byte.

- [ ] **Step 2: Run focused tests and confirm provider/maps remain active**

- [ ] **Step 3: Track and restore mappings**

Before installing a mapping, save `vim.fn.maparg(lhs, mode, false, true)`. On restore, delete Pint's mapping and recreate the saved mapping with `vim.keymap.set()`/`nvim_set_keymap()` according to its callback or rhs.

- [ ] **Step 4: Replace `on_line` with `on_range`**

Use `on_start` to clear redraw caches, `on_win` to record window scope and viewport, and `on_range(_, win, buf, first, last)` to fetch the line range once and render ephemeral guides. Guard every callback with `enabled`.

- [ ] **Step 5: Separate display and byte columns**

Indent width remains a display-cell calculation for virtual guide placement. Jump targets use the first non-whitespace byte from buffer text, never `vim.fn.indent()` as a cursor byte offset.

- [ ] **Step 6: Apply polish**

Add `scope_char` to config, link normal guides to `PintIndent`/`NonText` and scope guides to `PintIndentScope`/`Special`, and never draw a guide over a non-whitespace cell.

- [ ] **Step 7: Run tests and commit**

```bash
git add lua/pint/indent.lua tests/test_indent.lua tests/test_pint.lua
git commit -m "fix(indent): make guides reload-safe and range-based"
```

---

### Task 6: Make Words encoding-safe and stale-response-safe

**Files:**
- Modify: `lua/pint/words.lua`
- Create: `tests/test_words.lua`

**Interfaces:**
- Produces `pint.words.restore()` and per-buffer state `{ timer, generation, request_id, client_id, refs, changedtick }`.

- [ ] **Step 1: Write failing tests**

Test UTF-16 reference positions on non-ASCII text, stale response after cursor movement, stale response after `changedtick`, detached clients, per-buffer debounce isolation, restore clearing all namespaces/timers, and next/previous boundary selection.

- [ ] **Step 2: Run focused tests and confirm failures**

- [ ] **Step 3: Introduce per-buffer state and generations**

```lua
local states = {}

local function state_for(buf)
  states[buf] = states[buf] or { generation = 0, refs = {} }
  return states[buf]
end
```

Each schedule/request increments generation and captures buffer, window, cursor, client ID, changedtick, and encoding. Callback exits unless every captured condition still matches.

- [ ] **Step 4: Use native LSP highlighting**

Apply highlights with `vim.lsp.util.buf_highlight_references(buf, result, encoding)` and clear with `vim.lsp.util.buf_clear_references(buf)`.

- [ ] **Step 5: Convert jump columns correctly**

For each LSP start position, read the target line and call `vim.str_byteindex(line, encoding, character, false)`. Store byte columns in sorted refs.

- [ ] **Step 6: Cancel superseded requests**

If a prior `request_id` exists, find the client by ID and call `client:cancel_request(request_id)` in `pcall` before issuing the new request.

- [ ] **Step 7: Fix boundary selection and optional feedback**

Next chooses the first reference strictly after the cursor; previous chooses the last strictly before it. Cycle wraps. Non-cycling failure may call one concise `vim.notify`; successful jumps remain silent.

- [ ] **Step 8: Run tests and commit**

```bash
git add lua/pint/words.lua tests/test_words.lua tests/test_pint.lua
git commit -m "fix(words): reject stale LSP references"
```

---

### Task 7: Harden and polish dashboard

**Files:**
- Modify: `lua/pint/dashboard.lua`
- Create: `tests/test_dashboard.lua`

**Interfaces:**
- Produces `pint.dashboard.restore()`.
- Dashboard config adds `footer?: fun(): pint.dashboard.Seg[]|string|nil` and supports `Item.label` as string or segments.

- [ ] **Step 1: Move existing dashboard tests into `tests/test_dashboard.lua` and add regressions**

Add tests for cwd boundary (`/tmp/foo` must not include `/tmp/foobar`), two dashboard windows, obsolete key removal after refresh, section callback errors, tiny dimensions, autostart removal, and footer callback rendering.

- [ ] **Step 2: Run focused tests and confirm failures**

- [ ] **Step 3: Add module lifecycle and per-buffer groups**

`restore()` deletes only the `PintDashboard` autostart group. Each open buffer gets `PintDashboard:<buf>` so one dashboard cannot clear another's handlers.

- [ ] **Step 4: Make recent-file containment boundary-safe**

Resolve normalized absolute cwd/file paths and keep a file only when `file == cwd` or `file:sub(1, #cwd + 1) == cwd .. path_separator`.

- [ ] **Step 5: Track and refresh buffer mappings**

Maintain a set of installed row keys. Before rebinding after refresh, delete all tracked keys from the dashboard buffer, then install the new set.

- [ ] **Step 6: Contain section callback errors and empty states**

Wrap `section.items()` in `pcall`. On error render one disabled row linked to `PintError`; on an empty result render a muted `No items` row. Recent files renders `No recent files` when empty.

- [ ] **Step 7: Replace Lazy coupling with footer callback**

Remove `require("lazy")`. If `M.config.footer` exists, call it safely and render returned segments/string centred at the bottom. Default is no footer.

- [ ] **Step 8: Polish responsive layout**

Clamp all painted line indexes, ensure at least one buffer line, truncate content by display width, keep cursor on a valid actionable row, and restore chrome once. Continue re-rendering in place on resize.

- [ ] **Step 9: Run tests and commit**

```bash
git add lua/pint/dashboard.lua tests/test_dashboard.lua tests/test_pint.lua
git commit -m "feat(dashboard): polish responsive startup UI"
```

---

### Task 8: Tooling, docs and generated help

**Files:**
- Create: `.luarc.json`
- Create: `.github/workflows/typecheck.yml`
- Modify: `.github/workflows/tests.yml`
- Modify: `.github/workflows/lint.yml`
- Modify: `.github/workflows/format.yml`
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `doc/pint.txt`
- Modify: `tests/minimal_init.lua`

**Interfaces:**
- CI gains a LuaLS typecheck job and full-SHA workflow pinning.

- [ ] **Step 1: Add LuaLS configuration**

```json
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime.version": "LuaJIT",
  "workspace.library": ["$VIMRUNTIME/lua"],
  "diagnostics.globals": ["vim"],
  "diagnostics.disable": ["inject-field"]
}
```

- [ ] **Step 2: Add typecheck workflow**

Install pinned LuaLS, run `lua-language-server --check=. --checklevel=Warning`, retain the exit code, print `check.json`, and fail when diagnostics exist.

- [ ] **Step 3: Pin shared workflows to full commit SHA**

Replace short reusable-workflow refs with the exact current full SHA from `matt-riley-ci`.

- [ ] **Step 4: Update README configuration and migration notes**

Document `style`, footer callback, notifier animation/dismiss APIs, statuscolumn slots, indent `scope_char`, lifecycle restoration and the absence of Lazy coupling.

- [ ] **Step 5: Update docs generation inputs and regenerate help**

Include `lua/pint/ui.lua`, run `make docs`, and verify `:helptags` succeeds.

- [ ] **Step 6: Run all verification**

```bash
MINI_PATH="$(pwd)/.ci/mini.nvim" make test
make format-check
make lint
make docs
git diff --check
```

Expected: every command exits 0 and generated help has no uncommitted drift after regeneration.

- [ ] **Step 7: Commit**

```bash
git add .github .luarc.json Makefile README.md doc tests/minimal_init.lua
git commit -m "chore: document and typecheck polished Pint"
```

---

### Task 9: Final review and pull request

**Files:** all changed files.

- [ ] **Step 1: Review the complete diff against the design**

Check every `setup()` has a matching idempotent `restore()`, no module restores state it no longer owns, no hardcoded colours exist, and no new feature category slipped in because vibes.

- [ ] **Step 2: Re-run the complete verification suite on the final commit**

Run the commands from Task 8 and confirm GitHub Actions passes tests, format, lint, typecheck, docs/commit checks as configured.

- [ ] **Step 3: Open a ready-for-review PR**

Title: `feat: harden and polish Pint`

Body must summarize lifecycle fixes, dashboard/notifier polish, LSP correctness, statuscolumn/indent correctness, compatibility changes, and exact verification results.
