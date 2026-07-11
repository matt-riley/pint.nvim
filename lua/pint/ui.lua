local M = {}

---@class pint.StyleAnimation
---@field enabled? boolean
---@field duration? integer
---@field fps? integer

---@class pint.Style
---@field border? string
---@field icons? boolean
---@field animation? pint.StyleAnimation

local defaults = {
  border = nil,
  icons = true,
  animation = {
    enabled = true,
    duration = 120,
    fps = 30,
  },
}

M.config = vim.deepcopy(defaults)

local highlight_links = {
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

---@private
---@param opts? pint.Style
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  for name, target in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

---@private
---@param value? string
---@return string
function M.border(value)
  local resolved = value or M.config.border or vim.o.winborder
  if resolved == nil or resolved == "" then
    return "rounded"
  end
  return resolved
end

---@private
---@param opts table
---@return table
function M.clamp_float(opts)
  local max_width = math.max(vim.o.columns - 2, 1)
  local max_height = math.max(vim.o.lines - 2, 1)
  local width = math.min(math.max(opts.width or 1, 1), max_width)
  local height = math.min(math.max(opts.height or 1, 1), max_height)
  local max_row = math.max(vim.o.lines - height - 2, 0)
  local max_col = math.max(vim.o.columns - width - 2, 0)

  return vim.tbl_extend("force", opts, {
    width = width,
    height = height,
    row = math.min(math.max(opts.row or 0, 0), max_row),
    col = math.min(math.max(opts.col or 0, 0), max_col),
  })
end

---@private
---@param text string
---@param max_width integer
---@return string
function M.truncate(text, max_width)
  if max_width <= 0 then
    return ""
  end
  if vim.api.nvim_strwidth(text) <= max_width then
    return text
  end

  local ellipsis = "…"
  local ellipsis_width = vim.api.nvim_strwidth(ellipsis)
  if max_width <= ellipsis_width then
    return ellipsis
  end

  local out = ""
  local index = 0
  while true do
    local char = vim.fn.strcharpart(text, index, 1)
    if char == "" then
      break
    end
    if vim.api.nvim_strwidth(out .. char) + ellipsis_width > max_width then
      break
    end
    out = out .. char
    index = index + 1
  end

  return out .. ellipsis
end

---@private
---@param kind string
---@param fallback string
---@return string
function M.icon(kind, fallback)
  if M.config.icons == false then
    return ""
  end

  local icons = {
    info = "I",
    warn = "W",
    error = "E",
    hint = "H",
    dashboard = "◆",
    file = "·",
  }

  return icons[kind] or fallback
end

return M
