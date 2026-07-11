# Pint hardening and polish design

Date: 2026-07-11

## Goal

Make Pint a dependable, polished replacement for the small subset of larger Neovim UI suites used by Kilaaks, without broadening it into a general-purpose UI framework.

The work has two equal priorities:

1. Make every module safe to enable, reconfigure, disable, and reload.
2. Give the existing features a cohesive, pleasant look and feel comparable to a carefully configured Snacks setup.

Pint remains dependency-free and targets Neovim nightly.

## Design principles

- Small modules with explicit ownership of the Neovim state they modify.
- Native Neovim APIs before custom infrastructure.
- Polished defaults, while allowing colorschemes and user configuration to remain in control.
- Subtle feedback rather than decorative animation.
- No picker, terminal, Git UI, file explorer, scrolling engine, or generic component system.
- No external icon dependency. Optional MiniIcons or nvim-web-devicons integration may be used when already available.

## Public lifecycle contract

Every Pint module exposes:

- `setup(opts)`: idempotently configure and enable the module.
- `restore()`: idempotently disable the module and release all state owned by Pint.

`require("pint").setup(opts)` restores previously configured modules in reverse setup order before applying the new configuration. A module restores global state only when Pint still owns it. For example, the notifier restores `vim.notify` only when `vim.notify` is still Pint's wrapper.

This contract applies to dashboard autocommands, notification windows and timers, global statuscolumn state, decoration providers, mappings, LSP requests, namespaces, and per-buffer/per-window caches.

## Shared visual language

Pint introduces a small internal `pint.ui` utility module. It is not a public component framework. It contains only shared primitives needed by at least two existing modules:

- resolve configured or native borders;
- clamp window dimensions and positions to the current UI;
- apply Pint highlight links with `default = true`;
- resolve optional icons with dependency-free fallbacks;
- split and truncate text by display width.

A top-level `style` configuration provides cohesive defaults:

```lua
style = {
  border = nil, -- uses 'winborder', then "rounded"
  icons = true,
  animation = {
    enabled = true,
    duration = 120,
    fps = 30,
  },
}
```

Animation remains deliberately limited. It is used only for short notifier position/blend transitions and can be disabled globally. Dashboard, statuscolumn, indent guides, and LSP words do not animate.

All Pint highlight groups link to standard editor groups by default. Pint never hardcodes theme colors.

## Dashboard

### Reliability

- Register one augroup per dashboard buffer so multiple dashboard windows cannot clear one another's handlers.
- Track installed dashboard mappings and remove mappings for rows that disappear after refresh.
- Restore window-local and global chrome exactly once when leaving or wiping the dashboard.
- Remove the autostart augroup when the module is disabled or reconfigured with `autostart = false`.
- Use boundary-safe path containment for cwd-filtered recent files.
- Clamp painting, cursor placement, and footer positioning for very small windows.
- Validate section callbacks and render a contained error row rather than aborting dashboard creation.

### Polish

- Keep the current clean centred layout, segmented highlights, cursorline selection, and aligned shortcut hints.
- Add a configurable footer callback instead of directly depending on Lazy.
- Add polished empty states for recent files and custom sections.
- Use a compact visual hierarchy: header, section title, rule, item rows, shortcut hints, and footer.
- Add optional section and item icons with dependency-free fallbacks.
- Preserve a responsive layout when the editor becomes narrow or short.
- Refresh on resize without flicker or buffer recreation.

The default footer is empty. Kilaaks may supply Lazy statistics through the callback without Pint knowing about Lazy.

## Notifier

### Reliability

- Preserve and restore the previous `vim.notify` handler only while Pint owns the wrapper.
- Close active windows, buffers, and timers during restore.
- Remove resize and lifecycle augroups during restore.
- Support notification replacement by ID without leaking timers or duplicate history entries.
- Enforce `max_history` consistently; `0` continues to mean unlimited.
- Clamp notification and history windows for small UIs.
- Limit notification height and width; long content is wrapped or truncated safely.
- Continue deferring API work from fast events.

### Polish

- Use consistent title, icon, border, body, and severity highlights.
- Add compact progress-style replacement notifications through the existing ID mechanism.
- Add optional short slide/fade transitions when notifications appear, move, replace, or dismiss.
- Avoid overlapping command-line and tabline areas when calculating stack position.
- Improve history presentation with severity, timestamp, title, message spacing, and simple close mappings.
- Provide `dismiss(id?)` and `dismiss_all()` APIs for user control and testing.

Animations update only float position and `winblend`, are cancelled on replacement or restore, and immediately settle when the UI is resized.

## Statuscolumn

### Reliability

