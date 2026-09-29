-- Option A wiring: bind the project-scoped Codex CLI terminal.
--
-- This spec attaches to the already-configured toggleterm.nvim (see
-- lua/plugins/terminal.lua). lazy.nvim merges specs for the same plugin, so
-- these keys simply lazy-load toggleterm the first time you press them.
--
-- All Codex/ChatGPT mappings live under <leader>x ("codeX"), kept separate
-- from the Copilot mappings under <leader>a / <leader>c.
return {
  "akinsho/toggleterm.nvim",
  keys = {
    {
      "<leader>xx",
      function() require("codex_term").toggle() end,
      mode = "n",
      desc = "Codex CLI — toggle (project)",
    },
    {
      "<leader>xX",
      function() require("codex_term").toggle_cwd() end,
      mode = "n",
      desc = "Codex CLI — toggle (cwd)",
    },
    {
      "<leader>xF",
      function() require("codex_ask").ask(false) end,
      mode = "n",
      desc = "Codex — ask box (answer in nvim buffer)",
    },
    {
      "<leader>xN",
      function() require("codex_ask").ask_new() end,
      mode = "n",
      desc = "Codex — ask box (new thread)",
    },
    {
      "<leader>xt",
      function() require("codex_term").toggle_float() end,
      mode = "n",
      desc = "Codex CLI — interactive TUI float",
    },
    {
      "<leader>xf",
      function() require("codex_term").add_file() end,
      mode = "n",
      desc = "Codex CLI — attach current file (@)",
    },
    {
      "<leader>xr",
      function() require("codex_term").resume() end,
      mode = "n",
      desc = "Codex CLI — resume session (this project)",
    },
    {
      "<leader>xR",
      function() require("codex_term").resume(true) end,
      mode = "n",
      desc = "Codex CLI — resume session (all projects)",
    },
    {
      "<leader>xl",
      function() require("codex_term").resume_last() end,
      mode = "n",
      desc = "Codex CLI — continue last session",
    },
  },
}
