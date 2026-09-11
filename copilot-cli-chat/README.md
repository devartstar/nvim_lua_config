# copilot-cli-chat

A lightweight chat UI over the **GitHub Copilot CLI**, living in a Neovim
Markdown buffer. No Node.js required — it drives the standalone `copilot` CLI.

- Per-project chat threads with a pinned session id (memory persists across
  sends *and* reboots; resume the same thread in a terminal with
  `copilot --resume=<id>`).
- Reads **all** your Copilot sessions (CLI, app, and these nvim chats) and
  renders their transcripts — including Copilot's **reasoning** ("thoughts")
  as foldable blocks so you can learn how it thinks.
- Three modes: `agent` (edit files + run commands), `read` (view files only),
  `chat` (no tools). Cloud/remote sessions open read-only.

## Commands

| Command | Action |
|---|---|
| `:CopilotCli [chat\|read\|agent]` | Open chat for the current project (default `agent`) |
| `:CopilotCliSessions` | Pick/switch between all Copilot sessions |
| `:CopilotCliRefresh` | Rebuild the current chat from its event log (adds reasoning folds) |
| `:CopilotCliSend` | Send the current input |

## Keymaps

| Key | Action |
|---|---|
| `<leader>ai` | Toggle the agent chat for the current project |
| `<leader>as` | Switch between saved sessions |
| `<Enter>` (normal) / `<C-s>` (insert) | Send the message you typed |
| `q` | Hide the chat window |
| `za` / `zR` / `zM` | Toggle one / open all / close all reasoning folds |

Read in **normal mode** (rich markdown renders); press `i` to type.

## Requirements

- **GitHub Copilot CLI** — the desktop app (which caches the CLI under
  `~/.cache/github-copilot-sdk/cli/`) or `npm i -g @github/copilot`.
- `sqlite3`, `python3` (session listing + transcript/thoughts extraction).
- Chats/sessions are stored by Copilot under `~/.copilot/`; these nvim chat
  files live in `~/.copilot-cli/chats/`.

## Install on another machine

1. Clone your nvim config (this folder rides along). lazy.nvim auto-imports
   `lua/plugins/copilot_cli_chat.lua`, which loads this `copilot-cli-chat/`
   directory as a local plugin — nothing else to wire up.
2. (Optional) For terminal use, symlink the bundled helpers onto your PATH:
   ```sh
   ln -sf "$PWD/copilot-cli-chat/bin/"copilot* ~/.local/bin/
   ```
3. **Fonts / symbols:** a Nerd Font (e.g. FiraCode Nerd Font) for icons, plus an
   emoji font so emoji don't show as boxes:
   ```sh
   mkdir -p ~/.local/share/fonts
   curl -fsSL https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf \
     -o ~/.local/share/fonts/NotoColorEmoji.ttf && fc-cache -f
   ```
   Restart your terminal afterwards.

## Layout

```
copilot-cli-chat/
  lua/copilot_cli_chat.lua   the plugin
  bin/                       bundled helpers (copilot-ask, -transcript, -thoughts, -sessions, copilot)
lua/plugins/copilot_cli_chat.lua   lazy.nvim spec that loads it
```

To remove: delete `copilot-cli-chat/` and `lua/plugins/copilot_cli_chat.lua`.
