# Feature Backlog - AD Replication Manager

**Version:** 1.0  
**Last Updated:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** Internal Use

---

## 🎯 Quick-Win Features (Can Implement Today)

### 1. **Email Alerts on Issues** ⭐⭐⭐⭐⭐

**Value:** High | **Effort:** Low | **Priority:** 🔴 Critical

```powershell
param(
    # ... existing parameters ...
    
    [Parameter(Mandatory = $false)]
    [string]$EmailTo,
    
    [Parameter(Mandatory = $false)]
    [string]$SmtpServer = "smtp.company.com",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('OnError', 'OnIssues', 'Always', 'Never')]
    [string]$EmailNotification = 'OnIssues'
)

# At end of script
if ($EmailNotification -ne 'Never' -and $EmailTo) {
    $shouldEmail = $false
    
    switch ($EmailNotification) {
        'OnError' { $shouldEmail = ($Script:ExitCode -eq 4) }
        'OnIssues' { $shouldEmail = ($Script:ExitCode -in @(2, 3, 4)) }
        'Always' { $shouldEmail = $true }
    }
    
    if ($shouldEmail) {
        $summary = Get-Content "$OutputPath\summary.json" | ConvertFrom-Json
        
        $body = @"
AD Replication Manager Alert

Exit Code: $($Script:ExitCode)
Mode: $($summary.Mode)
Total DCs: $($summary.TotalDCs)
Healthy: $($summary.HealthyDCs)
Degraded: $($summary.DegradedDCs)
Unreachable: $($summary.UnreachableDCs)
Issues Found: $($summary.IssuesFound)
Actions Performed: $($summary.ActionsPerformed)

Duration: $($summary.ExecutionTime)

Reports: $OutputPath
"@
        
        Send-MailMessage -To $EmailTo `
            -From "ADReplication@company.com" `
            -Subject "AD Replication Alert - $($summary.DegradedDCs) DCs Degraded" `
            -Body $body `
            -SmtpServer $SmtpServer
    }
}
```

**Usage:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -DomainControllers DC01..DC50 `
    -FastMode `
    -EmailTo "ad-admins@company.com" `
    -EmailNotification OnIssues
```

---

### 2. **Slack/Teams Integration** ⭐⭐⭐⭐⭐

**Value:** High | **Effort:** Low | **Priority:** 🔴 Critical

```powershell
param(
    [Parameter(Mandatory = $false)]
    [string]$SlackWebhook,
    
    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhook
)

function Send-SlackAlert {
    param($Summary, $WebhookUrl)
    
    $color = switch ($Script:ExitCode) {
        0 { "good" }    # Green
        2 { "warning" } # Yellow
        default { "danger" } # Red
    }
    
    $payload = @{
        attachments = @(
            @{
                color = $color
                title = "AD Replication Report"
                fields = @(
                    @{ title = "Status"; value = if ($Script:ExitCode -eq 0) { "✅ Healthy" } else { "⚠️ Issues Detected" }; short = $true }
                    @{ title = "Mode"; value = $Summary.Mode; short = $true }
                    @{ title = "Total DCs"; value = $Summary.TotalDCs; short = $true }
                    @{ title = "Healthy"; value = $Summary.HealthyDCs; short = $true }
                    @{ title = "Degraded"; value = $Summary.DegradedDCs; short = $true }
                    @{ title = "Unreachable"; value = $Summary.UnreachableDCs; short = $true }
                    @{ title = "Issues Found"; value = $Summary.IssuesFound; short = $true }
                    @{ title = "Duration"; value = $Summary.ExecutionTime; short = $true }
                )
            }
        )
    } | ConvertTo-Json -Depth 5
    
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json'
}
```

---

### 3. **Scheduled Task Auto-Setup** ⭐⭐⭐⭐

**Value:** High | **Effort:** Low | **Priority:** 🟡 High

