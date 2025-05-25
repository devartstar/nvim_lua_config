return {
  -- Detect indentation
  { 'NMAC427/guess-indent.nvim' },

  -- Completion
  {
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    dependencies = {
      {
        'L3MON4D3/LuaSnip',
        version = '2.*',
        build = (function()
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        opts = {},
      },
      'folke/lazydev.nvim',
    },
    opts = {
      -- ...existing blink.cmp config...
    }
  },

  -- Formatting configuration
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Disable auto-format for kernel C files
        local disable_filetypes = { c = true, cpp = true }
        return disable_filetypes[vim.bo[bufnr].filetype] and nil or {
          timeout_ms = 500,
          lsp_format = 'fallback',
        }
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        c = { 'clang-format' },
        cpp = { 'clang-format' },
      },
    },
  },

  -- Mason configuration
  {
    "williamboman/mason.nvim",
    priority = 1000,
    config = function()
      require("mason").setup({
        -- Specify Python path for Windows
        PATH = "append",  -- Prepend/append/skip
        pip = {
          -- Try multiple Python executables
          install_args = {
            "--python", "python",  -- Try system Python first
            "--python", "python3", -- Then try python3
            "--python", string.format("%s/python.exe", vim.fn.expand("$LOCALAPPDATA/Programs/Python/Python*")), -- Try Windows Python installation
          },
        },
      })
    end,
  },

  -- Mason tool installer with fallback formatting option
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    dependencies = { "williamboman/mason.nvim" },
    cmd = { "MasonToolsInstall", "MasonToolsUpdate" },
    config = function()
      -- First try to install clang-format
      require('mason-tool-installer').setup {
        ensure_installed = {
          "stylua",
        },
        auto_update = false,
        run_on_start = false,
      }

      -- Fallback to system clang-format if Mason installation fails
      if vim.fn.executable('clang-format') == 0 then
        vim.notify("Please install clang-format manually or ensure Python is in PATH", vim.log.levels.WARN)
      end
    end,
  },
}
