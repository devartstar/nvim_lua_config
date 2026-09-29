-- task_notes.lua — the nvim end of the task/zk/AI "tangle".
--
-- <leader>na  (normal)  open the ACTIVE taskwarrior task's zk note
-- <leader>na  (visual)  append the selection under that note's "## Learnings"
--                        (use it in any AI chat to distill a reply into memory)
--
-- Source of truth is the `focus` CLI: `focus path` prints (and lazily creates)
-- the active task's note, so nvim and the shell never disagree.
local M = {}

local function active_note_path()
  local p = vim.trim(vim.fn.system({ "focus", "path" }))
  if vim.v.shell_error ~= 0 or p == "" then return nil end
  return p
end

function M.open()
  local p = active_note_path()
  if not p then
    vim.notify("No active task. Start one: `focus on` in a terminal.", vim.log.levels.WARN)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(p))
end

-- Grab the current charwise/linewise visual selection as a list of lines.
local function selection_lines()
  local a = vim.fn.getpos("'<")
  local b = vim.fn.getpos("'>")
  local lines = vim.fn.getline(a[2], b[2])
  if #lines == 0 then return {} end
  if #lines == 1 then
    lines[1] = string.sub(lines[1], a[3], b[3])
  else
    lines[1] = string.sub(lines[1], a[3])
    lines[#lines] = string.sub(lines[#lines], 1, b[3])
  end
  return lines
end

function M.capture()
  local p = active_note_path()
  if not p then
    vim.notify("No active task to capture into. Run `focus on` first.", vim.log.levels.WARN)
    return
  end
  local sel = selection_lines()
  while #sel > 0 and sel[#sel]:match("^%s*$") do table.remove(sel) end
  if #sel == 0 then
    vim.notify("Nothing selected to capture.", vim.log.levels.WARN)
    return
  end

  local file = vim.fn.readfile(p)
  -- find the "## Learnings" heading; skip an immediately following HTML comment
  local at
  for i, l in ipairs(file) do
    if l:match("^##%s+Learnings") then at = i break end
  end
  if not at then
    table.insert(file, "")
    table.insert(file, "## Learnings")
    at = #file
  end
  local insert = at
  if file[insert + 1] and file[insert + 1]:match("^%s*<!%-%-") then
    insert = insert + 1
  end

  local block = { "", "- " .. os.date("%Y-%m-%d") .. " · " .. sel[1] }
  for i = 2, #sel do block[#block + 1] = "  " .. sel[i] end

  for i = #block, 1, -1 do
    table.insert(file, insert + 1, block[i])
  end
  vim.fn.writefile(file, p)
  vim.notify("Captured " .. #sel .. " line(s) → " .. vim.fn.fnamemodify(p, ":t"), vim.log.levels.INFO)
end

-- The active taskwarrior task's description (or nil). Shared by the AI-chat
-- modules so a new chat can be auto-named after what you're working on.
function M.active_task_name()
  local out = vim.fn.system({ "task", "+ACTIVE", "export" })
  if vim.v.shell_error ~= 0 then return nil end
  local ok, arr = pcall(vim.json.decode, out)
  if not ok or type(arr) ~= "table" or not arr[1] then return nil end
  local d = arr[1].description
  if not d or d == "" then return nil end
  return d
end

function M.setup()
  vim.keymap.set("n", "<leader>na", M.open,
    { silent = true, desc = "Active task note (open)" })
  vim.keymap.set("v", "<leader>na", function()
    vim.cmd("normal! \27") -- leave visual so '< '> marks are set
    M.capture()
  end, { silent = true, desc = "Capture selection → task note" })
  vim.api.nvim_create_user_command("Focus", function(a)
    if a.args == "" or a.args == "note" then M.open() else M.capture() end
  end, { nargs = "?", desc = "Open active task note" })
end

return M
