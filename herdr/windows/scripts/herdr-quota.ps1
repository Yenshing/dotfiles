<#
.SYNOPSIS
    CodexBar for Herdr - Multi-Agent AI Usage & Quota Monitor (Codex, Claude & Antigravity)
.DESCRIPTION
    Monitors OpenAI Codex, Anthropic Claude (Claude Code), and Google Antigravity (Agy / Gemini / Claude) quota,
    providing 5h tab-bar status, 5h sidebar agent metadata, and a full 5h/7d modal dashboard.
#>

param(
    [Parameter(Position=0)]
    [string]$Target = "",

    [switch]$StatusBar,
    [switch]$Dashboard,
    [switch]$Context,
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
        '^(context|ctx)$'         { $Context = $true }
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

function Get-AgentContext([string]$agentName, [string]$sessionId = "") {
    $agent = [string]$agentName.ToLower()

    # 1. Google Antigravity (agy)
    if ($agent -in @("agy", "antigravity", "gemini")) {
        $brainBase = "$HOME\.gemini\antigravity-cli\brain"
        $targetLog = $null

        if ($sessionId -and (Test-Path "$brainBase\$sessionId")) {
            $fullPath = "$brainBase\$sessionId\.system_generated\logs\transcript_full.jsonl"
            $compactPath = "$brainBase\$sessionId\.system_generated\logs\transcript.jsonl"
            if (Test-Path $fullPath) { $targetLog = $fullPath }
            elseif (Test-Path $compactPath) { $targetLog = $compactPath }
        }

        if (-not $targetLog -and (Test-Path $brainBase)) {
            $latestDir = Get-ChildItem -Path $brainBase -Directory -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestDir) {
                $fullPath = "$($latestDir.FullName)\.system_generated\logs\transcript_full.jsonl"
                $compactPath = "$($latestDir.FullName)\.system_generated\logs\transcript.jsonl"
                if (Test-Path $fullPath) { $targetLog = $fullPath }
                elseif (Test-Path $compactPath) { $targetLog = $compactPath }
            }
        }

        if ($targetLog -and (Test-Path $targetLog)) {
            try {
                $bytes = (Get-Item $targetLog).Length
                $estTokens = [math]::Round($bytes / 3.8)
                $tokStr = if ($estTokens -ge 1000000) {
                    "$([math]::Round($estTokens / 1000000, 1))M"
                } elseif ($estTokens -ge 1000) {
                    "$([math]::Round($estTokens / 1000))k"
                } else {
                    "$estTokens"
                }
                $sizeStr = if ($bytes -ge 1048576) {
                    "$([math]::Round($bytes / 1048576, 1))MB"
                } else {
                    "$([math]::Round($bytes / 1024))KB"
                }
                return [ordered]@{
                    agent = "agy"
                    tokens_str = "~$tokStr"
                    size_str = $sizeStr
                    display = "ctx: ~$tokStr"
                    detailed = "~$tokStr tokens ($sizeStr)"
                    raw_tokens = $estTokens
                    raw_bytes = $bytes
                }
            } catch {}
        }
    }

    # 2. OpenAI Codex
    if ($agent -in @("codex", "openai")) {
        $codexSessionsDir = "$HOME\.codex\sessions"
        $targetFile = $null

        if ($sessionId -and (Test-Path $codexSessionsDir)) {
            $found = Get-ChildItem -Path $codexSessionsDir -Filter "*$sessionId*.jsonl" -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($found) { $targetFile = $found.FullName }
        }

        if (-not $targetFile -and (Test-Path $codexSessionsDir)) {
            $latest = Get-ChildItem -Path $codexSessionsDir -Filter "rollout-*.jsonl" -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $targetFile = $latest.FullName }
        }

        if ($targetFile -and (Test-Path $targetFile)) {
            try {
                $tailLines = Get-Content $targetFile -Tail 30 -ErrorAction SilentlyContinue
                if ($tailLines) {
                    for ($i = $tailLines.Count - 1; $i -ge 0; $i--) {
                        $line = $tailLines[$i]
                        if ($line -match '"type":"token_count"' -or ($line -match '"token_count"' -and $line -match '"model_context_window"')) {
                            $parsed = $line | ConvertFrom-Json
                            $info = $parsed.payload.info
                            if ($info -and $info.model_context_window) {
                                $maxTok = [long]$info.model_context_window
                                $inTok = if ($info.last_token_usage -and $info.last_token_usage.input_tokens) {
                                    [long]$info.last_token_usage.input_tokens
                                } elseif ($info.last_token_usage -and $info.last_token_usage.total_tokens) {
                                    [long]$info.last_token_usage.total_tokens
                                } else { 0 }

                                $pct = [math]::Round(($inTok / $maxTok) * 100)
                                $tokStr = if ($inTok -ge 1000) { "$([math]::Round($inTok / 1000))k" } else { "$inTok" }
                                $maxStr = if ($maxTok -ge 1000) { "$([math]::Round($maxTok / 1000))k" } else { "$maxTok" }

                                return [ordered]@{
                                    agent = "codex"
                                    tokens_str = $tokStr
                                    max_str = $maxStr
                                    pct = $pct
                                    display = "ctx: $tokStr ($pct%)"
                                    detailed = "$tokStr / $maxStr tokens ($pct%)"
                                    raw_tokens = $inTok
                                    max_tokens = $maxTok
                                }
                            }
                        }
                    }
                }

                $bytes = (Get-Item $targetFile).Length
                $estTokens = [math]::Round($bytes / 3.8)
                $tokStr = if ($estTokens -ge 1000) { "$([math]::Round($estTokens / 1000))k" } else { "$estTokens" }
                return [ordered]@{
                    agent = "codex"
                    tokens_str = "~$tokStr"
                    display = "ctx: ~$tokStr"
                    detailed = "~$tokStr tokens"
                    raw_tokens = $estTokens
                }
            } catch {}
        }
    }

    # 3. Anthropic Claude (Claude Code)
    if ($agent -in @("claude", "anthropic")) {
        $claudeProjectsDir = "$HOME\.claude\projects"
        $targetFile = $null

        if ($sessionId -and (Test-Path $claudeProjectsDir)) {
            $found = Get-ChildItem -Path $claudeProjectsDir -Filter "*$sessionId*.jsonl" -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($found) { $targetFile = $found.FullName }
        }

        if (-not $targetFile -and (Test-Path $claudeProjectsDir)) {
            $latest = Get-ChildItem -Path $claudeProjectsDir -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $targetFile = $latest.FullName }
        }

        if ($targetFile -and (Test-Path $targetFile)) {
            try {
                $tailLines = Get-Content $targetFile -Tail 30 -ErrorAction SilentlyContinue
                if ($tailLines) {
                    for ($i = $tailLines.Count - 1; $i -ge 0; $i--) {
                        $line = $tailLines[$i]
                        if ($line -match '"input_tokens"') {
                            try {
                                $parsed = $line | ConvertFrom-Json
                                $usage = $parsed.message.usage
                                if ($usage -and $usage.input_tokens -ne $null) {
                                    $inTok = [long]$usage.input_tokens +
                                        [long](if ($usage.cache_read_input_tokens) { $usage.cache_read_input_tokens } else { 0 }) +
                                        [long](if ($usage.cache_creation_input_tokens) { $usage.cache_creation_input_tokens } else { 0 })
                                    $tokStr = if ($inTok -ge 1000) { "$([math]::Round($inTok / 1000))k" } else { "$inTok" }
                                    $pct = [math]::Round(($inTok / 200000.0) * 100)
                                    return [ordered]@{
                                        agent = "claude"
                                        tokens_str = $tokStr
                                        pct = $pct
                                        display = "ctx: $tokStr"
                                        detailed = "$tokStr tokens"
                                        raw_tokens = $inTok
                                    }
                                }
                            } catch {}
                        }
                    }
                }

                $bytes = (Get-Item $targetFile).Length
                $tokStr = "~$([math]::Round($bytes / 3800))k"
                return [ordered]@{
                    agent = "claude"
                    tokens_str = $tokStr
                    display = "ctx: $tokStr"
                    detailed = "$tokStr tokens"
                    raw_tokens = [math]::Round($bytes / 3.8)
                }
            } catch {}
        }
    }

    return $null
}

