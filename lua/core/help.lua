local M = {}

-- Plugin help documentation
M.plugin_help = {
  -- Basic keymaps
  general = {
    title = "General Keymaps",
    description = "Basic Neovim operations",
    keymaps = {
      ["<Esc>"] = "Clear search highlights",
      ["<C-h/j/k/l>"] = "Navigate between windows",
      ["<leader>q"] = "Open diagnostic quickfix list",
      ["<Esc><Esc>"] = "Exit terminal mode",
    }
  },

  -- Folding
  folding = {
    title = "Code Folding",
    description = "Manage code folds",
    keymaps = {
      ["<leader>zf"] = "Toggle fold under cursor",
      ["<leader>zc"] = "Close fold under cursor",
      ["<leader>zo"] = "Open fold under cursor",
      ["<leader>zR"] = "Open all folds",
      ["<leader>zM"] = "Close all folds",
      ["<leader>zr"] = "Open one level of folds",
      ["<leader>zm"] = "Close one level of folds",
    }
  },

  -- LSP
  lsp = {
    title = "LSP (Language Server Protocol)",
    description = "Code intelligence and completion",
    keymaps = {
      ["gd"] = "Go to definition",
      ["gr"] = "Find references",
      ["gI"] = "Go to implementation",
      ["gD"] = "Go to declaration",
      ["K"] = "Show hover documentation",
      ["gK"] = "Show signature help",
      ["<leader>wa"] = "Add workspace folder",
      ["<leader>wr"] = "Remove workspace folder",
      ["<leader>wl"] = "List workspace folders",
      ["<leader>rn"] = "Rename symbol",
      ["<leader>ca"] = "Code actions",
      ["<leader>ds"] = "Document symbols",
      ["<leader>ws"] = "Workspace symbols",
      ["<leader>th"] = "Toggle inlay hints",
      ["gpd"] = "Preview definition",
      ["gh"] = "Get hover documentation",
      ["grt"] = "Go to type definition",
    }
  },

  -- Telescope
  telescope = {
    title = "Telescope (Fuzzy Finder)",
    description = "Advanced search and navigation",
    keymaps = {
      ["<leader>sh"] = "Search help tags",
      ["<leader>sk"] = "Search keymaps",
      ["<leader>sf"] = "Search files",
      ["<leader>ss"] = "Search select telescope",
      ["<leader>sw"] = "Search current word",
      ["<leader>sg"] = "Search by grep",
      ["<leader>sd"] = "Search diagnostics",
      ["<leader>sr"] = "Resume last search",
      ["<leader>s."] = "Search recent files",
      ["<leader>/"] = "Fuzzy search in current buffer",
      ["<leader>s/"] = "Live grep in open files",
      ["<leader>sn"] = "Search neovim config files",
      ["<leader><leader>"] = "Find existing buffers",
    }
  },

  -- File Explorer
  nvim_tree = {
    title = "Nvim-tree (File Explorer)",
    description = "File system navigation",
    keymaps = {
      ["<C-b>"] = "Toggle file explorer",
    }
  },

  -- Debug
  debug = {
    title = "Debugging (DAP)",
    description = "Debug adapter protocol integration",
    keymaps = {
      ["<F5>"] = "Start/Continue debugging",
      ["<F10>"] = "Step over",
      ["<F11>"] = "Step into",
      ["<F12>"] = "Step out",
      ["<leader>db"] = "Toggle breakpoint",
      ["<leader>dB"] = "Set conditional breakpoint",
    }
  },

  -- Git
  git = {
    title = "Git Integration (Gitsigns)",
    description = "Git operations and signs",
    features = {
      "Shows git changes in sign column (+, ~, _, ‾)",
      "Stage/unstage hunks",
      "Preview changes",
      "Blame line information"
    }
  },

  -- Formatting
  format = {
    title = "Code Formatting",
    description = "Code formatting with conform.nvim",
    keymaps = {
      ["<leader>f"] = "Format buffer",
    },
    features = {
      "Automatic format on save (except C/C++ files)",
      "Support for multiple formatters",
      "Language-specific formatting"
    }
  },

  -- Completion
  completion = {
    title = "Completion (blink.cmp)",
    description = "Intelligent code completion",
    keymaps = {
      ["<C-Space>"] = "Open completion menu",
      ["<C-y>"] = "Confirm completion",
      ["<C-e>"] = "Close completion menu",
      ["<C-n/p>"] = "Navigate completion items",
      ["<Tab>"] = "Next snippet position",
      ["<S-Tab>"] = "Previous snippet position",
      ["<C-k>"] = "Toggle signature help",
    }
  },

  -- Treesitter
  treesitter = {
    title = "Treesitter",
    description = "Syntax and code navigation",
    textobjects = {
      ["af"] = "Around function",
      ["if"] = "Inside function",
      ["ac"] = "Around class",
      ["ic"] = "Inside class",
      ["aa"] = "Around parameter",
      ["ia"] = "Inside parameter",
    },
    movements = {
      ["]f"] = "Next function start",
      ["[f"] = "Previous function start",
      ["]c"] = "Next class start",
      ["[c"] = "Previous class start",
      ["]F"] = "Next function end",
      ["[F"] = "Previous function end",
    }
  },

  -- Terminal
  terminal = {
    title = "Terminal Integration",
    description = "Built-in terminal features",
    keymaps = {
      ["<c-\\>"] = "Toggle terminal",
    },
    features = {
      "Floating terminal window",
      "Terminal persistence",
      "Multiple terminal support"
    }
  },

  -- Copilot
  copilot = {
    title = "GitHub Copilot",
    description = "AI code completion and chat",
    keymaps = {
      ["<M-l>"] = "Accept suggestion",
      ["<M-]>"] = "Next suggestion",
      ["<M-[>"] = "Previous suggestion",
      ["<C-]>"] = "Dismiss suggestion",
      ["<leader>ce"] = "Explain code",
      ["<leader>ct"] = "Generate tests",
      ["<leader>cr"] = "Review code",
      ["<leader>cf"] = "Refactor code",
    }
  },

  -- Kernel Development
  kernel = {
    title = "Kernel Development",
    description = "Linux kernel development tools",
    keymaps = {
      ["<leader>kc"] = "Switch between .c and .h files",
      ["<leader>kt"] = "Run kernel tests",
      ["<leader>km"] = "Build kernel module",
      ["<leader>kd"] = "Clean kernel build",
    },
    settings = {
      "8-space tabs (kernel style)",
      "80 character line limit",
      "Specialized clangd configuration",
      "Kernel-specific formatting rules"
    }
  },

  -- Symbol Outline
  symbols = {
    title = "Symbols Outline",
    description = "Code structure viewer",
    keymaps = {
      ["<leader>so"] = "Toggle symbols outline",
      ["o"] = "Goto location",
      ["<C-space>"] = "Hover symbol",
      ["r"] = "Rename symbol",
      ["a"] = "Code actions",
    }
  }
}

