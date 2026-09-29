return {
  {
    'akinsho/toggleterm.nvim',
    version = "*",
    lazy = false,
    config = function()
      require("toggleterm").setup({
        size = 20,
        -- NOTE: no `open_mapping` and `terminal_mappings = false` on purpose.
        -- toggleterm's open_mapping installs a *buffer-local* <C-\> inside every
        -- terminal it owns (including the Codex panel, which happens to be
        -- toggleterm #1). That buffer-local map ran bare `:ToggleTerm`, i.e. it
        -- toggled Codex itself instead of opening a shell. We instead bind <C-\>
        -- ourselves below to a DEDICATED scratch shell that is independent of
        -- Codex, so it behaves the same everywhere: editor, Codex, any terminal.
        terminal_mappings = false,
        hide_numbers = true,
        shade_filetypes = {},
        shade_terminals = true,
        start_in_insert = true,
        insert_mappings = false,
        persist_size = true,
        direction = "float",
        close_on_exit = true,
        shell = vim.o.shell,
        float_opts = {
          border = "curved",
          winblend = 0,
          highlights = {
            border = "Normal",
            background = "Normal",
          },
        },
      })

      -- A single, dedicated scratch shell on a fixed high id so it never
      -- collides with Codex (#1) or codecompanion terminals. `hidden = true`
      -- keeps it out of :ToggleTerm's numbered rotation; we drive it directly.
      local Terminal = require("toggleterm.terminal").Terminal
      local scratch = Terminal:new({
        cmd = vim.o.shell,
        count = 99,
        hidden = true,
        direction = "float",
        float_opts = { border = "curved" },
      })

      local function toggle_scratch()
        scratch:toggle()
      end

      -- <C-\> (== Caps+\) toggles the scratch shell from ANYWHERE:
      --   normal / insert  -> open or hide it
      --   terminal mode    -> works even while focused inside Codex or any
      --                       other terminal (opens the shell on top; press
      --                       again inside the shell to hide it).
      local map = vim.keymap.set
      map({ "n", "i" }, [[<C-\>]], toggle_scratch, { desc = "Toggle scratch shell" })
      map("t", [[<C-\>]], function()
        toggle_scratch()
      end, { desc = "Toggle scratch shell (from any terminal)" })
    end,
  },
}
