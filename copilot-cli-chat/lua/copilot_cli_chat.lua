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
  vim.keymap.set("n", "q", function()
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
  vim.b[buf].cc_busy = 0
  vim.b[buf].cc_is_chat = 1
  new_input(buf)
  set_keymaps(buf)
  apply_fold_opts(buf)
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
  vim.list_extend(block, { "", "## Copilot", "", "_...thinking..._" })
  vim.api.nvim_buf_set_lines(buf, start, -1, false, block)
  local think_row = vim.api.nvim_buf_line_count(buf) - 1
  vim.b[buf].cc_busy = 1
  save(buf)

  local args = { ASK, "--session", vim.b[buf].cc_sid, "--dir", vim.b[buf].cc_dir }
  local mode = vim.b[buf].cc_mode or "agent"
  if mode == "read" then
    args[#args + 1] = "--repo"
  elseif mode == "agent" then
    args[#args + 1] = "--agent"
  end

  vim.system(args, { stdin = prompt, text = true }, function(res)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.b[buf].cc_busy = 0
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
      vim.api.nvim_buf_set_lines(buf, think_row, think_row + 1, false, rlines)
      local n = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, n, n, false, { "", "---", "" })
      new_input(buf)
      apply_fold_opts(buf)
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
      init_buffer(buf, existing, (entry.dir ~= "" and entry.dir or nil), "agent")
    end
    -- one-time upgrade: chats rendered before reasoning-folds existed
    if not vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, 12, false), CT_VERSION) then
      M.refresh(buf)
    end
    vim.cmd("startinsert")
    notify_mode(buf)
    return
  end

  local base = slugify(entry.title ~= "" and entry.title or entry.id):sub(1, 40)
  local file = CHAT_DIR .. "/" .. base .. "-" .. entry.id:sub(1, 8) .. ".md"
  local dir = (entry.dir ~= "" and entry.dir) or vim.fn.getcwd()
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
  vim.b[buf].cc_cloud = cloud and 1 or 0
  vim.b[buf].cc_busy = 0
  vim.b[buf].cc_is_chat = 1
  new_input(buf)
  set_keymaps(buf)
  apply_fold_opts(buf)
  save(buf)
  vim.cmd("startinsert")
  notify_mode(buf)
end

-- Lay down a fresh, empty chat in `buf` bound to (sid, dir), ready to type.
local function fresh_chat(buf, sid, dir, mode)
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
  vim.b[buf].cc_cloud = 0
  vim.b[buf].cc_busy = 0
  vim.b[buf].cc_is_chat = 1
  new_input(buf)
  set_keymaps(buf)
  apply_fold_opts(buf)
  save(buf)
end

-- Rebind `buf` (whose file is `file`) to a chosen session and reload it in
-- place. `entry.id == "__new__"` starts a brand-new session for the project.
local function bind_and_load(buf, file, entry)
  if entry.id == "__new__" then
    local dir = read_line(file .. ".dir") or vim.b[buf].cc_dir or project_root()
    local sid = uuid()
    write_line(file .. ".sid", sid)
    write_line(file .. ".dir", dir)
    fresh_chat(buf, sid, dir, "agent")
    vim.cmd("startinsert")
    vim.notify("Started a new session for this chat", vim.log.levels.INFO)
    return
  end
  local cloud = entry.remote
  if cloud == nil then cloud = is_remote(entry.id) end
  local dir = (entry.dir ~= "" and entry.dir) or read_line(file .. ".dir") or project_root()
  write_line(file .. ".sid", entry.id)
  write_line(file .. ".dir", dir)
  vim.b[buf].cc_sid = entry.id
  vim.b[buf].cc_dir = dir
  vim.b[buf].cc_cloud = cloud and 1 or 0
  vim.b[buf].cc_mode = "agent"
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
  save(buf)
  local thoughts = 0
  for _, l in ipairs(transcript) do
    if l == FOLD_OPEN then thoughts = thoughts + 1 end
  end
  vim.notify("Refreshed (" .. #transcript .. " lines, " .. thoughts .. " reasoning blocks)", vim.log.levels.INFO)
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
  vim.api.nvim_create_user_command("CopilotCliSessions", function() M.switch() end,
    { desc = "Switch Copilot CLI chat session (in place)" })
  vim.api.nvim_create_user_command("CopilotCliSwitch", function() M.switch() end,
    { desc = "Switch this chat to another session (or start a new one)" })
  vim.api.nvim_create_user_command("CopilotCliRefresh", function() M.refresh() end,
    { desc = "Rebuild this chat from its event log (adds reasoning folds)" })

  -- Re-apply fold settings whenever a chat buffer is shown in a window.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("CopilotCliChat", { clear = true }),
    callback = function(a)
      if vim.b[a.buf] and vim.b[a.buf].cc_is_chat == 1 then
        apply_fold_opts(a.buf)
      end
    end,
  })

  vim.keymap.set("n", "<leader>ai", function() M.toggle({ mode = "agent" }) end,
    { desc = "Copilot CLI: toggle agent chat" })
  vim.keymap.set("n", "<leader>as", function() M.switch() end,
    { desc = "Copilot CLI: switch session (in place / new)" })
end

return M
