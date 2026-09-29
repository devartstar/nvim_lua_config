-- Minimal in-nvim PDF reading, backed by poppler's `pdftotext`.
--
-- Two layers (see also core/autocmds.lua which wires the autocmd + commands):
--   1. Read the TEXT of a PDF right inside a normal, searchable buffer:
--        * `nvim file.pdf`         -> opens the extracted text (BufReadCmd)
--        * `:Pdf https://…/x.pdf`  -> downloads + opens a web PDF's text
--   2. See the REAL PDF (figures/layout) in zathura with <leader>pv.
--
-- Buffer-local keymaps in a PDF-text buffer:
--   <leader>pv  open the source PDF in zathura (visual view)
--   <leader>pl  toggle layout mode (table-preserving  <->  reflowed prose)
--   <leader>pi  show pdfinfo metadata in a popup
--
-- No heavy deps: just pdftotext/pdfinfo (poppler), curl, and zathura — all of
-- which you already have.

local M = {}

local function has(exe)
  return vim.fn.executable(exe) == 1
end

-- Run pdftotext on a path and return its text. `layout` true preserves
-- columns/tables (-layout); false reflows into prose. Returns (lines, pages)
-- where pages[i] is the 1-based PDF page number that display line i sits on
-- (derived from pdftotext's form-feed page breaks), plus the total page count.
local function extract(path, layout)
  local cmd = { "pdftotext", "-q" }
  if layout then
    table.insert(cmd, "-layout")
  end
  vim.list_extend(cmd, { path, "-" })
  local raw = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, raw
  end

  local lines, pages = {}, {}
  local chunks = vim.split(raw, "\f", { plain = true })
  local total = #chunks
  if total > 0 and chunks[total] == "" then
    total = total - 1 -- trailing form-feed => phantom empty page
  end
  for pnum = 1, total do
    for _, l in ipairs(vim.split(chunks[pnum], "\n", { plain = true })) do
      table.insert(lines, l)
      table.insert(pages, pnum)
    end
  end
  return lines, pages, math.max(total, 1)
end

-- Populate `buf` with the extracted text of `path` and make it a comfortable,
-- read-only reading buffer. `source` fields let the zathura keymap find the
-- real file (a local path, or the temp file a URL was downloaded to).
function M.render(buf, path, opts)
  opts = opts or {}
  if not has("pdftotext") then
    vim.notify("pdftotext (poppler) not found on PATH", vim.log.levels.ERROR)
    return
  end

  local layout = opts.layout
  if layout == nil then layout = true end

  local lines, pages, total = extract(path, layout)
  if not lines then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "Failed to extract text from PDF:", "", path, "", (pages or "unknown error"),
    })
    vim.bo[buf].modifiable = false
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "text"

  vim.b[buf].pdf_path = path
  vim.b[buf].pdf_display = opts.display or path
  vim.b[buf].pdf_layout = layout
  vim.b[buf].pdf_pages = pages -- line -> PDF page number
  vim.b[buf].pdf_total = total

  -- Reading comfort in the window showing this buffer.
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].spell = false
  end

  M.set_keymaps(buf)
end

