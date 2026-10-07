# ==========================================================
# Windows PowerShell Linux-like Environment Configuration
# ==========================================================

# 1. UTF-8 Support
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# 2. Add user bin directories and Git GNU Linux tools to PATH
$userLocalBin = "$HOME\.local\bin"
if (Test-Path $userLocalBin) {
    if ($env:Path -notlike "*$userLocalBin*") {
        $env:Path = "$userLocalBin;" + $env:Path
    }
}
$userBin = "$HOME\bin"
if (Test-Path $userBin) {
    if ($env:Path -notlike "*$userBin*") {
        $env:Path = "$userBin;" + $env:Path
    }
}
$gitUsrBin = "C:\Program Files\Git\usr\bin"
if (Test-Path $gitUsrBin) {
    if ($env:Path -notlike "*$gitUsrBin*") {
        $env:Path = "$gitUsrBin;" + $env:Path
    }
}

# 3. Remove conflicting PowerShell aliases
$conflictAliases = @('ls', 'cat', 'rm', 'cp', 'mv', 'curl', 'wget', 'diff')
foreach ($alias in $conflictAliases) {
    if (Test-Path "Alias:$alias") {
        Remove-Item "Alias:$alias" -Force -ErrorAction SilentlyContinue
    }
}

# 4. Linux functions and aliases
function ls {
    & "$gitUsrBin\ls.exe" --color=auto --show-control-chars -F @args
}

function ll {
    & "$gitUsrBin\ls.exe" -lah --color=auto --show-control-chars -F @args
}

function la {
    & "$gitUsrBin\ls.exe" -A --color=auto --show-control-chars -F @args
}

function grep {
    & "$gitUsrBin\grep.exe" --color=auto @args
}

function which ($command) {
    Get-Command -Name $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function export ($expression) {
    if ($expression -match "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
        $val = $matches[2].Trim('"', "'")
        [System.Environment]::SetEnvironmentVariable($matches[1], $val, "Process")
    } elseif ($expression) {
        Get-ChildItem "env:$expression" -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem env:
    }
}

function touch ($filename) {
    if (Test-Path $filename) {
        (Get-Item $filename).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Name $filename -Force | Out-Null
    }
}

function wget ($url) {
    curl.exe -fL -O $url
}

# 5. Herdr / Terminal Live CWD integration (OSC 9;9)
# 自動向 Herdr 回報目前工作目錄，讓 Windows 端的 Herdr 能在 cd 切換目錄時即時更新 workspace
if ($null -eq $global:__HerdrOriginalPrompt) {
    $global:__HerdrOriginalPrompt = $function:prompt
    function global:prompt {
        $loc = $ExecutionContext.SessionState.Path.CurrentLocation
        if ($loc.Provider.Name -eq 'FileSystem') {
            try { [Environment]::CurrentDirectory = $loc.ProviderPath } catch {}
            $esc = [char]27
            Write-Host -NoNewline "$esc]9;9;$($loc.ProviderPath)$esc\"
        }
        if ($global:__HerdrOriginalPrompt) {
            & $global:__HerdrOriginalPrompt
        } else {
            "PS $($loc.Path)> "
        }
    }
}
