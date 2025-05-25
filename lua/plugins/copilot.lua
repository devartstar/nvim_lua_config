return {
  -- Main Copilot plugin
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    build = ":Copilot auth",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<M-l>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = {
        enabled = true,
        auto_refresh = true,
        keymap = {
          jump_prev = "[[",
          jump_next = "]]",
          accept = "<CR>",
          refresh = "gr",
          open = "<M-p>",
        },
      },
      filetypes = {
        markdown = true,
        help = true,
        gitcommit = true,
        gitrebase = true,
      },
    },
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
    },
    cmd = {
      "CopilotChat",
      "CopilotChatOpen",
      "CopilotChatToggle",
      "CopilotChatExplain",
      "CopilotChatTests",
      "CopilotChatReview",
      "CopilotChatFix",
      "CopilotChatOptimize",
      "CopilotChatDocs",
    },
    event = "VeryLazy",
    build = function()
      -- If on Windows, skip the `make tiktoken` build command
      if vim.fn.has("win32") == 1 then
        return
      end
      vim.fn.system("make tiktoken")
    end,
    config = function()
      local chat = require("CopilotChat")
      chat.setup({
        debug = false,
        show_help = true,
        name = "copilot-chat",
        separator = "───────────────────────────────",
        window = {
          size = "40%",
          relative = "win",
          row = 0,
          col = 1,
          border = "single",
          zindex = 1,
        },
        mappings = {
          close = {
            normal = "q",
            insert = "<C-c>",
          },
          reset = "<C-l>",
          submit_prompt = {
            normal = "<CR>",
            insert = "<C-s>",
          },
          accept_diff = "<C-y>",
          show_diff = "<C-d>",
        },
        prompts = {
          Explain = "Explain how the following code works:",
          Review = "Review the following code and point out potential issues or improvements:",
          Tests = "Generate unit tests for the following code:",
          Fix = "Fix the following code:",
          Optimize = "Optimize the following code:",
          Docs = "Write documentation for the following code:",
        },
      })

      -- Set up an autocmd to handle window positioning
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "copilot-chat",
        callback = function()
          -- Move window to the far right
          vim.cmd("wincmd L")
          -- Set width to 40% of the editor
          vim.cmd("vertical resize " .. math.floor(vim.o.columns * 0.4))
        end,
      })
    end,
    keys = {
      { "<leader>cc", "<cmd>CopilotChatToggle<CR>", desc = "CopilotChat - Toggle" },
      { "<leader>ce", "<cmd>CopilotChatExplain<CR>", desc = "CopilotChat - Explain code" },
      { "<leader>ct", "<cmd>CopilotChatTests<CR>", desc = "CopilotChat - Generate tests" },
      { "<leader>cr", "<cmd>CopilotChatReview<CR>", desc = "CopilotChat - Review code" },
      { "<leader>cf", "<cmd>CopilotChatFix<CR>", desc = "CopilotChat - Fix code" },
      { "<leader>co", "<cmd>CopilotChatOptimize<CR>", desc = "CopilotChat - Optimize code" },
      { "<leader>cd", "<cmd>CopilotChatDocs<CR>", desc = "CopilotChat - Document code" },
      {
        "<leader>cB",
        function()
          vim.ui.input({ prompt = "Ask Copilot: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CopilotChat " .. input)
            end
          end)
        end,
        desc = "CopilotChat - Custom prompt",
      },
    },
  },
}
