-- Browser-based Markdown preview with native Mermaid diagram support.
--
-- Why a browser preview instead of inline rendering?
--   This machine's terminal is a plain `xterm-256color` with no kitty/sixel
--   graphics protocol, so images (and therefore inline Mermaid diagrams) cannot
--   be drawn in the terminal. Instead, this plugin starts a tiny web server on
--   the remote host and renders Markdown — including Mermaid, KaTeX math, and
--   diagrams — with real HTML/JS in a browser.
--
-- Works great over SSH: because you're connected through VS Code Remote-SSH,
-- the preview port is automatically forwarded to your local machine. When you
-- run `:MarkdownPreviewToggle`, the preview URL is printed — open it (or the
-- forwarded `localhost` URL) in your local browser.
--
-- This lives alongside `render-markdown.nvim` (inline reading in the buffer):
--   • render-markdown  -> quick, terminal-only reading
--   • markdown-preview -> full-fidelity render with Mermaid, math, etc.
return {
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
    ft = { 'markdown' },
    -- Build the bundled Node.js preview app. We call yarn directly (via npx)
    -- rather than `mkdp#util#install()` because that Vim function only exists
    -- after the plugin is sourced, which isn't guaranteed during the build step
    -- (hence the "E117: Unknown function: mkdp#util#install" error otherwise).
    build = 'cd app && npx --yes yarn install',
    init = function()
      -- Expose the server so the forwarded port is reachable from your browser.
      vim.g.mkdp_open_ip = '0.0.0.0'
      vim.g.mkdp_port = '8765'
      -- Don't try to launch a browser on the remote host (there isn't one over
      -- SSH); just print the URL so you can open it locally instead.
      vim.g.mkdp_browser = ''
      vim.g.mkdp_echo_preview_url = 1
      vim.g.mkdp_open_to_the_world = 1
      -- Keep the preview server running when you switch away from the buffer.
      vim.g.mkdp_auto_close = 0
      -- Feature toggles: `maid` = Mermaid, `katex` = math, `uml` = PlantUML.
      vim.g.mkdp_preview_options = {
        mkit = {},
        katex = {},
        uml = {},
        maid = {},
        disable_sync_scroll = 0,
        sync_scroll_type = 'middle',
        hide_yaml_meta = 1,
        content_editable = false,
        disable_filename = 0,
      }
    end,
    keys = {
      { '<leader>mp', '<cmd>MarkdownPreviewToggle<cr>', ft = 'markdown', desc = '[M]arkdown [P]review (browser)' },
    },
  },
}
