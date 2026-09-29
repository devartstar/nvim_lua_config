-- Per-folder chat sessions + branching for CopilotChat.nvim.
--
-- CopilotChat has a single live chat buffer, but it can save/load named
-- histories. This module namespaces those histories PER PROJECT FOLDER and adds
-- a session workflow on top:
--
--   * multiple named sessions per folder (save / load / list / delete)
--   * "branch": snapshot the current conversation under a new name and keep
--     talking on the copy, leaving the original session untouched
--
-- Sessions live in:  stdpath('data')/copilotchat_history/<folder>-<hash>/<name>.json
--
-- Keymaps (also see plugins/copilot.lua):
--   <leader>css  save session (prompts; defaults to the current one)
--   <leader>csl  load a session (picker)
--   <leader>csb  branch the current conversation into a new session
--   <leader>csn  new / reset (start an empty conversation)
--   <leader>csd  delete a session (picker)
--   <leader>csi  info: current session name + list

local M = {}

-- name of the session the live buffer is currently associated with, keyed by
-- project dir, so continued saves target the right file.
M._current = {}

local function chat()
  return require("CopilotChat")
end

-- Default session name: the active taskwarrior task (slugified) when one is
-- running, else the given fallback. Always editable at the prompt.
local function task_default(fallback)
  local ok, tn = pcall(require, "task_notes")
  if ok and tn.active_task_name then
    local d = tn.active_task_name()
    if d then
      local slug = d:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
      if slug ~= "" then return slug:sub(1, 50) end
    end
  end
  return fallback
end

-- Per-folder history directory: readable folder name + short path hash so two
-- different folders that share a basename never collide.
function M.dir(cwd)
  cwd = cwd or vim.fn.getcwd()
  local name = vim.fn.fnamemodify(cwd, ":t")
  if name == "" then name = "root" end
  local hash = vim.fn.sha256(cwd):sub(1, 8)
  local dir = vim.fn.stdpath("data") .. "/copilotchat_history/" .. name .. "-" .. hash
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.current()
  return M._current[M.dir()]
end

-- List saved session names in the current folder (newest first).
function M.list()
  local dir = M.dir()
  local files = vim.fn.globpath(dir, "*.json", false, true)
  table.sort(files, function(a, b)
    return (vim.uv or vim.loop).fs_stat(a).mtime.sec > (vim.uv or vim.loop).fs_stat(b).mtime.sec
  end)
  return vim.tbl_map(function(f)
    return vim.fn.fnamemodify(f, ":t:r")
  end, files)
end

-- Save the live conversation. Prompts for a name, defaulting to the current
-- session (or "default").
function M.save(name)
  local dir = M.dir()
  local function do_save(n)
    if not n or n == "" then return end
    chat().save(n, dir)
    M._current[dir] = n
    vim.notify("Saved chat session: " .. n, vim.log.levels.INFO)
  end
  if name then
    do_save(name)
  else
    vim.ui.input({ prompt = "Save session as: ", default = task_default(M.current() or "default") }, do_save)
  end
end

-- Load a session (opens a picker when no name is given).
function M.load(name)
  local dir = M.dir()
  local function do_load(n)
    if not n or n == "" then return end
    chat().load(n, dir)
    M._current[dir] = n
    chat().open()
    vim.notify("Loaded chat session: " .. n, vim.log.levels.INFO)
  end
  if name then
    do_load(name)
    return
  end
  local sessions = M.list()
  if vim.tbl_isempty(sessions) then
    vim.notify("No saved sessions in this folder yet", vim.log.levels.WARN)
    return
  end
  vim.ui.select(sessions, { prompt = "Load chat session:" }, do_load)
end

-- Branch: snapshot the CURRENT conversation under a new name and continue on
-- it. The previously active session file is left as it was.
function M.branch(name)
  local dir = M.dir()
  local function do_branch(n)
    if not n or n == "" then return end
    chat().open() -- ensure the live buffer/messages exist
    chat().save(n, dir)
    M._current[dir] = n
    vim.notify("Branched into new session: " .. n .. "  (original left intact)", vim.log.levels.INFO)
  end
  local base = M.current() or "default"
  vim.ui.input({ prompt = "Branch current chat into: ", default = base .. "-branch" }, do_branch)
end

-- Start a fresh conversation, auto-named after the active task (editable).
function M.new()
  chat().reset()
  local dir = M.dir()
  M._current[dir] = nil
  chat().open()
  vim.ui.input({ prompt = "New chat name: ", default = task_default("chat") }, function(n)
    if n and n ~= "" then
      chat().save(n, dir)
      M._current[dir] = n
      vim.notify("New chat session: " .. n, vim.log.levels.INFO)
    else
      vim.notify("New chat session (unnamed)", vim.log.levels.INFO)
    end
  end)
end

-- Delete a saved session (picker).
function M.delete(name)
  local dir = M.dir()
  local function do_delete(n)
    if not n or n == "" then return end
    os.remove(dir .. "/" .. n .. ".json")
    if M._current[dir] == n then M._current[dir] = nil end
    vim.notify("Deleted chat session: " .. n, vim.log.levels.INFO)
  end
  if name then
    do_delete(name)
    return
  end
  local sessions = M.list()
  if vim.tbl_isempty(sessions) then
    vim.notify("No saved sessions to delete", vim.log.levels.WARN)
    return
  end
  vim.ui.select(sessions, { prompt = "Delete chat session:" }, do_delete)
end

-- Show current session + all sessions for this folder.
function M.info()
  local sessions = M.list()
  local cur = M.current() or "(unsaved)"
  local lines = { "Folder: " .. vim.fn.getcwd(), "Current session: " .. cur, "" }
  if vim.tbl_isempty(sessions) then
    table.insert(lines, "No saved sessions yet.")
  else
    table.insert(lines, "Saved sessions:")
    for _, s in ipairs(sessions) do
      table.insert(lines, ("  %s %s"):format(s == M.current() and "▸" or " ", s))
    end
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Copilot Chat sessions" })
end

function M.setup_keymaps()
  local map = vim.keymap.set
  local o = function(desc) return { desc = "Chat session: " .. desc } end
  map("n", "<leader>css", function() M.save() end, o("[S]ave"))
  map("n", "<leader>csl", function() M.load() end, o("[L]oad (picker)"))
  map("n", "<leader>csb", function() M.branch() end, o("[B]ranch from current"))
  map("n", "<leader>csn", function() M.new() end, o("[N]ew / reset"))
  map("n", "<leader>csd", function() M.delete() end, o("[D]elete (picker)"))
  map("n", "<leader>csi", function() M.info() end, o("[I]nfo / list"))

  vim.api.nvim_create_user_command("CopilotChatSessionSave", function(a) M.save(a.args ~= "" and a.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("CopilotChatSessionLoad", function(a) M.load(a.args ~= "" and a.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("CopilotChatSessionBranch", function(a) M.branch(a.args ~= "" and a.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("CopilotChatSessionNew", function() M.new() end, {})
  vim.api.nvim_create_user_command("CopilotChatSessionList", function() M.info() end, {})
end

return M
