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

-- Buffer navigation
keymap('n', '<Tab>', ':bnext<CR>', { silent = true, desc = 'Next buffer' })
keymap('n', '<S-Tab>', ':bprevious<CR>', { silent = true, desc = 'Previous buffer' })
keymap('n', '<leader>bd', ':bdelete<CR>', { silent = true, desc = '[B]uffer [D]elete' })
keymap('n', '<leader>bn', ':bnext<CR>', { silent = true, desc = '[B]uffer [N]ext' })
keymap('n', '<leader>bp', ':bprevious<CR>', { silent = true, desc = '[B]uffer [P]revious' })

-- Move selected lines up/down (keeps indentation)
keymap('v', 'J', ":m '>+1<CR>gv=gv", { desc = 'Move selection down' })
keymap('v', 'K', ":m '<-2<CR>gv=gv", { desc = 'Move selection up' })

-- Keep cursor centered when scrolling / searching
keymap('n', '<C-d>', '<C-d>zz', { desc = 'Scroll down and center' })
keymap('n', '<C-u>', '<C-u>zz', { desc = 'Scroll up and center' })
keymap('n', 'n', 'nzzzv', { desc = 'Next search result centered' })
keymap('n', 'N', 'Nzzzv', { desc = 'Previous search result centered' })


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
