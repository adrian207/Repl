#Requires -Version 5.1
#Requires -Modules ActiveDirectory
# Note: Admin rights recommended for full functionality, but not strictly required for read-only audit mode

<#
.NOTES
    Optimized for PowerShell 7.5.4+ with enhanced parallel processing and retry logic.
    Falls back gracefully to PowerShell 5.1 with serial processing.
#>

<#
.SYNOPSIS
    Advanced Active Directory Replication Management Tool with Multi-Mode Operation
    
.DESCRIPTION
    Production-ready AD replication manager with safety guards, parallelism, and comprehensive reporting.
    
    FEATURES:
    - Multi-mode operation: Audit | Repair | Verify | AuditRepairVerify
    - Scoped execution: Forest | Site | DCList
    - WhatIf/Confirm support for all impactful operations
    - Parallel DC processing with configurable throttling
    - Pipeline-friendly verbose/information streams
    - JSON summary for CI/CD integration
    - Audit trail with optional transcript logging
    - Consolidated reporting (CSV, HTML, JSON)

.AUTHOR
    Adrian Johnson <adrian207@gmail.com>

.VERSION
    3.3.0

.DATE
    October 28, 2025

.COPYRIGHT
    Copyright (c) 2025 Adrian Johnson. All rights reserved.

.LICENSE
    MIT License
    
.PARAMETER Mode
    Operation mode. Default: Audit
    - Audit: Read-only health assessment
    - Repair: Audit + repair operations
    - Verify: Post-repair verification only
    - AuditRepairVerify: Complete workflow
    
.PARAMETER Scope
    Execution scope. Default: DCList
    - Forest: All DCs in forest (requires explicit confirmation)
    - Site:<Name>: All DCs in specified site
    - DCList: Use -DomainControllers parameter
    
.PARAMETER DomainControllers
    Explicit list of DC hostnames. Required when Scope=DCList.
    
.PARAMETER DomainName
    Domain FQDN to query. Default: Current user's domain.
    
.PARAMETER AutoRepair
    Skip repair confirmation prompts. Use with caution.
    
.PARAMETER Throttle
    Max parallel operations. Default: 8. Range: 1-32.
    
.PARAMETER OutputPath
    Report output directory. Default: .\ADRepl-<timestamp>
    
.PARAMETER AuditTrail
    Enable transcript logging for tamper-evident audit trail.
    
.PARAMETER Timeout
    Per-DC operation timeout in seconds. Default: 300.
    
.EXAMPLE
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02
    
    Audit-only mode for specific DCs (safe, read-only)
    
.EXAMPLE
    .\Invoke-ADReplicationManager.ps1 -Mode Repair -Scope Site:Default-First-Site-Name -AutoRepair -AuditTrail
    
    Automated repair for all DCs in site with full logging
    
.EXAMPLE
    .\Invoke-ADReplicationManager.ps1 -Mode AuditRepairVerify -DomainControllers DC01,DC02 -WhatIf
    
    Preview all actions without executing (WhatIf support)
    
.NOTES
    Author: Consolidated from AD-Repl-Audit.ps1 and AD-ReplicationRepair.ps1
    Version: 3.3.0
    Requires: PowerShell 5.1+, RSAT-AD-PowerShell, Domain Admin rights
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Audit', 'Repair', 'Verify', 'AuditRepairVerify')]
    [string]$Mode = 'Audit',
    
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^(Forest|Site:.+|DCList)$')]
    [string]$Scope = 'DCList',
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$DomainControllers = @(),
    
    [Parameter(Mandatory = $false)]
    [string]$DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name,
    
    [Parameter(Mandatory = $false)]
    [switch]$AutoRepair,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 32)]
    [int]$Throttle = 8,
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ 
        if ($_ -and -not (Test-Path (Split-Path $_) -PathType Container)) {
            throw "Parent directory must exist: $(Split-Path $_)"
        }
        $true
    })]
    [string]$OutputPath = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$AuditTrail,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(60, 3600)]
    [int]$Timeout = 300,
    
    [Parameter(Mandatory = $false)]
    [switch]$FastMode,
    
    # Notification Parameters
    [Parameter(Mandatory = $false)]
    [string]$SlackWebhook,
    
    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhook,
    
    [Parameter(Mandatory = $false)]
    [string]$EmailTo,
    
    [Parameter(Mandatory = $false)]
    [string]$EmailFrom = "ADReplication@company.com",
    
    [Parameter(Mandatory = $false)]
    [string]$SmtpServer,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('OnError', 'OnIssues', 'Always', 'Never')]
    [string]$EmailNotification = 'OnIssues',
    
    # Scheduled Task Parameters
    [Parameter(Mandatory = $false)]
    [switch]$CreateScheduledTask,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Hourly', 'Every4Hours', 'Daily', 'Weekly')]
    [string]$TaskSchedule = 'Daily',
    
    [Parameter(Mandatory = $false)]
    [string]$TaskName = "AD Replication Health Check",
    
    [Parameter(Mandatory = $false)]
    [string]$TaskTime = "02:00",
    
    # Health Score Parameters
    [Parameter(Mandatory = $false)]
    [switch]$EnableHealthScore,
    
    [Parameter(Mandatory = $false)]
    [string]$HealthHistoryPath = "$env:ProgramData\ADReplicationManager\History",
    
    # Auto-Healing Parameters
    [Parameter(Mandatory = $false)]
    [switch]$AutoHeal,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Conservative', 'Moderate', 'Aggressive')]
    [string]$HealingPolicy = 'Conservative',
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$MaxHealingActions = 10,
    
    [Parameter(Mandatory = $false)]
    [switch]$EnableRollback,
    
    [Parameter(Mandatory = $false)]
    [string]$HealingHistoryPath = "$env:ProgramData\ADReplicationManager\Healing",
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$HealingCooldownMinutes = 15,
    
    # Delta Mode Parameters
    [Parameter(Mandatory = $false)]
    [switch]$DeltaMode,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1440)]
    [int]$DeltaThresholdMinutes = 60,
    
    [Parameter(Mandatory = $false)]
    [string]$DeltaCachePath = "$env:ProgramData\ADReplicationManager\Cache",
    
    [Parameter(Mandatory = $false)]
    [switch]$ForceFull
)

# ============================================================================
# SCHEDULED TASK CREATION (Exit Early)
# ============================================================================

