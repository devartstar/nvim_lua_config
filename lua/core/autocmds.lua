-- Highlight on yank
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Show a list of text lines in a centered floating popup (rounded border to
-- match the terminal/telescope floats). Closes with q or <Esc>. Reused by the
-- mermaid renderer and the Makefile dependency graph.
local function show_ascii_popup(lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'text'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local content_w = 0
  for _, l in ipairs(lines) do
    content_w = math.max(content_w, vim.fn.strdisplaywidth(l))
  end
  local max_w = math.floor(vim.o.columns * 0.9)
  local max_h = math.floor(vim.o.lines * 0.9)
  local width = math.max(20, math.min(content_w + 2, max_w))
  local height = math.max(3, math.min(#lines, max_h))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = title or ' preview ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

-- Pipe mermaid source text through the `mermaid-ascii` CLI and show the result
-- in a popup. Returns true on success; on failure calls on_fail(reason) (if
-- given) so callers can decide how to fall back.
local function render_mermaid_source(text, title, on_fail)
  if vim.fn.executable('mermaid-ascii') == 0 then
    vim.notify('mermaid-ascii not found on PATH', vim.log.levels.ERROR)
    return false
  end
  local out = vim.fn.systemlist({ 'mermaid-ascii' }, text)
  if vim.v.shell_error ~= 0 then
    if on_fail then
      on_fail(table.concat(out, '\n'))
    else
      vim.notify('mermaid-ascii failed:\n' .. table.concat(out, '\n'), vim.log.levels.ERROR)
    end
    return false
  end
  show_ascii_popup(out, title)
  return true
end

-- Render the ```mermaid block under the cursor as ASCII art in a popup.
--
-- This terminal has no image/graphics protocol, so mermaid diagrams can't be
-- drawn as pictures. Instead we pipe the fenced block through `mermaid-ascii`.
-- Usage in a markdown file: put the cursor inside a ```mermaid fence and press
-- <leader>mm (or run :Mermaid).
local function render_mermaid_ascii()
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

  render_mermaid_source(block, ' mermaid ', function()
    open_browser_fallback('mermaid-ascii could not render this diagram')
  end)
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

-- Build a target->prerequisite dependency graph of a Makefile and render it as
-- ASCII in a popup (reusing the mermaid-ascii pipeline).
--
-- How it works: `make -pnrR` prints make's internal rule database without
-- running anything. We parse the "target: prerequisites" lines out of it,
-- ignore builtin/implicit/pattern/special rules, emit a mermaid flowchart, and
-- render it. An edge A --> B means "A depends on B".
--
-- Usage: :MakeGraph  (or <leader>rg). Optionally :MakeGraph <target> to graph
-- only the tree reachable from one target.
local function make_dependency_graph(opts)
  if vim.fn.executable('make') == 0 then
    vim.notify('make not found on PATH', vim.log.levels.ERROR)
    return
  end

  -- Locate the Makefile directory: the current buffer's dir if it holds a
  -- makefile, otherwise the current working directory.
  local buf_name = vim.api.nvim_buf_get_name(0)
  local dir
  if buf_name ~= '' and vim.fn.fnamemodify(buf_name, ':t'):lower():match('makefile') then
    dir = vim.fn.fnamemodify(buf_name, ':h')
  else
    dir = vim.fn.getcwd()
  end
  local has_makefile = vim.fn.filereadable(dir .. '/Makefile') == 1
    or vim.fn.filereadable(dir .. '/makefile') == 1
    or vim.fn.filereadable(dir .. '/GNUmakefile') == 1
  if not has_makefile then
    vim.notify('No Makefile found in ' .. dir, vim.log.levels.WARN)
    return
  end

  local cmd = 'cd ' .. vim.fn.shellescape(dir) .. ' && make -pnrR 2>/dev/null'
  local db = vim.fn.systemlist(cmd)

  -- Parse "target: prereq1 prereq2" lines from the database.
  local edges, seen = {}, {}
  local nodes = {}
  local only = opts and opts.target and opts.target ~= '' and opts.target or nil
  for _, line in ipairs(db) do
    -- Skip comments, recipe lines (leading tab) and variable assignments.
    if not line:match('^[#\t]') and not line:match('^%s') then
      local tgt, prereqs = line:match('^([^:=|]+):%s*(.*)$')
      -- A leading ':' or '=' in the captured prereqs means the line was really
      -- an assignment (VAR := / VAR ::= ), not a rule — ignore those.
      if tgt and not prereqs:match('^[:=]') then
        tgt = tgt:match('^%s*(.-)%s*$')
        -- Ignore special/pattern/implicit targets and obvious noise.
        local skip = tgt == ''
          or tgt:match('^%.')      -- .PHONY, .SUFFIXES, ...
          or tgt:match('%%')       -- pattern rules
          or tgt:match('%$')       -- unexpanded variables
          or tgt:match('/')        -- path-y implicit rule targets
        if not skip then
          for prereq in prereqs:gmatch('%S+') do
            if not prereq:match('^%.') and not prereq:match('%%') and not prereq:match('|') then
              if (not only) or tgt == only then
                local key = tgt .. '\0' .. prereq
                if not seen[key] then
                  seen[key] = true
                  table.insert(edges, { tgt, prereq })
                  nodes[tgt] = true
                  nodes[prereq] = true
                end
              end
            end
          end
        end
      end
    end
  end

  if #edges == 0 then
    vim.notify('No target dependencies found' .. (only and (' for "' .. only .. '"') or '') .. '.', vim.log.levels.WARN)
    return
  end

  -- Cap the graph so huge trees don't overwhelm mermaid-ascii.
  local MAX_EDGES = 80
  local truncated = false
  if #edges > MAX_EDGES then
    truncated = true
    while #edges > MAX_EDGES do
      table.remove(edges)
    end
  end

  -- Assign short mermaid-safe ids to node names.
  local id_of, next_id = {}, 0
  local function nid(name)
    if not id_of[name] then
      next_id = next_id + 1
      id_of[name] = 'n' .. next_id
    end
    return id_of[name]
  end

  local mmd = { 'flowchart TD' }
  for _, e in ipairs(edges) do
    local a, b = e[1], e[2]
    table.insert(mmd, string.format('    %s["%s"] --> %s["%s"]', nid(a), a, nid(b), b))
  end

  local title = only and (' make: ' .. only .. ' ') or ' make dependencies '
  local ok = render_mermaid_source(table.concat(mmd, '\n'), title)
  if ok and truncated then
    vim.notify(string.format('Graph truncated to %d edges.', MAX_EDGES), vim.log.levels.INFO)
  end
end

vim.api.nvim_create_user_command('MakeGraph', function(a)
  make_dependency_graph({ target = a.args })
end, { nargs = '?', desc = 'Show Makefile target dependency graph as ASCII' })

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Makefile dependency graph keymap',
  group = vim.api.nvim_create_augroup('make-graph', { clear = true }),
  pattern = 'make',
  callback = function(ev)
    vim.keymap.set('n', '<leader>rg', function()
      make_dependency_graph({})
    end, { buffer = ev.buf, desc = '[R]un: make dependency [G]raph' })
  end,
})
