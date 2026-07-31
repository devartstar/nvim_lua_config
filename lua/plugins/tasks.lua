-- Task runner: discover and run Makefile (and other) targets from a picker.
--
-- overseer.nvim ships a built-in "make" template that parses the targets out
-- of your Makefile, lists them in a selection menu (rendered through your
-- existing telescope-ui-select), runs them, and streams output into a panel
-- that also populates the quickfix list. This makes it easy to see *what*
-- targets exist and run them without memorizing names.
--
-- Keymaps (under the <leader>r "Run/Tasks" group):
--   <leader>rt  pick & run a task/target
--   <leader>ro  toggle the task output panel
--   <leader>ra  quick action on a running/finished task (restart, stop, ...)
--   <leader>rc  run an arbitrary shell command as a task
return {
  {
    'stevearc/overseer.nvim',
    cmd = {
      'OverseerRun',
      'OverseerToggle',
      'OverseerRunCmd',
      'OverseerQuickAction',
      'OverseerTaskAction',
    },
    keys = {
      { '<leader>rt', '<cmd>OverseerRun<cr>', desc = '[R]un [T]ask / make target' },
      { '<leader>ro', '<cmd>OverseerToggle<cr>', desc = '[R]un: toggle [O]utput panel' },
      { '<leader>ra', '<cmd>OverseerQuickAction<cr>', desc = '[R]un: task [A]ction' },
      { '<leader>rc', '<cmd>OverseerRunCmd<cr>', desc = '[R]un shell [C]ommand' },
    },
    opts = {
      -- Pull in the bundled templates, including the Makefile target parser.
      templates = { 'builtin' },
      task_list = {
        direction = 'bottom',
        min_height = 12,
        default_detail = 1,
      },
    },
  },
}