function Get-PaneContext($pane) {
    if (-not $pane) { return $null }
    $agent = [string]$pane.agent
    $sessId = ""
    if ($pane.agent_session -and $pane.agent_session.value) {
        $sessId = [string]$pane.agent_session.value
    }
    return Get-AgentContext $agent $sessId
}

function Get-ClaudeQuota($cachedProfile = $null) {
    $credPath = "$HOME\.claude\.credentials.json"
    if (-not (Test-Path $credPath)) {
        # Fallback to WSL credentials if Windows credentials don't exist yet
        $wslCred1 = "\\wsl.localhost\Ubuntu\home\james\.claude\.credentials.json"
        $wslCred2 = "\\wsl$\Ubuntu\home\james\.claude\.credentials.json"
        if (Test-Path $wslCred1) { $credPath = $wslCred1 }
        elseif (Test-Path $wslCred2) { $credPath = $wslCred2 }
        else {
            return @{ Error = "Claude credentials.json not found" }
        }
    }

    try {
        $cred = Get-Content $credPath -Raw | ConvertFrom-Json
        $token = $cred.claudeAiOauth.accessToken
        $plan = if ($cred.claudeAiOauth.subscriptionType) { $cred.claudeAiOauth.subscriptionType } else { "unknown" }
        if (-not $token) {
            return @{ Error = "No access token in Claude credentials" }
        }

        $headers = @{
            "Authorization" = "Bearer $token"
            "anthropic-beta" = "oauth-2025-04-20"
            "User-Agent" = "claude-code/2.1.291"
        }

        $usage = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -Headers $headers -Method Get -TimeoutSec 5
        $nowUtc = [DateTime]::UtcNow

        $fh = $usage.five_hour
        $fhUtil = if ($fh -and $fh.utilization -ne $null) { [double]$fh.utilization } else { 0.0 }
        $fhUsed = [math]::Round($fhUtil)
        $fhRem = [math]::Max(0, 100 - $fhUsed)
        $fhResetSec = 0
        $fhResetText = ""
        if ($fh -and $fh.resets_at) {
            try {
                $dt = [DateTimeOffset]::Parse($fh.resets_at).UtcDateTime
                $diff = $dt - $nowUtc
                $fhResetSec = [math]::Max(0, [long]$diff.TotalSeconds)
                $fhResetText = Format-Duration $fhResetSec
            } catch {}
        }

        $sd = $usage.seven_day
        $sdUtil = if ($sd -and $sd.utilization -ne $null) { [double]$sd.utilization } else { 0.0 }
        $sdUsed = [math]::Round($sdUtil)
        $sdRem = [math]::Max(0, 100 - $sdUsed)
        $sdResetSec = 0
        $sdResetText = ""
        if ($sd -and $sd.resets_at) {
            try {
                $dt = [DateTimeOffset]::Parse($sd.resets_at).UtcDateTime
                $diff = $dt - $nowUtc
                $sdResetSec = [math]::Max(0, [long]$diff.TotalSeconds)
                $sdResetText = Format-Duration $sdResetSec
            } catch {}
        }

        $email = if ($cachedProfile -and $cachedProfile.email) { $cachedProfile.email } else { "" }
        $org = if ($cachedProfile -and $cachedProfile.org) { $cachedProfile.org } else { "" }
        if (-not $email) {
            try {
                $prof = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/profile" -Headers $headers -Method Get -TimeoutSec 3
                if ($prof) {
                    if ($prof.account -and $prof.account.email) { $email = $prof.account.email }
                    if ($prof.organization -and $prof.organization.name) { $org = $prof.organization.name }
                }
            } catch {}
        }

        return [ordered]@{
            email = $email
            plan = $plan
            org = $org
            primary = @{
                used = $fhUsed
                remaining = $fhRem
                reset_seconds = $fhResetSec
                reset_text = $fhResetText
            }
            secondary = @{
                used = $sdUsed
                remaining = $sdRem
                reset_seconds = $sdResetSec
                reset_text = $sdResetText
            }
        }
    } catch {
        return @{ Error = $_.Exception.Message }
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

    # 2. Fallback: Query agy CLI directly via `agy --print /usage`
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
        if ($cacheAge -lt $CacheTtlSeconds -and $cached.codex -and $cached.agy -and $cached.claude -and (-not $cached.codex.Error) -and (-not $cached.agy.Error) -and (-not $cached.claude.Error)) {
            return @{
                codex = $cached.codex
                agy = $cached.agy
                claude = $cached.claude
            }
        }
    }

    $cachedProfile = $null
    if ($cached -and $cached.claude -and (-not $cached.claude.Error)) {
        $cachedProfile = @{
            email = $cached.claude.email
            org = $cached.claude.org
        }
    }

    $claude = Get-ClaudeQuota $cachedProfile
    if ($claude.Error -and $cached -and $cached.claude -and (-not $cached.claude.Error)) {
        $claude = $cached.claude
    }

    $codex = Get-CodexQuota
    if ($codex.Error -and $cached -and $cached.codex -and (-not $cached.codex.Error)) {
        $codex = $cached.codex
    }

    $agy = Get-AgyQuota
    if ($agy.Error -and $cached -and $cached.agy -and (-not $cached.agy.Error)) {
        $agy = $cached.agy
    }

    @{
        timestamp = (Get-Date).ToString("o")
        codex = $codex
        agy = $agy
        claude = $claude
    } | ConvertTo-Json -Depth 8 | Set-Content $CacheFile -Force

    return @{
        codex = $codex
        agy = $agy
        claude = $claude
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
        $claude = $quotas.claude

        $g5hB = Get-BucketVal $agy.gemini "5h"

        foreach ($pane in $panes) {
            $ctx = Get-PaneContext $pane
            $ctxArgs = if ($ctx -and $ctx.display) { @("--token", "context=$($ctx.display)") } else { @() }

            if ($pane.agent -in @("claude", "anthropic")) {
                if (-not $claude.Error) {
                    $cReset = if ($claude.primary.reset_text) { " ($($claude.primary.reset_text))" } else { "" }
                    $val = "5h $($claude.primary.remaining)%$cReset"
                    & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" @ctxArgs 2>$null
                }
            } elseif ($pane.agent -in @("codex", "openai")) {
                if (-not $codex.Error) {
                    $cxReset = if ($codex.primary.reset_text) { " ($($codex.primary.reset_text))" } else { "" }
                    $val = "5h $($codex.primary.remaining)%$cxReset"
                    & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" @ctxArgs 2>$null
                }
            } elseif ($pane.agent -in @("agy", "antigravity", "gemini")) {
                if (-not $agy.Error -and $g5hB) {
                    $gRes = if ($g5hB.reset_text) { " ($($g5hB.reset_text))" } else { "" }
                    $val = "5h $($g5hB.remaining)%$gRes"
                    & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" @ctxArgs 2>$null
                }
            } else {
                # General shell panes: show 5h summaries
                $cxVal = if (-not $codex.Error) { "$($codex.primary.remaining)%" } else { "N/A" }
                $clVal = if (-not $claude.Error) { "$($claude.primary.remaining)%" } else { "N/A" }
                $gVal = if ($g5hB) { "$($g5hB.remaining)%" } else { "N/A" }
                $val = "Codex: $cxVal | Claude: $clVal | Agy: $gVal"
                & $herdrPath pane report-metadata $pane.pane_id --source codexbar --token "quota=$val" 2>$null
            }
        }
    } catch {}
}

