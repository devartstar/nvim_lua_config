-- Highlight on yank
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Render the ```mermaid block under the cursor as ASCII art in a side split.
--
-- This terminal has no image/graphics protocol, so mermaid diagrams can't be
-- drawn as pictures. Instead we pipe the fenced block through the `mermaid-ascii`
-- CLI (installed at ~/.local/bin/mermaid-ascii) and show the text result in a
-- scratch buffer — fully in-terminal, no browser needed.
--
-- Usage in a markdown file: put the cursor inside a ```mermaid fence and press
-- <leader>mm (or run :Mermaid).
local function render_mermaid_ascii()
  if vim.fn.executable('mermaid-ascii') == 0 then
    vim.notify('mermaid-ascii not found on PATH', vim.log.levels.ERROR)
    return
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find the opening fence (```mermaid) at or above the cursor.
  local start_fence
  for i = cur, 1, -1 do
    if lines[i]:match('^%s*```%s*mermaid%s*$') then
      start_fence = i
      break
    elseif lines[i]:match('^%s*```') and i ~= cur then
      break -- hit a different (closing/other) fence first
    end
  end
  if not start_fence then
    vim.notify('Cursor is not inside a ```mermaid block', vim.log.levels.WARN)
    return
  end

  -- Find the closing fence below the opening one.
  local end_fence
  for i = start_fence + 1, #lines do
    if lines[i]:match('^%s*```%s*$') then
      end_fence = i
      break
    end
  end
  if not end_fence then
    vim.notify('Unterminated ```mermaid block', vim.log.levels.WARN)
    return
  end

  local body = vim.list_slice(lines, start_fence + 1, end_fence - 1)
  local block = table.concat(body, '\n')

  -- Open the block in the browser preview instead of ASCII. Used for diagram
  -- types mermaid-ascii can't draw (sequence, class, gantt, state, ...).
  local function open_browser_fallback(reason)
    vim.notify(reason .. ' — opening browser preview instead.', vim.log.levels.INFO)
    pcall(vim.cmd, 'MarkdownPreview')
  end

  -- mermaid-ascii only understands flowchart/graph diagrams. Detect the type
  -- from the first non-empty line and fall back to the browser for the rest.
  local kind
  for _, l in ipairs(body) do
    local trimmed = l:match('^%s*(.-)%s*$')
    if trimmed ~= '' then
      kind = trimmed:match('^(%a+)')
      break
    end
  end
  if kind and not (kind == 'flowchart' or kind == 'graph') then
    open_browser_fallback('"' .. kind .. '" diagrams are not supported by mermaid-ascii')
    return
  end

  local out = vim.fn.systemlist({ 'mermaid-ascii' }, block)
  if vim.v.shell_error ~= 0 then
    open_browser_fallback('mermaid-ascii could not render this diagram')
    return
  end

  -- Show the ASCII output in a scratch buffer inside a centered floating window
  -- (curved border to match the terminal/telescope floats).
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'text'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false

  -- Size the float to the diagram, capped to ~90% of the editor.
  local content_w, content_h = 0, #out
  for _, l in ipairs(out) do
    content_w = math.max(content_w, vim.fn.strdisplaywidth(l))
  end
  local max_w = math.floor(vim.o.columns * 0.9)
  local max_h = math.floor(vim.o.lines * 0.9)
  local width = math.max(20, math.min(content_w + 2, max_w))
  local height = math.max(3, math.min(content_h, max_h))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' mermaid ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  -- Close the popup with q or <Esc>.
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set up mermaid ASCII rendering for markdown buffers',
  group = vim.api.nvim_create_augroup('mermaid-ascii', { clear = true }),
  pattern = 'markdown',
  callback = function(ev)
    vim.api.nvim_buf_create_user_command(ev.buf, 'Mermaid', render_mermaid_ascii, {
      desc = 'Render the mermaid block under the cursor as ASCII',
    })
    vim.keymap.set('n', '<leader>mm', render_mermaid_ascii, {
      buffer = ev.buf,
      desc = '[M]ermaid render (ASCII, in-terminal)',
    })
  end,
})
