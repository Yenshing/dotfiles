<#
.SYNOPSIS
    CodexBar for Herdr - Multi-Agent AI Usage & Quota Monitor (Codex & Antigravity)
.DESCRIPTION
    Monitors both OpenAI Codex and Google Antigravity (Agy / Gemini / Claude) quota,
    providing 5h tab-bar status, 5h sidebar agent metadata, and a full 5h/7d modal dashboard.
#>

param(
    [Parameter(Position=0)]
    [string]$Target = "",

    [switch]$StatusBar,
    [switch]$Dashboard,
    [switch]$Json,
    [switch]$UpdatePanes,
    [switch]$Refresh,
    [switch]$Help
)

$ErrorActionPreference = "SilentlyContinue"

# Parse positional argument if provided
if ($Target) {
    switch -Regex ($Target) {
        '^(status|status-?bar)$'  { $StatusBar = $true }
        '^(dash|dashboard)$'      { $Dashboard = $true }
        '^(json)$'                { $Json = $true }
        '^(update|update-?panes)$'{ $UpdatePanes = $true }
        '^(refresh|reload)$'      { $Refresh = $true }
        '^(help|-h|--help|/\?)$'  { $Help = $true }
    }
}

$HerdrDir = "$HOME\AppData\Roaming\herdr"
$CacheFile = "$HerdrDir\quota_cache_multi.json"
$CacheTtlSeconds = 40

function Format-Duration([long]$seconds) {
    if ($seconds -le 0) { return "now" }
    $days = [math]::Floor($seconds / 86400)
    $hours = [math]::Floor(($seconds % 86400) / 3600)
    $minutes = [math]::Floor(($seconds % 3600) / 60)

    if ($days -gt 0) {
        return "${days}d ${hours}h"
    } elseif ($hours -gt 0) {
        return "${hours}h ${minutes}m"
    } else {
        return "${minutes}m"
    }
}

function Shorten-ResetText([string]$text) {
    if (-not $text) { return "" }
    $t = $text -replace '(\d+)\s*days?', '${1}d'
    $t = $t -replace '(\d+)\s*hours?', '${1}h'
    $t = $t -replace '(\d+)\s*minutes?', '${1}m'
    $t = $t -replace '(\d+)\s*seconds?', '${1}s'
    $t = $t -replace ',\s*', ' '
    return $t.Trim()
}

function Get-ProgressBar([int]$percent, [int]$width = 24) {
    $filled = [math]::Round(($percent / 100) * $width)
    $empty = $width - $filled
    $fullChar = [string][char]0x2588
    $emptyChar = [string][char]0x2591
    return ($fullChar * $filled) + ($emptyChar * $empty)
}

function Get-BucketVal($groupObj, [string]$bucketName) {
    if (-not $groupObj -or -not $groupObj.buckets) { return $null }
    $b = $groupObj.buckets
    if ($b -is [System.Collections.IDictionary]) {
        return $b[$bucketName]
    } else {
        return $b."$bucketName"
    }
}

