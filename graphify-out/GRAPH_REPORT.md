# Graph Report - .  (2026-06-14)

## Corpus Check
- Corpus is ~13,483 words - fits in a single context window. You may not need a graph.

## Summary
- 112 nodes · 166 edges · 12 communities (9 shown, 3 thin omitted)
- Extraction: 76% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Dashboard UI|Dashboard UI]]
- [[_COMMUNITY_Notification System|Notification System]]
- [[_COMMUNITY_LSP Reference Highlighting|LSP Reference Highlighting]]
- [[_COMMUNITY_Status Column & Testing|Status Column & Testing]]
- [[_COMMUNITY_Indent Guides|Indent Guides]]
- [[_COMMUNITY_Release Automation|Release Automation]]
- [[_COMMUNITY_Plugin API|Plugin API]]
- [[_COMMUNITY_Core Setup|Core Setup]]
- [[_COMMUNITY_Dependency Management|Dependency Management]]
- [[_COMMUNITY_Commit Validation|Commit Validation]]
- [[_COMMUNITY_Config Schema|Config Schema]]

## God Nodes (most connected - your core abstractions)
1. `build_rows()` - 7 edges
2. `M.open()` - 7 edges
3. `refresh()` - 7 edges
4. `packages` - 7 edges
5. `M.notify()` - 6 edges
6. `scope_range()` - 5 edges
7. `truncate_strwidth()` - 4 edges
8. `truncate_strwidth_tail()` - 4 edges
9. `format_path()` - 4 edges
10. `recent_file_segments()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `M.open()` --calls--> `refresh()`  [INFERRED]
  lua/pint/dashboard.lua → lua/pint/words.lua

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **setup_flow** — pint_setup, pint_dashboard, pint_notifier, pint_statuscolumn, pint_indent, pint_words [0.95]
- **command_dispatch** — pint_command, dashboard_open, notifier_show_history, words_enable, words_disable [0.9]
- **dashboard_rendering** — dashboard_open, dashboard_recent_files, dashboard_format_path, dashboard_file_icon [0.85]
- **config_merge** — pint_setup, dashboard_config, notifier_config, statuscolumn_config, indent_config, words_config [0.8]

## Communities (12 total, 3 thin omitted)

### Community 0 - "Dashboard UI"
Cohesion: 0.15
Nodes (22): dashboard.Config, dashboard.Key, dashboard.Section, align_row_keys(), append_aligned_key(), build_rows(), file_icon(), format_path() (+14 more)

### Community 1 - "Notification System"
Cohesion: 0.21
Nodes (16): notifier.Config, notifier.Item, notifier.notify, border(), close_item(), dismiss(), layout(), M.notify() (+8 more)

### Community 2 - "LSP Reference Highlighting"
Cohesion: 0.24
Nodes (13): apply_highlights(), clear(), highlight(), jump_to(), M.disable(), M.enable(), M.jump(), M.setup() (+5 more)

### Community 3 - "Status Column & Testing"
Cohesion: 0.19
Nodes (8): mini.test, buf_signs(), fmt(), is_git(), M.get(), statuscolumn.Config, statuscolumn.get, test_statuscolumn_set

### Community 4 - "Indent Guides"
Cohesion: 0.31
Nodes (10): indent.Config, indent.jump, indent.textobject, line_indent(), M.jump(), M.setup(), M.textobject(), on_line() (+2 more)

### Community 5 - "Release Automation"
Cohesion: 0.22
Nodes (8): bump-minor-pre-major, bump-patch-for-minor-pre-major, changelog-path, include-component-in-tag, packages, release-type, $schema, version-file

### Community 6 - "Plugin API"
Cohesion: 0.25
Nodes (8): dashboard.file_icon, dashboard.format_path, dashboard.open, dashboard.recent_files, notifier.show_history, :Pint, words.disable, words.enable

### Community 7 - "Core Setup"
Cohesion: 0.29
Nodes (5): pint.Config, pint.nvim, pint.setup, README.md, test_setup_set

## Knowledge Gaps
- **10 isolated node(s):** `$schema`, `extends`, `$schema`, `release-type`, `changelog-path` (+5 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `M.open()` connect `Dashboard UI` to `LSP Reference Highlighting`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Why does `refresh()` connect `LSP Reference Highlighting` to `Dashboard UI`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **What connects `$schema`, `extends`, `$schema` to the rest of the system?**
  _10 weakly-connected nodes found - possible documentation gaps or missing edges._