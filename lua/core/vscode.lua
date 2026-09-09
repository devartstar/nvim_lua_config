-- =====================================================================
-- VS Code (vscode-neovim) integration layer
-- =====================================================================
-- This file is loaded ONLY when Neovim runs embedded inside VS Code
-- (i.e. when `vim.g.vscode` is set by the vscode-neovim extension).
--
-- Inside VS Code we do NOT load lazy.nvim or any of the UI/LSP plugins
-- (Telescope, nvim-tree, mason/lspconfig, gitsigns, cmp, which-key, ...).
-- VS Code already provides all of those. Instead we re-map the same
-- leader keybindings from the plugin config onto the equivalent VS Code
-- commands, so the muscle memory carries over 1:1.
--
-- Everything in core/options.lua and core/keymaps.lua still runs, so plain
-- Vim motions, options and editing keymaps behave exactly like the terminal
-- config. The maps below intentionally OVERRIDE the few core keymaps that
-- only make sense with real Neovim windows/buffers (window + buffer nav).

local ok, vscode = pcall(require, 'vscode')
if not ok then
	-- Not actually running under vscode-neovim; nothing to do.
	return
end

local map = vim.keymap.set

-- Small helper: run a VS Code command.
local function action(name, opts)
	return function()
		vscode.action(name, opts)
	end
end

-- Treesitter isn't loaded here, so the treesitter foldexpr set in
-- core/options.lua would error on fold. Let VS Code own folding instead.
vim.opt.foldmethod = 'manual'
vim.opt.foldexpr = ''

-- ------------------------------------------------------------------
-- Search / Telescope  ->  VS Code
-- ------------------------------------------------------------------
map('n', '<leader>sf', action('workbench.action.quickOpen'), { desc = '[S]earch [F]iles' })
map('n', '<leader><leader>', action('workbench.action.showAllEditors'), { desc = 'Find existing buffers' })
map('n', '<leader>sg', action('workbench.action.findInFiles'), { desc = '[S]earch by [G]rep' })
map('n', '<leader>s/', action('workbench.action.findInFiles'), { desc = '[S]earch in open files' })
map('n', '<leader>/', action('actions.find'), { desc = 'Search in current buffer' })
map('n', '<leader>sd', action('workbench.actions.view.problems'), { desc = '[S]earch [D]iagnostics' })
map('n', '<leader>s.', action('workbench.action.openRecent'), { desc = '[S]earch Recent Files' })
map('n', '<leader>sk', action('workbench.action.openGlobalKeybindings'), { desc = '[S]earch [K]eymaps' })
map('n', '<leader>ss', action('workbench.action.showCommands'), { desc = '[S]earch [S]elect (commands)' })
map('n', '<leader>sr', action('workbench.action.quickOpen'), { desc = '[S]earch [R]esume' })
map('n', '<leader>st', function()
	vscode.action('workbench.action.findInFiles', { args = { query = 'TODO', triggerSearch = true } })
end, { desc = '[S]earch [T]odos' })

-- Search current word under cursor across the project.
map('n', '<leader>sw', function()
	vscode.action('workbench.action.findInFiles', {
		args = { query = vim.fn.expand('<cword>'), triggerSearch = true },
	})
end, { desc = '[S]earch current [W]ord' })

-- File explorer / outline
map('n', '<C-b>', action('workbench.action.toggleSidebarVisibility'), { desc = 'Toggle sidebar' })
map('n', '<leader>so', action('outline.focus'), { desc = '[S]ymbols [O]utline' })

-- ------------------------------------------------------------------
-- LSP  ->  VS Code
-- ------------------------------------------------------------------
map('n', 'gd', action('editor.action.revealDefinition'), { desc = '[G]oto [D]efinition' })
map('n', 'gr', action('editor.action.goToReferences'), { desc = '[G]oto [R]eferences' })
map('n', 'gI', action('editor.action.goToImplementation'), { desc = '[G]oto [I]mplementation' })
map('n', 'gD', action('editor.action.revealDeclaration'), { desc = '[G]oto [D]eclaration' })
map('n', 'gK', action('editor.action.triggerParameterHints'), { desc = 'Signature help' })
map('n', '<leader>rn', action('editor.action.rename'), { desc = '[R]e[n]ame' })
map({ 'n', 'x' }, '<leader>ca', action('editor.action.quickFix'), { desc = '[C]ode [A]ction' })
map('n', '<leader>ds', action('workbench.action.gotoSymbol'), { desc = '[D]ocument [S]ymbols' })
map('n', '<leader>ws', action('workbench.action.showAllSymbols'), { desc = '[W]orkspace [S]ymbols' })
map('n', '<leader>th', action('editor.action.toggleInlayHints'), { desc = '[T]oggle Inlay [H]ints' })
map('n', '<leader>q', action('workbench.actions.view.problems'), { desc = 'Open diagnostics list' })

