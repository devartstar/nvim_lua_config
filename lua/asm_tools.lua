-- asm_tools.lua ------------------------------------------------------------
-- Tiny, dependency-free helpers for reading compiled artefacts from inside
-- Neovim: disassembly (objdump), ELF metadata (readelf) and symbols (nm).
-- No plugin needed — each command shells out to the binutils you already have
-- and drops the result into a throwaway scratch buffer with asm highlighting
-- and per-function folds.
--
--   :Objdump [file]     objdump -d (Intel syntax) of file (default: % )
--   :ObjdumpSrc [file]  objdump -S -l  — interleave the original source lines
--   :Readelf [file]     readelf -a
--   :Nm [file]          nm -C --defined-only, address-sorted
--
-- Keymaps (under <leader>o — "Objdump / ASM"):
--   <leader>oo disasm   <leader>oS disasm+source   <leader>oe readelf   <leader>on nm
local M = {}

-- Open a scratch buffer named <title> holding <lines>, filetype <ft>.
local function scratch(title, lines, ft)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, title)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if ft then vim.bo[buf].filetype = ft end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

-- Resolve the target file: an explicit arg, else the current buffer's file.
local function target(arg)
  if arg and #arg > 0 then return vim.fn.expand(arg) end
  local f = vim.api.nvim_buf_get_name(0)
  if f == "" then return nil end
  return f
end

-- Run <cmd_list> and return its output lines (stderr folded in on failure).
local function run(cmd_list)
  local out = vim.fn.systemlist(cmd_list)
  if vim.v.shell_error ~= 0 then
    table.insert(out, 1, "!! command failed (exit " .. vim.v.shell_error .. "): "
      .. table.concat(cmd_list, " "))
  end
  return out
end

local function need_file(arg)
  local f = target(arg)
  if not f then
    vim.notify("asm_tools: no file (open one or pass a path)", vim.log.levels.WARN)
  elseif vim.fn.filereadable(f) == 0 then
    vim.notify("asm_tools: not readable: " .. f, vim.log.levels.WARN)
    return nil
  end
  return f
end

-- Is <f> something objdump can disassemble (ELF/object/archive), vs source?
local function is_object(f)
  local desc = vim.fn.systemlist({ "file", "-b", f })[1] or ""
  return desc:match("ELF") or desc:match("relocatable") or desc:match("object")
      or desc:match("archive") or desc:match("executable")
end

local SRC_EXT = { c = true, cc = true, cpp = true, cxx = true, ["c++"] = true }

-- Compile <f> to a throwaway object (with debug info) so it can be disassembled.
-- Returns (object_path, cmd, output). object_path is nil on failure.
local function compile_temp(f)
  local ext = (vim.fn.fnamemodify(f, ":e")):lower()
  local is_cpp = (ext ~= "c")
  local cc  = is_cpp and (vim.env.CXX or "c++") or (vim.env.CC or "cc")
  local std = is_cpp and "-std=c++17" or "-std=c11"
  local out = vim.fn.tempname() .. ".o"
  local cmd = { cc, "-c", "-g", "-O2", std, f, "-o", out }
  local res = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then return nil, cmd, res end
  return out, cmd, res
end

function M.objdump(arg, with_source)
  local f = need_file(arg); if not f then return end

  local disasm_target, temp = f, nil
  if not is_object(f) then
    local ext = (vim.fn.fnamemodify(f, ":e")):lower()
    if SRC_EXT[ext] then
      -- Source file: auto-compile a temp object and disassemble that.
      local obj, cmd, err = compile_temp(f)
      if not obj then
        local lines = {
          "; " .. vim.fn.fnamemodify(f, ":t") .. " is source — auto-compile failed:",
          "; $ " .. table.concat(cmd, " "), "",
        }
        vim.list_extend(lines, err)
        vim.list_extend(lines, {
          "",
          "; This is normal for files that need project headers (e.g. kernel.c).",
          "; Fixes:",
          ";   * build it in your project, then  :Objdump path/to/file.o",
          ";   * or see source->asm live with  <leader>oc  (Compiler Explorer)",
        })
        scratch("objdump://" .. vim.fn.fnamemodify(f, ":t"), lines, "asm")
        return
      end
      disasm_target, temp = obj, obj
    else
      scratch("objdump://" .. vim.fn.fnamemodify(f, ":t"), {
        "; not an object file: " .. f,
        "; objdump disassembles compiled objects/executables.",
        "; Compile first, then  :Objdump <obj>  — or use  <leader>oc  (Compiler Explorer).",
      }, "asm")
      return
    end
  end

  local cmd = { "objdump", "-d", "-M", "intel", "--no-show-raw-insn" }
  if with_source then cmd = { "objdump", "-S", "-l", "-M", "intel" } end
  table.insert(cmd, disasm_target)
  local out = run(cmd)
  if temp then
    table.insert(out, 1, "; (auto-compiled " .. vim.fn.fnamemodify(f, ":t")
      .. " -> temp .o at -O2 -g)")
    pcall(os.remove, temp)
  end
  scratch("objdump://" .. vim.fn.fnamemodify(f, ":t"), out, "asm")
  -- Fold each function block: objdump prints "<name>:" as a label line.
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "getline(v:lnum)=~'^[0-9a-f]* <.*>:' ? '>1' : '1'"
  vim.wo.foldenable = false
end

function M.readelf(arg)
  local f = need_file(arg); if not f then return end
  scratch("readelf://" .. vim.fn.fnamemodify(f, ":t"),
    run({ "readelf", "-a", "-W", f }), "")
end

function M.nm(arg)
  local f = need_file(arg); if not f then return end
  scratch("nm://" .. vim.fn.fnamemodify(f, ":t"),
    run({ "nm", "-C", "--defined-only", "-n", f }), "")
end

function M.setup()
  local cmd = vim.api.nvim_create_user_command
  local complete = "file"
  cmd("Objdump",    function(o) M.objdump(o.args, false) end, { nargs = "?", complete = complete })
  cmd("ObjdumpSrc", function(o) M.objdump(o.args, true)  end, { nargs = "?", complete = complete })
  cmd("Readelf",    function(o) M.readelf(o.args) end,        { nargs = "?", complete = complete })
  cmd("Nm",         function(o) M.nm(o.args) end,             { nargs = "?", complete = complete })

  local map = vim.keymap.set
  map("n", "<leader>oo", "<cmd>Objdump<cr>",    { desc = "Objdump — disassemble (Intel)" })
  map("n", "<leader>oS", "<cmd>ObjdumpSrc<cr>", { desc = "Objdump — disasm + source" })
  map("n", "<leader>oe", "<cmd>Readelf<cr>",    { desc = "Readelf — ELF headers/sections" })
  map("n", "<leader>on", "<cmd>Nm<cr>",         { desc = "Nm — symbols (sorted)" })
end

return M
