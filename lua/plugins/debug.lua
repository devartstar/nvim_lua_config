return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "nvim-neotest/nvim-nio",
    },
    config = function()
      local dap = require('dap')
      
      -- C/C++ debugging setup
      dap.adapters.codelldb = {
        type = 'server',
        port = "${port}",
        executable = {
          command = vim.fn.exepath('codelldb'),
          args = {"--port", "${port}"},
        }
      }

      dap.configurations.cpp = {
        {
          name = "Launch",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }
      dap.configurations.c = dap.configurations.cpp

      -- Set up debugging UI
      require("dapui").setup()
      require("nvim-dap-virtual-text").setup()

      -- Debugging keymaps
      vim.keymap.set('n', '<F5>', function() require('dap').continue() end, { desc = 'Debug: Start/Continue' })
      vim.keymap.set('n', '<F10>', function() require('dap').step_over() end, { desc = 'Debug: Step Over' })
      vim.keymap.set('n', '<F11>', function() require('dap').step_into() end, { desc = 'Debug: Step Into' })
      vim.keymap.set('n', '<F12>', function() require('dap').step_out() end, { desc = 'Debug: Step Out' })
      vim.keymap.set('n', '<leader>db', function() require('dap').toggle_breakpoint() end, { desc = 'Debug: Toggle Breakpoint' })
      vim.keymap.set('n', '<leader>dB', function() 
        require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) 
      end, { desc = 'Debug: Set Conditional Breakpoint' })
    end,
  },

  {
    "p00f/godbolt.nvim",
    ft = { "c", "cpp", "rust" },
    config = function()
      require("godbolt").setup({
        languages = {
          c = { compiler = "cg121", options = {} },
          cpp = { compiler = "g121", options = {} },
        },
      })
      vim.keymap.set("n", "<leader>ga", ":Godbolt<CR>", { noremap = true, desc = "View assembly" })
    end,
  },
}