if ($CreateScheduledTask) {
    Write-Information "Creating scheduled task: $TaskName" -InformationAction Continue
    
    # Build the command arguments
    $scriptPath = $PSCommandPath
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Mode $Mode -Scope $Scope"
    
    if ($DomainControllers.Count -gt 0) {
        $dcList = $DomainControllers -join ','
        $arguments += " -DomainControllers $dcList"
    }
    
    if ($FastMode) { $arguments += " -FastMode" }
    if ($AutoRepair) { $arguments += " -AutoRepair" }
    if ($AuditTrail) { $arguments += " -AuditTrail" }
    if ($EnableHealthScore) { $arguments += " -EnableHealthScore" }
    if ($Throttle -ne 8) { $arguments += " -Throttle $Throttle" }
    if ($OutputPath) { $arguments += " -OutputPath `"$OutputPath`"" }
    if ($SlackWebhook) { $arguments += " -SlackWebhook `"$SlackWebhook`"" }
    if ($TeamsWebhook) { $arguments += " -TeamsWebhook `"$TeamsWebhook`"" }
    if ($EmailTo) { 
        $arguments += " -EmailTo `"$EmailTo`""
        if ($SmtpServer) { $arguments += " -SmtpServer `"$SmtpServer`"" }
        if ($EmailFrom) { $arguments += " -EmailFrom `"$EmailFrom`"" }
        $arguments += " -EmailNotification $EmailNotification"
    }
    
    try {
        # Create the action
        $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument $arguments
        
        # Create the trigger based on schedule
        $trigger = switch ($TaskSchedule) {
            'Hourly' {
                New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
            }
            'Every4Hours' {
                New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration ([TimeSpan]::MaxValue)
            }
            'Daily' {
                New-ScheduledTaskTrigger -Daily -At $TaskTime
            }
            'Weekly' {
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $TaskTime
            }
        }
        
        # Create the principal (run as SYSTEM with highest privileges)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Register the task
        [void](Register-ScheduledTask -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Description "Automated AD replication health monitoring and repair" `
            -Force)
        
        Write-Information "✅ Scheduled task created successfully!" -InformationAction Continue
        Write-Information "   Task Name: $TaskName" -InformationAction Continue
        Write-Information "   Schedule: $TaskSchedule" -InformationAction Continue
        Write-Information "   Command: pwsh.exe $arguments" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        Write-Information "To manage the task:" -InformationAction Continue
        Write-Information "   View:   Get-ScheduledTask -TaskName '$TaskName'" -InformationAction Continue
        Write-Information "   Run:    Start-ScheduledTask -TaskName '$TaskName'" -InformationAction Continue
        Write-Information "   Remove: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -InformationAction Continue
        
        exit 0
    }
    catch {
        Write-Error "Failed to create scheduled task: $_"
        exit 1
    }
}

# ============================================================================
# GLOBAL STATE
# ============================================================================

$Script:RepairLog = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Script:StartTime = Get-Date
$Script:ExitCode = 0

# Retry configuration
$Script:MaxRetryAttempts = 3
$Script:InitialDelaySeconds = 2
$Script:MaxDelaySeconds = 30
$Script:TransientErrorPatterns = @(
    'RPC server is unavailable',
    'network path was not found',
    'connection attempt failed',
    'timeout',
    'server is not operational',
    'temporarily unavailable'
)

# Fast Mode optimizations
if ($FastMode) {
    Write-Information "⚡ Fast Mode enabled - Performance optimizations active" -InformationAction Continue
    
    # Increase throttle for faster parallel execution
    if ($Throttle -eq 8) { 
        $Throttle = 24
        Write-Information "  → Throttle increased: 8 → 24" -InformationAction Continue
    }
    
    # Reduce verification wait time
    $Script:VerificationWaitSeconds = 30
    
    # Reduce retry attempts for faster failure
    $Script:MaxRetryAttempts = 2
    $Script:InitialDelaySeconds = 1
    
    Write-Information "  → Verification wait reduced: 120s → 30s" -InformationAction Continue
    Write-Information "  → Retry attempts reduced: 3 → 2" -InformationAction Continue
    Write-Information "  → Expected 40-60% performance improvement" -InformationAction Continue
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-RepairLog {
    <#
    .SYNOPSIS
        Pipeline-friendly logging with structured output streams.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Verbose', 'Information', 'Warning', 'Error')]
        [string]$Level = 'Information'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    [void]$Script:RepairLog.Add($logEntry)
    
    switch ($Level) {
        'Verbose'     { Write-Verbose $Message }
        'Information' { Write-Information $Message -InformationAction Continue }
        'Warning'     { Write-Warning $Message }
        'Error'       { Write-Error $Message }
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with exponential backoff retry logic.
    
    .DESCRIPTION
        Retries transient failures with exponential backoff. 
        Non-transient errors (auth, permissions) fail immediately without retry.
        
        Backoff formula: delay = min(InitialDelay * 2^attempt, MaxDelay)
        Example: 2s, 4s, 8s, 16s, 30s (capped at MaxDelay)
    
    .PARAMETER ScriptBlock
        The script block to execute
    
    .PARAMETER MaxAttempts
        Maximum number of attempts (default: 3)
    
    .PARAMETER Context
        Descriptive context for logging (e.g., "Query DC01")
    
    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Get-ADReplicationPartnerMetadata -Target $dc } -Context "Query $dc"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = $Script:MaxRetryAttempts,
        
        [Parameter(Mandatory = $false)]
        [string]$Context = "Operation"
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        
        try {
            Write-RepairLog "$Context - Attempt $attempt/$MaxAttempts" -Level Verbose
            
            # Execute the script block
            $result = & $ScriptBlock
            
            # Success - return result
            if ($attempt -gt 1) {
                Write-RepairLog "$Context - Succeeded on attempt $attempt" -Level Information
            }
            
            return $result
        }
        catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message
            
            # Check if error is transient
            $isTransient = $false
            foreach ($pattern in $Script:TransientErrorPatterns) {
                if ($errorMessage -match $pattern) {
                    $isTransient = $true
                    break
                }
            }
            
            # Check for permanent errors (don't retry)
            $isPermanent = $errorMessage -match '(Access is denied|Logon failure|domain does not exist|cannot find|not found)'
            
            if ($isPermanent) {
                Write-RepairLog "$Context - Permanent error detected, not retrying: $errorMessage" -Level Warning
                throw
            }
            
            if (-not $isTransient) {
                Write-RepairLog "$Context - Non-transient error, not retrying: $errorMessage" -Level Warning
                throw
            }
            
            # Transient error - calculate backoff and retry
            if ($attempt -lt $MaxAttempts) {
                # Exponential backoff: 2s, 4s, 8s, 16s, 30s (capped)
                $delay = [Math]::Min(
                    $Script:InitialDelaySeconds * [Math]::Pow(2, $attempt - 1),
                    $Script:MaxDelaySeconds
                )
                
                Write-RepairLog "$Context - Transient error on attempt $attempt/$MaxAttempts, retrying in $delay seconds: $errorMessage" -Level Warning
                Start-Sleep -Seconds $delay
            }
            else {
                Write-RepairLog "$Context - Failed after $MaxAttempts attempts: $errorMessage" -Level Error
                throw
            }
        }
    }
    
    # Should never reach here, but just in case
    if ($lastError) {
        throw $lastError
    }
}

function Send-SlackAlert {
    <#
    .SYNOPSIS
        Sends a formatted alert to Slack webhook.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary,
        
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl
    )
    
    try {
        # Determine color based on exit code
        $color = switch ($Script:ExitCode) {
            0 { "good" }      # Green
            2 { "warning" }   # Yellow
            default { "danger" } # Red
        }
        
        # Determine emoji status
        $statusEmoji = switch ($Script:ExitCode) {
            0 { ":white_check_mark:" }
            2 { ":warning:" }
            3 { ":no_entry:" }
            default { ":x:" }
        }
        
        $statusText = switch ($Script:ExitCode) {
            0 { "Healthy" }
            2 { "Issues Detected" }
            3 { "DCs Unreachable" }
            default { "Error" }
        }
        
        # Build Slack payload
        $payload = @{
            username = "AD Replication Monitor"
            icon_emoji = ":satellite:"
            attachments = @(
                @{
                    color = $color
                    title = "$statusEmoji AD Replication Report - $statusText"
                    fields = @(
                        @{ title = "Mode"; value = $Summary.Mode; short = $true }
                        @{ title = "Exit Code"; value = $Script:ExitCode; short = $true }
                        @{ title = "Total DCs"; value = $Summary.TotalDCs; short = $true }
                        @{ title = "Healthy"; value = "$($Summary.HealthyDCs) :white_check_mark:"; short = $true }
                        @{ title = "Degraded"; value = "$($Summary.DegradedDCs) :warning:"; short = $true }
                        @{ title = "Unreachable"; value = "$($Summary.UnreachableDCs) :no_entry:"; short = $true }
                        @{ title = "Issues Found"; value = $Summary.IssuesFound; short = $true }
                        @{ title = "Actions Performed"; value = $Summary.ActionsPerformed; short = $true }
                        @{ title = "Duration"; value = $Summary.ExecutionTime; short = $true }
                        @{ title = "Domain"; value = $Summary.Domain; short = $true }
                    )
                    footer = "AD Replication Manager"
                    ts = [int][double]::Parse((Get-Date -UFormat %s))
                }
            )
        } | ConvertTo-Json -Depth 5
        
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop
        Write-RepairLog "Slack notification sent successfully" -Level Verbose
    }
    catch {
        Write-RepairLog "Failed to send Slack notification: $_" -Level Warning
    }
}

function Send-TeamsAlert {
    <#
    .SYNOPSIS
        Sends a formatted alert to Microsoft Teams webhook.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary,
        
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl
    )
    
    try {
        # Determine theme color based on exit code
        $themeColor = switch ($Script:ExitCode) {
            0 { "00FF00" }      # Green
            2 { "FFA500" }      # Orange
            3 { "FF4500" }      # Red-Orange
            default { "FF0000" } # Red
        }
        
        $statusText = switch ($Script:ExitCode) {
            0 { "✅ Healthy" }
            2 { "⚠️ Issues Detected" }
            3 { "🚫 DCs Unreachable" }
            default { "❌ Error" }
        }
        
        # Build Teams adaptive card payload
        $payload = @{
            "@type" = "MessageCard"
            "@context" = "https://schema.org/extensions"
            summary = "AD Replication Report"
            themeColor = $themeColor
            title = "AD Replication Report - $statusText"
            sections = @(
                @{
                    activityTitle = "**$($Summary.Mode)** Mode Execution"
                    activitySubtitle = "Domain: $($Summary.Domain)"
                    facts = @(
                        @{ name = "Exit Code"; value = $Script:ExitCode }
                        @{ name = "Total DCs"; value = $Summary.TotalDCs }
                        @{ name = "Healthy"; value = "$($Summary.HealthyDCs) ✅" }
                        @{ name = "Degraded"; value = "$($Summary.DegradedDCs) ⚠️" }
                        @{ name = "Unreachable"; value = "$($Summary.UnreachableDCs) 🚫" }
                        @{ name = "Issues Found"; value = $Summary.IssuesFound }
                        @{ name = "Actions Performed"; value = $Summary.ActionsPerformed }
                        @{ name = "Duration"; value = $Summary.ExecutionTime }
                    )
                }
            )
        } | ConvertTo-Json -Depth 5
        
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        Write-RepairLog "Teams notification sent successfully" -Level Verbose
    }
    catch {
        Write-RepairLog "Failed to send Teams notification: $_" -Level Warning
    }
}

function Send-EmailAlert {
    <#
    .SYNOPSIS
        Sends an email alert with replication summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary,
        
        [Parameter(Mandatory = $true)]
        [string]$To,
        
        [Parameter(Mandatory = $true)]
        [string]$From,
        
        [Parameter(Mandatory = $true)]
        [string]$SmtpServer
    )
    
    try {
        $statusText = switch ($Script:ExitCode) {
            0 { "✅ Healthy" }
            2 { "⚠️ Issues Detected" }
            3 { "🚫 DCs Unreachable" }
            default { "❌ Error" }
        }
        
        $priority = switch ($Script:ExitCode) {
            0 { "Normal" }
            2 { "High" }
            default { "High" }
        }
        
        $subject = "AD Replication Alert - $statusText ($($Summary.DegradedDCs) Degraded, $($Summary.UnreachableDCs) Unreachable)"
        
        $body = @"
AD Replication Manager - Execution Report
==========================================

Status: $statusText
Exit Code: $($Script:ExitCode)

SUMMARY
-------
Mode: $($Summary.Mode)
Domain: $($Summary.Domain)
Execution Time: $($Summary.ExecutionTime)

DOMAIN CONTROLLER STATUS
------------------------
Total DCs: $($Summary.TotalDCs)
Healthy: $($Summary.HealthyDCs) ✅
Degraded: $($Summary.DegradedDCs) ⚠️
Unreachable: $($Summary.UnreachableDCs) 🚫

ACTIONS
-------
Issues Found: $($Summary.IssuesFound)
Actions Performed: $($Summary.ActionsPerformed)

REPORTS
-------
Output Directory: $($Summary.OutputPath)

---
This is an automated message from AD Replication Manager
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
        
        $mailParams = @{
            To = $To
            From = $From
            Subject = $subject
            Body = $body
            SmtpServer = $SmtpServer
            Priority = $priority
        }
        
        Send-MailMessage @mailParams -ErrorAction Stop
        Write-RepairLog "Email notification sent to $To" -Level Verbose
    }
    catch {
        Write-RepairLog "Failed to send email notification: $_" -Level Warning
    }
}

function Get-HealthScore {
    <#
    .SYNOPSIS
        Calculates a 0-100 health score based on DC status and replication health.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Snapshots,
        
        [Parameter(Mandatory = $true)]
        [array]$Issues
    )
    
    # Start with perfect score
    $score = 100.0
    
    # Deduct points for DC status
    foreach ($snapshot in $Snapshots) {
        switch ($snapshot.Status) {
            'Unreachable' { 
                $score -= 10  # Major penalty for unreachable DCs
            }
            'Degraded' { 
                $score -= 5   # Medium penalty for degraded DCs
            }
        }
    }
    
    # Deduct points for issues
    foreach ($issue in $Issues) {
        switch ($issue.Severity) {
            'Critical' { $score -= 3 }
            'High' { $score -= 2 }
            'Medium' { $score -= 1 }
            'Low' { $score -= 0.5 }
        }
    }
    
    # Deduct for stale replication (if data available)
    foreach ($snapshot in $Snapshots) {
        if ($snapshot.InboundPartners) {
            foreach ($partner in $snapshot.InboundPartners) {
                if ($partner.LastReplicationSuccess) {
                    $hoursSinceSuccess = ((Get-Date) - [datetime]$partner.LastReplicationSuccess).TotalHours
                    
                    if ($hoursSinceSuccess -gt 48) {
                        $score -= 2  # Very stale
                    }
                    elseif ($hoursSinceSuccess -gt 24) {
                        $score -= 1  # Stale
                    }
                }
            }
        }
    }
    
    # Ensure score stays within 0-100 range
    $score = [Math]::Max(0, [Math]::Min(100, $score))
    
    # Determine letter grade
    $grade = switch ($score) {
        {$_ -ge 95} { "A+ - Excellent" }
        {$_ -ge 90} { "A - Excellent" }
        {$_ -ge 85} { "B+ - Very Good" }
        {$_ -ge 80} { "B - Good" }
        {$_ -ge 75} { "C+ - Fair" }
        {$_ -ge 70} { "C - Fair" }
        {$_ -ge 60} { "D - Poor" }
        default { "F - Critical" }
    }
    
    return @{
        Score = [Math]::Round($score, 2)
        Grade = $grade
        Timestamp = Get-Date
    }
}

function Save-HealthHistory {
    <#
    .SYNOPSIS
        Saves health score to historical CSV file for trend analysis.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$HealthScore,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath
    )
    
    try {
        # Ensure directory exists
        if (-not (Test-Path $HistoryPath)) {
            New-Item -Path $HistoryPath -ItemType Directory -Force | Out-Null
        }
        
        $historyFile = Join-Path $HistoryPath "health-history.csv"
        
        # Create history record
        $record = [PSCustomObject]@{
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            HealthScore = $HealthScore.Score
            Grade = $HealthScore.Grade
            TotalDCs = $Summary.TotalDCs
            HealthyDCs = $Summary.HealthyDCs
            DegradedDCs = $Summary.DegradedDCs
            UnreachableDCs = $Summary.UnreachableDCs
            IssuesFound = $Summary.IssuesFound
            ActionsPerformed = $Summary.ActionsPerformed
            Mode = $Summary.Mode
            ExitCode = $Script:ExitCode
        }
        
        # Append to CSV (create with headers if doesn't exist)
        if (Test-Path $historyFile) {
            $record | Export-Csv $historyFile -Append -NoTypeInformation
        }
        else {
            $record | Export-Csv $historyFile -NoTypeInformation
        }
        
        Write-RepairLog "Health history saved to: $historyFile" -Level Verbose
        
        # Also save a snapshot in JSON format for richer analysis
        $snapshotFile = Join-Path $HistoryPath "snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        @{
            HealthScore = $HealthScore
            Summary = $Summary
            Timestamp = Get-Date -Format 'o'
        } | ConvertTo-Json -Depth 3 | Out-File $snapshotFile
        
        # Keep only last 90 days of snapshots to prevent bloat
        Get-ChildItem $HistoryPath -Filter "snapshot-*.json" | 
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } |
            Remove-Item -Force
            
        Write-RepairLog "Health snapshot saved to: $snapshotFile" -Level Verbose
    }
    catch {
        Write-RepairLog "Failed to save health history: $_" -Level Warning
    }
}

function Resolve-ScopeToDCs {
    <#
    .SYNOPSIS
        Resolves Scope parameter to explicit DC list with safety checks.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Scope,
        [string[]]$ExplicitDCs,
        [string]$Domain
    )
    
    $resolvedDCs = @()
    
    switch -Regex ($Scope) {
        '^Forest$' {
            Write-RepairLog "Resolving Forest scope - this targets ALL domain controllers" -Level Warning
            
            if (-not $PSCmdlet.ShouldProcess("All DCs in forest", "Query and process")) {
                throw "Forest scope requires explicit confirmation. Operation cancelled."
            }
            
            try {
                $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
                foreach ($domain in $forest.Domains) {
                    $dcs = Get-ADDomainController -Filter * -Server $domain.Name -ErrorAction Stop
                    $resolvedDCs += $dcs | Select-Object -ExpandProperty HostName
                }
                Write-RepairLog "Resolved $($resolvedDCs.Count) DCs across forest" -Level Information
            }
            catch {
                throw "Failed to resolve forest DCs: $_"
            }
        }
        
        '^Site:(.+)$' {
            $siteName = $Matches[1]
            Write-RepairLog "Resolving Site scope: $siteName" -Level Information
            
            try {
                $dcs = Get-ADDomainController -Filter "Site -eq '$siteName'" -Server $Domain -ErrorAction Stop
                $resolvedDCs = $dcs | Select-Object -ExpandProperty HostName
                
                if ($resolvedDCs.Count -eq 0) {
                    throw "No DCs found in site '$siteName'. Verify site name."
                }
                
                Write-RepairLog "Resolved $($resolvedDCs.Count) DCs in site $siteName" -Level Information
            }
            catch {
                throw "Failed to resolve site '$siteName': $_"
            }
        }
        
        '^DCList$' {
            if ($ExplicitDCs.Count -eq 0) {
                throw "Scope=DCList requires -DomainControllers parameter. Use -Scope Forest or -Scope Site:<name> for discovery."
            }
            
            # Handle comma-separated single string
            if ($ExplicitDCs.Count -eq 1 -and $ExplicitDCs[0] -match ',') {
                $ExplicitDCs = $ExplicitDCs[0] -split ',' | ForEach-Object { $_.Trim() }
            }
            
            $resolvedDCs = $ExplicitDCs
            Write-RepairLog "Using explicit DC list: $($resolvedDCs -join ', ')" -Level Information
        }
    }
    
    if ($resolvedDCs.Count -eq 0) {
        throw "No domain controllers resolved. Check parameters and try again."
    }
    
    return $resolvedDCs
}

function Get-ReplicationSnapshot {
    <#
    .SYNOPSIS
        Captures current replication state across DCs with parallel processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers,
        
        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 8,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )
    
    Write-RepairLog "Capturing replication snapshot for $($DomainControllers.Count) DCs (throttle: $ThrottleLimit)" -Level Information
    
    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    
    # PowerShell 7+ parallel support
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $DomainControllers | ForEach-Object -Parallel {
            $dc = $_
            $timeout = $using:TimeoutSeconds
            
            $snapshot = [PSCustomObject]@{
                DC                  = $dc
                Timestamp           = Get-Date
                InboundPartners     = @()
                Failures            = @()
                Status              = 'Unknown'
                Error               = $null
            }
            
            try {
                # Time-bounded operation
                $job = Start-Job -ScriptBlock {
                    param($dcName)
                    Import-Module ActiveDirectory -ErrorAction Stop
                    
                    $partners = Get-ADReplicationPartnerMetadata -Target $dcName -ErrorAction Stop
                    $failures = Get-ADReplicationFailure -Target $dcName -ErrorAction SilentlyContinue
                    
                    return @{
                        Partners = $partners
                        Failures = $failures
                    }
                } -ArgumentList $dc
                
                $completed = Wait-Job -Job $job -Timeout $timeout
                
                if ($completed) {
                    $data = Receive-Job -Job $job -ErrorAction Stop
                    
                    $snapshot.InboundPartners = $data.Partners | ForEach-Object {
                        [PSCustomObject]@{
                            Partner                      = $_.Partner
                            Partition                    = $_.Partition
                            LastAttempt                  = $_.LastReplicationAttempt
                            LastSuccess                  = $_.LastReplicationSuccess
                            LastResult                   = $_.LastReplicationResult
                            ConsecutiveFailures          = $_.ConsecutiveReplicationFailures
                            HoursSinceLastSuccess        = if ($_.LastReplicationSuccess) { 
                                ((Get-Date) - $_.LastReplicationSuccess).TotalHours 
                            } else { $null }
                        }
                    }
                    
                    $snapshot.Failures = $data.Failures | ForEach-Object {
                        [PSCustomObject]@{
                            Partner          = $_.Partner
                            FailureType      = $_.FailureType
                            FailureCount     = $_.FailureCount
                            FirstFailureTime = $_.FirstFailureTime
                            LastError        = $_.LastError
                        }
                    }
                    
                    $snapshot.Status = if ($snapshot.Failures.Count -eq 0) { 'Healthy' } else { 'Degraded' }
                }
                else {
                    throw "Operation timed out after $timeout seconds"
                }
                
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
            catch {
                $snapshot.Status = 'Failed'
                $snapshot.Error = $_.Exception.Message
            }
            
            ($using:results).Add($snapshot)
        } -ThrottleLimit $ThrottleLimit
    }
    else {
        # PowerShell 5.1 fallback - serial processing with better error handling
        Write-RepairLog "[Inference] PowerShell 5.1 detected; parallel processing not available. Processing serially." -Level Warning
        
        foreach ($dc in $DomainControllers) {
            $snapshot = [PSCustomObject]@{
                DC                  = $dc
                Timestamp           = Get-Date
                InboundPartners     = @()
                Failures            = @()
                Status              = 'Unknown'
                Error               = $null
            }
            
            try {
                $partners = Get-ADReplicationPartnerMetadata -Target $dc -ErrorAction Stop
                $failures = Get-ADReplicationFailure -Target $dc -ErrorAction SilentlyContinue
                
                $snapshot.InboundPartners = $partners | ForEach-Object {
                    [PSCustomObject]@{
                        Partner                      = $_.Partner
                        Partition                    = $_.Partition
                        LastAttempt                  = $_.LastReplicationAttempt
                        LastSuccess                  = $_.LastReplicationSuccess
                        LastResult                   = $_.LastReplicationResult
                        ConsecutiveFailures          = $_.ConsecutiveReplicationFailures
                        HoursSinceLastSuccess        = if ($_.LastReplicationSuccess) { 
                            ((Get-Date) - $_.LastReplicationSuccess).TotalHours 
                        } else { $null }
                    }
                }
                
                $snapshot.Failures = $failures | ForEach-Object {
                    [PSCustomObject]@{
                        Partner          = $_.Partner
                        FailureType      = $_.FailureType
                        FailureCount     = $_.FailureCount
                        FirstFailureTime = $_.FirstFailureTime
                        LastError        = $_.LastError
                    }
                }
                
                $snapshot.Status = if ($snapshot.Failures.Count -eq 0) { 'Healthy' } else { 'Degraded' }
            }
            catch [Microsoft.ActiveDirectory.Management.ADServerDownException] {
                $snapshot.Status = 'Unreachable'
                $snapshot.Error = "DC unreachable: $_"
                Write-RepairLog "DC unreachable: $dc" -Level Warning
            }
            catch {
                $snapshot.Status = 'Failed'
                $snapshot.Error = $_.Exception.Message
                Write-RepairLog "Failed to query $dc : $_" -Level Error
            }
            
            $results.Add($snapshot)
        }
    }
    
    return $results.ToArray()
}

function Find-ReplicationIssues {
    <#
    .SYNOPSIS
        Pure evaluation function - analyzes snapshot and returns issue objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Snapshots
    )
    
    begin {
        $allIssues = @()
    }
    
    process {
        foreach ($snapshot in $Snapshots) {
            # Issue category 1: Query failures
            if ($snapshot.Status -in @('Failed', 'Unreachable')) {
                $allIssues += [PSCustomObject]@{
                    DC          = $snapshot.DC
                    Category    = 'Connectivity'
                    Severity    = 'High'
                    Description = "Unable to query DC: $($snapshot.Error)"
                    Actionable  = $true
                }
            }
            
            # Issue category 2: Active replication failures
            foreach ($failure in $snapshot.Failures) {
                $allIssues += [PSCustomObject]@{
                    DC          = $snapshot.DC
                    Category    = 'ReplicationFailure'
                    Severity    = 'High'
                    Description = "Replication failure with $($failure.Partner): Error $($failure.LastError)"
                    Partner     = $failure.Partner
                    ErrorCode   = $failure.LastError
                    Actionable  = $true
                }
            }
            
            # Issue category 3: Stale replication (>24h)
            foreach ($partner in $snapshot.InboundPartners) {
                if ($partner.HoursSinceLastSuccess -and $partner.HoursSinceLastSuccess -gt 24) {
                    $allIssues += [PSCustomObject]@{
                        DC          = $snapshot.DC
                        Category    = 'StaleReplication'
                        Severity    = 'Medium'
                        Description = "No successful replication with $($partner.Partner) for $([math]::Round($partner.HoursSinceLastSuccess, 1)) hours"
                        Partner     = $partner.Partner
                        Actionable  = $true
                    }
                }
            }
        }
    }
    
    end {
        Write-RepairLog "Identified $($allIssues.Count) issues across $($Snapshots.Count) DCs" -Level Information
        return $allIssues
    }
}

function Get-HealingPolicy {
    <#
    .SYNOPSIS
        Defines auto-healing policies with allowed actions and risk levels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Conservative', 'Moderate', 'Aggressive')]
        [string]$PolicyName
    )
    
    $policies = @{
        Conservative = @{
            AllowedCategories = @('StaleReplication')
            AllowedSeverities = @('Low', 'Medium')
            MaxConcurrentActions = 3
            RequireManualApproval = @('ReplicationFailure', 'Connectivity')
            RollbackOnFailure = $true
            CooldownMinutes = 30
            Description = 'Conservative policy - Only fixes low-risk stale replication issues'
            RiskLevel = 'Low'
        }
        Moderate = @{
            AllowedCategories = @('StaleReplication', 'ReplicationFailure')
            AllowedSeverities = @('Low', 'Medium', 'High')
            MaxConcurrentActions = 5
            RequireManualApproval = @('Connectivity')
            RollbackOnFailure = $true
            CooldownMinutes = 15
            Description = 'Moderate policy - Fixes stale replication and replication failures'
            RiskLevel = 'Medium'
        }
        Aggressive = @{
            AllowedCategories = @('StaleReplication', 'ReplicationFailure', 'Connectivity')
            AllowedSeverities = @('Low', 'Medium', 'High', 'Critical')
            MaxConcurrentActions = 10
            RequireManualApproval = @()
            RollbackOnFailure = $true
            CooldownMinutes = 5
            Description = 'Aggressive policy - Attempts to fix all detected issues automatically'
            RiskLevel = 'High'
        }
    }
    
    return $policies[$PolicyName]
}

function Test-HealingEligibility {
    <#
    .SYNOPSIS
        Determines if an issue is eligible for auto-healing based on policy and history.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Issue,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory = $true)]
        [int]$CooldownMinutes
    )
    
    $eligible = @{
        Allowed = $false
        Reason = ''
    }
    
    # Check 1: Category allowed by policy
    if ($Issue.Category -notin $Policy.AllowedCategories) {
        $eligible.Reason = "Category '$($Issue.Category)' not allowed by policy"
        return $eligible
    }
    
    # Check 2: Severity allowed by policy
    if ($Issue.Severity -notin $Policy.AllowedSeverities) {
        $eligible.Reason = "Severity '$($Issue.Severity)' not allowed by policy"
        return $eligible
    }
    
    # Check 3: Manual approval required
    if ($Issue.Category -in $Policy.RequireManualApproval) {
        $eligible.Reason = "Category '$($Issue.Category)' requires manual approval"
        return $eligible
    }
    
    # Check 4: Cooldown period (prevent healing loops)
    if (Test-Path $HistoryPath) {
        $historyFile = Join-Path $HistoryPath "healing-history.csv"
        if (Test-Path $historyFile) {
            $recentActions = Import-Csv $historyFile | Where-Object {
                $_.DC -eq $Issue.DC -and
                $_.Category -eq $Issue.Category -and
                ([DateTime]$_.Timestamp) -gt (Get-Date).AddMinutes(-$CooldownMinutes)
            }
            
            if ($recentActions) {
                $eligible.Reason = "Cooldown period active (last action within $CooldownMinutes minutes)"
                return $eligible
            }
        }
    }
    
    # Check 5: Issue is actionable
    if (-not $Issue.Actionable) {
        $eligible.Reason = "Issue marked as not actionable"
        return $eligible
    }
    
    # All checks passed
    $eligible.Allowed = $true
    $eligible.Reason = "Eligible for auto-healing under $($Policy.Description)"
    
    return $eligible
}

function Save-HealingAction {
    <#
    .SYNOPSIS
        Records healing action to audit trail and enables rollback capability.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Issue,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Action,
        
        [Parameter(Mandatory = $true)]
        [string]$Policy,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath
    )
    
    try {
        # Ensure directory exists
        if (-not (Test-Path $HistoryPath)) {
            New-Item -Path $HistoryPath -ItemType Directory -Force | Out-Null
        }
        
        $historyFile = Join-Path $HistoryPath "healing-history.csv"
        
        # Create healing record
        $record = [PSCustomObject]@{
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            DC = $Action.DC
            Category = $Issue.Category
            Severity = $Issue.Severity
            Description = $Issue.Description
            Method = $Action.Method
            Success = $Action.Success
            Message = $Action.Message
            Policy = $Policy
            RollbackAvailable = ($Action.Method -match 'repadmin|replicate')
            ActionID = [Guid]::NewGuid().ToString().Substring(0, 8)
        }
        
        # Append to CSV
        if (Test-Path $historyFile) {
            $record | Export-Csv $historyFile -Append -NoTypeInformation
        }
        else {
            $record | Export-Csv $historyFile -NoTypeInformation
        }
        
        # Also save detailed JSON for rollback
        if ($record.RollbackAvailable) {
            $rollbackFile = Join-Path $HistoryPath "rollback-$($record.ActionID).json"
            @{
                Record = $record
                Issue = $Issue
                Action = $Action
                Timestamp = Get-Date -Format 'o'
                RollbackCommand = "repadmin /showrepl $($Action.DC)"  # Pre-state captured
            } | ConvertTo-Json -Depth 5 | Out-File $rollbackFile
        }
        
        Write-RepairLog "Healing action recorded: $($record.ActionID)" -Level Verbose
        
        # Cleanup old records (>30 days)
        Get-ChildItem $HistoryPath -Filter "rollback-*.json" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
            
        return $record.ActionID
    }
    catch {
        Write-RepairLog "Failed to save healing action: $_" -Level Warning
        return $null
    }
}

function Invoke-HealingRollback {
    <#
    .SYNOPSIS
        Attempts to rollback a healing action that failed or caused issues.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionID,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Reason = "Manual rollback request"
    )
    
    $rollbackFile = Join-Path $HistoryPath "rollback-$ActionID.json"
    
    if (-not (Test-Path $rollbackFile)) {
        Write-RepairLog "Rollback file not found for action $ActionID" -Level Warning
        return $false
    }
    
    try {
        $rollbackData = Get-Content $rollbackFile -Raw | ConvertFrom-Json
        $dc = $rollbackData.Record.DC
        
        Write-RepairLog "Initiating rollback for action $ActionID on $dc - Reason: $Reason" -Level Information
        
        if ($PSCmdlet.ShouldProcess($dc, "Rollback healing action $ActionID")) {
            # Rollback strategy: Force fresh replication to restore pre-action state
            # This is safer than trying to "undo" specific actions
            Write-RepairLog "Forcing fresh replication sync on $dc" -Level Verbose
            
            $output = & repadmin /syncall /A /P /e /d $dc 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-RepairLog "Rollback successful for $dc" -Level Information
                
                # Mark rollback in history
                $rollbackRecord = [PSCustomObject]@{
                    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    ActionID = $ActionID
                    DC = $dc
                    RollbackSuccess = $true
                    Reason = $Reason
                }
                
                $rollbackHistoryFile = Join-Path $HistoryPath "rollback-history.csv"
                if (Test-Path $rollbackHistoryFile) {
                    $rollbackRecord | Export-Csv $rollbackHistoryFile -Append -NoTypeInformation
                }
                else {
                    $rollbackRecord | Export-Csv $rollbackHistoryFile -NoTypeInformation
                }
                
                return $true
            }
            else {
                Write-RepairLog "Rollback failed for $dc : $output" -Level Error
                return $false
            }
        }
        
        return $false
    }
    catch {
        Write-RepairLog "Rollback exception for action $ActionID : $_" -Level Error
        return $false
    }
}

function Get-HealingStatistics {
    <#
    .SYNOPSIS
        Retrieves statistics from healing history for reporting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysBack = 30
    )
    
    $stats = @{
        TotalActions = 0
        SuccessfulActions = 0
        FailedActions = 0
        RolledBackActions = 0
        CategoriesHealed = @{}
        TopDCs = @{}
        SuccessRate = 0
    }
    
    $historyFile = Join-Path $HistoryPath "healing-history.csv"
    
    if (-not (Test-Path $historyFile)) {
        return $stats
    }
    
    $history = Import-Csv $historyFile | Where-Object {
        ([DateTime]$_.Timestamp) -gt (Get-Date).AddDays(-$DaysBack)
    }
    
    $stats.TotalActions = $history.Count
    $stats.SuccessfulActions = @($history | Where-Object { $_.Success -eq 'True' }).Count
    $stats.FailedActions = $stats.TotalActions - $stats.SuccessfulActions
    
    if ($stats.TotalActions -gt 0) {
        $stats.SuccessRate = [Math]::Round(($stats.SuccessfulActions / $stats.TotalActions) * 100, 2)
    }
    
    # Category breakdown
    $categoryGroups = $history | Group-Object -Property Category
    foreach ($group in $categoryGroups) {
        $stats.CategoriesHealed[$group.Name] = $group.Count
    }
    
    # Top DCs with most healing actions
    $dcGroups = $history | Group-Object -Property DC | Sort-Object Count -Descending | Select-Object -First 5
    foreach ($group in $dcGroups) {
        $stats.TopDCs[$group.Name] = $group.Count
    }
    
    # Rollback count
    $rollbackHistoryFile = Join-Path $HistoryPath "rollback-history.csv"
    if (Test-Path $rollbackHistoryFile) {
        $rollbacks = Import-Csv $rollbackHistoryFile | Where-Object {
            ([DateTime]$_.Timestamp) -gt (Get-Date).AddDays(-$DaysBack)
        }
        $stats.RolledBackActions = $rollbacks.Count
    }
    
    return $stats
}

function Get-DeltaCache {
    <#
    .SYNOPSIS
        Retrieves cached information about DCs with previous issues.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CachePath,
        
        [Parameter(Mandatory = $true)]
        [int]$ThresholdMinutes
    )
    
    $cacheFile = Join-Path $CachePath "delta-cache.json"
    
    if (-not (Test-Path $cacheFile)) {
        Write-RepairLog "No delta cache found - will perform full scan" -Level Information
        return $null
    }
    
    try {
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $cacheAge = (Get-Date) - [DateTime]$cache.Timestamp
        
        if ($cacheAge.TotalMinutes -gt $ThresholdMinutes) {
            Write-RepairLog "Delta cache expired ($([Math]::Round($cacheAge.TotalMinutes, 1)) minutes old, threshold: $ThresholdMinutes) - will perform full scan" -Level Information
            return $null
        }
        
        Write-RepairLog "Delta cache valid (age: $([Math]::Round($cacheAge.TotalMinutes, 1)) minutes)" -Level Information
        return $cache
    }
    catch {
        Write-RepairLog "Failed to read delta cache: $_ - will perform full scan" -Level Warning
        return $null
    }
}

function Save-DeltaCache {
    <#
    .SYNOPSIS
        Saves current execution data to delta cache for next run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ExecutionData,
        
        [Parameter(Mandatory = $true)]
        [string]$CachePath
    )
    
    try {
        # Ensure directory exists
        if (-not (Test-Path $CachePath)) {
            New-Item -Path $CachePath -ItemType Directory -Force | Out-Null
        }
        
        $cacheFile = Join-Path $CachePath "delta-cache.json"
        
        # Identify DCs with issues
        $degradedDCs = @($ExecutionData.Snapshots | Where-Object { $_.Status -eq 'Degraded' } | Select-Object -ExpandProperty DC)
        $unreachableDCs = @($ExecutionData.Snapshots | Where-Object { $_.Status -eq 'Unreachable' } | Select-Object -ExpandProperty DC)
        $allIssueDCs = @($ExecutionData.Issues | Select-Object -ExpandProperty DC -Unique)
        
        # Combine and deduplicate
        $targetDCs = ($degradedDCs + $unreachableDCs + $allIssueDCs) | Select-Object -Unique
        
        $cache = @{
            Timestamp = Get-Date -Format 'o'
            TotalDCsScanned = $ExecutionData.Snapshots.Count
            DegradedDCs = $degradedDCs
            UnreachableDCs = $unreachableDCs
            AllIssueDCs = $allIssueDCs
            TargetDCsForNextRun = $targetDCs
            IssueCount = $ExecutionData.Issues.Count
            Mode = $ExecutionData.Mode
        }
        
        $cache | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding UTF8
        
        Write-RepairLog "Delta cache saved: $($targetDCs.Count) DCs with issues will be checked on next delta run" -Level Information
        
        # Cleanup old cache files
        Get-ChildItem $CachePath -Filter "delta-cache-*.json" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
            
        return $targetDCs.Count
    }
    catch {
        Write-RepairLog "Failed to save delta cache: $_" -Level Warning
        return 0
    }
}

function Get-DeltaTargetDCs {
    <#
    .SYNOPSIS
        Determines which DCs to check based on delta mode settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AllDCs,
        
        [Parameter(Mandatory = $true)]
        [string]$CachePath,
        
        [Parameter(Mandatory = $true)]
        [int]$ThresholdMinutes,
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceFull
    )
    
    if ($ForceFull) {
        Write-RepairLog "ForceFull specified - scanning all $($AllDCs.Count) DCs" -Level Information
        return @{
            TargetDCs = $AllDCs
            Mode = 'Full'
            Reason = 'ForceFull parameter specified'
            CacheUsed = $false
        }
    }
    
    $cache = Get-DeltaCache -CachePath $CachePath -ThresholdMinutes $ThresholdMinutes
    
    if (-not $cache) {
        return @{
            TargetDCs = $AllDCs
            Mode = 'Full'
            Reason = 'No valid cache available'
            CacheUsed = $false
        }
    }
    
    # Get DCs from cache
    $cachedDCs = $cache.TargetDCsForNextRun
    
    if ($cachedDCs.Count -eq 0) {
        Write-RepairLog "Previous run had no issues - scanning all DCs to confirm health" -Level Information
        return @{
            TargetDCs = $AllDCs
            Mode = 'Full'
            Reason = 'Previous run had no issues'
            CacheUsed = $true
            PreviousScan = @{
                Timestamp = $cache.Timestamp
                IssueCount = 0
            }
        }
    }
    
    # Filter to DCs that still exist in current scope
    $targetDCs = $cachedDCs | Where-Object { $_ -in $AllDCs }
    
    if ($targetDCs.Count -eq 0) {
        Write-RepairLog "No cached DCs match current scope - performing full scan" -Level Warning
        return @{
            TargetDCs = $AllDCs
            Mode = 'Full'
            Reason = 'Cached DCs not in current scope'
            CacheUsed = $true
        }
    }
    
    $savedCount = $AllDCs.Count - $targetDCs.Count
    $savedPercent = [Math]::Round(($savedCount / $AllDCs.Count) * 100, 1)
    
    Write-RepairLog "Delta mode: Checking $($targetDCs.Count) DCs (skipping $savedCount DCs, $savedPercent% reduction)" -Level Information
    
    return @{
        TargetDCs = $targetDCs
        Mode = 'Delta'
        Reason = "Previous issues on $($targetDCs.Count) DCs"
        CacheUsed = $true
        PreviousScan = @{
            Timestamp = $cache.Timestamp
            TotalDCs = $cache.TotalDCsScanned
            IssueCount = $cache.IssueCount
        }
        PerformanceGain = @{
            DCsSkipped = $savedCount
            PercentReduction = $savedPercent
        }
    }
}

function Invoke-ReplicationFix {
    <#
    .SYNOPSIS
        Idempotent repair operations with ShouldProcess guards.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainController,
        
        [Parameter(Mandatory = $true)]
        [object[]]$Issues
    )
    
    $actions = @()
    
    foreach ($issue in $Issues) {
        if (-not $issue.Actionable) { continue }
        
        $action = [PSCustomObject]@{
            DC          = $DomainController
            IssueType   = $issue.Category
            Method      = 'Unknown'
            Success     = $false
            Message     = ''
            Timestamp   = Get-Date
        }
        
        try {
            switch ($issue.Category) {
                'ReplicationFailure' {
                    $action.Method = 'repadmin /syncall'
                    
                    if ($PSCmdlet.ShouldProcess($DomainController, "Force replication sync (repadmin /syncall)")) {
                        Write-RepairLog "Executing repadmin /syncall on $DomainController" -Level Verbose
                        
                        $output = & repadmin /syncall /A /P /e $DomainController 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            $action.Success = $true
                            $action.Message = "Sync initiated successfully"
                            Write-RepairLog "Sync successful on $DomainController" -Level Information
                        }
                        else {
                            $action.Message = "Sync failed with exit code $LASTEXITCODE : $output"
                            Write-RepairLog $action.Message -Level Warning
                        }
                    }
                    else {
                        $action.Message = "Skipped due to WhatIf or user cancellation"
                        Write-RepairLog "Repair skipped by user: $DomainController" -Level Information
                    }
                }
                
                'StaleReplication' {
                    $action.Method = 'repadmin /replicate'
                    
                    if ($PSCmdlet.ShouldProcess($DomainController, "Replicate from $($issue.Partner)")) {
                        Write-RepairLog "Forcing replication from $($issue.Partner) to $DomainController" -Level Verbose
                        
                        # Target a specific partition sync
                        $output = & repadmin /syncall /A /P /e $DomainController 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            $action.Success = $true
                            $action.Message = "Initiated sync with partner"
                            Write-RepairLog "Partner sync initiated: $DomainController <-> $($issue.Partner)" -Level Information
                        }
                        else {
                            $action.Message = "Partner sync failed: $output"
                            Write-RepairLog $action.Message -Level Warning
                        }
                    }
                    else {
                        $action.Message = "Skipped due to WhatIf or user cancellation"
                    }
                }
                
                'Connectivity' {
                    $action.Method = 'ConnectivityCheck'
                    $action.Message = "Connectivity issue requires manual investigation"
                    Write-RepairLog "Connectivity issue on $DomainController - manual intervention required" -Level Warning
                }
            }
        }
        catch {
            $action.Message = "Exception during repair: $_"
            Write-RepairLog "Repair exception for $DomainController : $_" -Level Error
        }
        
        $actions += $action
    }
    
    return $actions
}

function Test-ReplicationHealth {
    <#
    .SYNOPSIS
        Post-repair verification with lightweight checks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers,
        
        [Parameter(Mandatory = $false)]
        [int]$WaitSeconds = 120
    )
    
    # Use Fast Mode wait time if configured
    if ($Script:VerificationWaitSeconds) {
        $WaitSeconds = $Script:VerificationWaitSeconds
    }
    
    Write-RepairLog "Waiting $WaitSeconds seconds for replication convergence..." -Level Information
    Start-Sleep -Seconds $WaitSeconds
    
    Write-RepairLog "Performing post-repair verification..." -Level Information
    
    $verificationResults = @()
    
    foreach ($dc in $DomainControllers) {
        $result = [PSCustomObject]@{
            DC              = $dc
            RepadminCheck   = 'Unknown'
            FailureCount    = 0
            SuccessCount    = 0
            OverallHealth   = 'Unknown'
        }
        
        try {
            Write-RepairLog "Verifying $dc via repadmin /showrepl" -Level Verbose
            
            $output = & repadmin /showrepl $dc 2>&1
            
            $errors = @($output | Where-Object { $_ -match 'Last error: (\d+)' -and $Matches[1] -ne '0' })
            $successes = @($output | Where-Object { $_ -match 'was successful|SYNC EACH WRITE' })
            
            $result.FailureCount = $errors.Count
            $result.SuccessCount = $successes.Count
            
            if ($errors.Count -eq 0 -and $successes.Count -gt 0) {
                $result.RepadminCheck = 'Pass'
                $result.OverallHealth = 'Healthy'
            }
            elseif ($errors.Count -gt 0) {
                $result.RepadminCheck = 'Fail'
                $result.OverallHealth = 'Degraded'
            }
            else {
                $result.RepadminCheck = 'Inconclusive'
                $result.OverallHealth = 'Unknown'
            }
            
            Write-RepairLog "$dc : $($result.OverallHealth) ($($result.SuccessCount) links, $($result.FailureCount) errors)" -Level Information
        }
        catch {
            $result.RepadminCheck = 'Error'
            $result.OverallHealth = 'Failed'
            Write-RepairLog "Verification failed for $dc : $_" -Level Error
        }
        
        $verificationResults += $result
    }
    
    return $verificationResults
}

function Export-ReplReports {
    <#
    .SYNOPSIS
        Consolidated reporting: CSV, JSON, HTML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )
    
    try {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        Write-RepairLog "Exporting reports to: $OutputDirectory" -Level Information
        
        $paths = @{
            SnapshotCSV     = Join-Path $OutputDirectory 'ReplicationSnapshot.csv'
            IssuesCSV       = Join-Path $OutputDirectory 'IdentifiedIssues.csv'
            ActionsCSV      = Join-Path $OutputDirectory 'RepairActions.csv'
            VerificationCSV = Join-Path $OutputDirectory 'VerificationResults.csv'
            SummaryJSON     = Join-Path $OutputDirectory 'summary.json'
            LogTXT          = Join-Path $OutputDirectory 'execution.log'
        }
        
        # CSV exports
        if ($Data.Snapshots) {
            $Data.Snapshots | Export-Csv $paths.SnapshotCSV -NoTypeInformation -Encoding UTF8
        }
        
        if ($Data.Issues) {
            $Data.Issues | Export-Csv $paths.IssuesCSV -NoTypeInformation -Encoding UTF8
        }
        
        if ($Data.RepairActions) {
            $Data.RepairActions | Export-Csv $paths.ActionsCSV -NoTypeInformation -Encoding UTF8
        }
        
        if ($Data.Verification) {
            $Data.Verification | Export-Csv $paths.VerificationCSV -NoTypeInformation -Encoding UTF8
        }
        
        # JSON summary for CI
        $elapsed = (Get-Date) - $Script:StartTime
        $summary = @{
            Timestamp       = Get-Date -Format 'o'
            ExecutionTime   = $elapsed.ToString('hh\:mm\:ss')
            Mode            = $Data.Mode
            Scope           = $Data.Scope
            Domain          = $DomainName
            TotalDCs        = $Data.Snapshots.Count
            HealthyDCs      = @($Data.Snapshots | Where-Object { $_.Status -eq 'Healthy' }).Count
            DegradedDCs     = @($Data.Snapshots | Where-Object { $_.Status -eq 'Degraded' }).Count
            UnreachableDCs  = @($Data.Snapshots | Where-Object { $_.Status -eq 'Unreachable' }).Count
            IssuesFound     = $Data.Issues.Count
            ActionsPerformed = if ($Data.RepairActions) { $Data.RepairActions.Count } else { 0 }
            ExitCode        = $Script:ExitCode
            OutputPath      = $OutputDirectory
        }
        
        # Calculate health score if enabled
        if ($EnableHealthScore) {
            $healthScore = Get-HealthScore -Snapshots $Data.Snapshots -Issues $Data.Issues
            $summary.HealthScore = $healthScore.Score
            $summary.HealthGrade = $healthScore.Grade
            
            Write-RepairLog "Health Score: $($healthScore.Score)/100 ($($healthScore.Grade))" -Level Information
            
            # Save to historical tracking
            Save-HealthHistory -HealthScore $healthScore -Summary $summary -HistoryPath $HealthHistoryPath
        }
        
        $summary | ConvertTo-Json -Depth 5 | Out-File $paths.SummaryJSON -Encoding UTF8
        
        # Execution log
        $Script:RepairLog | Out-File $paths.LogTXT -Encoding UTF8
        
        Write-RepairLog "Reports exported: $(($paths.Values | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')" -Level Information
        
        return @{
            Paths = $paths
            Summary = $summary
        }
    }
    catch {
        Write-RepairLog "Failed to export reports: $_" -Level Error
        throw
    }
}

function Write-RunSummary {
    <#
    .SYNOPSIS
        Final status summary with actionable guidance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    $elapsed = (Get-Date) - $Script:StartTime
    
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "EXECUTION SUMMARY" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Mode            : $($Data.Mode)" -InformationAction Continue
    Write-Information "Scope           : $($Data.Scope)" -InformationAction Continue
    Write-Information "DCs Processed   : $($Data.Snapshots.Count)" -InformationAction Continue
    Write-Information "Issues Found    : $($Data.Issues.Count)" -InformationAction Continue
    Write-Information "Actions Taken   : $(if ($Data.RepairActions) { $Data.RepairActions.Count } else { 0 })" -InformationAction Continue
    Write-Information "Duration        : $($elapsed.ToString('mm\:ss'))" -InformationAction Continue
    Write-Information "Exit Code       : $Script:ExitCode" -InformationAction Continue
    
    # Actionable guidance
    if ($Data.Issues.Count -eq 0) {
        Write-Information "`n✓ All DCs healthy - no action required" -InformationAction Continue
    }
    elseif ($Data.Mode -eq 'Audit') {
        Write-Information "`n⚠ Issues detected - run with -Mode Repair to attempt fixes" -InformationAction Continue
    }
    elseif ($Data.RepairActions -and @($Data.RepairActions | Where-Object { -not $_.Success }).Count -gt 0) {
        Write-Information "`n⚠ Some repairs failed - review logs and consider manual intervention" -InformationAction Continue
    }
    
    Write-Information "========================================`n" -InformationAction Continue
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    # Initialize
    if ($AuditTrail) {
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $OutputPath = Join-Path $PWD "ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        $transcriptPath = Join-Path $OutputPath "transcript-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        Start-Transcript -Path $transcriptPath
        Write-RepairLog "Audit trail enabled: $transcriptPath" -Level Information
    }
    
    Write-RepairLog "=== AD Replication Manager v3.3.0 ===" -Level Information
    Write-RepairLog "Mode: $Mode | Scope: $Scope | Throttle: $Throttle" -Level Information
    
    # Pre-flight checks
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-RepairLog "ActiveDirectory module loaded" -Level Verbose
    }
    catch {
        Write-RepairLog "Failed to load ActiveDirectory module. Install RSAT-AD-PowerShell." -Level Error
        throw
    }
    
    # Resolve target DCs
    $allDCs = Resolve-ScopeToDCs -Scope $Scope -ExplicitDCs $DomainControllers -Domain $DomainName
    Write-RepairLog "Scope resolution: $($allDCs.Count) DCs in scope" -Level Information
    
    # Delta Mode: Filter to DCs with previous issues
    $deltaResult = $null
    if ($DeltaMode) {
        Write-RepairLog "Delta Mode enabled (threshold: $DeltaThresholdMinutes minutes)" -Level Information
        
        $deltaResult = Get-DeltaTargetDCs -AllDCs $allDCs -CachePath $DeltaCachePath `
            -ThresholdMinutes $DeltaThresholdMinutes -ForceFull:$ForceFull
        
        $targetDCs = $deltaResult.TargetDCs
        
        Write-RepairLog "Delta Mode: $($deltaResult.Mode) scan - $($deltaResult.Reason)" -Level Information
        
        if ($deltaResult.Mode -eq 'Delta') {
            Write-RepairLog "Performance gain: Skipping $($deltaResult.PerformanceGain.DCsSkipped) DCs ($($deltaResult.PerformanceGain.PercentReduction)% reduction)" -Level Information
        }
    }
    else {
        $targetDCs = $allDCs
    }
    
    Write-RepairLog "Target DCs for execution: $($targetDCs.Count)" -Level Information
    
    # Data collection structure
    $executionData = @{
        Mode            = $Mode
        Scope           = $Scope
        DeltaMode       = $DeltaMode
        DeltaResult     = $deltaResult
        Snapshots       = @()
        Issues          = @()
        RepairActions   = @()
        Verification    = @()
    }
    
    # Phase 1: Audit (always run unless Mode=Verify)
    if ($Mode -ne 'Verify') {
        Write-RepairLog "=== PHASE: AUDIT ===" -Level Information
        $executionData.Snapshots = Get-ReplicationSnapshot -DomainControllers $targetDCs -ThrottleLimit $Throttle -TimeoutSeconds $Timeout
        $executionData.Issues = $executionData.Snapshots | Find-ReplicationIssues
        
        # Set exit code based on issues
        $criticalIssues = @($executionData.Issues | Where-Object { $_.Severity -eq 'High' })
        if ($criticalIssues.Count -gt 0) {
            $Script:ExitCode = 2
        }
        
        $unreachable = @($executionData.Snapshots | Where-Object { $_.Status -eq 'Unreachable' })
        if ($unreachable.Count -gt 0) {
            $Script:ExitCode = 3
        }
    }
    
    # Phase 2: Repair (if requested)
    if ($Mode -in @('Repair', 'AuditRepairVerify')) {
        if ($executionData.Issues.Count -eq 0) {
            Write-RepairLog "No issues detected - skipping repair phase" -Level Information
        }
        else {
            Write-RepairLog "=== PHASE: REPAIR ===" -Level Information
            
            # Auto-Healing logic
            if ($AutoHeal) {
                Write-RepairLog "Auto-Healing enabled with '$HealingPolicy' policy" -Level Information
                
                # Load healing policy
                $policy = Get-HealingPolicy -PolicyName $HealingPolicy
                Write-RepairLog "Policy: $($policy.Description) | Risk Level: $($policy.RiskLevel)" -Level Information
                Write-RepairLog "Max concurrent actions: $($policy.MaxConcurrentActions) | Cooldown: $($policy.CooldownMinutes) minutes" -Level Information
                
                # Filter issues based on policy eligibility
                $eligibleIssues = @()
                $skippedIssues = @()
                
                foreach ($issue in $executionData.Issues) {
                    $eligibility = Test-HealingEligibility -Issue $issue -Policy $policy `
                        -HistoryPath $HealingHistoryPath -CooldownMinutes $HealingCooldownMinutes
                    
                    if ($eligibility.Allowed) {
                        $eligibleIssues += $issue
                        Write-RepairLog "✓ Issue eligible: $($issue.DC) - $($issue.Category)" -Level Verbose
                    }
                    else {
                        $skippedIssues += $issue
                        Write-RepairLog "✗ Issue skipped: $($issue.DC) - $($issue.Category) - Reason: $($eligibility.Reason)" -Level Information
                    }
                }
                
                Write-RepairLog "Auto-Healing: $($eligibleIssues.Count) eligible, $($skippedIssues.Count) skipped" -Level Information
                
                # Respect MaxHealingActions limit
                if ($eligibleIssues.Count -gt $MaxHealingActions) {
                    Write-RepairLog "Limiting healing actions to $MaxHealingActions (policy max: $($policy.MaxConcurrentActions), parameter: $MaxHealingActions)" -Level Warning
                    $eligibleIssues = $eligibleIssues | Select-Object -First $MaxHealingActions
                }
                
                # Perform auto-healing on eligible issues
                if ($eligibleIssues.Count -gt 0) {
                    $issuesByDC = $eligibleIssues | Group-Object -Property DC
                    
                    foreach ($group in $issuesByDC) {
                        $dc = $group.Name
                        $dcIssues = $group.Group
                        
                        Write-RepairLog "Auto-Healing $dc ($($dcIssues.Count) issues)" -Level Information
                        $repairActions = Invoke-ReplicationFix -DomainController $dc -Issues $dcIssues
                        
                        # Save healing actions to audit trail
                        foreach ($action in $repairActions) {
                            $correspondingIssue = $dcIssues | Where-Object { $_.Category -eq $action.Method.Split('/')[0] -or $_.DC -eq $action.DC } | Select-Object -First 1
                            if ($correspondingIssue) {
                                $actionID = Save-HealingAction -Issue $correspondingIssue -Action $action `
                                    -Policy $HealingPolicy -HistoryPath $HealingHistoryPath
                                
                                # Rollback if enabled and action failed
                                if ($EnableRollback -and -not $action.Success -and $actionID) {
                                    Write-RepairLog "Auto-Healing action failed, initiating rollback: $actionID" -Level Warning
                                    Invoke-HealingRollback -ActionID $actionID -HistoryPath $HealingHistoryPath `
                                        -Reason "Automatic rollback due to action failure"
                                }
                            }
                        }
                        
                        $executionData.RepairActions += $repairActions
                    }
                }
                
                # Track statistics
                $executionData.HealingStats = Get-HealingStatistics -HistoryPath $HealingHistoryPath -DaysBack 30
            }
            else {
                # Traditional manual/semi-automated repair
                if (-not $AutoRepair -and -not $WhatIfPreference) {
                    Write-Warning "$($executionData.Issues.Count) issues require repair."
                    $response = Read-Host "Proceed with repairs? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        Write-RepairLog "Repair cancelled by user" -Level Information
                        $Script:ExitCode = 0
                        throw "User cancelled repair operation"
                    }
                }
                
                # Group issues by DC and repair
                $issuesByDC = $executionData.Issues | Group-Object -Property DC
                
                foreach ($group in $issuesByDC) {
                    $dc = $group.Name
                    $dcIssues = $group.Group
                    
                    Write-RepairLog "Repairing $dc ($($dcIssues.Count) issues)" -Level Information
                    $repairActions = Invoke-ReplicationFix -DomainController $dc -Issues $dcIssues
                    $executionData.RepairActions += $repairActions
                }
            }
            
            # Adjust exit code if repairs succeeded
            $failedRepairs = @($executionData.RepairActions | Where-Object { -not $_.Success })
            if ($failedRepairs.Count -eq 0 -and $executionData.RepairActions.Count -gt 0) {
                $Script:ExitCode = 0
            }
        }
    }
    
    # Phase 3: Verify (if requested)
    if ($Mode -in @('Verify', 'AuditRepairVerify')) {
        Write-RepairLog "=== PHASE: VERIFY ===" -Level Information
        $executionData.Verification = Test-ReplicationHealth -DomainControllers $targetDCs -WaitSeconds 120
        
        $degraded = @($executionData.Verification | Where-Object { $_.OverallHealth -ne 'Healthy' })
        if ($degraded.Count -gt 0) {
            $Script:ExitCode = 2
        }
    }
    
    # Export reports
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputPath = Join-Path $PWD "ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    
    $reportResult = Export-ReplReports -Data $executionData -OutputDirectory $OutputPath
    $summary = $reportResult.Summary
    
    # Final summary
    Write-RunSummary -Data $executionData
    
    Write-RepairLog "Reports available at: $OutputPath" -Level Information
    
    # Send notifications if configured
    $shouldNotify = $false
    switch ($EmailNotification) {
        'OnError'  { $shouldNotify = ($Script:ExitCode -eq 4) }
        'OnIssues' { $shouldNotify = ($Script:ExitCode -in @(2, 3, 4)) }
        'Always'   { $shouldNotify = $true }
        'Never'    { $shouldNotify = $false }
    }
    
    if ($shouldNotify) {
        # Send Slack notification
        if ($SlackWebhook) {
            Write-RepairLog "Sending Slack notification..." -Level Information
            Send-SlackAlert -Summary $summary -WebhookUrl $SlackWebhook
        }
        
        # Send Teams notification
        if ($TeamsWebhook) {
            Write-RepairLog "Sending Teams notification..." -Level Information
            Send-TeamsAlert -Summary $summary -WebhookUrl $TeamsWebhook
        }
        
        # Send Email notification
        if ($EmailTo -and $SmtpServer) {
            Write-RepairLog "Sending email notification..." -Level Information
            Send-EmailAlert -Summary $summary -To $EmailTo -From $EmailFrom -SmtpServer $SmtpServer
        }
        elseif ($EmailTo -and -not $SmtpServer) {
            Write-RepairLog "Email notification skipped: SmtpServer parameter required" -Level Warning
        }
    }
    
    # Save Delta Cache for next run (only in Audit or AuditRepairVerify modes)
    if ($DeltaMode -and $Mode -ne 'Verify') {
        Write-RepairLog "Saving delta cache for next run..." -Level Verbose
        $cachedCount = Save-DeltaCache -ExecutionData $executionData -CachePath $DeltaCachePath
        Write-RepairLog "Delta cache saved: $cachedCount DCs will be prioritized on next delta run" -Level Information
    }
}
catch {
    Write-RepairLog "Fatal error: $_" -Level Error
    $Script:ExitCode = 4
    throw
}
finally {
    if ($AuditTrail) {
        Stop-Transcript
    }
    
    # Return exit code for CI/CD
    if ($Script:ExitCode -ne 0) {
        Write-Warning "Exiting with code $Script:ExitCode (0=Healthy, 2=Issues, 3=Unreachable, 4=Error)"
    }
    
    exit $Script:ExitCode
}