function Get-CodexQuota {
    $authPath = "$HOME\.codex\auth.json"
    if (-not (Test-Path $authPath)) {
        return @{ Error = "Codex auth.json not found" }
    }

    try {
        $auth = Get-Content $authPath -Raw | ConvertFrom-Json
        $token = $auth.tokens.access_token
        if (-not $token) {
            return @{ Error = "No access token in auth.json" }
        }

        $headers = @{
            "Authorization" = "Bearer $token"
            "User-Agent" = "CodexBar-Herdr/1.0"
        }

        $response = Invoke-RestMethod -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers $headers -Method Get -TimeoutSec 4
        if ($response) {
            $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            
            $primary = $response.rate_limit.primary_window
            $pUsed = if ($primary.used_percent -ne $null) { [math]::Round($primary.used_percent) } else { 0 }
            $pRem = [math]::Max(0, 100 - $pUsed)
            $pResetSec = if ($primary.reset_after_seconds) { $primary.reset_after_seconds } else { [math]::Max(0, $primary.reset_at - $nowUnix) }
            $pResetText = Format-Duration $pResetSec

            $secondary = $response.rate_limit.secondary_window
            $sUsed = if ($secondary.used_percent -ne $null) { [math]::Round($secondary.used_percent) } else { 0 }
            $sRem = [math]::Max(0, 100 - $sUsed)
            $sResetSec = if ($secondary.reset_after_seconds) { $secondary.reset_after_seconds } else { [math]::Max(0, $secondary.reset_at - $nowUnix) }
            $sResetText = Format-Duration $sResetSec

            return [ordered]@{
                email = $response.email
                plan = $response.plan_type
                primary = @{
                    used = $pUsed
                    remaining = $pRem
                    reset_seconds = $pResetSec
                    reset_text = $pResetText
                }
                secondary = @{
                    used = $sUsed
                    remaining = $sRem
                    reset_seconds = $sResetSec
                    reset_text = $sResetText
                }
                credits = $response.rate_limit_reset_credits.available_count
            }
        }
    } catch {
        return @{ Error = $_.Exception.Message }
    }

    return @{ Error = "Unable to fetch Codex usage" }
}

function Parse-AgyCliUsage($lines) {
    $result = [ordered]@{}
    foreach ($line in ($lines -split "`r?`n")) {
        if ($line -match '^(Gemini Models|Claude and GPT models)\t(Weekly Limit Remaining|Five Hour Limit Remaining)\t(\d+)%\t(.*)$') {
            $model = $matches[1]
            $bucketType = $matches[2]
            $pct = [int]$matches[3]
            $resetTimeStr = $matches[4].Trim()

            $key = if ($model -like "*Gemini*") { "gemini" } else { "third_party" }
            $window = if ($bucketType -like "*Five Hour*") { "5h" } else { "weekly" }

            if (-not $result[$key]) {
                $result[$key] = @{
                    name = $model
                    buckets = [ordered]@{}
                }
            }
            $resetText = ""
            if ($resetTimeStr) {
                try {
                    $dt = [DateTimeOffset]::Parse($resetTimeStr).UtcDateTime
                    $diff = $dt - [DateTime]::UtcNow
                    $sec = [math]::Max(0, [long]$diff.TotalSeconds)
                    $resetText = Format-Duration $sec
                } catch {}
            }
            $result[$key].buckets[$window] = @{
                remaining = $pct
                reset_text = $resetText
            }
        }
    }
    return $result
}

function Get-AgyQuota {
    # 1. First priority: Antigravity IDE background language_server (fastest, ~20-50ms)
    # NOTE: Never probe 'agy' process ports directly! agy CLI runs in the foreground terminal
    # and probing its HTTPS listener with HTTP causes Go's net/http server to dump
    # 'http: TLS handshake error' directly to the user's terminal window.
    $lsProcs = Get-Process -Name "language_server" -ErrorAction SilentlyContinue
    if ($lsProcs) {
        $csrfToken = ""
        foreach ($proc in $lsProcs) {
            try {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                if ($cmdLine -match '--csrf_token\s+([a-f0-9\-]+)') {
                    $csrfToken = $matches[1]
                    break
                }
            } catch {}
        }

        $candidatePorts = @()
        if ($env:ANTIGRAVITY_LS_ADDRESS -match ':(\d+)') {
            $candidatePorts += [int]$matches[1]
        }
        $pids = $lsProcs | Select-Object -ExpandProperty Id
        $netPorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.OwningProcess -in $pids } |
            Select-Object -ExpandProperty LocalPort -Unique
        $candidatePorts += $netPorts
        $candidatePorts = $candidatePorts | Select-Object -Unique

        $headers = @{
            "Content-Type" = "application/json"
            "Connect-Protocol-Version" = "1"
        }
        if ($csrfToken) {
            $headers["X-Codeium-Csrf-Token"] = $csrfToken
        }

        foreach ($port in $candidatePorts) {
            $url = "http://127.0.0.1:${port}/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
            try {
                $res = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body "{}" -TimeoutSec 1
                if ($res -and $res.response -and $res.response.groups) {
                    return Parse-AgyGroups $res.response.groups
                }
            } catch {}
        }
    }

    # 2. Fallback: Query agy CLI directly via `agy --print /usage` (safe, no socket probing)
    $agyCmd = Get-Command agy.exe -ErrorAction SilentlyContinue
    if ($agyCmd) {
        try {
            $lines = & $agyCmd.Source --print "/usage" 2>$null
            if ($lines) {
                $parsed = Parse-AgyCliUsage $lines
                if ($parsed -and $parsed.gemini) {
                    return $parsed
                }
            }
        } catch {}
    }

    return @{ Error = "Antigravity service not reachable" }
}

