-- Minimal Neovim config: no plugins, nothing to download.
-- Mimics the AstroNvim workflow (snacks picker, file tree, toggle terminal) with built-ins only.
-- Requires Neovim 0.12+. Uses `rg` when available, falls back to `git`/`grep`/pure Lua otherwise.
--
-- Usage: stow nvim-minimal && NVIM_APPNAME=nvim-minimal nvim
--    or: nvim -u /path/to/init.lua

local api = vim.api
local map = vim.keymap.set

vim.g.mapleader = " "
vim.g.maplocalleader = ","

------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------
local opt = vim.opt
opt.clipboard = "unnamedplus"
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.infercase = true
opt.linebreak = true
opt.wrap = true
opt.mouse = "a"
opt.number = true
opt.relativenumber = true
opt.numberwidth = 4
opt.signcolumn = "auto"
opt.cursorline = true
opt.scrolloff = 8
opt.showmatch = true
opt.splitbelow = true
opt.splitright = true
opt.swapfile = false
opt.writebackup = false
opt.undofile = true
opt.updatetime = 300
opt.timeoutlen = 500
opt.history = 100
opt.termguicolors = true
opt.showtabline = 2
opt.virtualedit = "block"
opt.wildoptions = "pum,fuzzy"
opt.completeopt = "menu,menuone,noselect,fuzzy"
opt.autocomplete = true -- built-in completion popup as you type (replaces blink.cmp)
opt.winborder = "rounded"
opt.foldmethod = "indent"
opt.foldlevel = 99

if vim.env.SSH_TTY or vim.env.TMUX then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    vim.g.clipboard = {
      name = "OSC 52",
      copy = { ["+"] = osc52.copy "+", ["*"] = osc52.copy "*" },
      paste = { ["+"] = osc52.paste "+", ["*"] = osc52.paste "*" },
    }
  end
end

vim.diagnostic.config { virtual_text = true, underline = true }

vim.filetype.add { pattern = { [".*/charts/[^/]+/templates/.*%.yaml"] = "helm" } }

api.nvim_create_autocmd("BufEnter", {
  callback = function() vim.opt.formatoptions:remove { "c", "r", "o" } end,
})

api.nvim_create_autocmd("TextYankPost", { callback = function() vim.hl.on_yank() end })

