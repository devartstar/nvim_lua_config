-- Copilot CLI chat — local plugin (no external repo).
-- Auto-imported by lazy.nvim from lua/plugins/. Provides :CopilotCli.
-- Installed by the Copilot setup helper; delete this file and the
-- ~/.config/nvim/copilot-cli-chat/ folder to fully remove it.
return {
  dir = vim.fn.stdpath("config") .. "/copilot-cli-chat",
  name = "copilot-cli-chat",
  lazy = false,
  config = function()
    require("copilot_cli_chat").setup()
  end,
}