function Parse-AgyGroups($groups) {
    $result = [ordered]@{}
    foreach ($g in $groups) {
        $name = $g.displayName
        $key = if ($name -like "*Gemini*") { "gemini" } else { "third_party" }
        $buckets = [ordered]@{}
        foreach ($b in $g.buckets) {
            $pct = if ($b.remainingFraction -ne $null) { [math]::Round($b.remainingFraction * 100) } else { 0 }
            $w = $b.window
            $resetText = ""
            if ($b.description -match 'will fully refresh in ([^.]+)') {
                $resetText = Shorten-ResetText $matches[1].Trim()
            } elseif ($b.resetTime) {
                try {
                    $dt = [DateTimeOffset]::Parse($b.resetTime).UtcDateTime
                    $diff = $dt - [DateTime]::UtcNow
                    $resetText = Format-Duration ([math]::Max(0, [long]$diff.TotalSeconds))
                } catch {}
            }
            $buckets[$w] = @{
                remaining = $pct
                reset_text = $resetText
            }
        }
        $result[$key] = @{
            name = $name
            buckets = $buckets
        }
    }
    return $result
}

function Get-AllQuotas([bool]$bypassCache = $false) {
    $cached = $null
    if (Test-Path $CacheFile) {
        try {
            $cached = Get-Content $CacheFile -Raw | ConvertFrom-Json
        } catch {}
    }

    if (-not $bypassCache -and $cached) {
        $cacheAge = ((Get-Date) - [DateTime]$cached.timestamp).TotalSeconds
        if ($cacheAge -lt $CacheTtlSeconds -and $cached.codex -and $cached.agy -and (-not $cached.codex.Error) -and (-not $cached.agy.Error)) {
            return @{
                codex = $cached.codex
                agy = $cached.agy
            }
        }
    }

    $codex = Get-CodexQuota
    # Fallback to cache if transient failure
    if ($codex.Error -and $cached -and $cached.codex -and (-not $cached.codex.Error)) {
        $codex = $cached.codex
    }

    $agy = Get-AgyQuota
    # Fallback to cache if transient failure
    if ($agy.Error -and $cached -and $cached.agy -and (-not $cached.agy.Error)) {
        $agy = $cached.agy
    }

    @{
        timestamp = (Get-Date).ToString("o")
        codex = $codex
        agy = $agy
    } | ConvertTo-Json -Depth 8 | Set-Content $CacheFile -Force

    return @{
        codex = $codex
        agy = $agy
    }
}