```powershell
param(
    [Parameter(Mandatory = $false)]
    [switch]$CreateScheduledTask,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Hourly', 'Daily', 'Weekly')]
    [string]$Schedule = 'Daily',
    
    [Parameter(Mandatory = $false)]
    [string]$TaskName = "AD Replication Health Check"
)

if ($CreateScheduledTask) {
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" `
        -Argument "-File `"$PSCommandPath`" -Mode Audit -Scope Forest -FastMode -EmailTo admin@company.com"
    
    $trigger = switch ($Schedule) {
        'Hourly' { New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) }
        'Daily' { New-ScheduledTaskTrigger -Daily -At "2:00 AM" }
        'Weekly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "2:00 AM" }
    }
    
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Description "Automated AD replication health monitoring"
    
    Write-Information "✅ Scheduled task '$TaskName' created ($Schedule)" -InformationAction Continue
    exit 0
}
```

---

### 4. **Health Score & Trends** ⭐⭐⭐⭐

**Value:** Medium | **Effort:** Medium | **Priority:** 🟡 High

```powershell
function Calculate-HealthScore {
    param($Snapshots)
    
    $score = 100
    
    foreach ($snapshot in $Snapshots) {
        # Deduct points for issues
        if ($snapshot.Status -eq 'Unreachable') {
            $score -= 10
        }
        elseif ($snapshot.Status -eq 'Degraded') {
            $score -= 5
        }
        
        # Deduct for failures
        $score -= ($snapshot.Failures.Count * 2)
        
        # Deduct for stale replication
        foreach ($partner in $snapshot.InboundPartners) {
            if ($partner.HoursSinceLastSuccess -gt 24) {
                $score -= 1
            }
        }
    }
    
    return [Math]::Max(0, $score)
}

# Add to summary
$healthScore = Calculate-HealthScore -Snapshots $executionData.Snapshots

$summary = @{
    # ... existing properties ...
    HealthScore = $healthScore
    HealthGrade = switch ($healthScore) {
        {$_ -ge 90} { "A - Excellent" }
        {$_ -ge 80} { "B - Good" }
        {$_ -ge 70} { "C - Fair" }
        {$_ -ge 60} { "D - Poor" }
        default { "F - Critical" }
    }
}

# Store historical scores
$historyFile = "C:\Reports\AD-Health\history.csv"
$record = [PSCustomObject]@{
    Timestamp = Get-Date
    HealthScore = $healthScore
    TotalDCs = $summary.TotalDCs
    HealthyDCs = $summary.HealthyDCs
    DegradedDCs = $summary.DegradedDCs
    UnreachableDCs = $summary.UnreachableDCs
}
$record | Export-Csv $historyFile -Append -NoTypeInformation
```

---

### 5. **Delta Mode (Only Check Changed DCs)** ⭐⭐⭐⭐

**Value:** High | **Effort:** Medium | **Priority:** 🟡 High

```powershell
param(
    [Parameter(Mandatory = $false)]
    [switch]$DeltaMode,
    
    [Parameter(Mandatory = $false)]
    [int]$DeltaThresholdMinutes = 60
)

if ($DeltaMode) {
    # Load previous run results
    $previousRun = Get-ChildItem "$env:TEMP\ADRepl-Cache" -Filter "last-run.json" -ErrorAction SilentlyContinue
    
    if ($previousRun) {
        $lastRun = Get-Content $previousRun.FullName | ConvertFrom-Json
        $timeSinceLastRun = (Get-Date) - [DateTime]$lastRun.Timestamp
        
        if ($timeSinceLastRun.TotalMinutes -lt $DeltaThresholdMinutes) {
            # Only check DCs that had issues last time
            $targetDCs = $targetDCs | Where-Object { 
                $dc = $_
                $lastRun.DegradedDCs -contains $dc -or 
                $lastRun.UnreachableDCs -contains $dc
            }
            
            if ($targetDCs.Count -eq 0) {
                Write-Information "✅ Delta mode: No previously degraded DCs to check" -InformationAction Continue
                exit 0
            }
            
            Write-Information "⚡ Delta mode: Checking $($targetDCs.Count) previously degraded DCs" -InformationAction Continue
        }
    }
    
    # Save current run for next delta check
    $currentRun = @{
        Timestamp = Get-Date
        DegradedDCs = @($executionData.Snapshots | Where-Object { $_.Status -eq 'Degraded' } | Select-Object -ExpandProperty DC)
        UnreachableDCs = @($executionData.Snapshots | Where-Object { $_.Status -eq 'Unreachable' } | Select-Object -ExpandProperty DC)
    }
    New-Item -Path "$env:TEMP\ADRepl-Cache" -ItemType Directory -Force | Out-Null
    $currentRun | ConvertTo-Json | Out-File "$env:TEMP\ADRepl-Cache\last-run.json"
}
```

