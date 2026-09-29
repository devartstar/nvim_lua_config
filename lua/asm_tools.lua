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
--   <leader>od build+disasm this file   <leader>oD +source
--   <leader>oe readelf   <leader>on nm
-- Commands (any path): :Objdump / :ObjdumpSrc / :Readelf / :Nm / :Odis / :OdisSrc
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

-- Nearest ancestor dir containing a Makefile (or .git) — the project root.
local function find_root(src)
  local dir = vim.fn.fnamemodify(src, ":p:h")
  local hit = vim.fs.find({ "Makefile", "makefile", "GNUmakefile", ".git" },
    { path = dir, upward = true })[1]
  return hit and vim.fn.fnamemodify(hit, ":h") or nil
end

-- Map an absolute source path to its built object under <root>/<build_dir>.
-- Tries build/<relpath>.o first, then the closest-matching <stem>.o under it.
local function locate_object(root, src)
  local build = vim.g.odis_build_dir or "build"
  local rel = src:gsub("^" .. vim.pesc(root .. "/"), "")
  local relo = rel:gsub("%.%w+$", ".o")
  local primary = root .. "/" .. build .. "/" .. relo
  if vim.fn.filereadable(primary) == 1 then return primary end

  local stem = vim.fn.fnamemodify(src, ":t:r")
  local cands = vim.fn.systemlist({ "find", root .. "/" .. build, "-name", stem .. ".o" })
  if vim.v.shell_error ~= 0 or #cands == 0 then return primary end
  -- Prefer the candidate whose trailing directory components match the source.
  local want = vim.split(vim.fn.fnamemodify(relo, ":h"), "/")
  local function score(p)
    local have = vim.split(vim.fn.fnamemodify(p, ":h"), "/")
    local s, i, j = 0, #want, #have
    while i >= 1 and j >= 1 and want[i] == have[j] do s = s + 1; i = i - 1; j = j - 1 end
    return s
  end
  table.sort(cands, function(a, b) return score(a) > score(b) end)
  return cands[1]
end

-- :Objdump / :ObjdumpSrc — disassemble an object or binary (Intel syntax).
-- Given an explicit path it dumps that. Given a SOURCE file it dumps that
-- file's ALREADY-BUILT object (build first with <leader>od / :Odis). It never
-- tries a bare compile — kernel-style sources need project headers.
function M.objdump(arg, with_source)
  local f = need_file(arg); if not f then return end
  f = vim.fn.fnamemodify(f, ":p")

  local target = f
  if not is_object(f) then
    local ext = (vim.fn.fnamemodify(f, ":e")):lower()
    if SRC_EXT[ext] then
      local root = find_root(f)
      local obj = root and locate_object(root, f) or nil
      if obj and vim.fn.filereadable(obj) == 1 then
        target = obj
      else
        scratch("objdump://" .. vim.fn.fnamemodify(f, ":t"), {
          "; " .. vim.fn.fnamemodify(f, ":t") .. " is source with no built object yet.",
          "; Build AND disassemble it in one step with  <leader>od  (:Odis).",
          obj and ("; (expected object: " .. obj .. ")")
              or  "; (no Makefile/build dir found above this file)",
        }, "asm")
        return
      end
    else
      scratch("objdump://" .. vim.fn.fnamemodify(f, ":t"), {
        "; not an object file: " .. f,
        "; :Objdump disassembles compiled objects/binaries.",
        "; For a source file, use  <leader>od  (:Odis) to build + disassemble.",
      }, "asm")
      return
    end
  end

  local cmd = { "objdump", "-d", "-M", "intel", "--no-show-raw-insn" }
  if with_source then cmd = { "objdump", "-S", "-l", "-M", "intel" } end
  table.insert(cmd, target)
  scratch("objdump://" .. vim.fn.fnamemodify(f, ":t"), run(cmd), "asm")
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

