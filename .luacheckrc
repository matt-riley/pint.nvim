-- .luacheckrc
-- Luacheck configuration for Neovim plugins

std = "luajit"

globals = {
  "vim",
  "MiniTest",
}

read_globals = {
  "describe",
  "it",
  "before_each",
  "after_each",
}

-- Ignore line length warnings
ignore = {
  "631", -- max_line_length
}