-- Which PDF page is the cursor currently on?
function M.current_page(buf, win)
  buf = buf or vim.api.nvim_get_current_buf()
  local pages = vim.b[buf].pdf_pages
  if not pages then return nil end
  win = win or vim.fn.bufwinid(buf)
  local line = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1
  return pages[line] or pages[#pages] or 1, vim.b[buf].pdf_total
end

-- Open the real PDF behind the current text buffer in zathura, jumping to the
-- page your cursor is on so the visual view matches where you were reading.
function M.open_in_viewer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local path = vim.b[buf].pdf_path
  if not path then
    vim.notify("No PDF source associated with this buffer", vim.log.levels.WARN)
    return
  end
  if not has("zathura") then
    vim.notify("zathura not found on PATH", vim.log.levels.ERROR)
    return
  end
  local page = M.current_page(buf)
  local cmd = { "zathura" }
  if page then
    vim.list_extend(cmd, { "-P", tostring(page) })
  end
  table.insert(cmd, path)
  vim.fn.jobstart(cmd, { detach = true })
  vim.notify(("Opened in zathura: %s (page %s)"):format(
    vim.fn.fnamemodify(path, ":t"), page or "?"), vim.log.levels.INFO)
end

-- Echo "Page N / total" for the cursor's position.
function M.show_page(buf)
  local page, total = M.current_page(buf)
  if not page then
    vim.notify("Not a PDF text buffer", vim.log.levels.WARN)
    return
  end
  vim.notify(("Page %d / %d"):format(page, total or page), vim.log.levels.INFO)
end

-- Toggle table-preserving layout vs reflowed prose and re-extract in place.
function M.toggle_layout(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local path = vim.b[buf].pdf_path
  if not path then return end
  local win = vim.fn.bufwinid(buf)
  local view = win ~= -1 and vim.api.nvim_win_call(win, vim.fn.winsaveview) or nil
  M.render(buf, path, {
    layout = not vim.b[buf].pdf_layout,
    display = vim.b[buf].pdf_display,
  })
  if view and win ~= -1 then
    vim.api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
  end
  vim.notify("PDF layout: " .. (vim.b[buf].pdf_layout and "preserved (tables)" or "reflowed (prose)"),
    vim.log.levels.INFO)
end

-- Show pdfinfo metadata in a floating popup.
function M.info(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local path = vim.b[buf].pdf_path
  if not path or not has("pdfinfo") then return end
  local out = vim.fn.systemlist({ "pdfinfo", path })
  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[pbuf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, out)
  vim.bo[pbuf].modifiable = false
  local width = 0
  for _, l in ipairs(out) do width = math.max(width, #l) end
  local w = math.min(width + 2, math.floor(vim.o.columns * 0.8))
  local h = math.min(#out, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(pbuf, true, {
    relative = "editor", width = math.max(w, 20), height = math.max(h, 3),
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    style = "minimal", border = "rounded", title = " pdfinfo ", title_pos = "center",
  })
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = pbuf, nowait = true, silent = true })
  end
end

function M.set_keymaps(buf)
  local opt = { buffer = buf, silent = true }
  vim.keymap.set("n", "<leader>pv", function() M.open_in_viewer(buf) end,
    vim.tbl_extend("force", opt, { desc = "[P]DF: open cursor page in [V]iewer (zathura)" }))
  vim.keymap.set("n", "<leader>pp", function() M.show_page(buf) end,
    vim.tbl_extend("force", opt, { desc = "[P]DF: current [P]age number" }))
  vim.keymap.set("n", "<leader>pl", function() M.toggle_layout(buf) end,
    vim.tbl_extend("force", opt, { desc = "[P]DF: toggle [L]ayout/reflow" }))
  vim.keymap.set("n", "<leader>pi", function() M.info(buf) end,
    vim.tbl_extend("force", opt, { desc = "[P]DF: [I]nfo (metadata)" }))
end

-- Open a local PDF path as a text buffer (used by the BufReadCmd autocmd).
function M.open_local(path, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  M.render(buf, path, { display = path })
end

-- Download a web PDF and open its text. Keeps the temp file so <leader>pv can
-- hand the real PDF to zathura.
function M.open_url(url)
  if not has("curl") then
    vim.notify("curl not found on PATH", vim.log.levels.ERROR)
    return
  end
  local tmp = vim.fn.tempname() .. ".pdf"
  vim.notify("Downloading " .. url .. " …", vim.log.levels.INFO)
  vim.system({ "curl", "-fsSL", url, "-o", tmp }, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      vim.notify("Download failed: " .. (res.stderr or ("exit " .. res.code)), vim.log.levels.ERROR)
      return
    end
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()
    local name = url:match("([^/]+%.pdf)") or ("web-" .. os.time() .. ".pdf")
    pcall(vim.api.nvim_buf_set_name, buf, "pdf://" .. name)
    M.render(buf, tmp, { display = url })
  end))
end

-- Fuzzy-find PDFs on disk and open the chosen one in zathura. Uses telescope
-- if available (with fd), else falls back to vim.ui.select over fd output.
function M.find(opts)
  opts = opts or {}
  local root = opts.cwd or vim.fn.expand("~")
  if not has("zathura") then
    vim.notify("zathura not found on PATH", vim.log.levels.ERROR)
    return
  end

  local find_cmd = has("fd")
    and { "fd", "--type", "f", "--extension", "pdf", "--hidden", "--exclude", ".git" }
    or { "find", ".", "-type", "f", "-iname", "*.pdf" }

  local ok_b, builtin = pcall(require, "telescope.builtin")
  if ok_b then
    local actions = require("telescope.actions")
    local state = require("telescope.actions.state")
    builtin.find_files({
      prompt_title = "PDFs → zathura",
      cwd = root,
      find_command = find_cmd,
      previewer = false,
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(bufnr)
          if not entry then return end
          local path = entry.path or (root .. "/" .. entry[1])
          vim.fn.jobstart({ "zathura", path }, { detach = true })
          vim.notify("Opened in zathura: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
        end)
        return true
      end,
    })
    return
  end

  -- Fallback: no telescope.
  local list = vim.fn.systemlist(vim.list_extend(vim.deepcopy(find_cmd), root and has("fd") and { root } or {}))
  if #list == 0 then
    vim.notify("No PDFs found under " .. root, vim.log.levels.INFO)
    return
  end
  vim.ui.select(list, { prompt = "Open PDF in zathura:" }, function(choice)
    if choice then vim.fn.jobstart({ "zathura", choice }, { detach = true }) end
  end)
end

return M
