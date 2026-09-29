-- codex_term.lua ----------------------------------------------------------
-- Option A: the OpenAI Codex CLI as a first-class, project-scoped panel living
-- inside Neovim. It uses your ChatGPT Plus login (run `codex login` once), so
-- there is no API key and no per-token billing.
--
-- One persistent Codex terminal is kept PER PROJECT ROOT, so the conversation,
-- context and agent state stay alive while you toggle it in and out. Codex can
-- read and edit the project's files and run commands, like the Copilot CLI —
-- you just never leave Neovim.
--
-- LAYOUT
--   Default is a docked VERTICAL SPLIT on the right, so your file and Codex are
--   visible side by side ("both open"). Because `splitright` is on, it opens on
--   the right. A fullscreen-ish centered FLOAT is available too, and you can set
--   a per-machine default with vim.g.codex_direction = "vertical" | "horizontal"
--   | "float", or the width with vim.g.codex_width (0-1 fraction of columns).
--
-- Keymaps (registered in lua/plugins/codex_terminal.lua):
--   <leader>xx  toggle Codex for the current project (side split)
--   <leader>xX  toggle Codex scoped to Neovim's :pwd
--   <leader>xF  toggle Codex as a centered float
--   <leader>xf  attach the current file to the Codex prompt (@path)
--   <leader>xr  resume a past Codex session for this project (float picker)
--   <leader>xR  resume from ALL projects' sessions (float picker)
--   <leader>xl  continue the most recent Codex session (no picker)
-- Inside the Codex window:
--   q            (normal mode) hide Codex without killing the session
--   <Esc><Esc>   leave terminal-insert mode, then scroll freely (k / <C-u> /
--                /search) — Codex runs inline (--no-alt-screen) so Neovim keeps
--                scrollback, and auto-scroll is OFF for Codex so a live spinner
--                (e.g. the Astra model's animation) no longer yanks you back to
--                the bottom on every repaint. Re-enable with
--                vim.g.codex_auto_scroll = true.
---------------------------------------------------------------------------

local M = {}

local function Terminal()
  local ok, term = pcall(require, "toggleterm.terminal")
  if not ok then return nil end
  return term.Terminal
end

-- Cache of live terminals, keyed by "<dir>\0<direction>", so each project keeps
-- its own session AND a split/float can coexist without clobbering each other.
local terms = {}

local function default_direction()
  return vim.g.codex_direction or "vertical"
end

local function default_width()
  return tonumber(vim.g.codex_width) or 0.42
end

-- Append inline mode to a codex command. `--no-alt-screen` makes Codex render
-- INLINE and preserve terminal scrollback, so inside Neovim you can hit
-- <Esc><Esc> and scroll up (k / <C-u> / search) to read history WITHOUT the
-- alt-screen TUI repainting and snapping the cursor back to the prompt.
-- Opt out (classic full-screen TUI) with: vim.g.codex_no_alt_screen = false
local function with_inline(cmd)
  if vim.g.codex_no_alt_screen == false then return cmd end
  return cmd .. " --no-alt-screen"
end

-- Walk upward from the current file (or cwd) to the nearest project marker.
local function project_root()
  local name = vim.api.nvim_buf_get_name(0)
  local start = (name ~= "" and vim.fn.filereadable(name) == 1)
      and vim.fs.dirname(name)
      or (vim.uv or vim.loop).cwd()
  local marker = vim.fs.find(
    { ".git", ".hg", "package.json", "Cargo.toml", "go.mod", "Makefile", "pyproject.toml" },
    { path = start, upward = true }
  )[1]
  return marker and vim.fs.dirname(marker) or start
end

local function checks_ok()
  if not Terminal() then
    vim.notify("toggleterm.nvim is required for the Codex terminal.", vim.log.levels.ERROR)
    return false
  end
  if vim.fn.executable("codex") == 0 then
    vim.notify("`codex` not found on PATH. Install Codex CLI, then run `codex login`.",
      vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Size for split directions: columns for vertical, rows for horizontal.
local function size_for(direction)
  if direction == "vertical" then
    return function() return math.floor(vim.o.columns * default_width()) end
  elseif direction == "horizontal" then
    return function() return math.floor(vim.o.lines * 0.35) end
  end
  return nil
end

-- Save cursor + scroll position when the panel is hidden, so toggling it back
-- on returns you to exactly where you were (e.g. scrolled up reading output in
-- normal mode) instead of snapping to the prompt at the bottom.
local function on_close(term)
  local win = term.window
  if win and vim.api.nvim_win_is_valid(win) then
    term._codex_view = vim.api.nvim_win_call(win, function()
      return vim.fn.winsaveview()
    end)
  end
end

-- Common on_open: map `q` to hide (keeps the session alive), strip UI chrome
-- (no numbers/signcolumn/fold gutter) so Codex's own TUI renders full-width and
-- unbroken. On the FIRST open drop into insert at the prompt; on later opens
-- restore the saved view and stay in normal mode so your reading position is
-- preserved. In the window: insert (terminal) mode types to Codex, <Esc><Esc>
-- drops to normal mode for hjkl/scroll navigation.
local function on_open(term)
  vim.keymap.set("n", "q", function() term:close() end,
    { buffer = term.bufnr, nowait = true, desc = "Hide Codex" })

  local win = term.window
  if win and vim.api.nvim_win_is_valid(win) then
    local wo = vim.wo[win]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.foldcolumn = "0"
    wo.cursorline = false
    wo.list = false
  end

  if term._codex_view and win and vim.api.nvim_win_is_valid(win) then
    local view = term._codex_view
    -- Restore now, then again on the next ticks: reopening the float resizes
    -- the PTY, so the live codex TUI repaints and Neovim's terminal would
    -- otherwise follow that output back down to the prompt. Re-asserting the
    -- saved view (in normal mode) after the repaint lands keeps you where you
    -- were reading.
    local function restore()
      if not vim.api.nvim_win_is_valid(win) then return end
      vim.api.nvim_win_call(win, function()
        vim.cmd("stopinsert")
        vim.fn.winrestview(view)
      end)
    end
    restore()
    vim.defer_fn(restore, 30)
    vim.defer_fn(restore, 120)
  else
    vim.cmd("startinsert")
  end
end

-- Centered floating window (not full-screen): a comfortable reading card that
-- leaves a margin around the editor. Rounded border, no title bar clutter.
local FLOAT_OPTS = {
  border = "rounded",
  width = function() return math.floor(vim.o.columns * 0.82) end,
  height = function() return math.floor(vim.o.lines * 0.82) end,
}

-- Get (or lazily create) the persistent Codex terminal for a dir + direction.
local function get_term(dir, direction, cmd)
  direction = direction or default_direction()
  local key = dir .. "\0" .. direction
  if terms[key] and vim.api.nvim_buf_is_valid(terms[key].bufnr or -1) then
    return terms[key]
  end

  local t = Terminal():new({
    cmd = cmd or with_inline("codex"),
    dir = dir,
    hidden = true,
    direction = direction,
    size = size_for(direction),
    close_on_exit = true,
    auto_scroll = vim.g.codex_auto_scroll == true,
    display_name = "Codex",
    float_opts = direction == "float" and FLOAT_OPTS or nil,
    on_open = on_open,
    on_close = on_close,
  })
  terms[key] = t
  return t
end

-- Toggle the Codex panel for the current PROJECT ROOT (default: side split).
function M.toggle()
  if not checks_ok() then return end
  get_term(project_root(), default_direction()):toggle()
end

-- Toggle Codex scoped to Neovim's current working directory.
function M.toggle_cwd()
  if not checks_ok() then return end
  get_term((vim.uv or vim.loop).cwd(), default_direction()):toggle()
end

-- Toggle Codex as a centered float (independent of the side-split instance).
function M.toggle_float()
  if not checks_ok() then return end
  get_term(project_root(), "float"):toggle()
end

-- Attach the current file to the Codex prompt as an @-mention, opening the
-- panel if needed. Lets you say "explain @src/foo.c" without typing paths.
function M.add_file()
  if not checks_ok() then return end
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("No file in the current buffer to attach.", vim.log.levels.WARN)
    return
  end

  local t = get_term(project_root(), default_direction())
  if not t:is_open() then t:open() end

  local rel = vim.fn.fnamemodify(path, ":.")
  if t.job_id then
    vim.fn.chansend(t.job_id, "@" .. rel .. " ")
    vim.schedule(function() vim.cmd("startinsert") end)
  end
end

-- A throwaway terminal that runs an arbitrary codex command (used for resume),
-- honoring the chosen layout so it sits beside your file too.
local function run(cmd, name, direction)
  direction = direction or default_direction()
  Terminal():new({
    cmd = cmd,
    dir = project_root(),
    direction = direction,
    size = size_for(direction),
    close_on_exit = true,
    auto_scroll = vim.g.codex_auto_scroll == true,
    display_name = name,
    float_opts = direction == "float" and FLOAT_OPTS or nil,
    on_open = on_open,
    on_close = on_close,
  }):toggle()
end

-- Resume a past session via Codex's picker (in a centered float so the session
-- list is easy to read). all=true lists every project.
function M.resume(all)
  if not checks_ok() then return end
  run(with_inline(all and "codex resume --all" or "codex resume"),
    all and "Codex resume (all)" or "Codex resume", "float")
end

-- Continue the most recent Codex session for this project (no picker).
function M.resume_last()
  if not checks_ok() then return end
  run(with_inline("codex resume --last"), "Codex (last)", "float")
end

return M