function Update-HerdrPanes($quotas) {
    $herdrPath = (Get-Command herdr.exe -ErrorAction SilentlyContinue).Source
    if (-not $herdrPath) { return }

    $panesJson = & $herdrPath pane list 2>$null
    if (-not $panesJson) { return }

    try {
        $panesObj = $panesJson | ConvertFrom-Json
        $panes = $panesObj.result.panes
        $codex = $quotas.codex
        $agy = $quotas.agy

        $g5hB = Get-BucketVal $agy.gemini "5h"
        $tp5hB = Get-BucketVal $agy.third_party "5h"

        foreach ($pane in $panes) {
            if ($pane.agent -eq "codex") {
                if (-not $codex.Error) {
                    $cReset = if ($codex.primary.reset_text) { " ($($codex.primary.reset_text))" } else { "" }
                    $val = "5h $($codex.primary.remaining)%$cReset"
                    & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" 2>$null
                }
            } elseif ($pane.agent -eq "agy") {
                if (-not $agy.Error -and $g5hB) {
                    $gRes = if ($g5hB.reset_text) { " ($($g5hB.reset_text))" } else { "" }
                    $val = "5h $($g5hB.remaining)%$gRes"
                    & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" 2>$null
                }
            } else {
                # General shell panes: show 5h summaries
                $cVal = if (-not $codex.Error) { "$($codex.primary.remaining)%" } else { "N/A" }
                $gVal = if ($g5hB) { "$($g5hB.remaining)%" } else { "N/A" }
                $val = "Codex 5h $cVal | Agy 5h $gVal"
                & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" 2>$null
            }
        }
    } catch {}
}

# --- HELP DISPLAY ---
if ($Help) {
    Write-Host "CodexBar for Herdr - Multi-Agent AI Quota Monitor"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  codexbar                 Display current usage for both Agy and Codex"
    Write-Host "  codexbar agy             Display only Antigravity (Gemini / Claude / GPT) usage"
    Write-Host "  codexbar codex           Display only OpenAI Codex usage"
    Write-Host "  codexbar dash            Open the full interactive ASCII dashboard (includes 7d & 3p)"
    Write-Host "  codexbar status          Print single-line 5h status for Herdr tab bar"
    Write-Host "  codexbar update          Update Herdr sidebar metadata for all agent panes"
    Write-Host "  codexbar refresh         Force refresh cache from APIs and print"
    Write-Host "  codexbar json            Output raw quota data as JSON"
    exit 0
}

# --- LOAD QUOTAS ---
$quotas = Get-AllQuotas -bypassCache ($Refresh -or $Target -eq "refresh")
$codex = $quotas.codex
$agy = $quotas.agy

$g5hB = Get-BucketVal $agy.gemini "5h"
$gWkB = Get-BucketVal $agy.gemini "weekly"
$tp5hB = Get-BucketVal $agy.third_party "5h"
$tpWkB = Get-BucketVal $agy.third_party "weekly"

if ($Json) {
    $quotas | ConvertTo-Json -Depth 6
    exit 0
}

if ($UpdatePanes) {
    Update-HerdrPanes $quotas
    Write-Output "Herdr panes metadata updated with 5h quota."
    exit 0
}

if ($StatusBar) {
    Update-HerdrPanes $quotas

    # Check focused pane to give context-aware status (5h ONLY)
    $herdrPath = (Get-Command herdr.exe -ErrorAction SilentlyContinue).Source
    $focusedAgent = ""
    if ($herdrPath) {
        $panesJson = & $herdrPath pane list 2>$null
        if ($panesJson) {
            try {
                $panesObj = $panesJson | ConvertFrom-Json
                $focused = $panesObj.result.panes | Where-Object { $_.focused -eq $true } | Select-Object -First 1
                if ($focused) { $focusedAgent = $focused.agent }
            } catch {}
        }
    }

    $c5h = if (-not $codex.Error) { "$($codex.primary.remaining)%" } else { "N/A" }
    $cReset = if (-not $codex.Error -and $codex.primary.reset_text) { " ($($codex.primary.reset_text))" } else { "" }

    $g5h = if ($g5hB) { "$($g5hB.remaining)%" } else { "N/A" }
    $gReset = if ($g5hB -and $g5hB.reset_text) { " ($($g5hB.reset_text))" } else { "" }

    if ($focusedAgent -eq "agy") {
        Write-Output "Agy 5h: $g5h$gReset  (Codex 5h: $c5h)"
    } elseif ($focusedAgent -eq "codex") {
        Write-Output "Codex 5h: $c5h$cReset  (Agy 5h: $g5h)"
    } else {
        Write-Output "Agy 5h: $g5h  |  Codex 5h: $c5h"
    }
    exit 0
}

