-- Run a CopilotChat command. When invoked from visual mode, leave visual mode
-- first so the '< and '> marks capture the CURRENT selection (CopilotChat's
-- `#selection` context reads those marks). Using <cmd> would keep visual mode
-- active and the marks would be stale, causing "I don't see the code".
local function chat_action(cmd)
  return function()
    if vim.fn.mode():match("^[vV\22]") then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    end
    vim.cmd(cmd)
  end
end

local function has_supported_node()
  local local_node = vim.fn.expand('~/.local/node/node-v22.23.1-linux-x64/bin/node')
  local node_cmd = nil

  if vim.fn.executable(local_node) == 1 then
    node_cmd = local_node
    vim.env.PATH = vim.fn.expand('~/.local/node/node-v22.23.1-linux-x64/bin') .. ':' .. vim.env.PATH
  elseif vim.fn.executable('node') == 1 then
    node_cmd = 'node'
  else
    return false, 'Node.js was not found in PATH.'
  end

  local ok, version = pcall(vim.fn.system, node_cmd .. ' --version')
  if not ok then
    return false, 'Node.js was not found in PATH.'
  end

  version = vim.trim(version)
  if version == '' then
    return false, 'Node.js is installed but its version could not be determined.'
  end

  local major = tonumber(version:match('v?(%d+)'))
  if not major or major < 22 then
    return false, ('Node.js 22 or newer is required, but found %s.'):format(version)
  end

  return true, version
end

local node_ok, node_msg = has_supported_node()
if not node_ok then
  vim.schedule(function()
    vim.notify(
      'Copilot plugins are disabled until Node.js 22+ is available: ' .. node_msg,
      vim.log.levels.WARN,
      { title = 'Copilot' }
    )
  end)
end

