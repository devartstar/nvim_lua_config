-- Render ANSI-colored terminal logs / `script(1)` typescripts in-buffer.
--
-- Files captured with `script` (e.g. /tmp/tls-lab/server.log) contain SGR color
-- codes you WANT to see, mixed with noise you don't: OSC title sequences
-- (ESC ] 0 ; ... BEL), bracketed-paste / private-mode toggles (ESC [ ? 2004 h),
-- and carriage returns used for terminal overstrike. This plugin cleans the
-- non-color noise, then hands the buffer to baleia.nvim which turns the SGR
-- codes into real highlights.

-- Suppress the auto BufReadPost handler while :AnsiView reloads the raw file
-- (the reload itself fires BufReadPost); the command colorizes explicitly.
local suppress_auto = false

-- SGR-preserving stripper: keep color codes (ESC [ ... m), drop every other CSI
-- escape (bracketed-paste ESC [ ? 2004 h/l, cursor/mode sequences, etc.).
local function strip_non_sgr(line)
  return (line:gsub("\27%[([%d;?]*)([A-Za-z])", function(params, final)
    if final == "m" then
      return "\27[" .. params .. "m"
    end
    return ""
  end))
end

local function clean_line(line)
  -- Drop a single trailing CR (line-continuation marker in `script` output)
  -- BEFORE overstrike, else a greedy match to the last CR wipes the whole line.
  line = line:gsub("\r$", "")
  -- Overstrike: text after a remaining CR overwrites from column 0, so keep
  -- only what follows the last CR.
  line = line:gsub("^.*\r", ""):gsub("\r", "")
  -- Drop OSC sequences: ESC ] ... (BEL | ST).
  line = line:gsub("\27%][^\7\27]*\7", ""):gsub("\27%][^\7\27]*\27\\", "")
  return strip_non_sgr(line)
end

local function colorize_buf(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.g.baleia or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    lines[i] = clean_line(line)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- baleia strips the remaining SGR codes and applies highlights. It runs
  -- asynchronously (rewriting text over scheduled chunks), so the buffer MUST
  -- stay modifiable until it finishes; lock it afterwards as a safe viewer.
  vim.g.baleia.once(buf)
  -- In sync mode baleia renders inline before once() returns, so it is safe to
  -- lock immediately. Defer only the "modified" reset so baleia's own scheduled
  -- on_complete (which runs via vim.schedule) has finished its bookkeeping.
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.b[buf].ansi_viewed = true
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modified = false
    end
  end)
end

-- Re-run cleanly: if the buffer was already colorized, reload the raw file from
-- disk first (suppressing the auto handler) so baleia has SGR codes to work on
-- instead of clearing highlights on already-stripped text.
local function ansi_view()
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].ansi_viewed and vim.api.nvim_buf_get_name(buf) ~= "" then
    suppress_auto = true
    vim.bo[buf].readonly = false
    vim.bo[buf].modifiable = true
    vim.cmd("silent keepalt edit!")
    suppress_auto = false
  end
  colorize_buf(buf)
end

local function looks_like_typescript(buf)
  local first = (vim.api.nvim_buf_get_lines(buf, 0, 1, false) or { "" })[1] or ""
  if first:match("^Script started on") then
    return true
  end
  local head = vim.api.nvim_buf_get_lines(buf, 0, 200, false)
  for _, l in ipairs(head) do
    if l:find("\27", 1, true) then
      return true
    end
  end
  return false
end

return {
  {
    "m00qek/baleia.nvim",
    cmd = { "AnsiView", "BaleiaColorize" },
    event = { "BufReadPost" },
    keys = {
      { "<leader>ca", function() require("lazy").load({ plugins = { "baleia.nvim" } }) vim.cmd("AnsiView") end, desc = "ANSI - Render colors in buffer" },
    },
    config = function()
      vim.g.baleia = require("baleia").setup({ strip_ansi_codes = true, async = false })

      vim.api.nvim_create_user_command("AnsiView", function()
        ansi_view()
      end, { desc = "Clean terminal-script noise and render ANSI colors" })

      vim.api.nvim_create_user_command("BaleiaColorize", function()
        if vim.g.baleia then
          vim.g.baleia.once(vim.api.nvim_get_current_buf())
        end
      end, { desc = "Colorize ANSI SGR codes only (no cleaning)" })

      local grp = vim.api.nvim_create_augroup("AnsiLogView", { clear = true })
      vim.api.nvim_create_autocmd("BufReadPost", {
        group = grp,
        callback = function(args)
          if suppress_auto then
            return
          end
          local buf = args.buf
          local name = vim.api.nvim_buf_get_name(buf)
          -- Only auto-handle log-ish captures to avoid touching normal files.
          if not (name:match("%.log$") or name:match("%.typescript$")) then
            return
          end
          if looks_like_typescript(buf) then
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(buf) then
                colorize_buf(buf)
              end
            end)
          end
        end,
      })
    end,
  },
}
