-- Global options
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = false

-- General options
local opt = vim.opt

opt.number = true
opt.mouse = 'a'
opt.showmode = false
opt.breakindent = true
opt.undofile = true
opt.ignorecase = true
opt.smartcase = true
opt.signcolumn = 'yes'
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.list = true
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
opt.inccommand = 'split'
opt.cursorline = true
opt.scrolloff = 10
opt.confirm = true

-- Folding settings
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
opt.foldcolumn = "1"

-- Cursor settings
opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,a:blinkon0"

-- Consistent 4-space indentation
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.smartindent = true
opt.autoindent = true
opt.textwidth = 80

-- Clipboard setting (scheduled)
vim.schedule(function()
  vim.opt.clipboard = 'unnamedplus'
end)
