-- lua/pint/scroll.lua
-- Smooth scrolling for half-page, page, and cursor-line motions.
local M = {}

--- pint.scroll
---
--- Smooth scrolling for `<C-d>`, `<C-u>`, `<C-f>`, `<C-b>`, `zz`, `zt`, and `zb`.
--- Each motion finishes on the same view and cursor as the builtin command.
--- The module is opt-in (`enabled` defaults to false). Mouse-wheel scrolling is
--- left untouched. Animation is skipped while recording or replaying a macro,
--- when another key is already queued, when the key was produced by a different
--- mapping, when the window changes, and in buffers longer than `max_lines`.
---
---@tag pint-scroll

--- Smooth scroll configuration.
---@class pint.scroll.Config
---@field enabled? boolean Install scroll mappings. Default: false
---@field duration? integer Animation length in milliseconds. Default: 200
---@field easing? string|fun(t: number): number `linear`, `ease-out-quad`, or a function of progress. Default: `ease-out-quad`
---@field max_lines? integer Skip animation in longer buffers. Default: 10000

local defaults = {
  enabled = false,
  duration = 200,
  easing = "ease-out-quad",
  max_lines = 10000,
}

M.config = vim.deepcopy(defaults)

local FRAME_MS = 16
local MAX_WALK = 800
local LONG_JUMP = 300

local COMMANDS = {
  ["<C-d>"] = true,
  ["<C-u>"] = true,
  ["<C-f>"] = true,
  ["<C-b>"] = true,
  zz = true,
  zt = true,
  zb = true,
}

local easings = {
  linear = function(t)
    return t
  end,
  ["ease-out-quad"] = function(t)
    return 1 - (1 - t) * (1 - t)
  end,
}

local enabled = false
local switching = 0
local skipped_fast = 0
local last_error ---@type string?
local last_typed = ""
local key_namespace = vim.api.nvim_create_namespace("pint.scroll")

---@private
---@class pint.scroll.View
---@field lnum integer
---@field col integer
---@field coladd integer
---@field curswant integer
---@field topline integer
---@field topfill integer
---@field leftcol integer
---@field skipcol integer

---@private
---@class pint.scroll.Position
---@field topline integer
---@field topfill integer
---@field skipcol integer
---@field leftcol integer

---@private
---@class pint.scroll.Options
---@field scrolloff integer
---@field sidescrolloff integer

---@private
---@class pint.scroll.Animation
---@field generation integer
---@field win integer
---@field buf integer
---@field timer? uv.uv_timer_t
---@field from pint.scroll.View
---@field target pint.scroll.View
---@field path pint.scroll.Position[]
---@field options pint.scroll.Options
---@field changedtick integer
---@field duration integer
---@field interval integer
---@field elapsed number

---@private
---@type pint.scroll.Animation?
local current

---@private
---@type {lhs:string, desc:string, previous:table?}[]
local installed_maps = {}

---@private
---@param view pint.scroll.View
---@return pint.scroll.View
local function copy_view(view)
  return {
    lnum = math.max(view.lnum or 1, 1),
    col = view.col or 0,
    coladd = view.coladd or 0,
    curswant = view.curswant or view.col or 0,
    topline = math.max(view.topline or 1, 1),
    topfill = view.topfill or 0,
    leftcol = view.leftcol or 0,
    skipcol = view.skipcol or 0,
  }
end

---@private
---@param view pint.scroll.View
---@return pint.scroll.Position
local function position_of(view)
  return {
    topline = view.topline,
    topfill = view.topfill or 0,
    skipcol = view.skipcol or 0,
    leftcol = view.leftcol or 0,
  }
end

---@private
--- Higher topfill sits above the same topline because it is filler revealed by scrolling up.
---@param left pint.scroll.View|pint.scroll.Position
---@param right pint.scroll.View|pint.scroll.Position
---@return integer
local function vertical_cmp(left, right)
  if left.topline ~= right.topline then
    return left.topline < right.topline and -1 or 1
  end
  local left_fill = left.topfill or 0
  local right_fill = right.topfill or 0
  if left_fill ~= right_fill then
    return left_fill > right_fill and -1 or 1
  end
  local left_skip = left.skipcol or 0
  local right_skip = right.skipcol or 0
  if left_skip ~= right_skip then
    return left_skip < right_skip and -1 or 1
  end
  return 0
