-- Inline Codex chat (Option B, the working one).
--
-- Why this exists: codecompanion's ACP path talks to zed-industries/codex-acp,
-- whose bundled codex-core is months old and cannot decode the current model
-- list (it chokes on the new `max`/`ultra` reasoning levels), so every model
-- resolves as "metadata not found". Instead of that dead bridge, this drives
-- the UP-TO-DATE `codex exec` binary directly:
--   * full model support (gpt-6-astra, gpt-5.6-sol, ... incl. max/ultra)
--   * ChatGPT-Plus login (no API key)
--   * reads your repo files for context (read-only sandbox)
--   * multi-turn continuity via the session thread id
-- The conversation renders inline in a markdown split (render-markdown.nvim),
-- so you never leave nvim and never open a terminal.

local M = {}

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local INPUT_SEP = "---"

-- Per-buffer runtime state: { thread_id, job, timer, busy, ph }
local state = {}

local function codex_bin()
  local p = vim.fn.exepath("codex")
  if p ~= "" then return p end
  return vim.fn.expand("~/.local/bin/codex")
end

local function default_model()
  return vim.g.codex_chat_model or "gpt-5.6-sol"
end

local function default_effort()
  return vim.g.codex_chat_effort or "medium"
end

local function project_root()
  local dir = vim.fn.getcwd()
  local git = vim.fs.find(".git", { path = dir, upward = true })[1]
  if git then return vim.fs.dirname(git) end
  return dir
end

-- Track the single chat buffer/window so <leader>xi reuses it.
local chat_buf = nil

local function set_lines(buf, s, e, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, s, e, false, lines)
  vim.bo[buf].modifiable = true
end

local function header(buf)
  local model = vim.b[buf].codex_model or default_model()
  local effort = vim.b[buf].codex_effort or default_effort()
  return {
    "# 🤖 Codex Chat",
    "> model: `" .. model .. "` · reasoning: `" .. effort .. "` · " .. project_root(),
    "> `<Enter>` (normal) or `Ctrl-s` send · `q` hide · `<leader>xm` model · `<C-c>` cancel",
    "",
    INPUT_SEP,
    "",
    "",
  }
end

local function last_sep(lines)
  for i = #lines, 1, -1 do
    if lines[i] == INPUT_SEP then return i end
  end
  return nil
end

-- Attach buffer-local keymaps.
local function set_keymaps(buf)
  local opt = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", function() M.send(buf) end, opt)
  vim.keymap.set({ "n", "i" }, "<C-s>", function() M.send(buf) end, opt)
  vim.keymap.set("n", "<C-c>", function() M.cancel(buf) end, opt)
  vim.keymap.set("n", "q", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then vim.api.nvim_win_hide(win) end
  end, opt)
  vim.keymap.set("n", "<leader>xm", function() M.set_model(buf) end, opt)
end

