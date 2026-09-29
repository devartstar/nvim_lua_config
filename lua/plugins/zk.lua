return {
  "zk-org/zk-nvim",
  ft = "markdown",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("zk").setup({
      picker = "telescope",
      lsp = { config = { cmd = { "zk", "lsp" }, name = "zk" }, auto_attach = { enabled = true } },
    })

    local map = vim.keymap.set
    local opts = { silent = false }
    -- new note in inbox from a title prompt
    map("n", "<leader>nn", "<Cmd>ZkNew { group = 'inbox', title = vim.fn.input('Title: ') }<CR>", opts)
    -- today's daily note
    map("n", "<leader>nd", "<Cmd>ZkNew { group = 'daily' }<CR>", opts)
    -- open note (fuzzy)
    map("n", "<leader>no", "<Cmd>ZkNotes { sort = { 'modified' } }<CR>", opts)
    -- full-text search
    map("n", "<leader>nf", "<Cmd>ZkNotes { sort = { 'modified' }, match = { vim.fn.input('Search: ') } }<CR>", opts)
    -- browse by tag
    map("n", "<leader>nt", "<Cmd>ZkTags<CR>", opts)
    -- backlinks / links of current note
    map("n", "<leader>nb", "<Cmd>ZkBacklinks<CR>", opts)
    map("n", "<leader>nl", "<Cmd>ZkLinks<CR>", opts)
    -- create a note from visual selection as its title, and link it
    map("v", "<leader>nc", ":'<,'>ZkNewFromTitleSelection { group = 'inbox' }<CR>", opts)
  end,
}
