<#
.SYNOPSIS
    Restore WezTerm and Herdr (with CodexBar) settings for Windows.
.DESCRIPTION
    Restores configurations from the backup folder to the user's home directory.
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Starting restoration of Windows development settings..." -ForegroundColor Cyan

# 1. Restore WezTerm settings
$weztermSrc = Join-Path $ScriptDir "wezterm\.wezterm.lua"
$weztermDst = Join-Path $HOME ".wezterm.lua"
if (Test-Path $weztermSrc) {
    Copy-Item -Path $weztermSrc -Destination $weztermDst -Force
    Write-Host "[OK] WezTerm config restored to: $weztermDst" -ForegroundColor Green
}

$sizeSrc = Join-Path $ScriptDir "wezterm\window_size.json"
$sizeDir = Join-Path $HOME ".config\wezterm"
if (Test-Path $sizeSrc) {
    if (-not (Test-Path $sizeDir)) {
        New-Item -ItemType Directory -Path $sizeDir -Force | Out-Null
    }
    Copy-Item -Path $sizeSrc -Destination (Join-Path $sizeDir "window_size.json") -Force
    Write-Host "[OK] WezTerm window size restored." -ForegroundColor Green
}

# 2. Restore Windows Herdr settings and Quota scripts
$herdrDir = Join-Path $HOME "AppData\Roaming\herdr"
$herdrScriptsDir = Join-Path $herdrDir "scripts"
if (-not (Test-Path $herdrScriptsDir)) {
    New-Item -ItemType Directory -Path $herdrScriptsDir -Force | Out-Null
}

$herdrConfigSrc = Join-Path $ScriptDir "herdr\windows\config.toml"
if (Test-Path $herdrConfigSrc) {
    Copy-Item -Path $herdrConfigSrc -Destination (Join-Path $herdrDir "config.toml") -Force
    Write-Host "[OK] Windows Herdr config.toml restored to: $herdrDir\config.toml" -ForegroundColor Green
}

$herdrQuotaSrc = Join-Path $ScriptDir "herdr\windows\scripts\herdr-quota.ps1"
if (Test-Path $herdrQuotaSrc) {
    Copy-Item -Path $herdrQuotaSrc -Destination (Join-Path $herdrScriptsDir "herdr-quota.ps1") -Force
    Write-Host "[OK] Windows Herdr Quota script restored to: $herdrScriptsDir\herdr-quota.ps1" -ForegroundColor Green
}

# 3. Restore codexbar CLI tools to ~/bin
$binDir = Join-Path $HOME "bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$binSrc = Join-Path $ScriptDir "herdr\windows\bin"
if (Test-Path $binSrc) {
    Get-ChildItem -Path "$binSrc\*" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $binDir $_.Name) -Force
    }
    Write-Host "[OK] codexbar CLI tools restored to: $binDir" -ForegroundColor Green
}

# 4. Check if $HOME\bin is in User PATH
$targetUser = [System.EnvironmentVariableTarget]::User
$userPath = [Environment]::GetEnvironmentVariable("Path", $targetUser)
if ($userPath -notlike "*$binDir*") {
    $newPath = $binDir + ";" + $userPath
    [Environment]::SetEnvironmentVariable("Path", $newPath, $targetUser)
    Write-Host "[OK] Added $binDir to User PATH environment variable." -ForegroundColor Yellow
}

# 5. Restore Git Bash and PowerShell shell integration configs
$bashrcSrc = Join-Path $ScriptDir "windows\.bashrc"
$bashrcDst = Join-Path $HOME ".bashrc"
if (Test-Path $bashrcSrc) {
    Copy-Item -Path $bashrcSrc -Destination $bashrcDst -Force
    Write-Host "[OK] Git Bash ~/.bashrc restored with Herdr Live CWD integration." -ForegroundColor Green
}

$psProfileSrc = Join-Path $ScriptDir "windows\Microsoft.PowerShell_profile.ps1"
$psProfileDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell"
if (Test-Path $psProfileSrc) {
    if (-not (Test-Path $psProfileDir)) {
        New-Item -ItemType Directory -Path $psProfileDir -Force | Out-Null
    }
    $psProfileDst = Join-Path $psProfileDir "Microsoft.PowerShell_profile.ps1"
    Copy-Item -Path $psProfileSrc -Destination $psProfileDst -Force
    Write-Host "[OK] PowerShell profile restored with Herdr Live CWD integration." -ForegroundColor Green
}

Write-Host "`n==> Windows settings restored successfully! Restart WezTerm to apply." -ForegroundColor Cyan
