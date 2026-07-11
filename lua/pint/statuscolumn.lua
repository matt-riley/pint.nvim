-- lua/pint/statuscolumn.lua
-- Statuscolumn: [non-git sign] [line number] [fold/git sign].
local M = {}

--- pint.statuscolumn
---
--- Statuscolumn layout: `[sign] [number] [fold/git sign]`.
---
---@tag pint-statuscolumn

---@class pint.statuscolumn.Folds
---@field open? boolean Show open-fold markers
---@field git_hl? boolean Reuse a Git sign highlight for fold markers
---@field precedence? "git"|"fold" Which item wins when a Git sign and fold marker share the right slot

--- Statuscolumn configuration.
---@class pint.statuscolumn.Config
---@field folds? pint.statuscolumn.Folds
---@field git_patterns? string[] Sign/extmark name patterns treated as Git signs
---@field sign_width? integer Width of the left sign slot. Default: 2
---@field right_width? integer Width of the fold/Git slot. Default: 2
---@field separator? string Text between line number and right slot. Default: " "

local defaults = {
  folds = { open = false, git_hl = false, precedence = "git" },
  git_patterns = { "GitSign", "MiniDiffSign" },
  sign_width = 2,
  right_width = 2,
  separator = " ",
}

M.config = vim.deepcopy(defaults)

---@alias pint.statuscolumn.Sign {name:string, text:string, texthl:string?, priority:integer}

---@private
---@type table<integer, table<integer, pint.statuscolumn.Sign[]>>
local cache = {}
---@private
local active = false
local previous_statuscolumn ---@type string?
local expression = "%!v:lua.require'pint.statuscolumn'.get()"
local namespace = vim.api.nvim_create_namespace("pint.statuscolumn")

---@private
---@param name string
---@return boolean
local function is_git(name)
  for _, pattern in ipairs(M.config.git_patterns) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

---@private
---@param text string
---@param width integer
---@return string
local function fit(text, width)
  if width <= 0 then
    return ""
  end

  text = vim.trim(text or "")
  local out = ""
  for index = 0, vim.fn.strchars(text) - 1 do
    local candidate = out .. vim.fn.strcharpart(text, index, 1)
    if vim.api.nvim_strwidth(candidate) > width then
      break
    end
    out = candidate
  end

  return out .. string.rep(" ", math.max(width - vim.api.nvim_strwidth(out), 0))
end

---@private
---@param sign? pint.statuscolumn.Sign
---@param width integer
---@return string
local function format_sign(sign, width)
  if not sign then
    return string.rep(" ", math.max(width, 0))
  end

  local text = fit(sign.text or "", width):gsub("%%", "%%%%")
  if sign.texthl and sign.texthl ~= "" then
    return ("%%#%s#%s%%*"):format(sign.texthl, text)
  end
  return text
end

---@private
---@param lnum integer
---@param relnum integer
---@param number boolean
---@param relativenumber boolean
---@return string
local function number_text(lnum, relnum, number, relativenumber)
  if relativenumber then
    if number and relnum == 0 then
      return tostring(lnum)
    end
    return tostring(relnum)
  end
  if number then
    return tostring(lnum)
  end
  return ""
end

---@private
---@param virtnum integer
---@return boolean
local function renderable(virtnum)
  return virtnum == 0
end

---@private
---@param buf integer
---@return table<integer, pint.statuscolumn.Sign[]>
local function buffer_signs(buf)
  if cache[buf] then
    return cache[buf]
  end

  local signs = {}
  local ok, extmarks = pcall(vim.api.nvim_buf_get_extmarks, buf, -1, 0, -1, {
    details = true,
    type = "sign",
  })
  if not ok then
    return signs
  end

  for _, extmark in ipairs(extmarks) do
    local lnum = extmark[2] + 1
    local details = extmark[4]
    if details and details.sign_text then
      signs[lnum] = signs[lnum] or {}
      signs[lnum][#signs[lnum] + 1] = {
        name = details.sign_name or details.sign_hl_group or "",
        text = details.sign_text,
        texthl = details.sign_hl_group,
        priority = details.priority or 0,
      }
    end
  end

  cache[buf] = signs
  return signs
end

---@private
---@param win integer
---@param lnum integer
---@param git? pint.statuscolumn.Sign
---@return pint.statuscolumn.Sign?
local function fold_sign(win, lnum, git)
  local ok, text = pcall(vim.api.nvim_win_call, win, function()
    if vim.fn.foldclosed(lnum) == lnum then
      return vim.opt.fillchars:get().foldclose or "+"
    end
    if M.config.folds.open and vim.fn.foldlevel(lnum) > vim.fn.foldlevel(math.max(lnum - 1, 1)) then
      return vim.opt.fillchars:get().foldopen or "-"
    end
  end)

  if not ok or not text then
    return nil
  end

  local highlight = "FoldColumn"
  if M.config.folds.git_hl and git and git.texthl then
    highlight = git.texthl
  end
  return { name = "PintFold", text = text, texthl = highlight, priority = 0 }
end

--- Render the statuscolumn for the current window.
---@return string
function M.get()
  if not active or not renderable(vim.v.virtnum) then
    return ""
  end

  local win = tonumber(vim.g.statusline_winid)
  if not win or win <= 0 or not vim.api.nvim_win_is_valid(win) then
    return ""
  end

  local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok then
    return ""
  end

  local window_options = vim.wo[win]
  local lnum = vim.v.lnum
  local left ---@type pint.statuscolumn.Sign?
  local git ---@type pint.statuscolumn.Sign?

  if window_options.signcolumn ~= "no" then
    for _, sign in ipairs(buffer_signs(buf)[lnum] or {}) do
      if is_git(sign.name) then
        if not git or sign.priority > git.priority then
          git = sign
        end
      elseif not left or sign.priority > left.priority then
        left = sign
      end
    end
  end

  local fold = fold_sign(win, lnum, git)
  local right = git
  if fold and (not git or M.config.folds.precedence == "fold") then
    right = fold
  end

  local number = number_text(lnum, vim.v.relnum, window_options.number, window_options.relativenumber)
  local number_width = math.max(window_options.numberwidth, #number)
  local number_slot = number == "" and string.rep(" ", number_width) or ("%" .. number_width .. "s"):format(number)

  return table.concat({
    format_sign(left, M.config.sign_width),
    number_slot,
    M.config.separator,
    format_sign(right, M.config.right_width),
  })
end

--- Restore the previous global statuscolumn when Pint still owns it.
function M.restore()
  active = false
  cache = {}
  pcall(vim.api.nvim_del_augroup_by_name, "PintStatuscolumn")
  vim.api.nvim_set_decoration_provider(namespace, {
    on_start = function()
      return false
    end,
  })

  if previous_statuscolumn ~= nil and vim.o.statuscolumn == expression then
    vim.o.statuscolumn = previous_statuscolumn
  end
  previous_statuscolumn = nil
end

--- Set 'statuscolumn' globally and keep the sign cache fresh.
---@param opts? pint.statuscolumn.Config
function M.setup(opts)
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  previous_statuscolumn = vim.o.statuscolumn
  active = true

  vim.api.nvim_set_decoration_provider(namespace, {
    on_start = function()
      if not active then
        return false
      end
      cache = {}
    end,
  })

  local group = vim.api.nvim_create_augroup("PintStatuscolumn", { clear = true })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(event)
      cache[event.buf] = nil
    end,
  })

  vim.o.statuscolumn = expression
end

M._test = {
  fit = fit,
  number_text = number_text,
  renderable = renderable,
}

return M
