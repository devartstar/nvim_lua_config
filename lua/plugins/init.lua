-- This file returns a table of all plugin specifications
return {
  -- Core functionality
  require('plugins.ui'),        -- UI enhancements
  require('plugins.coding'),    -- Coding tools
  require('plugins.lsp'),       -- LSP configuration
  require('plugins.debug'),     -- Debugging tools
  require('plugins.git'),       -- Git integration
  require('plugins.treesitter'), -- Treesitter configuration
  require('plugins.navigation'), -- Navigation tools
  require('plugins.terminal'),  -- Terminal integration
  require('plugins.completion'), -- Completion (blink.cmp)
  require('plugins.format'),    -- Formatting (conform.nvim)
  require('plugins.tools'),     -- Development tools
  require('plugins.copilot'),   -- GitHub Copilot
  require('plugins.clangd'),    -- Clangd specific settings
}
