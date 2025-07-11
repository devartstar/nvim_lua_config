return {
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
        return {
          timeout_ms = 500,
          lsp_format = 'fallback',
        }
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        c = { 'clang-format' },
        cpp = { 'clang-format' },
      },
      formatters = {
        ['clang-format'] = {
          prepend_args = {
            '--style={IndentWidth: 4, TabWidth: 4, UseTab: Never, ColumnLimit: 80, AccessModifierOffset: -4}',
          },
        },
        stylua = {
          prepend_args = {
            '--indent-type',
            'Spaces',
            '--indent-width',
            '4',
            '--column-width',
            '80',
          },
        },
      },
    },
  },
}
