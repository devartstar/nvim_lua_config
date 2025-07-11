local keymap = vim.keymap.set

-- Clear search highlights
keymap('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
keymap('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Terminal escape
keymap('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Window navigation
keymap('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
keymap('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
keymap('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
keymap('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Folding keymaps
keymap('n', '<leader>zf', 'za', { desc = 'Toggle [F]old under cursor' })
keymap('n', '<leader>zc', 'zc', { desc = '[C]lose fold under cursor' })
keymap('n', '<leader>zo', 'zo', { desc = '[O]pen fold under cursor' })
keymap('n', '<leader>zR', 'zR', { desc = 'Open all folds' })
keymap('n', '<leader>zM', 'zM', { desc = 'Close all folds' })
keymap('n', '<leader>zr', 'zr', { desc = 'Open one level of folds' })
keymap('n', '<leader>zm', 'zm', { desc = 'Close one level of folds' })

-- Development specific keymaps (updated from kernel-specific)
keymap('n', '<leader>kc', ':e %:p:s,.h$,.X123X,:s,.c$,.h,:s,.X123X$,.c,<CR>', { desc = "Swap between .c and .h file" })
keymap('n', '<leader>kt', ':new term://pwsh<CR>make test<CR>', { desc = "Run tests" })
keymap('n', '<leader>km', ':new term://pwsh<CR>make<CR>', { desc = "Build project" })
keymap('n', '<leader>kd', ':new term://pwsh<CR>make clean<CR>', { desc = "Clean build" })

-- Help keymaps
vim.keymap.set('n', '<leader>h?', function()
  require('core.help').show_plugin_help()
end, { desc = 'Show plugin [H]elp' })
