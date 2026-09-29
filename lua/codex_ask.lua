-- codex_ask.lua -----------------------------------------------------------
-- A "learning box": ask Codex a question in a small floating prompt and read
-- the answer in a NORMAL Neovim markdown buffer (not a live TUI). Because the
-- answer is plain buffer text you can move the cursor, scroll, search and yank
-- freely — none of the cursor-snapping you get when navigating inside Codex's
-- interactive terminal UI.
--
-- Flow:
--   <leader>xF            open the ask prompt (centered float)
--     <C-s> / <CR><CR>    submit the question
--     <Esc> / q           cancel
--   -> a "Codex" answer float opens with a spinner, then fills with the reply.
--   In the answer float:
--     i / a               ask a FOLLOW-UP (continues the same thread)
--     q / <Esc>           close
--     (normal editing)    hjkl / <C-d> / /search / y to yank — all work
--
-- Continuity: the first question starts a thread; follow-ups use
-- `codex exec resume --last` so the conversation is remembered per project.
-- Safety: runs with the read-only sandbox by default (a learning box shouldn't
-- edit your files); override with vim.g.codex_ask_sandbox.
---------------------------------------------------------------------------

local M = {}

-- Per-project flag: have we already started a Codex thread here this session?
local started = {}
-- Handles for the currently open answer float + its running job.
local answer = { buf = nil, win = nil, job = nil }

-- Resolve `codex` even when i3 launches Neovim with a stripped PATH that omits
-- ~/.local/bin (same fallback the Codex box uses).
local function codex_cmd()
  if vim.fn.executable("codex") == 1 then return "codex" end
  for _, p in ipairs({
    vim.fn.expand("~/.local/bin/codex"),
    vim.fn.expand("~/bin/codex"),
    "/usr/local/bin/codex",
    "/usr/bin/codex",
  }) do
    if vim.fn.executable(p) == 1 then return p end
  end
  return nil
end

-- Nearest project root above the current file (or cwd).
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

-- Open a centered floating window over <buf>. frac_w/frac_h are 0-1 of the UI.
local function open_float(buf, frac_w, frac_h, title, row_bias)
  local cols, lines = vim.o.columns, vim.o.lines
  local w = math.floor(cols * frac_w)
  local h = math.floor(lines * frac_h)
  local row = math.floor((lines - h) / 2) + (row_bias or 0)
  local col = math.floor((cols - w) / 2)
  return vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.max(w, 20),
    height = math.max(h, 3),
    row = math.max(row, 1),
    col = math.max(col, 0),
    style = "minimal",
    border = "rounded",
    title = title and (" " .. title .. " ") or nil,
    title_pos = title and "center" or nil,
  })
end

local function set_lines(buf, lines)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

-- Render (or refresh) the answer float as a readable markdown document.
local function show_answer(lines, opts)
  opts = opts or {}
  if not (answer.buf and vim.api.nvim_buf_is_valid(answer.buf)) then
    answer.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[answer.buf].bufhidden = "wipe"
    vim.bo[answer.buf].filetype = "markdown"
  end
  set_lines(answer.buf, lines)

  if not (answer.win and vim.api.nvim_win_is_valid(answer.win)) then
    answer.win = open_float(answer.buf, 0.72, 0.72, "Codex")
    local wo = vim.wo[answer.win]
    wo.wrap = true
    wo.linebreak = true
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.cursorline = true
    wo.conceallevel = 2
    wo.concealcursor = "nc"

    local kmap = function(lhs, fn, d)
      vim.keymap.set("n", lhs, fn, { buffer = answer.buf, nowait = true, silent = true, desc = d })
    end
    local close = function()
      if answer.job then pcall(function() answer.job:kill(9) end); answer.job = nil end
      if answer.win and vim.api.nvim_win_is_valid(answer.win) then
        vim.api.nvim_win_close(answer.win, true)
      end
      answer.win = nil
    end
    kmap("q", close, "Close")
    kmap("<Esc>", close, "Close")
    kmap("i", function() M.ask(true) end, "Ask a follow-up")
    kmap("a", function() M.ask(true) end, "Ask a follow-up")
  end
  if opts.cursor_top and answer.win and vim.api.nvim_win_is_valid(answer.win) then
    pcall(vim.api.nvim_win_set_cursor, answer.win, { 1, 0 })
  end
end

-- Run `codex exec` for <prompt> under <root>, streaming the reply into the
-- answer float. Uses -o <file> so we capture the clean FINAL message (not the
-- event log), and resume --last for follow-ups to keep the thread.
local function run_exec(prompt, root)
  local codex = codex_cmd()
  if not codex then
    show_answer({ "# Codex not found", "",
      "`codex` is not on PATH. Install the Codex CLI and run `codex login`." })
    return
  end

  local outfile = vim.fn.tempname()
  local sandbox = vim.g.codex_ask_sandbox or "read-only"
  local resume = started[root] == true

  local cmd = { codex, "exec" }
  if resume then vim.list_extend(cmd, { "resume", "--last" }) end
  vim.list_extend(cmd, {
    "--color", "never",
    "--skip-git-repo-check",
    "-s", sandbox,
    "-C", root,
    "-o", outfile,
    prompt,
  })

  local header = {
    "> " .. prompt:gsub("\n", "\n> "),
    "",
    "⟳  Asking Codex…  (q / <Esc> to cancel)",
  }
  show_answer(header, { cursor_top = true })

  answer.job = vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
    answer.job = nil
    local body
    local ok, data = pcall(vim.fn.readfile, outfile)
    if ok and type(data) == "table" and #data > 0 then
      body = data
    elseif res.stdout and #res.stdout > 0 then
      body = vim.split(res.stdout, "\n", { trimempty = true })
    else
      body = {}
    end
    pcall(vim.fn.delete, outfile)

    if res.code ~= 0 and #body == 0 then
      local err = vim.split(res.stderr or "", "\n", { trimempty = true })
      local lines = { "# Codex error (exit " .. res.code .. ")", "" }
      vim.list_extend(lines, #err > 0 and err or { "(no output)" })
      show_answer(lines, { cursor_top = true })
      return
    end

    started[root] = true
    local lines = { "### ❯ " .. prompt:gsub("\n", " "), "" }
    vim.list_extend(lines, body)
    vim.list_extend(lines, { "", "---", "*i/a — follow-up · q — close*" })
    show_answer(lines, { cursor_top = true })
  end))
end

-- Open the ask prompt. follow=true keeps the current thread (a follow-up).
function M.ask(follow)
  local root = project_root()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"

  local title = follow and "Follow-up → Codex" or "Ask Codex"
  local win = open_float(buf, 0.6, 0.18, title, -3)
  local wo = vim.wo[win]
  wo.wrap = true
  wo.linebreak = true
  wo.number = false
  wo.signcolumn = "no"

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function submit()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    text = vim.trim(text)
    close()
    if text == "" then return end
    run_exec(text, root)
  end

  vim.keymap.set("i", "<C-s>", function() vim.cmd("stopinsert"); submit() end,
    { buffer = buf, silent = true, desc = "Submit" })
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, silent = true, desc = "Submit" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true, desc = "Cancel" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true, desc = "Cancel" })

  vim.cmd("startinsert")
end

-- Start a brand-new thread (forget the remembered session for this project).
function M.ask_new()
  started[project_root()] = nil
  M.ask(false)
end

return M