-- Function to show help in a floating window
function M.show_plugin_help()
  local content = {}
  for category, info in pairs(M.plugin_help) do
    -- Add title
    table.insert(content, string.format("# %s", info.title))
    table.insert(content, info.description)
    table.insert(content, "") -- Empty line after description
    
    -- Add keymaps section
    if info.keymaps then
      table.insert(content, "## Keymaps")
      for key, desc in pairs(info.keymaps) do
        table.insert(content, string.format("%-20s %s", key, desc))
      end
      table.insert(content, "") -- Empty line after section
    end

    -- Add features section
    if info.features then
      table.insert(content, "## Features")
      for _, feature in ipairs(info.features) do
        table.insert(content, "- " .. feature)
      end
      table.insert(content, "") -- Empty line after section
    end
    
    -- Add settings section
    if info.settings then
      table.insert(content, "## Settings")
      for _, setting in ipairs(info.settings) do
        table.insert(content, "- " .. setting)
      end
      table.insert(content, "") -- Empty line after section
    end

    table.insert(content, "") -- Extra line between categories
  end
  
  -- Calculate window size and position
  local width = 80
  local height = 40
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create the floating window
  local buf = vim.api.nvim_create_buf(false, true)
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Plugin Help ',
    title_pos = 'center',
  }
  
  -- Set buffer content and options
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  -- Create window and set keymaps
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  
  -- Add keymap to close the window
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
end

return M
