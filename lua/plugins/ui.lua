return {
  -- Colorschemes
  {
    'projekt0n/github-nvim-theme',
    priority = 1000,
    lazy = false,
  },
  {
    'sainnhe/gruvbox-material',
    priority = 1000,
    lazy = false,
  },
  {
    'sainnhe/everforest',
    priority = 1000,
    lazy = false,
  },
  {
    'ellisonleao/gruvbox.nvim',
    priority = 1000,
    lazy = false,
  },
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function()
      vim.cmd([[
        set termguicolors
        colorscheme gruvbox
      ]])
    end,
  },
  
  {
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      delay = 0,
      icons = {
        mappings = vim.g.have_nerd_font,
        keys = vim.g.have_nerd_font and {} or {
          Up = '<Up> ', Down = '<Down> ', Left = '<Left> ', Right = '<Right> ',
          C = '<C-…> ', M = '<M-…> ', D = '<D-…> ', S = '<S-…> ',
          CR = '<CR> ', Esc = '<Esc> ', ScrollWheelDown = '<ScrollWheelDown> ',
          ScrollWheelUp = '<ScrollWheelUp> ', NL = '<NL> ', BS = '<BS> ',
          Space = '<Space> ', Tab = '<Tab> ',
          F1 = '<F1>', F2 = '<F2>', F3 = '<F3>', F4 = '<F4>',
          F5 = '<F5>', F6 = '<F6>', F7 = '<F7>', F8 = '<F8>',
          F9 = '<F9>', F10 = '<F10>', F11 = '<F11>', F12 = '<F12>',
        },
      },
      spec = {
        { '<leader>s', group = '[S]earch' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
        { '<leader>b', group = '[B]uffer' },
        { '<leader>z', group = 'Folds' },
        { '<leader>c', group = '[C]opilot / Chat' },
        { '<leader>m', group = '[M]arkdown' },
        { '<leader>r', group = '[R]un / Tasks' },
      },
    },
  },

  -- Statusline: shows mode, git branch, diagnostics, file info at a glance
  {
    'nvim-lualine/lualine.nvim',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
      'AndreM222/copilot-lualine',
    },
    event = 'VeryLazy',
    opts = {
      options = {
        icons_enabled = vim.g.have_nerd_font,
        theme = 'auto',
        component_separators = { left = '|', right = '|' },
        section_separators = vim.g.have_nerd_font and { left = '', right = '' } or { left = '', right = '' },
        globalstatus = true,
      },
      sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = { { 'filename', path = 1 } },
        lualine_x = {
          {
            'copilot',
            show_colors = true,
            -- readable status text when a Nerd Font isn't available
            symbols = vim.g.have_nerd_font and nil or {
              status = {
                icons = {
                  enabled = ' AI',
                  sleep = ' zZ',
                  disabled = ' off',
                  warning = ' AI!',
                  unknown = ' AI?',
                },
              },
            },
          },
          'encoding',
          'fileformat',
          'filetype',
        },
        lualine_y = { 'progress' },
        lualine_z = { 'location' },
      },
    },
  },

  -- Indent guides: vertical lines that make nesting/scopes easy to read
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    event = { 'BufReadPost', 'BufNewFile' },
    opts = {
      indent = { char = '│' },
      scope = { enabled = true, show_start = false, show_end = false },
    },
  },

  -- Highlight and navigate TODO/FIXME/HACK/NOTE comments
  {
    'folke/todo-comments.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = vim.g.have_nerd_font },
    config = function(_, opts)
      require('todo-comments').setup(opts)
      vim.keymap.set('n', ']t', function()
        require('todo-comments').jump_next()
      end, { desc = 'Next [T]odo comment' })
      vim.keymap.set('n', '[t', function()
        require('todo-comments').jump_prev()
      end, { desc = 'Previous [T]odo comment' })
      vim.keymap.set('n', '<leader>st', ':TodoTelescope<CR>', { desc = '[S]earch [T]odos' })
    end,
  },
}
