return {
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = { "c", "cpp", "make", "cmake", "bash", "regex", "vim", "lua" },
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },
        fold = {
          enable = true,
        },
        indent = {
          enable = true
        },
      })
      
      -- Create custom fold text function in the global scope
      _G.CustomFoldText = function()
        local line = vim.fn.getline(vim.v.foldstart)
        local line_count = vim.v.foldend - vim.v.foldstart + 1
        return string.format('%s ... [%d lines]', line, line_count)
      end
      
      vim.opt.foldtext = 'v:lua.CustomFoldText()'
      vim.opt.fillchars = { fold = ' ' }
    end,
  },
  
  -- Treesitter textobjects
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('nvim-treesitter.configs').setup({
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner",
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
            },
          },
        },
      })
    end,
  },

  -- Enhanced folding
  {
    'kevinhwang91/nvim-ufo',
    dependencies = {
      'kevinhwang91/promise-async',
      'neovim/nvim-lspconfig',
    },
    config = function()
      local winid = nil
      local function closePreviewWindow()
        if winid and vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
          winid = nil
        end
      end

      require('ufo').setup({
        provider_selector = function()
          return {'treesitter', 'indent'}
        end,
        preview = {
          win_config = {
            border = 'rounded',
            winblend = 0,
            winhighlight = 'Normal:Normal,FloatBorder:Normal',
            maxheight = 40,
          },
          mappings = {
            scrollB = '<C-b>',
            scrollF = '<C-f>',
            scrollU = '<C-u>',
            scrollD = '<C-d>',
            close = {'q', '<Esc>'},
          },
        },
        close_fold_kinds_for_ft = {
          default = {'imports', 'comment'},
        },
        open_fold_hl_timeout = 400,
      })

      -- Enhanced preview function setup
      local function enhanced_preview()
        closePreviewWindow()
        winid = require('ufo').peekFoldedLinesUnderCursor()
        if not winid then
          local params = vim.lsp.util.make_position_params()
          vim.lsp.buf_request(0, 'textDocument/definition', params, function(_, result)
            if result and result[1] then
              local lines = vim.lsp.util.preview_location(result[1])
              if lines then
                winid = vim.lsp.util.open_floating_preview(lines, 'lua', {
                  border = 'rounded',
                  focus = false,
                })
              end
            end
          end)
        end
      end

      -- Set up keymaps
      vim.keymap.set('n', 'gpd', enhanced_preview, { noremap = true, silent = true, desc = '[P]review [D]efinition' })
      vim.keymap.set('n', 'gP', function()
        vim.lsp.buf.hover()
      end, { noremap = true, silent = true, desc = '[G]et Full Preview' })
      
      -- Close preview on cursor move
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = vim.api.nvim_create_augroup('close_preview_on_move', { clear = true }),
        callback = closePreviewWindow,
      })
    end,
  },
}
