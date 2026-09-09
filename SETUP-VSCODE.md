# Using this Neovim config inside VS Code (and keeping machines in sync)

This repo doubles as my portable dev environment. It runs **real Neovim as the
editing engine inside VS Code** (via the `vscode-neovim` extension) while VS Code
draws the UI, and it also gives me the **full Neovim TUI** in the integrated
terminal. This document explains the moving parts and how to replicate the exact
same setup on a new machine.

## The three layers

| Layer | What it contains | How it syncs |
|-------|------------------|--------------|
| **1. Neovim config** | `init.lua`, `lua/core/*`, `lua/plugins/*`, `lua/core/vscode.lua`, `lazy-lock.json` | **This git repo** |
| **2. VS Code prefs** | `settings.json`, `keybindings.json`, extensions | **VS Code Settings Sync** (live) + committed baseline in [`vscode/`](vscode/) |
| **3. Native deps** | Neovim, zig (treesitter compiler), FiraCode Nerd Font | [`bootstrap.ps1`](bootstrap.ps1) (winget) |

### How vscode-neovim works
Neovim is used **only** as the keybinding/editing engine; VS Code renders
everything. Plugin UIs (Telescope, nvim-tree, lualine, gitsigns, treesitter
colors) do **not** render inside VS Code. So:

- `init.lua` checks `if vim.g.vscode then require('core.vscode') return end`
  **before** bootstrapping `lazy.nvim`, so UI plugins are skipped when embedded.
- [`lua/core/vscode.lua`](lua/core/vscode.lua) remaps the important plugin
  keybindings (Telescope search, LSP, git, folds, tasks, window/buffer nav) onto
  native VS Code commands.
- `vim.g.vscode` is set **only** when embedded, so the integrated-terminal
  Neovim ("Neovim" profile, `Ctrl+Alt+N`) loads the full plugin config normally.

## Set up a brand-new Windows machine

One command reproduces everything:

```powershell
irm https://raw.githubusercontent.com/devartstar/nvim_lua_config/main/bootstrap.ps1 | iex
```

or from a local clone:

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

`bootstrap.ps1` will:
1. `winget install` Neovim, zig, Git, VS Code (skips what's present).
2. Install **FiraCode Nerd Font** per-user (no admin needed).
3. Clone/update this config into `%LOCALAPPDATA%\nvim`.
4. Install `asvetliakov.vscode-neovim` (+ the essential public extensions) and
   remove the conflicting `vscodevim.vim`.
5. Headlessly compile the Treesitter parsers (needs zig).
6. Seed `settings.json` / `keybindings.json` from [`vscode/`](vscode/) **only if
   they don't already exist** (so Settings Sync stays the source of truth).

Then, once VS Code opens:
- **Turn on Settings Sync** (Accounts icon → *Turn on Settings Sync…*), signed in
  with the same GitHub account, so prefs + extensions replicate live.
- **Fully quit and reopen** VS Code (File → Exit) so the font and the
  vscode-neovim extension load cleanly.

## Keeping the two machines in sync (ongoing)

- **Neovim config** — edit → commit → push here; on the other machine `git pull`
  (or re-run `bootstrap.ps1`, which does a fast-forward pull). `lazy-lock.json`
  is committed so plugin versions match exactly.
- **VS Code prefs** — Settings Sync handles `settings.json`, `keybindings.json`,
  and the extension list automatically. The copies in [`vscode/`](vscode/) are a
  human-readable, reproducible baseline, not the live channel.

## Notes / gotchas

- The `vscode/settings.jsonc` baseline is a **curated subset** (fonts,
  neovim path, terminal profile, extension affinity) meant to be *merged*, not a
  dump of every personal setting.
- Folds inside VS Code are owned by VS Code, so `core/vscode.lua` sets
  `foldmethod=manual` and routes `za/zc/zo/...` to `editor.*` fold commands.
- `Ctrl+C` copies a selection in the editor but still passes through to Neovim
  as *interrupt* when nothing is selected (see `vscode/keybindings.jsonc`).
- If the `_getNeovimClient already exists` error appears, a second Vim-style
  extension is still loaded — fully quit VS Code (File → Exit), not just Reload.
