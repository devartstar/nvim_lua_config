return {
  -- Main Copilot plugin
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = true, -- Use default configuration
  },

  -- Copilot Chat integration
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "main",
    dependencies = {
      "zbirenbaum/copilot.lua",
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("copilotchat_setup").setup()
    end,
  },
}
