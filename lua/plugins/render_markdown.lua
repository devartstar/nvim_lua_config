-- Pretty in-buffer Markdown rendering for AI chats (and Markdown files).
--
-- Without this, CodeCompanion responses show raw Markdown (literal #, *, `).
-- render-markdown.nvim draws headings, bullets, code blocks, tables, rules and
-- inline styles as real formatting, live, while the buffer stays editable.
--
-- Scoped to the chat/markdown filetypes so it only touches those buffers. It
-- also prettifies the existing Copilot CLI chat (a `markdown` buffer) for free.
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    file_types = { "markdown", "codecompanion" },
    -- Render even while editing; only stop concealing on the cursor's own line.
    render_modes = { "n", "c", "i" },
    anti_conceal = { enabled = true },
    heading = { sign = false, width = "block", left_pad = 0, right_pad = 2 },
    code = {
      sign = false,
      width = "block",
      left_pad = 1,
      right_pad = 2,
      border = "thin",
    },
    bullet = { icons = { "•", "◦", "▸", "▹" } },
    checkbox = {
      unchecked = { icon = "󰄱 " },
      checked = { icon = "󰱒 " },
    },
  },
}