end

---@private
---@param left pint.scroll.View
---@param right pint.scroll.View
---@return boolean
local function same_place(left, right)
  return vertical_cmp(left, right) == 0
    and left.lnum == right.lnum
    and left.col == right.col
    and left.leftcol == right.leftcol
end

---@private
---@param win integer
---@param fn fun(): any
---@return any
local function win_call(win, fn)
  switching = switching + 1
  local ok, result = pcall(vim.api.nvim_win_call, win, fn)
  switching = switching - 1
  if not ok then
    error(result)
  end
  return result
end

---@private
---@param timer uv.uv_timer_t?
local function stop_timer(timer)
  if not timer then
    return
  end
  timer:stop()
  if not timer:is_closing() then
    timer:close()
  end
end

---@private
---@param win integer
---@return pint.scroll.Options
local function capture_options(win)
  return {
    scrolloff = vim.wo[win].scrolloff,
    sidescrolloff = vim.wo[win].sidescrolloff,
  }
end

---@private
---@param win integer
---@param options pint.scroll.Options
local function apply_options(win, options)
  vim.wo[win].scrolloff = options.scrolloff
  vim.wo[win].sidescrolloff = options.sidescrolloff
end

---@private
---@param win integer
---@param options pint.scroll.Options
local function lock_viewport(win, options)
  apply_options(win, options)
  vim.wo[win].scrolloff = 0
  vim.wo[win].sidescrolloff = 0
end

---@private
---@param lhs string
---@return string?
local function canonical(lhs)
  if type(lhs) ~= "string" then
    return nil
  end
  local translated = vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, false, true))
  local aliases = {
    ["<C-D>"] = "<C-d>",
    ["<C-U>"] = "<C-u>",
    ["<C-F>"] = "<C-f>",
    ["<C-B>"] = "<C-b>",
    ZZ = "zz",
    ZT = "zt",
    ZB = "zb",
  }
  local name = aliases[translated] or lhs
  if COMMANDS[name] then
    return name
  end
  return nil
end

---@private
---@param lhs string
---@param count integer
local function execute(lhs, count)
  local prefix = count > 0 and tostring(count) or ""
  local keys = vim.api.nvim_replace_termcodes(prefix .. lhs, true, false, true)
  vim.cmd.normal({ bang = true, args = { keys }, mods = { keepjumps = true } })
end

---@private
---@param snap boolean
local function stop_current(snap)
  local anim = current
  if not anim then
    return
  end
  local win = anim.win
  local target = anim.target
  local options = anim.options
  anim.generation = anim.generation + 1
  stop_timer(anim.timer)
  anim.timer = nil
  current = nil

  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  apply_options(win, options)

  local same_buffer = vim.api.nvim_buf_is_valid(anim.buf) and vim.api.nvim_win_get_buf(win) == anim.buf
  local unchanged = same_buffer and vim.api.nvim_buf_get_changedtick(anim.buf) == anim.changedtick
  if snap and unchanged then
    pcall(win_call, win, function()
      vim.fn.winrestview(target)
    end)
  end
end

---@private
---@param t number
---@return number
local function ease(t)
  local specified = M.config.easing
  local value ---@type number?
  if type(specified) == "function" then
    local ok, result = pcall(specified, t)
    if ok and type(result) == "number" then
      value = result
    end
  elseif type(specified) == "string" and easings[specified] then
    value = easings[specified](t)
  end
  if type(value) ~= "number" then
    value = easings["ease-out-quad"](t)
  end
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

---@private
---@return integer
local function duration_ms()
  local value = M.config.duration
  if type(value) ~= "number" then
    return defaults.duration
  end
  return math.max(math.floor(value), 0)
end

---@private
---@return integer
local function line_limit()
  local value = M.config.max_lines
  if type(value) ~= "number" then
    return defaults.max_lines
  end
  return math.max(math.floor(value), 0)
