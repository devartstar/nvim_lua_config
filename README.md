# Neovim Configuration

This configuration is based on [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim), a powerful starting point for Neovim configuration. It provides a rich set of features while maintaining clarity and extensibility.

## Features

All features from kickstart.nvim, including:
- Modern Lua-based configuration
- Lazy-loaded plugin management with lazy.nvim
- LSP configuration out of the box
- Treesitter for better syntax highlighting
- Telescope for fuzzy finding
- Which-key for discovering keymaps
- Git integration with gitsigns
- Completion with nvim-cmp
- And much more!

## Installation

1. Make sure you have Neovim 0.8 or later installed
2. Clone this repository to your Neovim configuration directory:
   - Windows: `%LOCALAPPDATA%\nvim`
   - Linux/macOS: `~/.config/nvim`

3. Start Neovim and lazy.nvim will automatically:
   - Install itself
   - Install configured plugins

## Structure

- `init.lua`: Main configuration file
  - Basic Neovim settings
  - Plugin management setup
  - Key mappings

## Key Mappings

- `<Space>` - Leader key
- `<leader>w` - Save file
- `<leader>q` - Quit

## Adding Plugins

To add new plugins, edit the `init.lua` file and add them to the lazy.nvim setup table. For example:

```lua
require("lazy").setup({
  "username/plugin-name",
  -- Add more plugins here
})
```

## Customization

Feel free to modify `init.lua` to add your own settings, key mappings, and plugins.