-- ---- :Odis — build the project, then disassemble the CURRENT file's object ---
-- For files wired into a build tree (kernel.c & friends) godbolt/auto-compile
-- can't work, but `make` + objdump of the produced .o is exactly right. :Odis
-- finds the project root, runs make (async, so nvim stays responsive), maps the
-- source to build/<relpath>.o, and disassembles it. Override with:
--   vim.g.odis_make      (default "make")   e.g. "make -j8" or "gmake"
--   vim.g.odis_build_dir (default "build")
--   vim.g.odis_make_target (default: none — a full build)

function M.odis(arg, with_source)
  local src = need_file(arg); if not src then return end
  src = vim.fn.fnamemodify(src, ":p")
  local ext = (vim.fn.fnamemodify(src, ":e")):lower()
  -- Already an object? just disassemble it.
  if not SRC_EXT[ext] then
    if is_object(src) then return M.objdump(src, with_source) end
    vim.notify("Odis: not a C/C++ source or object: " .. src, vim.log.levels.WARN)
    return
  end

  local root = find_root(src)
  if not root then
    vim.notify("Odis: no Makefile/.git found above " .. src, vim.log.levels.WARN)
    return
  end

  -- Assemble the make command (word-split so "make -j8" works).
  local mcmd = {}
  for w in (vim.g.odis_make or "make"):gmatch("%S+") do mcmd[#mcmd + 1] = w end
  vim.list_extend(mcmd, { "-C", root })
  if vim.g.odis_make_target and #vim.g.odis_make_target > 0 then
    mcmd[#mcmd + 1] = vim.g.odis_make_target
  end

  local function after_build(code, output)
    if code ~= 0 then
      local lines = { "; make failed (exit " .. code .. ") in " .. root .. ":",
        "; $ " .. table.concat(mcmd, " "), "" }
      vim.list_extend(lines, output)
      scratch("odis://make-error", lines, "asm")
      return
    end
    local obj = locate_object(root, src)
    if vim.fn.filereadable(obj) == 0 then
      scratch("odis://" .. vim.fn.fnamemodify(src, ":t"), {
        "; build succeeded, but no object found for " .. src,
        "; looked for: " .. obj,
        "; set  :lua vim.g.odis_build_dir='<dir>'  or run  :Objdump <path>  directly.",
      }, "asm")
      return
    end
    M.objdump(obj, with_source)
  end

  vim.notify("Odis: building (" .. table.concat(mcmd, " ") .. ") …")
  if vim.system then
    vim.system(mcmd, { text = true }, vim.schedule_wrap(function(res)
      local out = vim.split((res.stdout or "") .. (res.stderr or ""), "\n", { trimempty = true })
      after_build(res.code, out)
    end))
  else
    local out = vim.fn.systemlist(mcmd)
    after_build(vim.v.shell_error, out)
  end
end

function M.setup()
  local cmd = vim.api.nvim_create_user_command
  local complete = "file"
  cmd("Objdump",    function(o) M.objdump(o.args, false) end, { nargs = "?", complete = complete })
  cmd("ObjdumpSrc", function(o) M.objdump(o.args, true)  end, { nargs = "?", complete = complete })
  cmd("Readelf",    function(o) M.readelf(o.args) end,        { nargs = "?", complete = complete })
  cmd("Nm",         function(o) M.nm(o.args) end,             { nargs = "?", complete = complete })
  cmd("Odis",       function(o) M.odis(o.args ~= "" and o.args or nil, false) end, { nargs = "?", complete = complete })
  cmd("OdisSrc",    function(o) M.odis(o.args ~= "" and o.args or nil, true)  end, { nargs = "?", complete = complete })

  local map = vim.keymap.set
  -- Primary: build + disassemble the CURRENT file (works for kernel-style
  -- sources). :Objdump/:ObjdumpSrc remain as commands for explicit paths.
  map("n", "<leader>od", "<cmd>Odis<cr>",       { desc = "Odis — make + disasm this file's .o" })
  map("n", "<leader>oD", "<cmd>OdisSrc<cr>",    { desc = "Odis — make + disasm + source" })
  map("n", "<leader>oe", "<cmd>Readelf<cr>",    { desc = "Readelf — ELF headers/sections" })
  map("n", "<leader>on", "<cmd>Nm<cr>",         { desc = "Nm — symbols (sorted)" })
end

return M