# --- HELP DISPLAY ---
if ($Help) {
    Write-Host "CodexBar for Herdr - Multi-Agent AI Quota & Context Monitor (Codex, Claude, Agy)"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  codexbar                 Display current usage for all agents (Claude, Codex, Agy)"
    Write-Host "  codexbar claude          Display only Anthropic Claude usage"
    Write-Host "  codexbar codex           Display only OpenAI Codex usage"
    Write-Host "  codexbar agy             Display only Antigravity (Gemini / Claude / GPT) usage"
    Write-Host "  codexbar context (ctx)   Display current session context / token usage"
    Write-Host "  codexbar dash            Open the full interactive ASCII dashboard (includes 7d, 3p, ctx)"
    Write-Host "  codexbar status          Print single-line 5h & context status for Herdr tab bar"
    Write-Host "  codexbar update          Update Herdr sidebar metadata for all agent panes"
    Write-Host "  codexbar refresh         Force refresh cache from APIs and print"
    Write-Host "  codexbar json            Output raw quota data as JSON"
    exit 0
}

# --- LOAD QUOTAS ---
$quotas = Get-AllQuotas -bypassCache ($Refresh -or $Target -eq "refresh")
$codex = $quotas.codex
$agy = $quotas.agy
$claude = $quotas.claude

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
    Write-Output "Herdr panes metadata updated with 5h quota and context."
    exit 0
}