------------------------------------------------------------------------
-- Buffer tabline (replaces heirline's buffer list)
------------------------------------------------------------------------
function _G.MinimalTabline()
  local parts, current = {}, api.nvim_get_current_buf()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
      if name == "" then name = "[No Name]" end
      local hl = buf == current and "%#TabLineSel#" or "%#TabLine#"
      parts[#parts + 1] = hl .. " " .. name:gsub("%%", "%%%%") .. (vim.bo[buf].modified and " ●" or "") .. " "
    end
  end
  return table.concat(parts) .. "%#TabLineFill#"
end
opt.tabline = "%!v:lua.MinimalTabline()"

------------------------------------------------------------------------
-- File tree (netrw)
------------------------------------------------------------------------
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3 -- tree view
vim.g.netrw_browse_split = 4 -- open files in the previous window
vim.g.netrw_altv = 1
vim.g.netrw_winsize = 20
vim.g.netrw_list_hide = [[^\.git/$,^\.DS_Store$]]

------------------------------------------------------------------------
-- Fuzzy picker
------------------------------------------------------------------------
local Picker = {}
local ns = api.nvim_create_namespace "minimal_picker"
local MAX_ITEMS = 1000
local last_opts

api.nvim_set_hl(0, "PickerMatch", { default = true, link = "Special" })

local function rel(path) return vim.fn.fnamemodify(path, ":~:.") end

local function jump(item, how)
  if not item.file then
    if how ~= "edit" then vim.cmd(how == "tab" and "tab split" or how) end
  else
    local cmd = ({ edit = "edit", split = "split", vsplit = "vsplit", tab = "tabedit" })[how]
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(item.file))
  end
  if item.lnum then
    pcall(api.nvim_win_set_cursor, 0, { item.lnum, math.max((item.col or 1) - 1, 0) })
    vim.cmd "normal! zz"
  end
end

--- Open a picker.
--- opts.items: fun(): item[]                      static list, fuzzy filtered with matchfuzzypos()
--- opts.live:  fun(query, done): vim.SystemObj?   re-run on every query change (e.g. grep)
--- item: { text = string, file?, lnum?, col?, bufnr? }
function Picker.open(opts)
  last_opts = opts
  local state = {
    query = opts.query or "",
    items = {},
    lookup = {},
    texts = {},
    shown = {},
    selected = 1,
    gen = 0,
    origin_win = api.nvim_get_current_win(),
    origin_buf = api.nvim_get_current_buf(),
  }

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.max(math.floor(vim.o.lines * 0.7), 8)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  state.prompt_buf = api.nvim_create_buf(false, true)
  state.list_buf = api.nvim_create_buf(false, true)
  vim.bo[state.prompt_buf].bufhidden = "wipe"
  vim.bo[state.list_buf].bufhidden = "wipe"

  state.prompt_win = api.nvim_open_win(state.prompt_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 1,
    style = "minimal",
    title = " " .. opts.title .. " ",
  })
  state.list_win = api.nvim_open_win(state.list_buf, false, {
    relative = "editor",
    row = row + 3,
    col = col,
    width = width,
    height = height - 3,
    style = "minimal",
    focusable = false,
  })
  vim.wo[state.list_win].cursorline = true
  vim.wo[state.list_win].wrap = false

  local function render()
    local shown, positions = {}, nil
    if opts.live or state.query == "" then
      shown = vim.list_slice(state.items, 1, MAX_ITEMS)
    else
      local res = vim.fn.matchfuzzypos(state.texts, state.query, { limit = MAX_ITEMS })
      for i, text in ipairs(res[1]) do
        shown[i] = state.lookup[text]
      end
      positions = res[2]
    end
    state.shown, state.selected = shown, 1

    local lines = vim.tbl_map(function(item) return item.text end, shown)
    api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)
    for i, pos in ipairs(positions or {}) do
      for _, p in ipairs(pos) do
        local start = vim.fn.byteidx(lines[i], p)
        local stop = vim.fn.byteidx(lines[i], p + 1)
        api.nvim_buf_set_extmark(state.list_buf, ns, i - 1, start, { end_col = stop, hl_group = "PickerMatch" })
      end
    end
    api.nvim_win_set_cursor(state.list_win, { 1, 0 })
    api.nvim_win_set_config(state.list_win, { title = (" %d/%d "):format(#shown, #state.items), title_pos = "right" })
  end

  local function set_items(items)
    state.items, state.lookup, state.texts = items, {}, {}
    for i, item in ipairs(items) do
      state.lookup[item.text] = item
      state.texts[i] = item.text
    end
    render()
  end

  local function close()
    if state.closed then return end
    state.closed = true
    last_opts = vim.tbl_extend("force", opts, { query = state.query })
    if state.timer then state.timer:close() end
    if state.job then pcall(state.job.kill, state.job, 15) end
    for _, win in ipairs { state.prompt_win, state.list_win } do
      if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    end
    vim.cmd.stopinsert()
    if api.nvim_win_is_valid(state.origin_win) then api.nvim_set_current_win(state.origin_win) end
  end

  local function choose(how)
    local item = state.shown[state.selected]
    close()
    if item then (opts.on_choose or jump)(item, how) end
  end

  local function move(delta)
    if #state.shown == 0 then return end
    state.selected = (state.selected - 1 + delta) % #state.shown + 1
    api.nvim_win_set_cursor(state.list_win, { state.selected, 0 })
  end

  local function to_quickfix()
    local qf = {}
    for _, item in ipairs(state.shown) do
      if item.file or item.lnum then
        qf[#qf + 1] = {
          filename = item.file,
          bufnr = not item.file and state.origin_buf or nil,
          lnum = item.lnum or 1,
          col = item.col or 1,
          text = item.match or item.text,
        }
      end
    end
    close()
    vim.fn.setqflist(qf, "r")
    vim.cmd.copen()
  end

  local function run_live()
    state.gen = state.gen + 1
    local gen = state.gen
    if state.job then pcall(state.job.kill, state.job, 15) end
    if state.query == "" then return set_items {} end
    state.job = opts.live(state.query, vim.schedule_wrap(function(items)
      if not state.closed and gen == state.gen then set_items(items) end
    end))
  end

  local function on_change()
    state.query = api.nvim_buf_get_lines(state.prompt_buf, 0, 1, false)[1] or ""
    if not opts.live then return render() end
    state.timer = state.timer or vim.uv.new_timer()
    state.timer:start(100, 0, vim.schedule_wrap(function()
      if not state.closed then run_live() end
    end))
  end

  local keys = {
    ["<CR>"] = function() choose "edit" end,
    ["<C-s>"] = function() choose "split" end,
    ["<C-v>"] = function() choose "vsplit" end,
    ["<C-t>"] = function() choose "tab" end,
    ["<C-q>"] = to_quickfix,
    ["<Down>"] = function() move(1) end,
    ["<C-n>"] = function() move(1) end,
    ["<C-j>"] = function() move(1) end,
    ["<Up>"] = function() move(-1) end,
    ["<C-p>"] = function() move(-1) end,
    ["<C-k>"] = function() move(-1) end,
    ["<Esc>"] = close,
    ["<C-c>"] = close,
  }
  for lhs, fn in pairs(keys) do
    map({ "i", "n" }, lhs, fn, { buffer = state.prompt_buf, nowait = true })
  end
  map("n", "q", close, { buffer = state.prompt_buf, nowait = true })

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = state.prompt_buf, callback = on_change })
  api.nvim_create_autocmd("BufLeave", { buffer = state.prompt_buf, once = true, callback = close })

  api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, { state.query })
  vim.cmd "startinsert!"
  if opts.live then
    run_live()
  else
    set_items(opts.items())
  end