---

### 6. **Comparison Reports (Before/After)** ⭐⭐⭐⭐

**Value:** Medium | **Effort:** Low | **Priority:** 🟢 Medium

```powershell
param(
    [Parameter(Mandatory = $false)]
    [string]$CompareWithPreviousRun
)

if ($CompareWithPreviousRun -and (Test-Path $CompareWithPreviousRun)) {
    $previousSummary = Get-Content "$CompareWithPreviousRun\summary.json" | ConvertFrom-Json
    $currentSummary = Get-Content "$OutputPath\summary.json" | ConvertFrom-Json
    
    $comparison = [PSCustomObject]@{
        Metric = @('TotalDCs', 'HealthyDCs', 'DegradedDCs', 'UnreachableDCs', 'IssuesFound')
        Previous = @(
            $previousSummary.TotalDCs,
            $previousSummary.HealthyDCs,
            $previousSummary.DegradedDCs,
            $previousSummary.UnreachableDCs,
            $previousSummary.IssuesFound
        )
        Current = @(
            $currentSummary.TotalDCs,
            $currentSummary.HealthyDCs,
            $currentSummary.DegradedDCs,
            $currentSummary.UnreachableDCs,
            $currentSummary.IssuesFound
        )
        Change = @(
            $currentSummary.TotalDCs - $previousSummary.TotalDCs,
            $currentSummary.HealthyDCs - $previousSummary.HealthyDCs,
            $currentSummary.DegradedDCs - $previousSummary.DegradedDCs,
            $currentSummary.UnreachableDCs - $previousSummary.UnreachableDCs,
            $currentSummary.IssuesFound - $previousSummary.IssuesFound
        )
    }
    
    $comparison | Export-Csv "$OutputPath\comparison.csv" -NoTypeInformation
    
    Write-Information "`n📊 COMPARISON REPORT" -InformationAction Continue
    Write-Information "Healthy DCs: $($previousSummary.HealthyDCs) → $($currentSummary.HealthyDCs) ($(if($currentSummary.HealthyDCs -gt $previousSummary.HealthyDCs){'↑'}else{'↓'}) $([Math]::Abs($currentSummary.HealthyDCs - $previousSummary.HealthyDCs)))" -InformationAction Continue
    Write-Information "Degraded DCs: $($previousSummary.DegradedDCs) → $($currentSummary.DegradedDCs) ($(if($currentSummary.DegradedDCs -lt $previousSummary.DegradedDCs){'↓'}else{'↑'}) $([Math]::Abs($currentSummary.DegradedDCs - $previousSummary.DegradedDCs)))" -InformationAction Continue
}
```

---

### 7. **Interactive Mode (TUI)** ⭐⭐⭐

**Value:** Medium | **Effort:** High | **Priority:** 🟢 Medium

```powershell
param(
    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

if ($Interactive) {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   AD Replication Manager - Interactive Mode       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Menu
    Write-Host "Select an option:" -ForegroundColor Yellow
    Write-Host "  1. Quick Audit (All DCs)" -ForegroundColor White
    Write-Host "  2. Audit Specific Site" -ForegroundColor White
    Write-Host "  3. Audit & Repair" -ForegroundColor White
    Write-Host "  4. Full Workflow (Audit/Repair/Verify)" -ForegroundColor White
    Write-Host "  5. View Last Report" -ForegroundColor White
    Write-Host "  6. Exit" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter choice (1-6)"
    
    switch ($choice) {
        '1' {
            $Mode = 'Audit'
            $Scope = 'Forest'
            $FastMode = $true
        }
        '2' {
            $sites = Get-ADReplicationSite -Filter * | Select-Object -ExpandProperty Name
            Write-Host "`nAvailable sites:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $sites.Count; $i++) {
                Write-Host "  $($i+1). $($sites[$i])" -ForegroundColor White
            }
            $siteChoice = Read-Host "`nSelect site (1-$($sites.Count))"
            $Scope = "Site:$($sites[[int]$siteChoice - 1])"
            $Mode = 'Audit'
        }
        # ... more options
    }
}
```

---

### 8. **Export to Excel (Rich Reports)** ⭐⭐⭐⭐

**Value:** High | **Effort:** Medium | **Priority:** 🟡 High

```powershell
param(
    [Parameter(Mandatory = $false)]
    [switch]$ExportToExcel
)

