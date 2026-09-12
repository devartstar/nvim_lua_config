-- copilot_cli_chat.lua
-- A tiny chat UI over the GitHub Copilot CLI, living in a Markdown buffer.
--
-- Commands:
--   :CopilotCli [chat|read|agent]   open chat for the current project
--                                   (default: agent). read = view files only,
--                                   agent = can edit files & run commands.
--   :CopilotCliSessions             pick and switch to a saved chat thread
--   :CopilotCliSend                 send the current input
--
-- Default keymaps:
--   <leader>ai   toggle the agent chat for the current project (open / hide)
--   <leader>as   switch between saved chat sessions (picker)
--
-- In the chat buffer:
--   <Enter> (normal) or <C-s> (insert)   send the message you typed
--   q                                     hide the chat window
--
-- Each project gets its own Markdown file under ~/.copilot-cli/chats/ and a
-- pinned Copilot session id (sidecar .sid), so conversation memory persists
-- across sends AND reboots. Resume the same thread in a terminal with:
--   copilot --resume=<id>
--
-- Installed by the Copilot setup helper. Remove by deleting this folder and
-- ~/.config/nvim/lua/plugins/copilot_cli_chat.lua.

local M = {}

local ns = vim.api.nvim_create_namespace("copilot_cli_chat")
local ns_prog = vim.api.nvim_create_namespace("copilot_cli_chat_progress")

-- In-flight requests, keyed by buffer. Holds the vim.system handle, the poll
-- timer, timing, cancel flag, and event-log tail offset for live activity.
local jobs = {}
-- ASCII spinner (renders in any font — no Nerd/emoji glyphs needed).
local SPINNER = { "|", "/", "-", "\\" }


-- Resolve helper scripts from the plugin's own bin/ (portable across machines),
-- falling back to ~/.local/bin if they aren't bundled.
local PLUGIN_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local function bin(name)
  local bundled = PLUGIN_DIR .. "/bin/" .. name
  if vim.fn.executable(bundled) == 1 then return bundled end
  return vim.fn.expand("~/.local/bin/" .. name)
end
local ASK = bin("copilot-ask")
local TRANSCRIPT = bin("copilot-transcript")
local THOUGHTS = bin("copilot-thoughts")
local CHAT_DIR = vim.fn.expand("~/.copilot-cli/chats")

-- Model used for chats. Default to Claude Opus 4.8 (highest quality, matches
-- the model your older app sessions used). Change per-chat with :CopilotCliModel
-- or <leader>am; override the global default by setting vim.g.copilot_cli_model.
local DEFAULT_MODEL = "claude-opus-4.8"
-- Curated pick list (freeform also allowed). 'auto' lets Copilot choose.
local MODELS = {
  "claude-opus-4.8",
  "claude-sonnet-5",
  "claude-haiku-4.5",
  "claude-opus-4.7",
  "gpt-5.4",
  "gpt-5.3-codex",
  "auto",
}

local function default_model()
  return vim.g.copilot_cli_model or DEFAULT_MODEL
end

-- Humanize a token count: 1863866 -> "1.9M", 15982 -> "16k".
local function humanize(n)
  n = tonumber(n) or 0
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.0fk", n / 1e3) end
  return tostring(n)
end

-- Cumulative token usage for a session from the local usage table.
local function usage_stats(sid)
  if not sid then return nil end
  local db = vim.fn.expand("~/.copilot/session-store.db")
  if vim.fn.filereadable(db) == 0 then return nil end
  local sql = ([[SELECT COALESCE(SUM(input_tokens),0) inp, COALESCE(SUM(output_tokens),0) outp,
      COUNT(DISTINCT turn_index) turns
      FROM assistant_usage_events WHERE session_id='%s';]]):format(sid:gsub("'", ""))
  local out = vim.fn.system({ "sqlite3", "-readonly", "-json", db, sql })
  if vim.v.shell_error ~= 0 or out == "" then return nil end
  local ok, arr = pcall(vim.json.decode, out)
  if not ok or not arr or not arr[1] then return nil end
  return arr[1]
end