end

function Picker.resume()
  if last_opts then Picker.open(last_opts) end
end

-- Sources --------------------------------------------------------------

local has_rg = vim.fn.executable "rg" == 1

local function systemlist(cmd)
  local ok, res = pcall(function() return vim.system(cmd, { text = true }):wait() end)
  if not ok or res.code ~= 0 then return nil end
  return vim.split(res.stdout, "\n", { trimempty = true })
end

function Picker.files(all)
  Picker.open {
    title = all and "All Files" or "Files",
    items = function()
      local files
      if has_rg then
        files = systemlist(vim.list_extend({ "rg", "--files", "--hidden", "-g", "!.git" }, all and { "--no-ignore" } or {}))
      elseif not all then
        files = systemlist { "git", "ls-files", "--cached", "--others", "--exclude-standard" }
      end
      if not files then -- pure Lua fallback
        files = {}
        local skip = { [".git"] = true, node_modules = not all or nil }
        for name, type in vim.fs.dir(".", { depth = 30, skip = function(dir) return not skip[vim.fs.basename(dir)] end }) do
          if type == "file" then files[#files + 1] = name end
        end
      end
      return vim.tbl_map(function(f) return { text = f, file = f } end, files)
    end,
  }
end

function Picker.grep(opts)
  opts = opts or {}
  Picker.open {
    title = opts.fixed and "Grep (literal)" or "Grep",
    query = opts.query,
    live = function(query, done)
      local cmd
      if has_rg then
        cmd = { "rg", "--vimgrep", "--smart-case", "--hidden", "-g", "!.git", "--max-columns=300", "--max-count=100" }
        if opts.all then table.insert(cmd, "--no-ignore") end
        if opts.fixed then table.insert(cmd, "--fixed-strings") end
      else
        cmd = { "grep", "-rnI", "--exclude-dir=.git", opts.fixed and "-F" or "-E" }
      end
      vim.list_extend(cmd, { "--", query })
      if not has_rg then table.insert(cmd, ".") end
      return vim.system(cmd, { text = true }, function(res)
        local items = {}
        for line in vim.gsplit(res.stdout or "", "\n", { trimempty = true }) do
          local file, lnum, col, text
          if has_rg then
            file, lnum, col, text = line:match "^(.-):(%d+):(%d+):(.*)$"
          else
            file, lnum, text = line:match "^%./(.-):(%d+):(.*)$"
          end
          if file then
            items[#items + 1] = {
              text = ("%s:%s: %s"):format(file, lnum, vim.trim(text)),
              match = text,
              file = file,
              lnum = tonumber(lnum),
              col = tonumber(col),
            }
            if #items >= MAX_ITEMS then break end
          end
        end
        done(items)
      end)
    end,
  }
end

function Picker.lines()
  local buf = api.nvim_get_current_buf()
  Picker.open {
    title = "Lines",
    items = function()
      local items = {}
      for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find "%S" then items[#items + 1] = { text = ("%4d  %s"):format(i, line), lnum = i } end
      end
      return items
    end,
  }
end

function Picker.buffers()
  Picker.open {
    title = "Buffers",
    items = function()
      local bufs = vim.fn.getbufinfo { buflisted = 1 }
      table.sort(bufs, function(a, b) return a.lastused > b.lastused end)
      local items = {}
      for _, b in ipairs(bufs) do
        local name = b.name ~= "" and rel(b.name) or ("[No Name] " .. b.bufnr)
        items[#items + 1] = { text = name, file = b.name ~= "" and b.name or nil, lnum = b.lnum }
      end
      return items
    end,
  }
end

function Picker.recent()
  Picker.open {
    title = "Recent",
    items = function()
      local items, seen = {}, {}
      for _, f in ipairs(vim.v.oldfiles) do
        local text = rel(f)
        if not seen[text] and vim.fn.filereadable(f) == 1 then
          seen[text] = true
          items[#items + 1] = { text = text, file = f }
        end
      end
      return items
    end,
  }
end

------------------------------------------------------------------------
-- Floating terminal (replaces toggleterm)
------------------------------------------------------------------------
local function float_win(buf)
  local width, height = math.floor(vim.o.columns * 0.8), math.floor(vim.o.lines * 0.8)
  return api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
  })
end

-- Run `cmd` in a terminal in the current buffer, closing its window and buffer when it exits
local function run_in_term(cmd, win, buf)
  local function on_exit()
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  vim.fn.jobstart(cmd, { term = true, on_exit = on_exit })
  vim.cmd.startinsert()
end

local term = {}
local function toggle_term()
  if term.win and api.nvim_win_is_valid(term.win) then
    api.nvim_win_hide(term.win)
    term.win = nil
  elseif term.buf and api.nvim_buf_is_valid(term.buf) then
    term.win = float_win(term.buf)
    vim.cmd.startinsert()
  else
    term.buf = api.nvim_create_buf(false, true)
    term.win = float_win(term.buf)
    run_in_term(vim.o.shell, term.win, term.buf)
  end
end

local function lazygit()
  local buf = api.nvim_create_buf(false, true)
  run_in_term("lazygit", float_win(buf), buf)
end

------------------------------------------------------------------------
-- Buffers
------------------------------------------------------------------------
local function close_buffer()
  local buf = api.nvim_get_current_buf()
  local alt = vim.fn.bufnr "#"
  if alt > 0 and alt ~= buf and vim.fn.buflisted(alt) == 1 then
    vim.cmd.buffer(alt)
  else
    vim.cmd.bprevious()
  end
  if api.nvim_get_current_buf() == buf then vim.cmd.enew() end
  pcall(vim.cmd, "confirm bdelete " .. buf)
end

local function visual_selection()
  local lines = vim.fn.getregion(vim.fn.getpos "v", vim.fn.getpos ".", { type = vim.fn.mode() })
  return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Mappings (same keys as the AstroNvim config)
------------------------------------------------------------------------
-- Core
map("n", "<Leader>w", "<Cmd>confirm qall<CR>", { desc = "Quit" })
map("n", "<Leader>e", "<Cmd>Lexplore<CR>", { desc = "File Explorer" })
map("n", "<Leader>o", "<Cmd>Lexplore %:p:h<CR>", { desc = "File Explorer (current file)" })
map("i", "fd", "<Esc>", { desc = "Escape" })
map("n", "<Esc>", "<Cmd>nohlsearch<CR>")

-- Windows
map("n", "<C-h>", "<C-w>h", { desc = "Move to left split" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to below split" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to above split" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right split" })

-- Buffers
map("n", "<Tab>", function() vim.cmd.bnext { count = vim.v.count1 } end, { desc = "Next buffer" })
map("n", "<S-Tab>", function() vim.cmd.bprevious { count = vim.v.count1 } end, { desc = "Previous buffer" })
map("n", "<Leader><Tab>", Picker.buffers, { desc = "Buffers list" })
map("n", "<Leader>q", close_buffer, { desc = "Close buffer" })
map("n", "<Leader>bd", close_buffer, { desc = "Delete buffer" })

-- Files
map("n", "<Leader><Space>", function() Picker.files() end, { desc = "Find files" })
map("n", "<Leader>fF", function() Picker.files(true) end, { desc = "Find all files" })
map("n", "<Leader>fg", function() Picker.files() end, { desc = "Find git files" })
map("n", "<Leader>fr", Picker.recent, { desc = "Recent" })
map("n", "<Leader>fs", Picker.recent, { desc = "Find recent files" })
map("n", "<Leader>ff", Picker.lines, { desc = "Find lines in buffer" })

-- Grep
map("n", "<Leader>/", function() Picker.grep() end, { desc = "Grep" })
map("n", "<Leader>fw", function() Picker.grep { all = true } end, { desc = "Grep all files" })
map("n", "<Leader>fc", function() Picker.grep { query = vim.fn.expand "<cword>", fixed = true } end, { desc = "Find word under cursor" })
map("v", "<Leader>fc", function() Picker.grep { query = visual_selection(), fixed = true } end, { desc = "Find selection" })
map("n", "<Leader>f<CR>", Picker.resume, { desc = "Resume" })

-- Terminal
map({ "n", "t" }, "<C-\\>", toggle_term, { desc = "Toggle terminal" })
map("t", "fd", [[<C-\><C-n>]], { desc = "Terminal normal mode" })

-- Git (only if lazygit is installed)
if vim.fn.executable "lazygit" == 1 then
  map("n", "<Leader>gg", lazygit, { desc = "Lazygit" })
end