end

---@private
--- A lone Esc is the flush byte left by feedkeys and :normal, not a queued motion.
---@return boolean
local function typing_fast()
  local ahead = vim.fn.getcharstr(1)
  return ahead ~= "" and ahead ~= "\27"
end

---@private
---@param buf integer
---@return string?
local function block_reason(buf)
  if not enabled then
    return "disabled"
  end
  if vim.fn.reg_executing() ~= "" or vim.fn.reg_recording() ~= "" then
    return "macro"
  end
  if typing_fast() then
    skipped_fast = skipped_fast + 1
    return "typeahead"
  end
  if vim.bo[buf].buftype == "terminal" or vim.fn.getcmdwintype() ~= "" then
    return "special"
  end
  if vim.wo.scrollbind then
    return "scrollbind"
  end
  if vim.fn.mode() ~= "n" then
    return "mode"
  end
  if duration_ms() <= 0 then
    return "duration"
  end
  local limit = line_limit()
  if limit > 0 and vim.api.nvim_buf_line_count(buf) > limit then
    return "large"
  end
  return nil
end

---@private
---@param from pint.scroll.View
---@param to pint.scroll.View
---@return pint.scroll.Position[]
local function proportional_path(from, to)
  local steps = 8
  local path = {}
  for step = 0, steps do
    local progress = step / steps
    path[#path + 1] = {
      topline = math.max(math.floor(from.topline + (to.topline - from.topline) * progress + 0.5), 1),
      topfill = math.max(
        math.floor((from.topfill or 0) + ((to.topfill or 0) - (from.topfill or 0)) * progress + 0.5),
        0
      ),
      skipcol = 0,
      leftcol = math.max(
        math.floor((from.leftcol or 0) + ((to.leftcol or 0) - (from.leftcol or 0)) * progress + 0.5),
        0
      ),
    }
  end
  path[#path] = position_of(to)
  return path
end

---@private
---@param from pint.scroll.View
---@param to pint.scroll.View
---@return pint.scroll.Position[]
local function walk_path(from, to)
  local saved = copy_view(vim.fn.winsaveview())
  local direction = vertical_cmp(from, to)
  if direction == 0 then
    return { position_of(from) }
  end

  local down = direction < 0
  local key = vim.api.nvim_replace_termcodes(down and "<C-e>" or "<C-y>", true, false, true)
  local path = { position_of(from) }
  local ok, err = pcall(function()
    vim.fn.winrestview(from)
    local steps = 0
    while steps < MAX_WALK do
      steps = steps + 1
      local here = vim.fn.winsaveview()
      local compared = vertical_cmp(here, to)
      if compared == 0 or (down and compared > 0) or (not down and compared < 0) then
        break
      end
      vim.cmd.normal({ bang = true, args = { key }, mods = { keepjumps = true } })
      local nxt = vim.fn.winsaveview()
      if vertical_cmp(nxt, here) == 0 then
        break
      end
      local next_compared = vertical_cmp(nxt, to)
      if (down and next_compared > 0) or (not down and next_compared < 0) then
        break
      end
      path[#path + 1] = position_of(nxt)
    end
  end)
  pcall(vim.fn.winrestview, saved)
  if not ok then
    error(err)
  end
  if vertical_cmp(path[#path], to) ~= 0 then
    path[#path + 1] = position_of(to)
  end
  return path
end

---@private
---@param win integer
---@param from pint.scroll.View
---@param to pint.scroll.View
---@return pint.scroll.Position[]
local function build_path(win, from, to)
  if math.abs(to.topline - from.topline) > LONG_JUMP then
    return proportional_path(from, to)
  end
  local ok, path = pcall(win_call, win, function()
    return walk_path(from, to)
  end)
  if not ok or type(path) ~= "table" or #path == 0 then
    return proportional_path(from, to)
  end
  return path
end

---@private
---@param progress number
---@param length integer
---@return integer
local function path_index(progress, length)
  if length <= 1 then
    return 1
  end
  local index = math.floor(progress * (length - 1) + 0.5) + 1
  if index < 1 then
    return 1
  end
  if index > length then
    return length
  end
  return index
end

---@private
---@param win integer
---@param pos pint.scroll.Position
---@param lnum integer
---@param col integer
---@param curswant integer
local function apply_partial(win, pos, lnum, col, curswant)
  win_call(win, function()
    vim.fn.winrestview({
      lnum = pos.topline,
      col = 0,
      coladd = 0,
      curswant = curswant,
      topline = pos.topline,
      topfill = pos.topfill,
      leftcol = pos.leftcol,
      skipcol = pos.skipcol,
    })
    local info = vim.fn.getwininfo(win)[1] or {}
    local top = pos.topline
    local bot = info.botline or top
    if bot < top then
      bot = top
    end
    local line = math.max(top, math.min(lnum, bot))
    local closed = vim.fn.foldclosed(line)
    if closed > 0 and closed >= top and closed <= bot then
      line = closed
    end
    vim.fn.winrestview({
      lnum = line,
      col = col,
      coladd = 0,
      curswant = curswant,
      topline = pos.topline,
      topfill = pos.topfill,
      leftcol = pos.leftcol,
      skipcol = pos.skipcol,
    })
  end)
end

---@private
---@param anim pint.scroll.Animation
local function finish(anim)
  if current ~= anim then
    return
  end
  anim.generation = anim.generation + 1
  stop_timer(anim.timer)
  anim.timer = nil
  current = nil
  if not vim.api.nvim_win_is_valid(anim.win) then
    return
  end
  apply_options(anim.win, anim.options)
  if
    vim.api.nvim_win_get_buf(anim.win) == anim.buf and vim.api.nvim_buf_get_changedtick(anim.buf) == anim.changedtick
  then
    pcall(win_call, anim.win, function()
      vim.fn.winrestview(anim.target)
    end)
  end
end

---@private
---@param anim pint.scroll.Animation
---@param generation integer
---@param t number
local function on_tick(anim, generation, t)
  if current ~= anim or anim.generation ~= generation then
    return
  end
  local win_ok = vim.api.nvim_win_is_valid(anim.win)
    and vim.api.nvim_buf_is_valid(anim.buf)
    and vim.api.nvim_win_get_buf(anim.win) == anim.buf
    and vim.api.nvim_get_current_win() == anim.win
    and vim.api.nvim_buf_get_changedtick(anim.buf) == anim.changedtick
  if not win_ok or vim.fn.mode() ~= "n" then
    stop_current(false)
    return
  end
  if t >= 1 then
    finish(anim)
    pcall(vim.cmd.redraw)
    return
  end

  local progress = ease(t)
  local index = path_index(progress, #anim.path)
  local pos = anim.path[index]
  local last = vim.api.nvim_buf_line_count(anim.buf)
  local lnum = math.floor(anim.from.lnum + (anim.target.lnum - anim.from.lnum) * progress + 0.5)
  if lnum < 1 then
    lnum = 1
  elseif lnum > last then
    lnum = last
  end
  local ok, err = xpcall(function()
    apply_partial(anim.win, pos, lnum, anim.from.col, anim.from.curswant)
  end, debug.traceback)
  if not ok then
    last_error = tostring(err)
    stop_current(true)
    return
  end
  pcall(vim.cmd.redraw)
end

---@private
---@param win integer
---@param buf integer
---@param from pint.scroll.View
---@param target pint.scroll.View
---@param options pint.scroll.Options
---@param path pint.scroll.Position[]
local function start_animation(win, buf, from, target, options, path)
  local duration = duration_ms()
  local steps = math.max(#path - 1, 1)
  local frames = math.min(steps, math.max(math.floor(duration / FRAME_MS), 1))
  local interval = math.max(math.floor(duration / frames), 1)
  local timer = vim.uv.new_timer()
  if not timer then
    apply_options(win, options)
    win_call(win, function()
      vim.fn.winrestview(target)
    end)
    return
  end

  ---@type pint.scroll.Animation
  local anim = {
    generation = 1,
    win = win,
    buf = buf,
    timer = timer,
    from = from,
    target = target,
    path = path,
    options = options,
    changedtick = vim.api.nvim_buf_get_changedtick(buf),
    duration = duration,
    interval = interval,
    elapsed = 0,
  }
  current = anim
  local generation = anim.generation
  -- Sample the easing curve immediately so the first frame does not wait a
  -- full interval, and a very short animation still consults `easing`.
  on_tick(anim, generation, 0)
  if current ~= anim then
    return
  end
  local started = tonumber(vim.uv.hrtime()) or 0
  local span = duration * 1000000
  timer:start(interval, interval, function()
    local now = tonumber(vim.uv.hrtime()) or started
    local t = span <= 0 and 1 or math.min((now - started) / span, 1)
    vim.schedule(function()
      on_tick(anim, generation, t)
    end)
  end)
end

---@private
---@param win integer
---@param lhs string
---@param count integer
local function play_now(win, lhs, count)
  local logical ---@type pint.scroll.View?
  local options ---@type pint.scroll.Options?
  if current and current.win == win then
    logical = copy_view(current.target)
    options = current.options
  end
  stop_current(false)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if options then
    apply_options(win, options)
  end
  win_call(win, function()
    if logical then
      vim.fn.winrestview(logical)
    end
    execute(lhs, count)
  end)
end

---@private
---@param win integer
---@param buf integer
---@param lhs string
---@param count integer
local function play_animated(win, buf, lhs, count)
  local visual = copy_view(vim.fn.winsaveview())
  local logical = visual
  local options = capture_options(win)
  if current and current.win == win then
    logical = copy_view(current.target)
    options = current.options
    current.generation = current.generation + 1
    stop_timer(current.timer)
    current.timer = nil
    current = nil
  elseif current then
    stop_current(false)
  end

  apply_options(win, options)
  local target = win_call(win, function()
    vim.fn.winrestview(visual)
    vim.fn.winrestview(logical)
    execute(lhs, count)
    local landed = copy_view(vim.fn.winsaveview())
    vim.fn.winrestview(visual)
    return landed
  end)

  if same_place(visual, target) then
    win_call(win, function()
      vim.fn.winrestview(target)
    end)
    return
  end

  lock_viewport(win, options)
  win_call(win, function()
    vim.fn.winrestview(visual)
  end)
  local path = build_path(win, visual, target)
  win_call(win, function()
    vim.fn.winrestview(visual)
  end)
  start_animation(win, buf, visual, target, options, path)
end

local function lhs_bytes(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, false, true)
end

---@private
---@param candidate string
---@param lhs string
---@return boolean
local function lhs_matches(candidate, lhs)
  return candidate == lhs or lhs_bytes(candidate) == lhs_bytes(lhs)
end

---@private
---@param lhs string
---@return table?
local function global_mapping(lhs)
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
    if lhs_matches(map.lhs, lhs) then
      return map
    end
  end
end

---@private
---@param lhs string
---@return boolean
local function typed_is(lhs)
  return last_typed == lhs_bytes(lhs)
end

---@private
---@param mapping {lhs:string, desc:string, previous:table?}
local function restore_mapping(mapping)
  local found = global_mapping(mapping.lhs)
  if not found or found.desc ~= mapping.desc then
    return
  end

  pcall(vim.keymap.del, "n", mapping.lhs)
  local previous = mapping.previous
  if not previous then
    return
  end

  local opts = {
    desc = previous.desc ~= "" and previous.desc or nil,
    expr = previous.expr == 1,
    nowait = previous.nowait == 1,
    remap = previous.noremap ~= 1,
    script = previous.script == 1,
    silent = previous.silent == 1,
  }
  vim.keymap.set("n", mapping.lhs, previous.callback or previous.rhs or "", opts)
end

local function restore_maps()
  for index = #installed_maps, 1, -1 do
    restore_mapping(installed_maps[index])
  end
  installed_maps = {}
end

---@private
---@param lhs string
local function map_scroll(lhs)
  return function()
    local count = vim.v.count
    M.scroll(lhs, { count = count, immediate = not typed_is(lhs) })
  end
end

local function install_maps()
  for lhs in pairs(COMMANDS) do
    local desc = "pint: smooth scroll " .. lhs
    local previous = global_mapping(lhs)
    vim.keymap.set("n", lhs, map_scroll(lhs), { desc = desc, silent = true })
    installed_maps[#installed_maps + 1] = {
      lhs = lhs,
      desc = desc,
      previous = previous,
    }
  end
end

local function watch_keys()
  vim.on_key(function(_, typed)
    if typed ~= "" then
      last_typed = typed
    end
  end, key_namespace)
end

local function unwatch_keys()
  pcall(vim.on_key, nil, key_namespace)
  last_typed = ""
end

local function ensure_autocmds()
  local group = vim.api.nvim_create_augroup("PintScroll", { clear = true })
  vim.api.nvim_create_autocmd({ "WinClosed", "WinLeave", "BufWipeout" }, {
    group = group,
    callback = function(event)
      if switching > 0 or not current then
        return
      end
      if event.event == "WinClosed" and tonumber(event.match) == current.win then
        stop_current(false)
      elseif event.event == "WinLeave" and vim.api.nvim_get_current_win() == current.win then
        stop_current(false)
      elseif event.event == "BufWipeout" and event.buf == current.buf then
        stop_current(false)
      end
    end,
  })
end

--- Is smooth scrolling currently installed?
---@return boolean
function M.is_enabled()
  return enabled
end

--- Enable smooth scrolling and install its mappings.
function M.enable()
  if enabled and #installed_maps > 0 then
    return
  end
  enabled = true
  watch_keys()
  ensure_autocmds()
  install_maps()
end

--- Disable smooth scrolling, finish any in-flight motion, and restore mappings.
function M.disable()
  enabled = false
  stop_current(true)
  restore_maps()
  unwatch_keys()
  pcall(vim.api.nvim_del_augroup_by_name, "PintScroll")
end

--- Toggle smooth scrolling.
function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

--- Disable smooth scrolling and release timers, mappings, and window options.
function M.restore()
  last_error = nil
  skipped_fast = 0
  M.disable()
end

--- Configure smooth scrolling.
---
--- Mappings are installed only when `enabled` is true. Call `enable()`,
--- `disable()`, or `toggle()` to change that later without repeating setup.
---@param opts? pint.scroll.Config
function M.setup(opts)
  M.restore()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if M.config.enabled then
    M.enable()
  end
end

--- Run a scroll command, animating when it is safe.
---
--- `lhs` is `<C-d>`, `<C-u>`, `<C-f>`, `<C-b>`, `zz`, `zt`, or `zb`.
--- Counts match the builtin commands. `zz`, `zt`, and `zb` take a line number,
--- while `<C-d>` and `<C-u>` use a count as the `'scroll'` amount.
---@param lhs string
---@param opts? {immediate?: boolean, count?: integer}
function M.scroll(lhs, opts)
  opts = opts or {}
  local name = canonical(lhs)
  if not name then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local count = opts.count
  if type(count) ~= "number" then
    count = vim.v.count
  end
  count = math.floor(count)
  if count < 0 then
    count = 0
  end

  local ok, err = xpcall(function()
    if opts.immediate or block_reason(buf) then
      play_now(win, name, count)
    else
      play_animated(win, buf, name, count)
    end
  end, debug.traceback)
  if not ok then
    last_error = tostring(err)
    stop_current(true)
  end
end

M._test = {
  animating = function()
    return current ~= nil and current.timer ~= nil
  end,
  last_error = function()
    return last_error
  end,
  skipped = function()
    return skipped_fast
  end,
  ease = ease,
  -- Step one frame without pumping Neovim's main loop. mini.test runs every
  -- case from the schedule queue, so a real `vim.wait()` lets later cases
  -- start before this one finishes.
  advance = function()
    local anim = current
    if not anim or not anim.timer then
      return
    end
    local duration = anim.duration or 1
    local interval = anim.interval or FRAME_MS
    anim.elapsed = math.min((anim.elapsed or 0) + interval, duration)
    local t = duration <= 0 and 1 or anim.elapsed / duration
    on_tick(anim, anim.generation, t)
  end,
}

return M