- Preserve and restore the previous global `statuscolumn` value.
- Render safely when the statusline window ID is missing or invalid.
- Correctly handle absolute, relative, hybrid, wrapped, and virtual line contexts.
- Clip multibyte and double-width signs to their configured slot width.
- Cache extmark signs once per redraw cycle.
- Make Git-sign and fold-marker precedence explicit and configurable.
- Disable cleanly without leaving an active decoration provider or expression.

### Polish

- Keep the compact three-part layout: diagnostic or other sign, number, fold or Git sign.
- Use consistent slot widths and alignment at all line-number widths.
- Allow configurable separators and slot widths without exposing a format-string language.
- Link fold, number, and sign highlights to standard groups.

## Indent

### Reliability

- Migrate the decoration provider from deprecated `on_line` handling to `on_range`.
- Disable the provider through an enabled guard and clear all cached scope state on restore.
- Track Pint-installed mappings and restore any mappings replaced by Pint.
- Cache line text and calculated indentation during each redraw range.
- Handle tabs, horizontal scrolling, blank lines, and split windows correctly.
- Use byte columns for cursor movement and display columns only for virtual guide placement.

### Polish

- Keep static guides and one highlighted current-scope guide.
- Add configurable guide characters for normal and active scope states.
- Fade non-scope guides using highlight links rather than changing colors directly.
- Avoid drawing guides over non-whitespace text or outside the visible range.
- Preserve the existing `ii`, `ai`, `[i`, and `]i` behaviour unless the mappings are disabled.

## Words

### Reliability

- Maintain debounce, request, generation, and cached-reference state per buffer.
- Capture the originating buffer, window, cursor, and changedtick for each request.
- Reject stale responses after cursor movement, edits, detach, disable, or a newer request.
- Cancel superseded LSP requests where the client supports cancellation.
- Use native LSP reference highlight and clear helpers.
- Convert LSP character offsets to byte columns using the client's offset encoding when building jump locations.
- Clear references and timers for every tracked buffer during restore.
- Correct forward and backward jump selection at the beginning and end of the result set.

### Polish

- Keep native LSP reference highlight groups so the colorscheme controls appearance.
- Add optional jump feedback through `vim.notify` only when no references are available or a non-cycling jump reaches the end.
- Avoid routine notifications during successful navigation.

## Command surface

`:Pint` retains the existing subcommands and adds:

- `:Pint dismiss`
- `:Pint dismiss-all`
- `:Pint restore`

Completion returns only commands relevant to enabled modules where practical. Unknown subcommands continue to report a concise error.

## Testing

Split the current large test file into module-focused files:

- `tests/test_setup.lua`
- `tests/test_dashboard.lua`
- `tests/test_notifier.lua`
- `tests/test_statuscolumn.lua`
- `tests/test_indent.lua`
- `tests/test_words.lua`
- `tests/test_command.lua`

Regression coverage includes:

- repeated setup and module disable/enable cycles;
- ownership-safe restoration of `vim.notify`, `statuscolumn`, mappings, providers, timers, and augroups;
- dashboard cwd boundaries, multiple windows, stale mappings, callback failures, and tiny dimensions;
- notifier replacement, history bounds, animation cancellation, fast events, and tiny dimensions;
- wide Unicode signs, relative numbers, wrapped lines, and invalid windows;
- tab indentation, split windows, mapping restoration, and provider disable;
- UTF-8 and UTF-16 LSP positions, stale replies, changed buffers, detached clients, and jump boundaries.

Tests must close all windows and timers they create and restore any stubbed Neovim APIs in teardown hooks.

## Tooling and documentation

- Add LuaLS configuration and a typecheck workflow.
- Keep nightly Neovim in CI.
- Pin reusable workflow references to full commit SHAs.
- Keep format, lint, test, docs, and conventional-commit checks.
- Update README configuration examples and migration notes.
- Regenerate `doc/pint.txt` from all public modules.

## Deliberate non-goals

This pass does not add:

- a fuzzy finder or picker;
- terminal management;
- Git or forge integration;
- file browsing;
- scrolling animation;
- generic layout or component APIs;
- persisted notification history;
- external dependencies.

Those are excluded even when they might be aesthetically pleasing, because vibes are not an architecture.

## Completion criteria

The work is complete when:

1. Every module can be repeatedly enabled, reconfigured, disabled, and restored without stale state.
2. Existing public behaviour remains compatible except for documented correctness fixes and the dashboard footer becoming opt-in.
3. The UI remains usable in small terminals, split windows, and non-ASCII buffers.
4. Notifier polish is visible but restrained, cancellable, and optional.
5. Tests, formatting, lint, LuaLS typechecking, docs generation, and commit-message checks pass.
6. Pint remains focused on its five existing UI features.