if ($ExportToExcel) {
    # Requires ImportExcel module
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Install-Module -Name ImportExcel -Scope CurrentUser -Force
    }
    
    Import-Module ImportExcel
    
    $excelPath = Join-Path $OutputPath "AD-Replication-Report.xlsx"
    
    # Export to different worksheets
    $executionData.Snapshots | Export-Excel $excelPath -WorksheetName "Snapshots" -AutoSize -FreezeTopRow -TableStyle Medium6
    $executionData.Issues | Export-Excel $excelPath -WorksheetName "Issues" -AutoSize -FreezeTopRow -TableStyle Medium6
    
    if ($executionData.RepairActions) {
        $executionData.RepairActions | Export-Excel $excelPath -WorksheetName "Repairs" -AutoSize -FreezeTopRow -TableStyle Medium6
    }
    
    if ($executionData.Verification) {
        $executionData.Verification | Export-Excel $excelPath -WorksheetName "Verification" -AutoSize -FreezeTopRow -TableStyle Medium6
    }
    
    Write-Information "📊 Excel report: $excelPath" -InformationAction Continue
}
```

---

### 9. **Custom Repair Actions** ⭐⭐⭐⭐

**Value:** High | **Effort:** Medium | **Priority:** 🟡 High

```powershell
param(
    [Parameter(Mandatory = $false)]
    [string]$CustomRepairScript
)

# In Invoke-ReplicationFix function, add:
'Custom' {
    if ($CustomRepairScript -and (Test-Path $CustomRepairScript)) {
        $action.Method = 'CustomScript'
        
        if ($PSCmdlet.ShouldProcess($DomainController, "Run custom repair script")) {
            try {
                $result = & $CustomRepairScript -DC $DomainController -Issue $issue
                $action.Success = $result.Success
                $action.Message = $result.Message
            }
            catch {
                $action.Success = $false
                $action.Message = "Custom script failed: $_"
            }
        }
    }
}
```

**Custom repair script example:**
```powershell
# CustomRepair.ps1
param($DC, $Issue)

# Your custom logic here
if ($Issue.Category -eq 'HighLatency') {
    # Restart netlogon service
    Invoke-Command -ComputerName $DC -ScriptBlock {
        Restart-Service Netlogon -Force
    }
    
    return @{
        Success = $true
        Message = "Restarted Netlogon service"
    }
}

return @{
    Success = $false
    Message = "No custom action defined for $($Issue.Category)"
}
```

---

### 10. **Webhook Integration (Generic)** ⭐⭐⭐⭐

**Value:** High | **Effort:** Low | **Priority:** 🟡 High

```powershell
param(
    [Parameter(Mandatory = $false)]
    [string]$WebhookUrl,
    
    [Parameter(Mandatory = $false)]
    [hashtable]$WebhookHeaders = @{ 'Content-Type' = 'application/json' }
)