return {
  -- Main Copilot plugin
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    build = ":Copilot auth",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<M-l>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = {
        enabled = true,
        auto_refresh = true,
        keymap = {
          jump_prev = "[[",
          jump_next = "]]",
          accept = "<CR>",
          refresh = "gr",
          open = "<M-p>",
        },
      },
      filetypes = {
        markdown = true,
        help = true,
        gitcommit = true,
        gitrebase = true,
      },
    },
    config = function(_, opts)
      if not node_ok then
        return
      end

      require('copilot').setup(opts)

      -- Toggle inline (ghost-text) suggestions on demand
      vim.keymap.set('n', '<leader>tc', function()
        require('copilot.suggestion').toggle_auto_trigger()
        local enabled = vim.b.copilot_suggestion_auto_trigger
        vim.notify('Copilot suggestions ' .. (enabled ~= false and 'enabled' or 'disabled'), vim.log.levels.INFO)
      end, { desc = '[T]oggle [C]opilot suggestions' })
    end,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
      {
        -- Renders markdown (headings, bullets, code blocks) live in the chat
        -- buffer so responses are easy to read instead of raw markdown.
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        ft = { "markdown", "copilot-chat" },
        opts = {
          file_types = { "markdown", "copilot-chat" },
          -- keep it readable without a Nerd Font
          heading = {
            icons = { "# ", "## ", "### ", "#### ", "##### ", "###### " },
          },
          bullet = {
            icons = { "•", "◦", "▸", "▹" },
          },
          code = {
            width = "block",
            left_pad = 1,
            right_pad = 1,
          },
        },
        config = function(_, opts)
          -- While CopilotChat streams a response the buffer changes on every
          -- token, so render-markdown may re-parse against a stale treesitter
          -- tree. The markdown injection directive `set-lang-from-info-string!`
          -- then calls `get_node_text` on an invalidated fenced-code-block
          -- info-string node, which throws "attempt to call method 'range'
          -- (a nil value)" and aborts rendering. Re-register that directive
          -- (force = true) with a pcall guard so a transient invalid node is
          -- skipped instead of crashing.
          local tsquery = require("vim.treesitter.query")
          local directive_opts = vim.fn.has("nvim-0.10") == 1 and { force = true, all = false } or true
          local alias_map = { ex = "elixir", pl = "perl", sh = "bash", uxn = "uxntal", ts = "typescript" }
          tsquery.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
            local node = match[pred[2]]
            if not node then
              return
            end
            local ok, text = pcall(vim.treesitter.get_node_text, node, bufnr)
            if not ok or not text then
              return
            end
            local alias = text:lower()
            local ft = vim.filetype.match({ filename = "a." .. alias })
            metadata["injection.language"] = ft or alias_map[alias] or alias
          end, directive_opts)

          require("render-markdown").setup(opts)
        end,
      },
    },
    cmd = {
      "CopilotChat",
      "CopilotChatOpen",
      "CopilotChatToggle",
      "CopilotChatExplain",
      "CopilotChatTests",
      "CopilotChatReview",
      "CopilotChatFix",
      "CopilotChatOptimize",
      "CopilotChatDocs",
    },
    event = "VeryLazy",
    build = function()
      -- If on Windows, skip the `make tiktoken` build command
      if vim.fn.has("win32") == 1 then
        return
      end
      vim.fn.system("make tiktoken")
    end,
    config = function()
      if not node_ok then
        return
      end

      local chat = require("CopilotChat")
      chat.setup({
        debug = false,
        show_help = true,
        separator = "───────────────────────────────",
        -- default to Claude Opus 4.8; change it any time via :CopilotChatModels
        model = "claude-opus-4.8",
        -- include the visual selection automatically when chat is opened
        -- from visual mode
        selection = "visual",
        highlight_selection = true,
        -- start typing immediately when the chat opens
        auto_insert_mode = true,
        -- centered floating window that adapts to the editor size
        window = {
          layout = "float",
          relative = "editor",
          border = "rounded",
          width = 0.85,
          height = 0.85,
          title = "  Copilot Chat",
          zindex = 100,
        },
        mappings = {
          close = {
            normal = "q",
            insert = "<C-c>",
          },
          reset = "<C-l>",
          submit_prompt = {
            normal = "<CR>",
            insert = "<C-s>",
          },
          -- open the context/prompt completion menu (# for context, / for prompts)
          complete = {
            insert = "<C-o>",
          },
          accept_diff = "<C-y>",
          show_diff = "<C-d>",
        },
        prompts = {
          Explain = "Explain how the following code works:",
          Review = "Review the following code and point out potential issues or improvements:",
          Tests = "Generate unit tests for the following code:",
          Fix = "Fix the following code:",
          Optimize = "Optimize the following code:",
          Docs = "Write documentation for the following code:",
        },
      })

      -- Chat about a specific file: pick it with Telescope, then attach it as
      -- #file context to a prompt you type.
      local function copilot_chat_with_file()
        require("telescope.builtin").find_files({
          attach_mappings = function(prompt_bufnr, _)
            local actions = require("telescope.actions")
            local state = require("telescope.actions.state")
            actions.select_default:replace(function()
              local entry = state.get_selected_entry()
              actions.close(prompt_bufnr)
              if entry then
                vim.ui.input({ prompt = "Ask about " .. entry[1] .. ": " }, function(input)
                  vim.cmd(("CopilotChat #file:%s %s"):format(entry[1], input or ""))
                end)
              end
            end)
            return true
          end,
        })
      end
      vim.keymap.set("n", "<leader>cf", copilot_chat_with_file, { desc = "CopilotChat - Chat with a file" })
    end,
    keys = {
      -- Toggle the floating chat window from any mode (normal, insert, visual,
      -- terminal) so it can be opened/closed without leaving what you're doing.
      {
        "<leader>cc",
        "<cmd>CopilotChatToggle<CR>",
        mode = { "n", "i", "x", "t" },
        desc = "CopilotChat - Toggle window",
      },
      { "<C-g>", "<cmd>CopilotChatToggle<CR>", mode = { "n", "i", "x", "t" }, desc = "CopilotChat - Toggle window" },
      { "<leader>ce", chat_action("CopilotChatExplain"), mode = { "n", "x" }, desc = "CopilotChat - Explain code" },
      { "<leader>ct", chat_action("CopilotChatTests"), mode = { "n", "x" }, desc = "CopilotChat - Generate tests" },
      { "<leader>cr", chat_action("CopilotChatReview"), mode = { "n", "x" }, desc = "CopilotChat - Review code" },
      { "<leader>cx", chat_action("CopilotChatFix"), mode = { "n", "x" }, desc = "CopilotChat - Fix code" },
      { "<leader>co", chat_action("CopilotChatOptimize"), mode = { "n", "x" }, desc = "CopilotChat - Optimize code" },
      { "<leader>cd", chat_action("CopilotChatDocs"), mode = { "n", "x" }, desc = "CopilotChat - Document code" },
      -- Context helpers (buffer context already includes diagnostics)
      { "<leader>cb", "<cmd>CopilotChat #buffer<CR>", desc = "CopilotChat - Current buffer context" },
      { "<leader>cl", "<cmd>CopilotChat #buffer:listed<CR>", desc = "CopilotChat - All listed buffers" },
      { "<leader>cg", "<cmd>CopilotChat #gitdiff:staged<CR>", desc = "CopilotChat - Git staged changes" },
      {
        "<leader>cB",
        function()
          if vim.fn.mode():match("^[vV\22]") then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
          end
          vim.ui.input({ prompt = "Ask Copilot: " }, function(input)
            if input and input ~= "" then
              vim.cmd("CopilotChat " .. input)
            end
          end)
        end,
        mode = { "n", "x" },
        desc = "CopilotChat - Custom prompt",
      },
    },
  },
}
