-- codexbox.lua — a tiny, isolated Neovim used ONLY by the i3 Codex learning
-- box ($mod+Shift+c, via ~/.config/i3/scripts/codex-box-toggle). Launched with
-- `nvim -u ~/.config/nvim/codexbox.lua`, so it never loads your main config or
-- plugins (fast, and nothing can interfere).
--
-- You get full nvim navigation over Codex:
--   * type to Codex normally (Terminal mode)
--   * <C-q> -> Normal mode (NOTE: plain Esc goes to Codex, not nvim)
--   * <C-p> -> "grab": freeze the visible Codex screen into a scratch buffer you
--              can freely scroll / search / visually select; y -> clipboard; q -> back
--   * i / a -> back to typing at Codex

vim.o.clipboard = "unnamedplus"
vim.o.number = false
vim.o.relativenumber = false
vim.o.signcolumn = "no"
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.ruler = false
vim.o.termguicolors = true
vim.o.scrollback = 100000
vim.o.mouse = "a"
vim.o.fillchars = "eob: "

-- Easy escape to Normal mode for copying, then i/a to resume typing.
vim.keymap.set("t", "<C-q>", [[<C-\><C-n>]], { silent = true })

-- Grab the current Codex screen into a free-scroll scratch buffer.
-- Codex is a full-screen TUI that repaints constantly, so you cannot usefully
-- scroll its live view (the cursor snaps back to the bottom on every repaint).
-- <C-p> freezes what's on screen into a normal, modifiable buffer where you can
-- move the cursor anywhere, /search, visually select, and y to the clipboard.
-- Press q in that buffer to hop back to Codex and keep typing.
local function grab()
  local term_buf = vim.api.nvim_get_current_buf()
  if vim.bo[term_buf].buftype ~= "terminal" then return end
  local lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
  while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_set_current_buf(buf)
  vim.cmd("stopinsert")
  pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, #lines), 0 })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(term_buf) then
      vim.api.nvim_set_current_buf(term_buf)
      vim.cmd("startinsert")
    end
  end, { buffer = buf, silent = true })
end
vim.keymap.set({ "t", "n" }, "<C-p>", grab, { silent = true })

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    vim.cmd("startinsert")
  end,
})

-- When Codex exits: clean exit -> close the box; error -> KEEP it open so the
-- message is visible (press q to dismiss), instead of the window vanishing.
vim.api.nvim_create_autocmd("TermClose", {
  callback = function(ev)
    local code = (vim.v.event or {}).status or 0
    if code == 0 then
      vim.schedule(function() pcall(vim.cmd, "qa!") end)
    else
      pcall(function()
        vim.keymap.set("n", "q", "<cmd>qa!<cr>", { buffer = ev.buf, silent = true })
        vim.cmd("stopinsert")
        vim.schedule(function()
          vim.api.nvim_echo(
            { { "codex exited (code " .. tostring(code) .. ") — press q to close", "ErrorMsg" } },
            true, {})
        end)
      end)
    end
  end,
})

-- Resolve codex robustly: i3 launches with a stripped PATH that may omit
-- ~/.local/bin, so fall back to well-known install locations.
local function codex_cmd()
  if vim.fn.executable("codex") == 1 then
    return "codex"
  end
  for _, p in ipairs({
    vim.fn.expand("~/.local/bin/codex"),
    vim.fn.expand("~/bin/codex"),
    "/usr/local/bin/codex",
    "/usr/bin/codex",
  }) do
    if vim.fn.executable(p) == 1 then
      return vim.fn.shellescape(p)
    end
  end
  return nil
end

-- Start Codex once the UI is ready.
vim.schedule(function()
  local cmd = codex_cmd()
  if cmd then
    vim.cmd("terminal " .. cmd)
  else
    vim.cmd("terminal echo 'codex not found (looked on PATH + ~/.local/bin)'; sleep 5")
  end
end)