if ($WebhookUrl) {
    $payload = @{
        timestamp = Get-Date -Format 'o'
        script = 'AD-Replication-Manager'
        version = '3.0'
        exitCode = $Script:ExitCode
        summary = $summary
    } | ConvertTo-Json -Depth 5
    
    try {
        Invoke-RestMethod -Uri $WebhookUrl `
            -Method Post `
            -Body $payload `
            -Headers $WebhookHeaders `
            -ErrorAction Stop
        
        Write-Verbose "Webhook notification sent successfully"
    }
    catch {
        Write-Warning "Failed to send webhook: $_"
    }
}
```

---

## 🚀 Medium-Term Features (v3.1-v3.2)

### 11. **Real-Time Monitoring Mode** ⭐⭐⭐⭐⭐

**Value:** Very High | **Effort:** High | **Priority:** 🔴 Critical

```powershell
param(
    [Parameter(Mandatory = $false)]
    [switch]$Monitor,
    
    [Parameter(Mandatory = $false)]
    [int]$MonitorIntervalSeconds = 300  # 5 minutes
)

if ($Monitor) {
    Write-Information "🔄 Starting continuous monitoring (Ctrl+C to stop)..." -InformationAction Continue
    
    while ($true) {
        $result = & $PSCommandPath -Mode Audit -Scope Forest -FastMode
        
        if ($LASTEXITCODE -ne 0) {
            # Alert logic here
            Send-SlackAlert -Summary $result
        }
        
        Write-Information "Next check in $MonitorIntervalSeconds seconds..." -InformationAction Continue
        Start-Sleep -Seconds $MonitorIntervalSeconds
    }
}
```

---

### 12. **Azure AD Connect Health Integration** ⭐⭐⭐⭐⭐

**Value:** Very High | **Effort:** Medium | **Priority:** 🔴 Critical

```powershell
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeAzureADConnect,
    
    [Parameter(Mandatory = $false)]
    [string[]]$AADConnectServers
)