-- Set the per-window winbar to: model + working dir + token usage.
local function set_winbar(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  local model = vim.b[buf].cc_model or default_model()
  local tag = vim.b[buf].cc_cloud == 1 and "cloud" or "local"
  local parts = { "%#Title#  Copilot%*  ", model, "  %#Comment#[", tag, "]%*" }
  local dir = vim.b[buf].cc_dir
  if dir and dir ~= "" then
    parts[#parts + 1] = "  %#Directory#" .. vim.fn.fnamemodify(dir, ":~") .. "%*"
  end
  local u = usage_stats(vim.b[buf].cc_sid)
  if u then
    parts[#parts + 1] = string.format("  %%#Comment#· up %s down %s · %d turns%%*",
      humanize(u.inp), humanize(u.outp), u.turns or 0)
  end
  vim.wo[win].winbar = table.concat(parts)
end

-- Fold reasoning ("thoughts") blocks. Markers are HTML comments with no spaces
-- so they are valid 'foldmarker' values and stay invisible in rendered markdown.
local FOLD_OPEN = "<!--ct:think-->"
local FOLD_CLOSE = "<!--ct:/think-->"
-- Hidden marker stamped into rendered chats; its absence means the file was
-- rendered by an older version and should be upgraded (to add reasoning folds).
local CT_VERSION = "<!--ct:v2-->"

function _G.CopilotChatFoldText()
  local n = vim.v.foldend - vim.v.foldstart + 1
  return "  [+] Copilot's reasoning (" .. n .. " lines) - za toggle, zR all"
end

local function apply_fold_opts(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  vim.wo[win].foldmethod = "marker"
  vim.wo[win].foldmarker = FOLD_OPEN .. "," .. FOLD_CLOSE
  vim.wo[win].foldtext = "v:lua.CopilotChatFoldText()"
  vim.wo[win].foldenable = true
  vim.wo[win].foldlevel = 0
end

-- Wrap reasoning text in fold markers for insertion into the buffer.
local function fold_lines(reasoning)
  if not reasoning or reasoning:match("^%s*$") then return {} end
  local out = { FOLD_OPEN, "_Copilot's reasoning:_", "" }
  for _, l in ipairs(vim.split(reasoning, "\n", { plain = true })) do
    out[#out + 1] = l
  end
  out[#out + 1] = FOLD_CLOSE
  out[#out + 1] = ""
  return out
end

local MODE_LABEL = {
  chat = "chat (no tools)",
  read = "read-only (view files)",
  agent = "AGENT - can edit files & run commands",
}

-- A session is "cloud/remote" if it was run by the cloud agent, marked by an
-- mc_task_id in its workspace.yaml (host_type='github' is NOT reliable — local
-- CLI sessions in a GitHub repo have it too).
local function is_remote(id)
  if not id or id == "" then return false end
  local f = io.open(vim.fn.expand("~/.copilot/session-state/" .. id .. "/workspace.yaml"), "r")
  if not f then return false end
  local remote = false
  for line in f:lines() do
    if line:match("^mc_task_id:%s*%S") then remote = true break end
  end
  f:close()
  return remote
end

-- ── helpers ────────────────────────────────────────────────────────────────

local function uuid()
  local f = io.open("/proc/sys/kernel/random/uuid", "r")
  if f then
    local s = f:read("*l")
    f:close()
    if s and #s >= 8 then
      return s
    end
  end
  math.randomseed(os.time() + os.clock() * 1000)
  return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end

local function read_line(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  if s and #s > 0 then return s end
  return nil
end

local function write_line(path, s)
  local f = io.open(path, "w")
  if f then f:write(s); f:close() end
end

local function project_root()
  local cwd = vim.fn.getcwd()
  -- Guard: if nvim's cwd is inside the chat store (rare), use the global cwd so
  -- we resolve the user's real project, not ~/.copilot-cli/chats.
  if cwd:sub(1, #CHAT_DIR) == CHAT_DIR then
    cwd = vim.fn.getcwd(-1, -1)
  end
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
    return out[1]
  end
  return cwd
end

local function slugify(path)
  local s = path:gsub("^" .. vim.pesc(vim.fn.expand("~")), "home")
  s = s:gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if s == "" then s = "global" end
  return s
end

local function chat_file_for(root)
  return CHAT_DIR .. "/" .. slugify(root) .. ".md"
end

-- Resolve the model pinned for a chat file (persisted in a .model sidecar),
-- defaulting to the global default and backfilling the sidecar.
local function resolve_model(file)
  local m = read_line(file .. ".model")
  if not m or m == "" then
    m = default_model()
    write_line(file .. ".model", m)
  end
  return m
end

-- Resolve (sid, dir) for a chat file, creating/backfilling sidecars.
local function meta(file, root)
  local sidf, dirf = file .. ".sid", file .. ".dir"
  local sid = read_line(sidf)
  if not sid or #sid < 8 then
    sid = uuid()
    write_line(sidf, sid)
  end
  local dir = root or read_line(dirf) or vim.fn.getcwd()
  write_line(dirf, dir)
  return sid, dir
end

local function save(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! keepalt write")
    end)
  end
end

local function notify_mode(buf)
  if vim.b[buf].cc_cloud == 1 then
    vim.notify(
      "Copilot [cloud session - continues LOCALLY]  ·  <Enter> send · q hide",
      vim.log.levels.INFO
    )
    return
  end
  vim.notify(
    "Copilot [" .. (MODE_LABEL[vim.b[buf].cc_mode] or "?") .. "]  ·  <Enter> send · q hide",
    vim.log.levels.INFO
  )
end

-- Append a fresh input region at the end and drop a gravity-left extmark on it
-- so we always know where the user's next message starts, regardless of any
-- "##" markdown the model emitted above. A virtual hint line shows how to send.
local function new_input(buf)
  local n = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, n, n, false, { "" })
  local row = vim.api.nvim_buf_line_count(buf) - 1
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local hint = vim.b[buf].cc_cloud == 1
      and "  [ cloud session - typing continues it LOCALLY  ·  Enter = send  ·  q = close ]"
      or "  [ Enter = send  ·  C-j = newline  ·  q = close ]"
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
    right_gravity = false,
    virt_lines = { { { hint, "Comment" } } },
    virt_lines_above = true,
  })
  vim.b[buf].cc_mark = id
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { row + 1, 0 })
  end
end

-- Submit the current input (used by all the submit keymaps).
local function do_submit(buf)
  vim.cmd("stopinsert")
  vim.schedule(function() M.send(buf) end)
end

local function set_keymaps(buf)
  local o = { buffer = buf, silent = true, nowait = true }
  -- Normal mode: Enter sends.
  vim.keymap.set("n", "<CR>", function() M.send(buf) end, o)
  -- Insert mode: Enter sends too (natural chat UX). If the blink.cmp completion
  -- menu is open, Enter accepts the completion instead of sending.
  vim.keymap.set("i", "<CR>", function()
    local ok, blink = pcall(require, "blink.cmp")
    if ok and type(blink.is_visible) == "function" and blink.is_visible() then
      if type(blink.accept) == "function" then blink.accept() end
      return
    end
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
      return
    end
    do_submit(buf)
  end, o)
  -- Insert mode: Ctrl-J inserts a real newline for multi-line prompts.
  vim.keymap.set("i", "<C-j>", function()
    vim.api.nvim_put({ "", "" }, "c", false, true)
  end, o)
  -- Keep Ctrl-S as an alternate submit (muscle memory).
  vim.keymap.set("i", "<C-s>", function() do_submit(buf) end, o)
  -- Cancel an in-flight request (normal mode). Note: insert-mode <C-c> keeps
  -- its default (leave insert mode) so typing isn't disrupted.
  vim.keymap.set("n", "<C-c>", function() M.cancel(buf) end, o)
  vim.keymap.set("n", "q", function()
    if jobs[buf] then
      vim.notify("A request is running — press <C-c> to cancel first (or wait)", vim.log.levels.WARN)
      return
    end
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then pcall(vim.api.nvim_win_close, win, false) end
  end, o)
end

-- Attach chat state + keymaps to a freshly shown buffer (new or reopened).
local function init_buffer(buf, file, root, mode)
  local sid, dir = meta(file, root)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "hide"

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Copilot chat — " .. vim.fn.fnamemodify(file, ":t:r"),
      "",
      "> session `" .. sid .. "`",
      "> mode: " .. (MODE_LABEL[mode] or mode),
      "> resume in terminal: `copilot --resume=" .. sid .. "`",
      CT_VERSION,
      "",
      "---",
      "",
    })
  end

  vim.b[buf].cc_sid = sid
  vim.b[buf].cc_dir = dir
  vim.b[buf].cc_mode = mode
  vim.b[buf].cc_model = resolve_model(file)
  vim.b[buf].cc_busy = 0
  vim.b[buf].cc_is_chat = 1
  new_input(buf)
  set_keymaps(buf)
  apply_fold_opts(buf)
  set_winbar(buf)
end

-- Show a chat file in a right-hand split (focus it if already visible).
local function show(file)
  local bufnr = vim.fn.bufnr(file)
  local win = (bufnr ~= -1) and vim.fn.bufwinid(bufnr) or -1
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit " .. vim.fn.fnameescape(file))
  end
  return vim.api.nvim_get_current_buf()
end

-- ── progress + cancel ──────────────────────────────────────────────────────

-- Read new lines appended to the session event log since the last poll and
-- return a short description of the latest activity (tool being run, etc.).
local function latest_activity(state)
  local path = state.ev_path
  if not path then return state.activity end
  local st = vim.uv.fs_stat(path)
  if not st or st.size <= state.ev_off then return state.activity end
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return state.activity end
  local data = vim.uv.fs_read(fd, st.size - state.ev_off, state.ev_off) or ""
  vim.uv.fs_close(fd)
  local last_nl = data:match(".*()\n")           -- index just after final newline
  if not last_nl then return state.activity end   -- no complete line yet
  state.ev_off = state.ev_off + last_nl - 1
  for line in data:sub(1, last_nl - 1):gmatch("[^\n]+") do
    if line:sub(1, 1) == "{" then
      local ok, o = pcall(vim.json.decode, line)
      if ok and type(o) == "table" then
        local t, d = o.type, o.data or {}
        if t == "tool.execution_start" then
          local name = d.toolName or "tool"
          local arg
          if type(d.arguments) == "table" then
            arg = d.arguments.command or d.arguments.path or d.arguments.query
                or d.arguments.pattern or d.arguments.filePath
          end
          state.steps = (state.steps or 0) + 1
          state.activity = "running " .. name .. (arg and (": " .. tostring(arg):gsub("%s+", " ")) or "")
        elseif t == "assistant.turn_start" then
          state.activity = "thinking"
        elseif t == "assistant.message" then
          state.activity = "writing response"
        end
      end
    end
  end
  return state.activity
end

-- Tear down a finished/cancelled job's timer and state.
local function finish_job(buf)
  local st = jobs[buf]
  if not st then return end
  if st.timer then
    st.timer:stop()
    if not st.timer:is_closing() then st.timer:close() end
  end
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns_prog, 0, -1)
  end
  jobs[buf] = nil
  vim.b[buf].cc_busy = 0
end

-- Kill a process and all its descendants (specific PIDs, walked via /proc).
-- vim.system' child shares Neovim's process group, so we must NOT kill by
-- group; we enumerate descendants and signal each one individually.
local function kill_tree(root, signal)
  if not root then return end
  local parent_of = {}
  local ok = pcall(function()
    for name in vim.fs.dir("/proc") do
      local pid = tonumber(name)
      if pid then
        local f = io.open("/proc/" .. pid .. "/stat", "r")
        if f then
          local data = f:read("*a"); f:close()
          local rp = data and data:match("^.*()%)")   -- index of last ')'
          if rp then
            local ppid = data:sub(rp + 2):match("^%S+%s+(%d+)")
            if ppid then parent_of[pid] = tonumber(ppid) end
          end
        end
      end
    end
  end)
  -- collect descendants of root
  local victims = {}
  if ok then
    local changed = true
    local inset = { [root] = true }
    while changed do
      changed = false
      for pid, ppid in pairs(parent_of) do
        if inset[ppid] and not inset[pid] then
          inset[pid] = true; victims[#victims + 1] = pid; changed = true
        end
      end
    end
  end
  -- kill deepest-first, then the root
  for i = #victims, 1, -1 do pcall(vim.uv.kill, victims[i], signal) end
  pcall(vim.uv.kill, root, signal)
end

-- Cancel the in-flight request for a chat buffer.
function M.cancel(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = jobs[buf]
  if not st then
    vim.notify("No Copilot request is running here", vim.log.levels.INFO)
    return
  end
  st.cancelled = true
  -- SIGTERM the copilot process AND its descendants (tool subprocesses, server)
  kill_tree(st.handle and st.handle.pid, 15)
  local row = st.think_row
  local secs = math.floor((vim.uv.now() - st.start) / 1000)
  finish_job(buf)
  if vim.api.nvim_buf_is_valid(buf) and row and row < vim.api.nvim_buf_line_count(buf) then
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false,
      { "_(cancelled after " .. secs .. "s" .. (st.steps and st.steps > 0 and (", " .. st.steps .. " steps") or "") .. ")_" })
    local n = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, n, n, false, { "", "---", "" })
    new_input(buf)
    apply_fold_opts(buf)
    save(buf)
  end
  vim.notify("Copilot request cancelled", vim.log.levels.INFO)
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.send(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.b[buf].cc_sid then
    vim.notify("Not a Copilot chat buffer", vim.log.levels.WARN)
    return
  end
  if vim.b[buf].cc_busy == 1 then
    vim.notify("Copilot is still answering…", vim.log.levels.WARN)
    return
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, vim.b[buf].cc_mark, {})
  if not pos or not pos[1] then
    vim.notify("Lost the input marker; reopen with :CopilotCli", vim.log.levels.ERROR)
    return
  end
  local start = pos[1]
  local plines = vim.api.nvim_buf_get_lines(buf, start, -1, false)
  while #plines > 0 and plines[#plines]:match("^%s*$") do table.remove(plines) end
  while #plines > 0 and plines[1]:match("^%s*$") do table.remove(plines, 1) end
  if #plines == 0 then
    vim.notify("Type a message first", vim.log.levels.WARN)
    return
  end
  local prompt = table.concat(plines, "\n")

  local block = { "## You", "" }
  for _, l in ipairs(plines) do block[#block + 1] = l end
  vim.list_extend(block, { "", "## Copilot", "", "_working..._" })
  vim.api.nvim_buf_set_lines(buf, start, -1, false, block)
  local think_row = vim.api.nvim_buf_line_count(buf) - 1
  vim.b[buf].cc_busy = 1
  save(buf)

  local args = { ASK, "--session", vim.b[buf].cc_sid, "--dir", vim.b[buf].cc_dir }
  local model = vim.b[buf].cc_model or default_model()
  if model ~= "" then
    args[#args + 1] = "--model"
    args[#args + 1] = model
  end
  local mode = vim.b[buf].cc_mode or "agent"
  if mode == "read" then
    args[#args + 1] = "--repo"
  elseif mode == "agent" then
    args[#args + 1] = "--agent"
  end

  -- Per-request state for live progress + cancellation. The anchor row is fixed
  -- (nothing edits above it mid-request), so the progress line updates in place.
  local ev_path = vim.fn.expand("~/.copilot/session-state/" .. vim.b[buf].cc_sid .. "/events.jsonl")
  local ev_st = vim.uv.fs_stat(ev_path)
  local state = {
    start = vim.uv.now(),
    frame = 0,
    cancelled = false,
    ev_path = ev_path,
    ev_off = ev_st and ev_st.size or 0,   -- only report NEW activity
    activity = "thinking",
    steps = 0,
    think_row = think_row,
  }
  jobs[buf] = state

  -- Poll timer: animate spinner, elapsed time, and current activity in place.
  state.timer = vim.uv.new_timer()
  state.timer:start(150, 150, vim.schedule_wrap(function()
    if not jobs[buf] or state.cancelled or not vim.api.nvim_buf_is_valid(buf) then return end
    local row = state.think_row
    if row >= vim.api.nvim_buf_line_count(buf) then return end
    state.frame = state.frame + 1
    local secs = math.floor((vim.uv.now() - state.start) / 1000)
    local act = latest_activity(state) or "thinking"
    local line = string.format("_%s  %ds · %s · <C-c> to cancel_",
      SPINNER[state.frame % #SPINNER + 1], secs, act)
    pcall(vim.api.nvim_buf_set_lines, buf, row, row + 1, false, { line })
  end))

  state.handle = vim.system(args, { stdin = prompt, text = true }, function(res)
    vim.schedule(function()
      if state.cancelled then return end
      if not vim.api.nvim_buf_is_valid(buf) then finish_job(buf); return end
      local row = state.think_row
      finish_job(buf)
      local resp
      if res.code == 0 and res.stdout and #res.stdout > 0 then
        resp = res.stdout
      else
        resp = "[!] copilot error (exit " .. tostring(res.code) .. ")\n" .. (res.stderr or "")
      end
      resp = resp:gsub("\r\n", "\n"):gsub("%s+$", "")
      local rlines = {}
      -- prepend Copilot's reasoning (folded) if this turn recorded any
      local reasoning = ""
      if res.code == 0 then
        reasoning = vim.fn.system({ THOUGHTS, vim.b[buf].cc_sid })
        if vim.v.shell_error ~= 0 then reasoning = "" end
      end
      vim.list_extend(rlines, fold_lines(reasoning))
      vim.list_extend(rlines, vim.split(resp, "\n", { plain = true }))
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, rlines)
      local n = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, n, n, false, { "", "---", "" })
      new_input(buf)
      apply_fold_opts(buf)
      set_winbar(buf)
      save(buf)
    end)
  end)
end

-- Open the chat for the current project. opts.mode = chat|read|agent
function M.open(opts)
  opts = opts or {}
  local mode = opts.mode or "agent"
  vim.fn.mkdir(CHAT_DIR, "p")
  local root = project_root()
  local file = chat_file_for(root)
  local buf = show(file)
  if not vim.b[buf].cc_sid then
    init_buffer(buf, file, root, mode)
    if not vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, 12, false), CT_VERSION) then
      M.refresh(buf)
    end
    apply_fold_opts(buf)
    vim.cmd("startinsert")
  else
    vim.b[buf].cc_mode = mode
    apply_fold_opts(buf)
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, vim.b[buf].cc_mark, {})
    local win = vim.fn.bufwinid(buf)
    if pos and pos[1] and win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { pos[1] + 1, 0 })
    end
    vim.cmd("startinsert")
  end
  notify_mode(buf)
end

-- Toggle the current project's chat window (hide if visible, else open).
function M.toggle(opts)
  local file = chat_file_for(project_root())
  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 then
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      pcall(vim.api.nvim_win_close, win, false)
      return
    end
  end
  M.open(opts)
end

-- List sessions from the Copilot session store — includes CLI sessions, app
-- sessions, AND our own nvim chats. Newest first: {id,loc,title,dir,ts}.
local function store_sessions()
  local db = vim.fn.expand("~/.copilot/session-store.db")
  if vim.fn.filereadable(db) == 0 then return {} end
  local sql = [[
    SELECT id,
      COALESCE(NULLIF(TRIM(summary),''),'(untitled)') AS title,
      COALESCE(cwd,'') AS dir,
      datetime(COALESCE(updated_at,created_at)) AS ts
    FROM sessions
    WHERE COALESCE(cwd,'') NOT LIKE '/tmp/.mount%'
    ORDER BY COALESCE(updated_at,created_at) DESC
    LIMIT 100;]]
  local out = vim.fn.system({ "sqlite3", "-readonly", "-json", db, sql })
  if vim.v.shell_error ~= 0 or out == "" then return {} end
  local ok, arr = pcall(vim.json.decode, out)
  if not ok or type(arr) ~= "table" then return {} end
  for _, e in ipairs(arr) do
    e.title = (e.title or "(untitled)"):gsub("%s+", " "):sub(1, 70)
    e.dir = e.dir or ""
    e.ts = e.ts or ""
    e.remote = is_remote(e.id)
  end
  return arr
end

-- Find an existing chat file already bound to a given session id.
local function md_for_sid(id)
  for _, sf in ipairs(vim.fn.globpath(CHAT_DIR, "*.sid", false, true)) do
    if read_line(sf) == id then return (sf:gsub("%.sid$", "")) end
  end
  return nil
end

-- Open a specific store session in a buffer, rendering its past transcript the
-- first time (so existing CLI/app chats are readable), then continue it.
-- Cloud-origin sessions are labelled but still continuable (locally).
function M.open_session(entry)
  vim.fn.mkdir(CHAT_DIR, "p")
  local cloud = entry.remote
  if cloud == nil then cloud = is_remote(entry.id) end
  local existing = md_for_sid(entry.id)
  if existing then
    local buf = show(existing)
    vim.b[buf].cc_cloud = cloud and 1 or 0
    if not vim.b[buf].cc_sid then
      init_buffer(buf, existing, project_root(), "agent")
    end
    vim.b[buf].cc_model = vim.b[buf].cc_model or resolve_model(existing)
    -- one-time upgrade: chats rendered before reasoning-folds existed
    if not vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, 12, false), CT_VERSION) then
      M.refresh(buf)
    end
    set_winbar(buf)
    vim.cmd("startinsert")
    notify_mode(buf)
    return
  end

  local base = slugify(entry.title ~= "" and entry.title or entry.id):sub(1, 40)
  local file = CHAT_DIR .. "/" .. base .. "-" .. entry.id:sub(1, 8) .. ".md"
  -- Working dir = the project you have open in nvim NOW, not the session's
  -- original (possibly stale worktree) cwd. This is where you can edit/verify
  -- code, so the agent must operate there and can read uncommitted changes.
  local dir = project_root()
  write_line(file .. ".sid", entry.id)
  write_line(file .. ".dir", dir)

  local buf = show(file)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "hide"

  local content = {
    "# Copilot chat - " .. entry.title,
    "",
    "> session `" .. entry.id .. "` (" .. (cloud and "cloud" or "local") .. ")",
  }
  if cloud then
    content[#content + 1] = "> cloud session - typing here continues it LOCALLY (new turns are local)"
  else
    content[#content + 1] = "> mode: " .. (MODE_LABEL.agent)
  end
  content[#content + 1] = "> resume in terminal: `copilot --resume=" .. entry.id .. "`"
  content[#content + 1] = CT_VERSION
  vim.list_extend(content, { "", "---", "" })

  local transcript = vim.fn.systemlist({ TRANSCRIPT, entry.id })
  if vim.v.shell_error ~= 0 or #transcript == 0 then
    transcript = { "_Could not load this session's transcript._" }
  end
  vim.list_extend(content, transcript)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  vim.b[buf].cc_sid = entry.id
  vim.b[buf].cc_dir = dir
  vim.b[buf].cc_mode = "agent"
  vim.b[buf].cc_model = resolve_model(file)
  vim.b[buf].cc_cloud = cloud and 1 or 0
  vim.b[buf].cc_busy = 0
  vim.b[buf].cc_is_chat = 1
  new_input(buf)
  set_keymaps(buf)
  apply_fold_opts(buf)
  set_winbar(buf)
  save(buf)
  vim.cmd("startinsert")
  notify_mode(buf)
end

-- Lay down a fresh, empty chat in `buf` bound to (sid, dir), ready to type.
local function fresh_chat(buf, sid, dir, mode, model)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "hide"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# Copilot chat - " .. (dir ~= "" and vim.fn.fnamemodify(dir, ":t") or "chat"),
    "",
    "> session `" .. sid .. "` (local, new)",
    "> mode: " .. (MODE_LABEL[mode] or mode),
    "> resume in terminal: `copilot --resume=" .. sid .. "`",
    CT_VERSION,
    "",
    "---",
    "",
  })
  vim.b[buf].cc_sid = sid
  vim.b[buf].cc_dir = dir
  vim.b[buf].cc_mode = mode
  vim.b[buf].cc_model = model or default_model()
  vim.b[buf].cc_cloud = 0
  vim.b[buf].cc_busy = 0
  vim.b[buf].cc_is_chat = 1
  new_input(buf)
  set_keymaps(buf)
  apply_fold_opts(buf)
  set_winbar(buf)
  save(buf)
end

-- Rebind `buf` (whose file is `file`) to a chosen session and reload it in
-- place. `entry.id == "__new__"` starts a brand-new session for the project.
-- The working dir always tracks the project you have open in nvim now, so
-- switching to an old session never drags along its stale worktree cwd.
local function bind_and_load(buf, file, entry)
  local model = resolve_model(file)
  local dir = project_root()
  if entry.id == "__new__" then
    local sid = uuid()
    write_line(file .. ".sid", sid)
    write_line(file .. ".dir", dir)
    fresh_chat(buf, sid, dir, "agent", model)
    vim.cmd("startinsert")
    vim.notify("Started a new session for this chat (dir: " .. dir .. ")", vim.log.levels.INFO)
    return
  end
  local cloud = entry.remote
  if cloud == nil then cloud = is_remote(entry.id) end
  write_line(file .. ".sid", entry.id)
  write_line(file .. ".dir", dir)
  vim.b[buf].cc_sid = entry.id
  vim.b[buf].cc_dir = dir
  vim.b[buf].cc_cloud = cloud and 1 or 0
  vim.b[buf].cc_mode = "agent"
  vim.b[buf].cc_model = model
  vim.b[buf].cc_is_chat = 1
  set_keymaps(buf)
  M.refresh(buf)
  vim.cmd("startinsert")
  notify_mode(buf)
end

-- Switch the CURRENT chat panel to a different session (or a brand-new one),
-- rebinding this project's chat file and reloading in place. This is how you
-- change which session <leader>ai continues.
function M.switch()
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].cc_is_chat ~= 1 then
    M.open({ mode = "agent" })
    buf = vim.api.nvim_get_current_buf()
  end
  local file = vim.api.nvim_buf_get_name(buf)
  local cur = vim.b[buf].cc_sid

  local list = { { id = "__new__", title = "+ New session (fresh)", dir = "", ts = "", remote = false } }
  vim.list_extend(list, store_sessions())

  vim.ui.select(list, {
    prompt = "Switch this chat to session:",
    format_item = function(e)
      if e.id == "__new__" then return e.title end
      local tag = e.remote and "[cloud]" or "[local]"
      local dirb = e.dir ~= "" and vim.fn.fnamemodify(e.dir, ":t") or "-"
      local mark = (e.id == cur) and "  <- current" or ""
      return string.format("%-7s %s  ·  %s  ·  %s%s", tag, e.title, dirb, e.ts, mark)
    end,
  }, function(choice)
    if choice then bind_and_load(buf, file, choice) end
  end)
end

-- Backwards-compatible alias.
function M.sessions()
  M.switch()
end

-- Rebuild the current chat buffer from the session's event log, so existing
-- chats gain the foldable "reasoning" blocks (and any turns made elsewhere).
function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local sid = vim.b[buf].cc_sid
  if not sid then
    vim.notify("Not a Copilot chat buffer", vim.log.levels.WARN)
    return
  end
  local cloud = vim.b[buf].cc_cloud == 1

  -- preserve any unsent draft in the current input region
  local draft = {}
  if vim.b[buf].cc_mark then
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, vim.b[buf].cc_mark, {})
    if pos and pos[1] then
      draft = vim.api.nvim_buf_get_lines(buf, pos[1], -1, false)
    end
  end
  while #draft > 0 and draft[#draft]:match("^%s*$") do table.remove(draft) end

  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
  local content = {
    "# Copilot chat - " .. name,
    "",
    "> session `" .. sid .. "` (" .. (cloud and "cloud" or "local") .. ")",
  }
  if cloud then
    content[#content + 1] = "> cloud session - typing here continues it LOCALLY (new turns are local)"
  end
  content[#content + 1] = "> resume in terminal: `copilot --resume=" .. sid .. "`"
  content[#content + 1] = CT_VERSION
  vim.list_extend(content, { "", "---", "" })
  local transcript = vim.fn.systemlist({ TRANSCRIPT, sid })
  if vim.v.shell_error ~= 0 or #transcript == 0 then
    transcript = { "_Could not load this session's transcript._" }
  end
  vim.list_extend(content, transcript)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  new_input(buf)
  if #draft > 0 then
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, vim.b[buf].cc_mark, {})
    if pos and pos[1] then
      vim.api.nvim_buf_set_lines(buf, pos[1], -1, false, draft)
    end
  end
  apply_fold_opts(buf)
  set_winbar(buf)
  save(buf)
  local thoughts = 0
  for _, l in ipairs(transcript) do
    if l == FOLD_OPEN then thoughts = thoughts + 1 end
  end
  vim.notify("Refreshed (" .. #transcript .. " lines, " .. thoughts .. " reasoning blocks)", vim.log.levels.INFO)
end

-- Set the model for the current chat (persisted per-chat). No arg -> picker.
function M.set_model(model)
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].cc_is_chat ~= 1 then
    vim.notify("Open a Copilot chat first (<leader>ai)", vim.log.levels.WARN)
    return
  end
  local function apply(m)
    if not m or m == "" then return end
    vim.b[buf].cc_model = m
    write_line(vim.api.nvim_buf_get_name(buf) .. ".model", m)
    set_winbar(buf)
    vim.notify("Model for this chat set to: " .. m, vim.log.levels.INFO)
  end
  if model and model ~= "" then
    apply(model)
    return
  end
  vim.ui.select(MODELS, {
    prompt = "Model for this chat (current: " .. (vim.b[buf].cc_model or default_model()) .. ")",
  }, function(choice) apply(choice) end)
end

-- Set the working directory the agent operates in for the current chat
-- (persisted per-chat). No arg -> the project you have open in nvim now.
-- This is what lets the agent read your uncommitted/unstaged code.
function M.set_dir(path)
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].cc_is_chat ~= 1 then
    vim.notify("Open a Copilot chat first (<leader>ai)", vim.log.levels.WARN)
    return
  end
  local dir
  if path and path ~= "" then
    dir = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("/$", "")
  else
    dir = project_root()
  end
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.notify("Not a directory: " .. dir, vim.log.levels.ERROR)
    return
  end
  vim.b[buf].cc_dir = dir
  write_line(vim.api.nvim_buf_get_name(buf) .. ".dir", dir)
  set_winbar(buf)
  vim.notify("Agent working dir for this chat: " .. dir, vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("CopilotCli", function(a)
    local mode = (a.args ~= "" and a.args) or "agent"
    if not MODE_LABEL[mode] then
      vim.notify("Unknown mode '" .. mode .. "' (use chat|read|agent)", vim.log.levels.ERROR)
      return
    end
    M.open({ mode = mode })
  end, {
    nargs = "?",
    complete = function() return { "chat", "read", "agent" } end,
    desc = "Open Copilot CLI chat [chat|read|agent]",
  })
  vim.api.nvim_create_user_command("CopilotCliSend", function() M.send() end,
    { desc = "Send the current Copilot CLI chat input" })
  vim.api.nvim_create_user_command("CopilotCliCancel", function() M.cancel() end,
    { desc = "Cancel the in-flight Copilot request" })
  vim.api.nvim_create_user_command("CopilotCliSessions", function() M.switch() end,
    { desc = "Switch Copilot CLI chat session (in place)" })
  vim.api.nvim_create_user_command("CopilotCliSwitch", function() M.switch() end,
    { desc = "Switch this chat to another session (or start a new one)" })
  vim.api.nvim_create_user_command("CopilotCliRefresh", function() M.refresh() end,
    { desc = "Rebuild this chat from its event log (adds reasoning folds)" })
  vim.api.nvim_create_user_command("CopilotCliModel", function(a) M.set_model(a.args) end, {
    nargs = "?",
    complete = function() return MODELS end,
    desc = "Set the model for this Copilot chat",
  })
  vim.api.nvim_create_user_command("CopilotCliDir", function(a) M.set_dir(a.args) end, {
    nargs = "?",
    complete = "dir",
    desc = "Set the agent working dir for this chat (default: current project)",
  })

  -- Re-apply fold + winbar whenever a chat buffer is shown in a window.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("CopilotCliChat", { clear = true }),
    callback = function(a)
      if vim.b[a.buf] and vim.b[a.buf].cc_is_chat == 1 then
        apply_fold_opts(a.buf)
        set_winbar(a.buf)
      end
    end,
  })

  vim.keymap.set("n", "<leader>ai", function() M.toggle({ mode = "agent" }) end,
    { desc = "Copilot CLI: toggle agent chat" })
  vim.keymap.set("n", "<leader>as", function() M.switch() end,
    { desc = "Copilot CLI: switch session (in place / new)" })
  vim.keymap.set("n", "<leader>am", function() M.set_model() end,
    { desc = "Copilot CLI: set model for this chat" })
  vim.keymap.set("n", "<leader>ad", function() M.set_dir() end,
    { desc = "Copilot CLI: set working dir to current project" })
end

return M
