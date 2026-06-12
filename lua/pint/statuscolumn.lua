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
  local text = vim.trim(sign.text or "")
  text = text .. (" "):rep(width - vim.api.nvim_strwidth(text))
  return sign.texthl and ("%%#%s#%s%%*"):format(sign.texthl, text) or text
end

--- Render the statuscolumn for the current window. Use via:
--- `vim.o.statuscolumn = "%!v:lua.require'pint.statuscolumn'.get()"`
---@return string
function M.get()
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

  -- fold marker in the right slot when there's no git sign
  local right = git
  if not right then
    if vim.fn.foldclosed(lnum) == lnum then
      right = { text = vim.opt.fillchars:get().foldclose or "+", texthl = "FoldColumn", priority = 0 }
    elseif M.config.folds.open and vim.fn.foldlevel(lnum) > vim.fn.foldlevel(lnum - 1) then
      right = { text = vim.opt.fillchars:get().foldopen or "-", texthl = "FoldColumn", priority = 0 }
    end
  end

  local nu = ""
  if vim.wo[win].number or vim.wo[win].relativenumber then
    nu = "%=%l"
  end

  return table.concat({ fmt(left, 2), nu, " ", fmt(right, 2) })
end

--- Set 'statuscolumn' globally and keep the sign cache fresh.
---@param opts? pint.statuscolumn.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  local group = vim.api.nvim_create_augroup("PintStatuscolumn", { clear = true })
  -- extmark signs have no change event; invalidate per redraw cycle
  vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace("pint.statuscolumn"), {
    on_start = function()
      cache = {}
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      cache[ev.buf] = nil
    end,
  })

  vim.o.statuscolumn = "%!v:lua.require'pint.statuscolumn'.get()"
end

return M
