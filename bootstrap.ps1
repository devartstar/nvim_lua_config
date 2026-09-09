<#
.SYNOPSIS
    One-command setup for the vscode-neovim + Neovim TUI environment on Windows.

.DESCRIPTION
    Reproduces, on a fresh Windows machine, the same setup you built interactively:
      1. Installs native dependencies via winget: Neovim, zig (treesitter compiler),
         Git and VS Code (skipped if already present).
      2. Installs FiraCode Nerd Font (per-user) so the file-tree / statusline glyphs render.
      3. Clones (or updates) this Neovim config into %LOCALAPPDATA%\nvim.
      4. Installs the vscode-neovim extension and removes the conflicting VSCodeVim.
      5. Pre-compiles the Treesitter parsers headlessly so first launch is clean.
      6. Seeds VS Code settings.json / keybindings.json from the committed baseline
         ONLY if they don't already exist (so Settings Sync stays the source of truth).

    Safe to re-run: every step is idempotent.

.PARAMETER SeedVSCodeSettings
    Force-seed settings.json / keybindings.json from the baseline even if VS Code
    already has them. A timestamped backup is written first. Use this only on a
    machine that is NOT using Settings Sync.

.EXAMPLE
    # From anywhere:
    irm https://raw.githubusercontent.com/devartstar/nvim_lua_config/main/bootstrap.ps1 | iex

.EXAMPLE
    # From a local clone:
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
#>
[CmdletBinding()]
param(
    [switch]$SeedVSCodeSettings
)

$ErrorActionPreference = 'Stop'
$RepoUrl   = 'https://github.com/devartstar/nvim_lua_config.git'
$NvimDir   = Join-Path $env:LOCALAPPDATA 'nvim'
$CodeUser  = Join-Path $env:APPDATA 'Code\User'
$NvimExe   = 'C:\Program Files\Neovim\bin\nvim.exe'

