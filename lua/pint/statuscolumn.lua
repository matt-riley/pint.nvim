-- lua/pint/statuscolumn.lua
-- Statuscolumn: [non-git sign] [line number] [fold] [git sign].
local M = {}

--- Statuscolumn configuration.
---@class pint.statuscolumn.Config
---@field folds? {open: boolean, git_hl: boolean} Show open-fold markers; reuse git sign hl for fold icons
---@field git_patterns? string[] Sign/extmark name patterns treated as git signs

---@private
local defaults = {
  folds = { open = false, git_hl = false },
  git_patterns = { "GitSign", "MiniDiffSign" },
}

M.config = vim.deepcopy(defaults)
local previous_statuscolumn
local active = false
local statuscolumn_expr = "%!v:lua.require'pint.statuscolumn'.get()"

---@private
---@alias pint.statuscolumn.Sign {name: string, text: string, texthl: string, priority: integer}

---@private
---@type table<integer, table<integer, pint.statuscolumn.Sign[]>> buf -> lnum -> signs
local cache = {}

local function is_git(name)
  for _, pat in ipairs(M.config.git_patterns) do
    if name:find(pat) then
      return true
    end
  end
  return false
end

---@private
local function fold_text(lnum)
  if vim.fn.foldclosed(lnum) == lnum then
    return vim.opt.fillchars:get().foldclose or "+"
  end
  if M.config.folds.open and vim.fn.foldlevel(lnum) > vim.fn.foldlevel(lnum - 1) then
    return vim.opt.fillchars:get().foldopen or "-"
  end
end

---@private
---@return table<integer, pint.statuscolumn.Sign[]>
local function buf_signs(buf)
  if cache[buf] then
    return cache[buf]
  end
  local signs = {}
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true, type = "sign" })
  for _, extmark in ipairs(extmarks) do
    local lnum, details = extmark[2] + 1, extmark[4]
    if details and details.sign_text then
      signs[lnum] = signs[lnum] or {}
      table.insert(signs[lnum], {
        name = details.sign_name or details.sign_hl_group or "",
        text = details.sign_text,
        texthl = details.sign_hl_group,
        priority = details.priority or 0,
      })
    end
  end
  cache[buf] = signs
  return signs
end

---@private
local function fmt(sign, width)
  if not sign then
    return (" "):rep(width)
  end
  if width <= 0 then
    return ""
  end
  local text = vim.trim(sign.text or "")
  local chars = vim.fn.strchars(text)
  local clipped = ""
  for i = 1, chars do
    local next_text = vim.fn.strcharpart(text, 0, i)
    if vim.api.nvim_strwidth(next_text) > width then
      break
    end
    clipped = next_text
  end
  text = clipped
  local padding = width - vim.api.nvim_strwidth(text)
  if padding > 0 then
    text = text .. (" "):rep(padding)
  end
  return sign.texthl and ("%%#%s#%s%%*"):format(sign.texthl, text) or text
end

--- Render the statuscolumn for the current window. Use via:
--- `vim.o.statuscolumn = "%!v:lua.require'pint.statuscolumn'.get()"`
---@return string
function M.get()
  if not active then
    return ""
  end
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.wo[win].signcolumn == "no" then
    return "%l "
  end

  local lnum = vim.v.lnum
  local signs = buf_signs(buf)[lnum] or {}

  ---@type pint.statuscolumn.Sign|nil, pint.statuscolumn.Sign|nil
  local left, git
  for _, s in ipairs(signs) do
    if is_git(s.name) then
      if not git or s.priority > git.priority then
        git = s
      end
    elseif not left or s.priority > left.priority then
      left = s
    end
  end

  local fold = fold_text(lnum)
  local right = git
  if fold and git and M.config.folds.git_hl then
    right = { text = fold, texthl = git.texthl or "FoldColumn", priority = git.priority }
  elseif not right and fold then
    right = { text = fold, texthl = "FoldColumn", priority = 0 }
  end

  local nu = ""
  if vim.wo[win].number or vim.wo[win].relativenumber then
    nu = "%=%l"
  end

  return table.concat({ fmt(left, 2), nu, " ", fmt(right, 2) })
end

--- Set 'statuscolumn' globally and keep the sign cache fresh.
---@tag pint.statuscolumn.setup
---@param opts? pint.statuscolumn.Config
function M.setup(opts)
  M.teardown()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  previous_statuscolumn = vim.o.statuscolumn
  active = true

  local group = vim.api.nvim_create_augroup("PintStatuscolumn", { clear = true })
  -- extmark signs have no change event; invalidate per redraw cycle
  vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace("pint.statuscolumn"), {
    on_start = function()
      if active then
        cache = {}
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      cache[ev.buf] = nil
    end,
  })

  vim.o.statuscolumn = statuscolumn_expr
end

--- Restore the previous statuscolumn and clear cached sign state.
---@tag pint.statuscolumn.teardown
function M.teardown()
  active = false
  cache = {}
  if vim.o.statuscolumn == statuscolumn_expr and previous_statuscolumn ~= nil then
    vim.o.statuscolumn = previous_statuscolumn
  end
  previous_statuscolumn = nil
  pcall(vim.api.nvim_del_augroup_by_name, "PintStatuscolumn")
end

return M