if ($StatusBar) {
    Update-HerdrPanes $quotas

    # Check focused pane to give context-aware status (5h + context)
    $herdrPath = (Get-Command herdr.exe -ErrorAction SilentlyContinue).Source
    $focusedAgent = ""
    $focusedPane = $null
    if ($herdrPath) {
        $panesJson = & $herdrPath pane list 2>$null
        if ($panesJson) {
            try {
                $panesObj = $panesJson | ConvertFrom-Json
                $focused = $panesObj.result.panes | Where-Object { $_.focused -eq $true } | Select-Object -First 1
                if ($focused) {
                    $focusedAgent = [string]$focused.agent
                    $focusedPane = $focused
                }
            } catch {}
        }
    }

    $c5h = if (-not $claude.Error) { "$($claude.primary.remaining)%" } else { "N/A" }
    $cReset = if (-not $claude.Error -and $claude.primary.reset_text) { " ($($claude.primary.reset_text))" } else { "" }

    $cx5h = if (-not $codex.Error) { "$($codex.primary.remaining)%" } else { "N/A" }
    $cxReset = if (-not $codex.Error -and $codex.primary.reset_text) { " ($($codex.primary.reset_text))" } else { "" }

    $g5h = if ($g5hB) { "$($g5hB.remaining)%" } else { "N/A" }
    $gReset = if ($g5hB -and $g5hB.reset_text) { " ($($g5hB.reset_text))" } else { "" }

    $ctx = if ($focusedPane) { Get-PaneContext $focusedPane } else { $null }
    $ctxPart = if ($ctx -and $ctx.display) { " | $($ctx.display)" } else { "" }

    if ($focusedAgent -in @("claude", "anthropic")) {
        Write-Output "Claude 5h: $c5h$cReset$ctxPart  (Codex 5h: $cx5h | Agy 5h: $g5h)"
    } elseif ($focusedAgent -in @("codex", "openai")) {
        Write-Output "Codex 5h: $cx5h$cxReset$ctxPart  (Claude 5h: $c5h | Agy 5h: $g5h)"
    } elseif ($focusedAgent -in @("agy", "antigravity")) {
        Write-Output "Agy 5h: $g5h$gReset$ctxPart  (Codex 5h: $cx5h | Claude 5h: $c5h)"
    } else {
        Write-Output "Codex 5h: $cx5h  |  Claude 5h: $c5h  |  Agy 5h: $g5h"
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

    # === SECTION 1: ANTHROPIC CLAUDE ===
    Write-Host "  $blue$bold[1] Anthropic Claude (Claude Code)$reset"
    if ($claude.Error) {
        Write-Host "     $red Error: $($claude.Error)$reset"
    } else {
        $infoParts = @()
        if ($claude.email) { $infoParts += "Account: $($claude.email)" }
        if ($claude.plan) { $infoParts += "($($claude.plan.ToUpper()) plan)" }
        if ($claude.org) { $infoParts += "Org: $($claude.org)" }
        if ($infoParts.Count -gt 0) {
            Write-Host "     $dim$($infoParts -join ' ')$reset"
        }

        $cpRem = if ($claude.primary.remaining -ne $null) { $claude.primary.remaining } else { 0 }
        $csRem = if ($claude.secondary.remaining -ne $null) { $claude.secondary.remaining } else { 0 }
        $cpColor = if ($cpRem -ge 50) { $green } elseif ($cpRem -ge 20) { $yellow } else { $red }
        $csColor = if ($csRem -ge 50) { $green } elseif ($csRem -ge 20) { $yellow } else { $red }

        $claudeCtx = Get-AgentContext "claude"
        if ($claudeCtx) {
            Write-Host "     $bold Active Session Context:$reset $bold$($claudeCtx.detailed)$reset"
            Write-Host ""
        }

        $cpResetStr = if ($claude.primary.reset_text) { " (resets in $($claude.primary.reset_text))" } else { "" }
        $csResetStr = if ($claude.secondary.reset_text) { " (resets in $($claude.secondary.reset_text))" } else { "" }
        Write-Host "     $bold 5-Hour Session Limit:$reset"
        Write-Host "     $cpColor[$(Get-ProgressBar $cpRem 24)]$reset $bold${cpRem}%$reset remaining$cpResetStr"
        Write-Host "     $bold 7-Day Weekly Limit:$reset"
        Write-Host "     $csColor[$(Get-ProgressBar $csRem 24)]$reset $bold${csRem}%$reset remaining$csResetStr"
    }

    Write-Host ""
    # === SECTION 2: OPENAI CODEX ===
    Write-Host "  $cyan$bold[2] OpenAI Codex$reset"
    if ($codex.Error) {
        Write-Host "     $red Error: $($codex.Error)$reset"
    } else {
        $cpRem = if ($codex.primary.remaining -ne $null) { $codex.primary.remaining } else { 0 }
        $csRem = if ($codex.secondary.remaining -ne $null) { $codex.secondary.remaining } else { 0 }
        $cpColor = if ($cpRem -ge 50) { $green } elseif ($cpRem -ge 20) { $yellow } else { $red }
        $csColor = if ($csRem -ge 50) { $green } elseif ($csRem -ge 20) { $yellow } else { $red }

        Write-Host "     $dim Account: $($codex.email) ($($codex.plan.ToUpper()) plan) | Credits: $($codex.credits) reset credits$reset"
        $codexCtx = Get-AgentContext "codex"
        if ($codexCtx) {
            Write-Host "     $bold Active Session Context:$reset $bold$($codexCtx.detailed)$reset"
            Write-Host ""
        }

        Write-Host "     $bold 5-Hour Session Limit:$reset"
        Write-Host "     $cpColor[$(Get-ProgressBar $cpRem 24)]$reset $bold${cpRem}%$reset remaining (resets in $($codex.primary.reset_text))"
        Write-Host "     $bold 7-Day Weekly Limit:$reset"
        Write-Host "     $csColor[$(Get-ProgressBar $csRem 24)]$reset $bold${csRem}%$reset remaining (resets in $($codex.secondary.reset_text))"
    }

    Write-Host ""
    # === SECTION 3: ANTIGRAVITY (AGY) ===
    Write-Host "  $magenta$bold[3] Google Antigravity (Agy)$reset"
    if ($agy.Error) {
        Write-Host "     $red Error: $($agy.Error)$reset"
    } else {
        $g5h = if ($g5hB) { $g5hB.remaining } else { 0 }
        $gWk = if ($gWkB) { $gWkB.remaining } else { 0 }
        $tp5h = if ($tp5hB) { $tp5hB.remaining } else { 0 }
        $tpWk = if ($tpWkB) { $tpWkB.remaining } else { 0 }

        $gColor = if ($g5h -ge 50) { $green } elseif ($g5h -ge 20) { $yellow } else { $red }
        $tpColor = if ($tp5h -ge 50) { $green } elseif ($tp5h -ge 20) { $yellow } else { $red }

        $agyCtx = Get-AgentContext "agy"
        if ($agyCtx) {
            Write-Host "     $bold Active Session Context:$reset $bold$($agyCtx.detailed)$reset"
            Write-Host ""
        }

        Write-Host "     $bold Gemini Models (Flash, Pro):$reset"
        Write-Host "     $gColor[$(Get-ProgressBar $g5h 24)]$reset $bold${g5h}%$reset remaining (5h reset: $($g5hB.reset_text))"
        Write-Host "     $dim Weekly limit: ${gWk}% remaining (resets in: $($gWkB.reset_text))$reset"
        Write-Host ""
        Write-Host "     $bold Claude & GPT Models (Sonnet, Opus, GPT):$reset"
        Write-Host "     $tpColor[$(Get-ProgressBar $tp5h 24)]$reset $bold${tp5h}%$reset remaining (5h reset: $($tp5hB.reset_text))"
        Write-Host "     $dim Weekly limit: ${tpWk}% remaining (resets in: $($tpWkB.reset_text))$reset"
    }

    Write-Host ""
    # === SECTION 4: HERDR PANES ===
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
                    $tokenContext = if ($p.tokens -and $p.tokens.context) { " | Context: $($p.tokens.context)" } else { "" }
                    Write-Host "    $focusMark[$($p.pane_id)] $bold$agentName$reset ($($p.workspace_id)/$($p.tab_id)) - $statusText$dim$tokenQuota$tokenContext$reset"
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

# === CONTEXT ONLY DISPLAY ===
if ($Context) {
    $esc = [char]27
    $bold = "$esc[1m"
    $reset = "$esc[0m"
    $cyan = "$esc[36m"
    $magenta = "$esc[35m"
    $blue = "$esc[34m"
    $dim = "$esc[2m"

    Write-Host "$cyan$bold==> CodexBar: AI Context & Token Monitor$reset"
    Write-Host ""

    $claudeCtx = Get-AgentContext "claude"
    Write-Host "$blue$bold[Anthropic Claude (Claude Code)]$reset"
    if ($claudeCtx) {
        Write-Host "  Session Context:   $bold$($claudeCtx.detailed)$reset"
        Write-Host "  Estimated Tokens:  $($claudeCtx.raw_tokens)"
    } else {
        Write-Host "  No active Claude session found."
    }
    Write-Host ""

    $codexCtx = Get-AgentContext "codex"
    Write-Host "$cyan$bold[OpenAI Codex]$reset"
    if ($codexCtx) {
        Write-Host "  Session Context:   $bold$($codexCtx.detailed)$reset"
        if ($codexCtx.pct -ne $null) {
            Write-Host "  Context Used:      $($codexCtx.pct)%"
        }
    } else {
        Write-Host "  No active Codex session found."
    }
    Write-Host ""

    $agyCtx = Get-AgentContext "agy"
    Write-Host "$magenta$bold[Antigravity / Agy]$reset"
    if ($agyCtx) {
        Write-Host "  Session Context:   $bold$($agyCtx.detailed)$reset"
        Write-Host "  Estimated Tokens:  $($agyCtx.raw_tokens)"
        Write-Host "  Transcript Size:   $($agyCtx.size_str) ($($agyCtx.raw_bytes) bytes)"
    } else {
        Write-Host "  No active Agy session found."
    }
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

$showClaude = ($Target -eq "" -or $Target -match '^(claude|anthropic)$')
$showCodex = ($Target -eq "" -or $Target -match '^(codex|openai)$')
$showAgy = ($Target -eq "" -or $Target -match '^(agy|antigravity|gemini)$')

Write-Host "$cyan$bold==> CodexBar: AI Usage & Quota Monitor$reset"
Write-Host ""

$sectionsShown = 0

if ($showClaude) {
    if ($sectionsShown -gt 0) { Write-Host "" }
    Write-Host "$blue$bold[Anthropic Claude (Claude Code)]$reset"
    if ($claude.Error) {
        Write-Host "  Error: $($claude.Error)"
    } else {
        $cpRem = if ($claude.primary.remaining -ne $null) { $claude.primary.remaining } else { 0 }
        $csRem = if ($claude.secondary.remaining -ne $null) { $claude.secondary.remaining } else { 0 }
        $cpColor = if ($cpRem -ge 50) { $green } elseif ($cpRem -ge 20) { $yellow } else { $red }
        $csColor = if ($csRem -ge 50) { $green } elseif ($csRem -ge 20) { $yellow } else { $red }

        $infoParts = @()
        if ($claude.email) { $infoParts += "Account: $($claude.email)" }
        if ($claude.plan) { $infoParts += "($($claude.plan.ToUpper()) plan)" }
        if ($claude.org) { $infoParts += "Org: $($claude.org)" }
        if ($infoParts.Count -gt 0) {
            Write-Host "  $dim$($infoParts -join ' ')$reset"
        }

        $claudeCtx = Get-AgentContext "claude"
        if ($claudeCtx) {
            Write-Host "  Session Context:   $bold$($claudeCtx.detailed)$reset"
        }
        $cpResetStr = if ($claude.primary.reset_text) { " (resets in $($claude.primary.reset_text))" } else { "" }
        $csResetStr = if ($claude.secondary.reset_text) { " (resets in $($claude.secondary.reset_text))" } else { "" }
        Write-Host "  Session 5h:        $cpColor${cpRem}%$reset$cpResetStr"
        Write-Host "  Weekly 7d:         $csColor${csRem}%$reset$csResetStr"
    }
    $sectionsShown++
}

if ($showCodex) {
    if ($sectionsShown -gt 0) { Write-Host "" }
    Write-Host "$cyan$bold[OpenAI Codex]$reset"
    if ($codex.Error) {
        Write-Host "  Error: $($codex.Error)"
    } else {
        $cpColor = if ($codex.primary.remaining -ge 50) { $green } elseif ($codex.primary.remaining -ge 20) { $yellow } else { $red }
        $csColor = if ($codex.secondary.remaining -ge 50) { $green } elseif ($codex.secondary.remaining -ge 20) { $yellow } else { $red }

        Write-Host "  $dim Account: $($codex.email) ($($codex.plan.ToUpper())) | Credits: $($codex.credits)$reset"
        $codexCtx = Get-AgentContext "codex"
        if ($codexCtx) {
            Write-Host "  Session Context:   $bold$($codexCtx.detailed)$reset"
        }
        Write-Host "  Session 5h:        $cpColor$($codex.primary.remaining)%$reset (resets in $($codex.primary.reset_text))"
        Write-Host "  Weekly 7d:         $csColor$($codex.secondary.remaining)%$reset (resets in $($codex.secondary.reset_text))"
    }
    $sectionsShown++
}

if ($showAgy) {
    if ($sectionsShown -gt 0) { Write-Host "" }
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

        $agyCtx = Get-AgentContext "agy"
        if ($agyCtx) {
            Write-Host "  Session Context:   $bold$($agyCtx.detailed)$reset"
        }

        Write-Host "  Gemini Models:     5h $gColor${g5h}%$reset (resets in $($g5hB.reset_text)) | Weekly: ${gWk}%"
        Write-Host "  Claude/GPT Models: 5h $tpColor${tp5h}%$reset (resets in $($tp5hB.reset_text)) | Weekly: ${tpWk}%"
    }
    $sectionsShown++
}