-- Switch between header / source (.c <-> .h). Uses the Microsoft C/C++
-- extension (ms-vscode.cpptools) command.
local function switch_header_source()
	vscode.action('C_Cpp.SwitchHeaderSource')
end
map('n', '<leader>ah', switch_header_source, { desc = 'Switch header/source' })
map('n', '<leader>kc', switch_header_source, { desc = 'Swap between .c and .h file' })

-- ------------------------------------------------------------------
-- Window navigation  ->  VS Code editor groups
-- (overrides the <C-w> based maps from core/keymaps.lua)
-- ------------------------------------------------------------------
map('n', '<C-h>', action('workbench.action.navigateLeft'), { desc = 'Focus left group' })
map('n', '<C-l>', action('workbench.action.navigateRight'), { desc = 'Focus right group' })
map('n', '<C-j>', action('workbench.action.navigateDown'), { desc = 'Focus lower group' })
map('n', '<C-k>', action('workbench.action.navigateUp'), { desc = 'Focus upper group' })

-- ------------------------------------------------------------------
-- Buffer navigation  ->  VS Code editors/tabs
-- (overrides the :bnext/:bprevious maps from core/keymaps.lua)
-- ------------------------------------------------------------------
map('n', '<Tab>', action('workbench.action.nextEditor'), { desc = 'Next editor' })
map('n', '<S-Tab>', action('workbench.action.previousEditor'), { desc = 'Previous editor' })
map('n', '<leader>bd', action('workbench.action.closeActiveEditor'), { desc = '[B]uffer [D]elete' })
map('n', '<leader>bn', action('workbench.action.nextEditor'), { desc = '[B]uffer [N]ext' })
map('n', '<leader>bp', action('workbench.action.previousEditor'), { desc = '[B]uffer [P]revious' })

-- ------------------------------------------------------------------
-- Build / test tasks  ->  VS Code tasks
-- (the terminal config shells out to `make`; here we use VS Code tasks)
-- ------------------------------------------------------------------
map('n', '<leader>km', action('workbench.action.tasks.build'), { desc = 'Build project' })
map('n', '<leader>kt', action('workbench.action.tasks.test'), { desc = 'Run tests' })
map('n', '<leader>kd', action('workbench.action.tasks.runTask'), { desc = 'Run a task (clean)' })

-- ------------------------------------------------------------------
-- Git (gitsigns)  ->  VS Code SCM / gutter
-- ------------------------------------------------------------------
map('n', ']c', action('workbench.action.editor.nextChange'), { desc = 'Next git change' })
map('n', '[c', action('workbench.action.editor.previousChange'), { desc = 'Previous git change' })
map('n', '<leader>hp', action('editor.action.dirtydiff.next'), { desc = 'Preview git hunk' })

-- ------------------------------------------------------------------
-- Folding  ->  VS Code
-- ------------------------------------------------------------------
-- In vscode-neovim, folds are owned by VS Code (the treesitter foldexpr from
-- core/options.lua does not run here). So the standard `z*` fold keys and the
-- config's <leader>z* fold keys are routed to VS Code's fold commands.
map('n', 'za', action('editor.toggleFold'), { desc = 'Toggle fold' })
map('n', 'zc', action('editor.fold'), { desc = 'Close fold' })
map('n', 'zo', action('editor.unfold'), { desc = 'Open fold' })
map('n', 'zC', action('editor.foldRecursively'), { desc = 'Close fold recursively' })
map('n', 'zO', action('editor.unfoldRecursively'), { desc = 'Open fold recursively' })
map('n', 'zR', action('editor.unfoldAll'), { desc = 'Open all folds' })
map('n', 'zM', action('editor.foldAll'), { desc = 'Close all folds' })
map('n', 'zr', action('editor.unfoldAll'), { desc = 'Open more folds' })
map('n', 'zm', action('editor.foldAll'), { desc = 'Close more folds' })
map('n', 'zv', action('editor.unfold'), { desc = 'Reveal fold at cursor' })

-- The config's <leader>z* fold keymaps (from core/keymaps.lua)
map('n', '<leader>zf', action('editor.toggleFold'), { desc = 'Toggle [F]old under cursor' })
map('n', '<leader>zc', action('editor.fold'), { desc = '[C]lose fold under cursor' })
map('n', '<leader>zo', action('editor.unfold'), { desc = '[O]pen fold under cursor' })
map('n', '<leader>zR', action('editor.unfoldAll'), { desc = 'Open all folds' })
map('n', '<leader>zM', action('editor.foldAll'), { desc = 'Close all folds' })
map('n', '<leader>zr', action('editor.unfoldAll'), { desc = 'Open one level of folds' })
map('n', '<leader>zm', action('editor.foldAll'), { desc = 'Close one level of folds' })