if ($IncludeAzureADConnect) {
    foreach ($server in $AADConnectServers) {
        $syncStatus = Invoke-Command -ComputerName $server -ScriptBlock {
            Import-Module ADSync
            Get-ADSyncScheduler
        }
        
        # Add to report
        $executionData.AADConnectStatus += [PSCustomObject]@{
            Server = $server
            SyncCycleEnabled = $syncStatus.SyncCycleEnabled
            LastSyncResult = $syncStatus.LastSyncResult
            LastSuccessfulSync = $syncStatus.LastSuccessfulSyncTime
        }
    }
}
```

---

### 13. **Predictive Analytics** ⭐⭐⭐⭐

**Value:** High | **Effort:** Very High | **Priority:** 🟢 Medium

Uses historical data to predict issues before they occur.

```powershell
function Get-PredictedIssues {
    param($HistoricalData)
    
    # Load last 30 days of health scores
    $history = Import-Csv "C:\Reports\AD-Health\history.csv" | 
        Where-Object { ([DateTime]$_.Timestamp) -gt (Get-Date).AddDays(-30) }
    
    # Simple linear regression for trend
    $predictions = @()
    
    foreach ($dc in $executionData.Snapshots.DC | Select-Object -Unique) {
        $dcHistory = $history | Where-Object { $_.DC -eq $dc }
        
        if ($dcHistory.Count -gt 5) {
            # Calculate trend
            $trend = ($dcHistory[-1].HealthScore - $dcHistory[0].HealthScore) / $dcHistory.Count
            
            if ($trend -lt -2) {  # Declining health
                $predictions += [PSCustomObject]@{
                    DC = $dc
                    PredictedIssue = "Health declining"
                    Probability = [Math]::Min(1, [Math]::Abs($trend) / 10)
                    EstimatedDays = [Math]::Ceiling(($dcHistory[-1].HealthScore / [Math]::Abs($trend)))
                    Recommendation = "Schedule maintenance"
                }
            }
        }
    }
    
    return $predictions
}
```

---

## 🔮 Long-Term Features (v4.0+)

### 14. **Web Dashboard** ⭐⭐⭐⭐⭐
- Real-time topology visualization
- Interactive DC health map
- Historical trend charts
- Mobile-responsive design

### 15. **Multi-Forest Support** ⭐⭐⭐⭐
- Cross-forest replication monitoring
- Trust relationship validation
- Consolidated reporting

### 16. **Auto-Healing with AI** ⭐⭐⭐⭐⭐
- ML-based issue prediction
- Automated remediation
- Learning from past actions

### 17. **Distributed Execution** ⭐⭐⭐
- Run across multiple management servers
- Load balancing
- Faster for large environments

---

## 📊 Feature Priority Matrix

| Feature | Value | Effort | ROI | Implement? |
|---------|-------|--------|-----|------------|
| Email Alerts | ⭐⭐⭐⭐⭐ | Low | **Very High** | ✅ Yes - Today |
| Slack/Teams | ⭐⭐⭐⭐⭐ | Low | **Very High** | ✅ Yes - Today |
| Health Score | ⭐⭐⭐⭐ | Med | **High** | ✅ Yes - This Week |
| Delta Mode | ⭐⭐⭐⭐ | Med | **High** | ✅ Yes - This Week |
| Scheduled Task | ⭐⭐⭐⭐ | Low | **High** | ✅ Yes - Today |
| Excel Export | ⭐⭐⭐⭐ | Med | **High** | ✅ Yes - This Week |
| Comparison Reports | ⭐⭐⭐⭐ | Low | **High** | ✅ Yes - This Week |
| Webhook Integration | ⭐⭐⭐⭐ | Low | **High** | ✅ Yes - Today |
| Real-Time Monitor | ⭐⭐⭐⭐⭐ | High | **Medium** | 🟡 v3.1 |
| Azure AD Connect | ⭐⭐⭐⭐⭐ | Med | **High** | 🟡 v3.1 |
| Interactive Mode | ⭐⭐⭐ | High | **Low** | 🟢 v3.2 |
| Predictive Analytics | ⭐⭐⭐⭐ | Very High | **Medium** | 🔵 v4.0 |
| Web Dashboard | ⭐⭐⭐⭐⭐ | Very High | **High** | 🔵 v4.0 |

---

## 🎯 Recommended Implementation Order

### Phase 1: Quick Wins (This Week)
1. ✅ Email Alerts (1 hour)
2. ✅ Slack/Teams Integration (1 hour)
3. ✅ Webhook Integration (30 min)
4. ✅ Scheduled Task Auto-Setup (1 hour)
5. ✅ Comparison Reports (1 hour)

### Phase 2: High Value (Next 2 Weeks)
6. ✅ Health Score & Trends (4 hours)
7. ✅ Delta Mode (4 hours)
8. ✅ Excel Export (2 hours)
9. ✅ Custom Repair Actions (3 hours)

### Phase 3: Strategic (v3.1 - Next Month)
10. 🟡 Real-Time Monitoring Mode
11. 🟡 Azure AD Connect Integration
12. 🟡 Multi-Site Parallel Execution

### Phase 4: Advanced (v4.0 - Q1 2026)
13. 🔵 Predictive Analytics
14. 🔵 Web Dashboard
15. 🔵 Auto-Healing with Policy Engine

---

## 💡 Which Features Should We Implement First?

**My Recommendation - Top 5 Quick Wins:**

1. **Email Alerts** - Essential for production monitoring
2. **Slack/Teams Integration** - Modern alerting
3. **Health Score** - Easy to understand trends
4. **Delta Mode** - Massive performance improvement for monitoring
5. **Scheduled Task** - Easy deployment

**Want me to implement any of these now?** Just let me know which ones!

---

## Document Information

**Prepared by:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer  
Organization: Enterprise IT Operations

**Version History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-28 | Adrian Johnson | Initial feature backlog with implementation examples |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