if ($Dashboard) {
    [Console]::Clear()
    $esc = [char]27
    $bold = "$esc[1m"
    $reset = "$esc[0m"
    $cyan = "$esc[36m"
    $green = "$esc[32m"
    $yellow = "$esc[33m"
    $red = "$esc[31m"
    $dim = "$esc[2m"
    $magenta = "$esc[35m"
    $blue = "$esc[34m"

    Write-Host ""
    Write-Host "$cyan$bold  +-------------------------------------------------------------------+$reset"
    Write-Host "$cyan$bold  |                 CODEXBAR * AI USAGE MONITOR                       |$reset"
    Write-Host "$cyan$bold  +-------------------------------------------------------------------+$reset"
    Write-Host ""

    # === SECTION 1: ANTIGRAVITY (AGY) ===
    Write-Host "  $magenta$bold[1] Google Antigravity (Agy)$reset"
    if ($agy.Error) {
        Write-Host "     $red Error: $($agy.Error)$reset"
    } else {
        $g5h = if ($g5hB) { $g5hB.remaining } else { 0 }
        $gWk = if ($gWkB) { $gWkB.remaining } else { 0 }
        $tp5h = if ($tp5hB) { $tp5hB.remaining } else { 0 }
        $tpWk = if ($tpWkB) { $tpWkB.remaining } else { 0 }

        $gColor = if ($g5h -ge 50) { $green } elseif ($g5h -ge 20) { $yellow } else { $red }
        $tpColor = if ($tp5h -ge 50) { $green } elseif ($tp5h -ge 20) { $yellow } else { $red }

        Write-Host "     $bold Gemini Models (Flash, Pro):$reset"
        Write-Host "     $gColor[$(Get-ProgressBar $g5h 24)]$reset $bold${g5h}%$reset remaining (5h reset: $($g5hB.reset_text))"
        Write-Host "     $dim Weekly limit: ${gWk}% remaining (resets in: $($gWkB.reset_text))$reset"
        Write-Host ""
        Write-Host "     $bold Claude & GPT Models (Sonnet, Opus, GPT):$reset"
        Write-Host "     $tpColor[$(Get-ProgressBar $tp5h 24)]$reset $bold${tp5h}%$reset remaining (5h reset: $($tp5hB.reset_text))"
        Write-Host "     $dim Weekly limit: ${tpWk}% remaining (resets in: $($tpWkB.reset_text))$reset"
    }

    Write-Host ""
    # === SECTION 2: OPENAI CODEX ===
    Write-Host "  $blue$bold[2] OpenAI Codex$reset"
    if ($codex.Error) {
        Write-Host "     $red Error: $($codex.Error)$reset"
    } else {
        $cpColor = if ($codex.primary.remaining -ge 50) { $green } elseif ($codex.primary.remaining -ge 20) { $yellow } else { $red }
        $csColor = if ($codex.secondary.remaining -ge 50) { $green } elseif ($codex.secondary.remaining -ge 20) { $yellow } else { $red }

        Write-Host "     $dim Account: $($codex.email) ($($codex.plan.ToUpper()) plan) | Credits: $($codex.credits) reset credits$reset"
        Write-Host "     $bold 5-Hour Session Limit:$reset"
        Write-Host "     $cpColor[$(Get-ProgressBar $codex.primary.remaining 24)]$reset $bold$($codex.primary.remaining)%$reset remaining (resets in $($codex.primary.reset_text))"
        Write-Host "     $bold 7-Day Weekly Limit:$reset"
        Write-Host "     $csColor[$(Get-ProgressBar $codex.secondary.remaining 24)]$reset $bold$($codex.secondary.remaining)%$reset remaining (resets in $($codex.secondary.reset_text))"
    }

    Write-Host ""
    # === SECTION 3: HERDR PANES ===
    $herdrPath = (Get-Command herdr.exe -ErrorAction SilentlyContinue).Source
    if ($herdrPath) {
        $panesJson = & $herdrPath pane list 2>$null
        if ($panesJson) {
            try {
                $panesObj = $panesJson | ConvertFrom-Json
                $panes = $panesObj.result.panes
                Write-Host "  $dim$bold Active Herdr Panes & Agents:$reset"
                foreach ($p in $panes) {
                    $agentName = if ($p.agent) { $p.agent } else { "shell" }
                    $statusColor = switch ($p.agent_status) {
                        "working" { $green }
                        "blocked" { $red }
                        "idle"    { $dim }
                        default   { $dim }
                    }
                    $statusText = if ($p.agent_status) { "$statusColor$($p.agent_status)$reset" } else { "active" }
                    $focusMark = if ($p.focused) { "$cyan* $reset" } else { "  " }
                    $tokenQuota = if ($p.tokens -and $p.tokens.quota) { " | Quota: $($p.tokens.quota)" } else { "" }
                    Write-Host "    $focusMark[$($p.pane_id)] $bold$agentName$reset ($($p.workspace_id)/$($p.tab_id)) - $statusText$dim$tokenQuota$reset"
                }
            } catch {}
        }
    }

    Write-Host ""
    Write-Host "$dim  ---------------------------------------------------------------------$reset"
    Write-Host "$dim  Press Enter or Esc to close...$reset"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# === CLI OUTPUT ===
$esc = [char]27
$bold = "$esc[1m"
$reset = "$esc[0m"
$cyan = "$esc[36m"
$green = "$esc[32m"
$yellow = "$esc[33m"
$red = "$esc[31m"
$dim = "$esc[2m"
$magenta = "$esc[35m"
$blue = "$esc[34m"

$showAgy = ($Target -notmatch '^(codex|openai)$')
$showCodex = ($Target -notmatch '^(agy|antigravity)$')

Write-Host "$cyan$bold==> CodexBar: AI Usage & Quota Monitor$reset"
Write-Host ""

if ($showAgy) {
    Write-Host "$magenta$bold[Antigravity / Agy]$reset"
    if ($agy.Error) {
        Write-Host "  Error: $($agy.Error)"
    } else {
        $g5h = if ($g5hB) { $g5hB.remaining } else { 0 }
        $gWk = if ($gWkB) { $gWkB.remaining } else { 0 }
        $tp5h = if ($tp5hB) { $tp5hB.remaining } else { 0 }
        $tpWk = if ($tpWkB) { $tpWkB.remaining } else { 0 }

        $gColor = if ($g5h -ge 50) { $green } elseif ($g5h -ge 20) { $yellow } else { $red }
        $tpColor = if ($tp5h -ge 50) { $green } elseif ($tp5h -ge 20) { $yellow } else { $red }

        Write-Host "  Gemini Models:     5h $gColor${g5h}%$reset (resets in $($g5hB.reset_text)) | Weekly: ${gWk}%"
        Write-Host "  Claude/GPT Models: 5h $tpColor${tp5h}%$reset (resets in $($tp5hB.reset_text)) | Weekly: ${tpWk}%"
    }
}

if ($showAgy -and $showCodex) {
    Write-Host ""
}

if ($showCodex) {
    Write-Host "$blue$bold[OpenAI Codex]$reset"
    if ($codex.Error) {
        Write-Host "  Error: $($codex.Error)"
    } else {
        $cpColor = if ($codex.primary.remaining -ge 50) { $green } elseif ($codex.primary.remaining -ge 20) { $yellow } else { $red }
        $csColor = if ($codex.secondary.remaining -ge 50) { $green } elseif ($codex.secondary.remaining -ge 20) { $yellow } else { $red }

        Write-Host "  Account: $($codex.email) ($($codex.plan.ToUpper())) | Credits: $($codex.credits)"
        Write-Host "  Session 5h: $cpColor$($codex.primary.remaining)%$reset (resets in $($codex.primary.reset_text))"
        Write-Host "  Weekly 7d:  $csColor$($codex.secondary.remaining)%$reset (resets in $($codex.secondary.reset_text))"
    }
}