function M.open()
  if chat_buf and vim.api.nvim_buf_is_valid(chat_buf) then
    local win = vim.fn.bufwinid(chat_buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(0, chat_buf)
    end
    return chat_buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  chat_buf = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(buf, "codex://chat")
  vim.b[buf].codex_model = default_model()
  vim.b[buf].codex_effort = default_effort()
  state[buf] = { thread_id = nil, busy = false }

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.wrap = true
  vim.wo.linebreak = true

  set_lines(buf, 0, -1, header(buf))
  set_keymaps(buf)

  -- Park the cursor in the input area, insert mode.
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
  vim.cmd("startinsert")
  return buf
end

local function refresh_header(buf)
  -- Rewrite only the first two header lines (model/reasoning line may change).
  local model = vim.b[buf].codex_model or default_model()
  local effort = vim.b[buf].codex_effort or default_effort()
  set_lines(buf, 1, 2, {
    "> model: `" .. model .. "` · reasoning: `" .. effort .. "` · " .. project_root(),
  })
end

local function start_spinner(buf)
  local st = state[buf]
  local i = 1
  st.timer = vim.uv.new_timer()
  st.timer:start(0, 90, vim.schedule_wrap(function()
    if not (st.busy and vim.api.nvim_buf_is_valid(buf) and st.ph) then return end
    i = (i % #SPINNER) + 1
    pcall(set_lines, buf, st.ph, st.ph + 1, { SPINNER[i] .. " thinking…" })
  end))
end

local function stop_spinner(buf)
  local st = state[buf]
  if st.timer then
    st.timer:stop()
    st.timer:close()
    st.timer = nil
  end
end

function M.send(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = state[buf]
  if not st then return end
  if st.busy then
    vim.notify("Codex is still responding — <C-c> to cancel", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local sep = last_sep(lines)
  if not sep then return end
  local prompt = vim.trim(table.concat(vim.list_slice(lines, sep + 1, #lines), "\n"))
  if prompt == "" then
    vim.notify("Type a message below the --- line first", vim.log.levels.INFO)
    return
  end

  local model = vim.b[buf].codex_model or default_model()
  local effort = vim.b[buf].codex_effort or default_effort()

  -- Replace the input separator + typed text with a rendered You/Codex block.
  local block = { "### 🧑 You", "" }
  for _, l in ipairs(vim.split(prompt, "\n", { plain = true })) do
    block[#block + 1] = l
  end
  vim.list_extend(block, { "", "### 🤖 Codex", "", SPINNER[1] .. " thinking…" })
  set_lines(buf, sep - 1, -1, block)

  st.ph = (sep - 1) + #block - 1 -- 0-based line index of the placeholder
  st.busy = true
  vim.bo[buf].modifiable = false
  start_spinner(buf)

  local out = vim.fn.tempname()
  local args = {
    "exec", "--json", "--color", "never",
    "-s", "read-only", "--skip-git-repo-check",
    "-c", "model_reasoning_effort=" .. effort,
    "-m", model,
    "-o", out,
  }
  if st.thread_id then
    args[#args + 1] = "resume"
    args[#args + 1] = st.thread_id
  end
  args[#args + 1] = prompt

  st.job = vim.system(
    vim.list_extend({ codex_bin() }, args),
    { cwd = project_root(), text = true },
    vim.schedule_wrap(function(res)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      stop_spinner(buf)
      st.busy = false
      st.job = nil

      -- Capture the thread id on the first turn for continuity.
      if not st.thread_id and res.stdout then
        local id = res.stdout:match('"thread_id":"([^"]+)"')
        if id then st.thread_id = id end
      end

      local answer = ""
      local f = io.open(out, "r")
      if f then answer = f:read("*a") or ""; f:close() end
      os.remove(out)
      if vim.trim(answer) == "" and res.stdout then
        -- Fallback: last agent_message from the JSONL stream.
        for line in res.stdout:gmatch("[^\n]+") do
          local ok, ev = pcall(vim.json.decode, line)
          if ok and ev and ev.item and ev.item.type == "agent_message" then
            answer = ev.item.text or answer
          end
        end
      end
      if vim.trim(answer) == "" then
        answer = "_(no response)_"
        if res.code ~= 0 and res.stderr and res.stderr ~= "" then
          answer = "**Codex error (exit " .. tostring(res.code) .. "):**\n\n```\n"
            .. vim.trim(res.stderr) .. "\n```"
        end
      end

      local reply = vim.split(answer, "\n", { plain = true })
      set_lines(buf, st.ph, st.ph + 1, reply)
      -- Fresh input area at the bottom.
      set_lines(buf, -1, -1, { "", INPUT_SEP, "", "" })
      st.ph = nil

      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
        if vim.api.nvim_get_current_win() == win then vim.cmd("startinsert") end
      end
    end)
  )
end

function M.cancel(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = state[buf]
  if st and st.job then
    st.job:kill(15)
    st.busy = false
    stop_spinner(buf)
    if st.ph then
      set_lines(buf, st.ph, st.ph + 1, { "_(cancelled)_" })
      set_lines(buf, -1, -1, { "", INPUT_SEP, "", "" })
      st.ph = nil
    end
    vim.notify("Codex request cancelled", vim.log.levels.INFO)
  end
end

-- Model picker sourced from the live models cache written by the codex CLI.
function M.set_model(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local models = {}
  local path = vim.fn.expand("~/.codex/models_cache.json")
  local f = io.open(path, "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and data and data.models then
      for _, m in ipairs(data.models) do
        if m.visibility == "list" and m.slug then models[#models + 1] = m.slug end
      end
    end
  end
  if #models == 0 then
    models = { "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5" }
  end
  vim.ui.select(models, { prompt = "Codex model:" }, function(choice)
    if choice then
      vim.b[buf].codex_model = choice
      refresh_header(buf)
      vim.notify("Codex model → " .. choice, vim.log.levels.INFO)
    end
  end)
end

return M
