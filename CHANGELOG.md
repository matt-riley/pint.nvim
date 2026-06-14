# Changelog

## [0.1.2](https://github.com/matt-riley/pint.nvim/compare/v0.1.1...v0.1.2) (2026-06-14)


### Features

* **dashboard:** improve layout, recent files, and section spacing ([6395a1c](https://github.com/matt-riley/pint.nvim/commit/6395a1c4444eebe5781fcc9f4bd35e78480e21f0))


### Bug Fixes

* **dashboard:** allow recent=false to disable the section ([3b91945](https://github.com/matt-riley/pint.nvim/commit/3b91945a60ca9f6ac73a1fbebc85043daf3edd5b))
* **dashboard:** restore line numbers and statuscolumn after leaving startup screen ([ff95748](https://github.com/matt-riley/pint.nvim/commit/ff957482fb34e4c5f24cca668760bb72d6df5088))
* **indent:** compute indent from buffer text for correct guides in splits ([de02e09](https://github.com/matt-riley/pint.nvim/commit/de02e09b5fe463b14daa227c4e6c5183029582ae))
* **notifier:** defer vim.notify when called in a fast event ([c797cda](https://github.com/matt-riley/pint.nvim/commit/c797cda26d28ccc3542ff2b0a66b6d0d68124161))

## [0.1.1](https://github.com/matt-riley/pint.nvim/compare/v0.1.0...v0.1.1) (2026-06-14)


### Features

* initial pint.nvim — dashboard, notifier, statuscolumn, indent, words ([e2b741c](https://github.com/matt-riley/pint.nvim/commit/e2b741c2aa3c1cc966ee26372288b01624ab2a01))


### Bug Fixes

* address audit findings across all pint modules ([c83de01](https://github.com/matt-riley/pint.nvim/commit/c83de01476e0f0214cce0c80cd447c2324dae8b2))
* dashboard error again ([878562b](https://github.com/matt-riley/pint.nvim/commit/878562b53797ecd3e8751f70ae6cbf9730a15e33))
* error in rendering ([72afa90](https://github.com/matt-riley/pint.nvim/commit/72afa90bcf044a0aaddde7ce4c528af379b04314))

## [0.1.0](https://github.com/matt-riley/pint.nvim/compare/v0.0.0...v0.1.0) (2026-06-14)


### Features

* dashboard with header, keyed actions, recent files, and custom sections
* floating vim.notify handler with history (`:Pint history`)
* statuscolumn layout with git signs on the right
* indent guides with scope highlight, textobjects, and jumps
* LSP document highlight words with reference jumping