function Info($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Ok  ($m){ Write-Host "    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "    $m" -ForegroundColor Yellow }

function Have($cmd){ [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Install-Winget($id, $probeCmd){
    if ($probeCmd -and (Have $probeCmd)) { Ok "$id already present ($probeCmd)"; return }
    if (-not (Have 'winget')) { throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run." }
    Info "Installing $id via winget..."
    winget install -e --id $id --accept-source-agreements --accept-package-agreements --silent
    Ok "$id installed"
}

# ---------------------------------------------------------------------------
# 1. Native dependencies
# ---------------------------------------------------------------------------
Info 'Step 1/6: native dependencies'
Install-Winget 'Git.Git'          'git'
Install-Winget 'Neovim.Neovim'    'nvim'
Install-Winget 'zig.zig'          'zig'
Install-Winget 'Microsoft.VisualStudioCode' 'code'

# Make freshly-installed tools visible in this session.
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')

# ---------------------------------------------------------------------------
# 2. FiraCode Nerd Font (per-user install; no admin required)
# ---------------------------------------------------------------------------
Info 'Step 2/6: FiraCode Nerd Font'
Add-Type -AssemblyName System.Drawing
$fc = New-Object System.Drawing.Text.InstalledFontCollection
if ($fc.Families.Name -contains 'FiraCode Nerd Font Mono') {
    Ok 'FiraCode Nerd Font already installed'
} else {
    $tmp = Join-Path $env:TEMP 'FiraCodeNF'
    $zip = Join-Path $env:TEMP 'FiraCode.zip'
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Info 'Downloading FiraCode Nerd Font...'
    Invoke-WebRequest 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip' -OutFile $zip
    Expand-Archive $zip -DestinationPath $tmp -Force

    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    $regKey  = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    function Get-FullName($base){
        $weight = ($base -split '-')[-1]
        $fam = $base -replace "-$weight$",''
        $fam = $fam -replace 'FiraCodeNerdFontMono','FiraCode Nerd Font Mono' `
                    -replace 'FiraCodeNerdFontPropo','FiraCode Nerd Font Propo' `
                    -replace 'FiraCodeNerdFont','FiraCode Nerd Font'
        if ($weight -eq 'Regular') { return $fam } else { return "$fam $weight" }
    }

    $n = 0
    Get-ChildItem $tmp -Filter *.ttf | ForEach-Object {
        $dest = Join-Path $fontDir $_.Name
        Copy-Item $_.FullName $dest -Force
        $full = Get-FullName $_.BaseName
        New-ItemProperty -Path $regKey -Name "$full (TrueType)" -Value $dest -PropertyType String -Force | Out-Null
        $n++
    }
    Ok "Installed $n font faces"

    # Tell running apps to re-enumerate fonts.
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FB { [DllImport("user32.dll")] public static extern int SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r); }
"@
    $r = [IntPtr]::Zero
    [FB]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$r) | Out-Null
    Remove-Item -Recurse -Force $tmp, $zip -ErrorAction SilentlyContinue
    Ok 'FiraCode Nerd Font installed'
}

# ---------------------------------------------------------------------------
# 3. Clone / update the Neovim config
# ---------------------------------------------------------------------------
Info 'Step 3/6: Neovim config'
if (Test-Path (Join-Path $NvimDir '.git')) {
    Info "Updating existing config at $NvimDir"
    git -C $NvimDir pull --ff-only
} elseif (Test-Path $NvimDir) {
    Warn "$NvimDir exists but is not a git repo. Backing it up."
    Move-Item $NvimDir "$NvimDir.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    git clone $RepoUrl $NvimDir
} else {
    git clone $RepoUrl $NvimDir
}
Ok 'Config in place'

# ---------------------------------------------------------------------------
# 4. VS Code extensions
# ---------------------------------------------------------------------------
Info 'Step 4/6: VS Code extensions'
if (Have 'code') {
    $installed = (code --list-extensions) 2>$null
    if ($installed -contains 'vscodevim.vim') {
        Warn 'Removing conflicting VSCodeVim (vscodevim.vim)'
        code --uninstall-extension vscodevim.vim | Out-Null
    }
    $extFile = Join-Path $NvimDir 'vscode\extensions.txt'
    Get-Content $extFile | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object {
        $id = $_.Trim()
        if ($installed -contains $id) { Ok "$id already installed" }
        else { Info "Installing $id"; code --install-extension $id | Out-Null }
    }
} else {
    Warn 'code CLI not on PATH yet; open VS Code once, then re-run to install extensions.'
}

# ---------------------------------------------------------------------------
# 5. Pre-compile Treesitter parsers (headless)
# ---------------------------------------------------------------------------
Info 'Step 5/6: Treesitter parsers (this can take a couple of minutes)'
if (Test-Path $NvimExe) {
    & $NvimExe --headless '+Lazy! sync' '+qa' 2>&1 | Out-Null
    & $NvimExe --headless '+TSUpdateSync' '+qa' 2>&1 | Out-Null
    Ok 'Parsers compiled'
} else {
    Warn "Neovim not at $NvimExe yet; open a new shell and run:  nvim --headless +TSUpdateSync +qa"
}

# ---------------------------------------------------------------------------
# 6. Seed VS Code settings/keybindings from baseline (only if missing)
# ---------------------------------------------------------------------------
Info 'Step 6/6: VS Code settings & keybindings'
New-Item -ItemType Directory -Force $CodeUser | Out-Null
$baseSettings = Join-Path $NvimDir 'vscode\settings.jsonc'
$baseKeys     = Join-Path $NvimDir 'vscode\keybindings.jsonc'
$dstSettings  = Join-Path $CodeUser 'settings.json'
$dstKeys      = Join-Path $CodeUser 'keybindings.json'

function Seed($src, $dst, $label){
    if ((Test-Path $dst) -and -not $SeedVSCodeSettings) {
        Warn "$label already exists - left untouched (Settings Sync owns it). Re-run with -SeedVSCodeSettings to overwrite."
        return
    }
    if (Test-Path $dst) {
        $bak = "$dst.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $dst $bak -Force
        Warn "Backed up existing $label -> $(Split-Path $bak -Leaf)"
    }
    Copy-Item $src $dst -Force
    Ok "Seeded $label from baseline"
}
Seed $baseSettings $dstSettings 'settings.json'
Seed $baseKeys     $dstKeys     'keybindings.json'

Write-Host ''
Info 'Done.'
Write-Host @'
Next steps:
  1. Sign in to VS Code and enable Settings Sync (Accounts icon -> Turn on Settings Sync)
     so preferences/extensions stay live-synced with your other machine.
  2. Fully quit and reopen VS Code (File -> Exit) so the new font + extension load cleanly.
  3. Ctrl+Alt+N opens the real Neovim TUI in the current folder.
'@ -ForegroundColor Cyan
