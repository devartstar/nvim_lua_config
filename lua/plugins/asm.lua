-- asm.lua — assembly / machine-code workbench plugins.
--   * compiler-explorer.nvim : Godbolt inside nvim. See the exact asm your C
--     compiles to, with source<->asm line highlighting. Ideal for MMIO/kernel
--     work (watch what `volatile` accesses and optimisation levels really emit).
--   * hex.nvim               : toggle any file into a live hex view (xxd) you
--     can edit and write back — for raw machine code / firmware blobs.
-- Objdump/readelf/nm helpers live in lua/asm_tools.lua (no plugin needed).
return {
  {
    'krady21/compiler-explorer.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = {
      'CECompile', 'CECompileLive', 'CEFormat', 'CEAddLibrary',
      'CELoadExample', 'CEDeleteCache', 'CEShowTooltip', 'CEGotoLabel',
      'CEOpenWebsite',
    },
    keys = {
      { '<leader>oc', '<cmd>CECompile<cr>',     mode = { 'n', 'v' }, desc = 'Compiler Explorer — compile to asm' },
      { '<leader>ol', '<cmd>CECompileLive<cr>', desc = 'Compiler Explorer — live (recompile on save)' },
      { '<leader>of', '<cmd>CEFormat<cr>',      desc = 'Compiler Explorer — format source' },
      { '<leader>ok', '<cmd>CEGotoLabel<cr>',   desc = 'Compiler Explorer — jump to label under cursor' },
    },
    config = function()
      require('compiler-explorer').setup({
        url = 'https://godbolt.org',
        infer_lang = true,       -- guess language from filetype
        line_match = {
          highlight = true,      -- highlight matching source<->asm lines
          jump = true,
        },
        split = 'split',         -- horizontal asm pane
        job_action = 'compile',
        -- Kernel-style defaults: optimised, C11. Override per-compile with the
        -- flags prompt if needed.
        compiler_flags = '-O2 -std=c11',
        languages = {
          c   = { compiler_flags = '-O2 -std=c11' },
          cpp = { compiler_flags = '-O2 -std=c++17' },
        },
      })
    end,
  },

  {
    'RaafatTurki/hex.nvim',
    cmd = { 'HexToggle', 'HexDump', 'HexAssemble' },
    keys = {
      { '<leader>ox', '<cmd>HexToggle<cr>', desc = 'Hex view — toggle (xxd)' },
    },
    config = true,
  },
}
