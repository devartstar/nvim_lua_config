-- Custom setup for CopilotChat
local M = {}

function M.setup()  -- Set up CopilotChat with minimal configuration
  require("CopilotChat").setup({
    window = {
      layout = "float", -- Use floating window
      border = "rounded",
      width = 80,
      height = 20,
    },
    -- Prompts that will be used in keymaps
    prompts = {
      Explain = "Explain this code:",
      Review = "Review this code:",
      Tests = "Generate tests for this code:",
    },
  })

  -- Simple keymaps
  vim.keymap.set("n", "<leader>cc", "<cmd>CopilotChatOpen<cr>", { desc = "Open Copilot Chat" })
  vim.keymap.set("v", "<leader>cc", ":'<,'>CopilotChatOpen<cr>", { desc = "Open Copilot Chat with selection" })
  vim.keymap.set("n", "<leader>ce", "<cmd>CopilotChatExplain<cr>", { desc = "Explain code" })
  vim.keymap.set("n", "<leader>ct", "<cmd>CopilotChatTests<cr>", { desc = "Generate tests" })
end

return M
