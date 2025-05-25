return {
  -- Mason tool installer
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    config = function()
      require('mason-tool-installer').setup {
        ensure_installed = {
          'stylua',        -- Lua formatter
          'clang-format',  -- C/C++ formatter
          'codelldb',      -- Debugger for C/C++
          'cppcheck',      -- Static analysis for C/C++
          'ltex-ls',       -- Language tool for documentation
          'cmake-language-server', -- CMake support
          'cpplint',       -- Google C++ style checker
          'include-what-you-use', -- Header optimization
        },
        auto_update = true,
        run_on_start = true,
      }
    end,
  },

  -- Indent detection
  { 'NMAC427/guess-indent.nvim' },
}
