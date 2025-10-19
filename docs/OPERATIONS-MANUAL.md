# Active Directory Replication Manager v3.0
## Operations Manual

**Document Version:** 1.0  
**Last Updated:** October 18, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Status:** Final  
**Classification:** Internal Use

---

## Document Information

| Property | Value |
|----------|-------|
| **Document ID** | ADRM-OPS-001 |
| **Version** | 1.0 |
| **Effective Date** | October 18, 2025 |
| **Review Cycle** | Quarterly |
| **Owner** | Adrian Johnson <adrian207@gmail.com> |
| **Approver** | IT Operations Manager |

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Daily Operations](#2-daily-operations)
3. [Standard Operating Procedures](#3-standard-operating-procedures)
4. [Monitoring & Alerting](#4-monitoring--alerting)
5. [Incident Response](#5-incident-response)
6. [Scheduled Maintenance](#6-scheduled-maintenance)
7. [Reporting](#7-reporting)
8. [Emergency Procedures](#8-emergency-procedures)
9. [Appendices](#9-appendices)

---

## 1. Introduction

### 1.1 Purpose

This Operations Manual provides comprehensive guidance for day-to-day operation, monitoring, and maintenance of the Active Directory Replication Manager (ADRM) v3.0. It is intended for IT operations staff, system administrators, and on-call engineers.

### 1.2 Audience

**Primary Audience:**
- System Administrators
- IT Operations Engineers
- On-Call Support Staff
- Service Desk Personnel (escalation reference)

**Secondary Audience:**
- IT Management (reporting sections)
- Security Operations (audit sections)
- Compliance Teams (audit trail sections)

### 1.3 Scope

This manual covers:
- Routine operational tasks
- Monitoring and alerting configuration
- Incident response procedures
- Scheduled maintenance activities
- Reporting and compliance requirements

**Out of Scope:**
- Detailed technical design (see DESIGN-DOCUMENT.md)
- Migration procedures (see MIGRATION-GUIDE.md)
- Development/customization guidelines

### 1.4 Related Documents

| Document | Purpose | Location |
|----------|---------|----------|
| **Design Document** | Technical architecture | DESIGN-DOCUMENT.md |
| **README** | Feature overview | README-ADReplicationManager.md |
| **Migration Guide** | v2.0 → v3.0 migration | MIGRATION-GUIDE.md |
| **API Reference** | Function specifications | API-REFERENCE.md |
| **Troubleshooting Guide** | Problem resolution | TROUBLESHOOTING-GUIDE.md |

---

## 2. Daily Operations

### 2.1 Routine Health Checks

#### 2.1.1 Morning Health Check (15 minutes)

**Objective:** Verify overnight replication health and address any degraded states.

**Procedure:**

1. **Review Overnight Audit Results**
   ```powershell
   # Navigate to report directory
   cd C:\Reports\ADReplication
   
   # Find most recent report
   $latest = Get-ChildItem -Filter "ADRepl-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
   
   # Review JSON summary
   $summary = Get-Content "$($latest.FullName)\summary.json" | ConvertFrom-Json
   
   # Display key metrics
   Write-Host "Health Check - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
   Write-Host "  Total DCs: $($summary.TotalDCs)"
   Write-Host "  Healthy: $($summary.HealthyDCs)" -ForegroundColor Green
   Write-Host "  Degraded: $($summary.DegradedDCs)" -ForegroundColor Yellow
   Write-Host "  Unreachable: $($summary.UnreachableDCs)" -ForegroundColor Red
   Write-Host "  Exit Code: $($summary.ExitCode)"
   ```

2. **Assess Status**
   
   | Exit Code | Status | Action Required |
   |-----------|--------|-----------------|
   | **0** | All Healthy | No action - log review complete |
   | **2** | Issues Detected | Review detailed logs (§2.1.2) |
   | **3** | DCs Unreachable | Investigate connectivity (§5.2) |
   | **4** | Script Error | Escalate to Tier 2 (§5.5) |

3. **Document Findings**
   ```powershell
   # Log health check result
   Add-Content -Path "C:\Reports\HealthCheckLog.txt" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm') - Exit Code: $($summary.ExitCode) - Healthy: $($summary.HealthyDCs)/$($summary.TotalDCs)"
   ```

#### 2.1.2 Detailed Issue Review

If exit code = 2 (issues detected):

```powershell
# Review identified issues
$issues = Import-Csv "$($latest.FullName)\IdentifiedIssues.csv"

# Group by severity
$highSeverity = $issues | Where-Object Severity -eq 'High'
$mediumSeverity = $issues | Where-Object Severity -eq 'Medium'

Write-Host "`nHigh Severity Issues: $($highSeverity.Count)" -ForegroundColor Red
$highSeverity | Format-Table DC, Category, Description -AutoSize

Write-Host "`nMedium Severity Issues: $($mediumSeverity.Count)" -ForegroundColor Yellow
$mediumSeverity | Format-Table DC, Category, Description -AutoSize
```

**Decision Matrix:**

| Condition | Action |
|-----------|--------|
| High severity issues detected | Create incident ticket, initiate repair (§3.2) |
| Only medium severity (stale replication) | Schedule repair during maintenance window |
| Recurring issues (same DC 3+ times) | Escalate for root cause analysis |

---

### 2.2 Log Review

#### 2.2.1 Execution Log Review

**Frequency:** Daily (post-morning health check)

**Procedure:**
```powershell
# Review execution log for errors/warnings
$log = Get-Content "$($latest.FullName)\execution.log"

# Filter for errors and warnings
$errors = $log | Where-Object { $_ -match '\[Error\]' }
$warnings = $log | Where-Object { $_ -match '\[Warning\]' }

if ($errors.Count -gt 0) {
    Write-Host "Errors detected: $($errors.Count)" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}

if ($warnings.Count -gt 0) {
    Write-Host "Warnings detected: $($warnings.Count)" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
}
```

**Action Items:**
- **Errors:** Investigate immediately, create ticket if unresolved
- **Warnings:** Document, monitor for recurrence
- **Patterns:** 3+ similar warnings → investigate root cause

#### 2.2.2 Transcript Review (If Audit Trail Enabled)

```powershell
# Review transcript for repair operations
$transcript = Get-ChildItem "$($latest.FullName)\transcript-*.log" | Get-Content

# Search for ShouldProcess confirmations
$confirmations = $transcript | Select-String "Performing the operation"

# Verify all repairs were authorized
$confirmations | ForEach-Object { Write-Host $_ }
```

---

### 2.3 Metric Collection

#### 2.3.1 Daily Metrics Dashboard

```powershell
# Collect last 7 days of metrics
$last7Days = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
    Sort-Object LastWriteTime

$metrics = $last7Days | ForEach-Object {
    $summary = Get-Content "$($_.FullName)\summary.json" | ConvertFrom-Json
    [PSCustomObject]@{
        Date = $_.LastWriteTime.ToString('yyyy-MM-dd')
        TotalDCs = $summary.TotalDCs
        HealthyDCs = $summary.HealthyDCs
        DegradedDCs = $summary.DegradedDCs
        UnreachableDCs = $summary.UnreachableDCs
        HealthPercentage = [math]::Round(($summary.HealthyDCs / $summary.TotalDCs) * 100, 1)
        ExitCode = $summary.ExitCode
    }
}

# Display trend
$metrics | Format-Table -AutoSize

# Calculate average health
$avgHealth = ($metrics | Measure-Object -Property HealthPercentage -Average).Average
Write-Host "`nAverage Health (7 days): $([math]::Round($avgHealth, 1))%" -ForegroundColor $(if ($avgHealth -ge 95) { 'Green' } else { 'Yellow' })
```

**Target Metrics:**
- **Health Percentage:** ≥ 95% (healthy DCs / total DCs)
- **Unreachable DCs:** 0
- **Recurring Issues:** 0 (same DC/partner for 3+ days)

---

## 3. Standard Operating Procedures

### 3.1 SOP-001: Scheduled Audit Execution

**Objective:** Execute routine AD replication health audit.

**Frequency:** Daily at 02:00 AM (via scheduled task)

**Prerequisites:**
- Scheduled task configured (see §6.2)
- Service account has Domain Admin rights
- Output directory exists and is writable

**Procedure:**

1. **Verify Scheduled Task Status**
   ```powershell
   Get-ScheduledTask -TaskName "AD Replication Daily Audit" | Format-List State, LastRunTime, LastTaskResult
   ```

2. **Manual Execution (If Needed)**
   ```powershell
   # Execute audit for all DCs in HQ site
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode Audit `
       -Scope Site:HQ `
       -OutputPath C:\Reports\ADReplication `
       -Verbose
   ```

3. **Validation**
   ```powershell
   # Check exit code
   $LASTEXITCODE
   
   # Verify reports generated
   Test-Path C:\Reports\ADReplication\ADRepl-*\summary.json
   ```

4. **Documentation**
   - Log execution time and exit code
   - Note any anomalies or failures
   - Update runbook if procedure changes

**Expected Duration:** 2-5 minutes (depends on DC count)

**Success Criteria:**
- Exit code = 0 or 2
- All CSV and JSON files generated
- No script errors in execution log

**Rollback:** Not applicable (read-only operation)

---

### 3.2 SOP-002: Interactive Repair Operation

**Objective:** Resolve detected replication issues through guided repair.

**Frequency:** As needed (triggered by health check alerts)

**Prerequisites:**
- Replication issues identified (exit code 2)
- Change ticket approved (if in change freeze)
- Backup/snapshot of AD (recommended)

**Procedure:**

1. **Pre-Repair Assessment**
   ```powershell
   # Review issues
   $issues = Import-Csv "C:\Reports\ADReplication\ADRepl-latest\IdentifiedIssues.csv"
   
   # Display summary
   $issues | Group-Object Category | Select-Object Name, Count
   
   # Identify affected DCs
   $affectedDCs = $issues | Select-Object -ExpandProperty DC -Unique
   Write-Host "Affected DCs: $($affectedDCs -join ', ')"
   ```

2. **Create Change Record**
   ```
   Change Ticket: CHG-20251018-001
   Summary: AD Replication Repair - Issues on DC01, DC03
   Risk: Low (automated repair with rollback capability)
   Duration: 10-15 minutes
   Rollback: Automatic (replication will reconverge)
   ```

3. **Execute Repair with Preview**
   ```powershell
   # Step 3a: Preview changes (WhatIf)
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode Repair `
       -DomainControllers $affectedDCs `
       -WhatIf
   
   # Step 3b: Review preview output, then execute
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode Repair `
       -DomainControllers $affectedDCs `
       -AuditTrail
   
   # Note: Script will prompt for confirmation unless -AutoRepair is specified
   ```

4. **Post-Repair Verification**
   ```powershell
   # Wait for replication convergence (default: 120 seconds)
   Start-Sleep -Seconds 120
   
   # Re-run audit
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode Audit `
       -DomainControllers $affectedDCs
   
   # Check exit code
   if ($LASTEXITCODE -eq 0) {
       Write-Host "Repair successful - all DCs healthy" -ForegroundColor Green
   } elseif ($LASTEXITCODE -eq 2) {
       Write-Host "Issues remain - escalate for investigation" -ForegroundColor Yellow
   }
   ```

5. **Documentation**
   ```powershell
   # Update change ticket with results
   $summary = Get-Content "C:\Reports\ADReplication\ADRepl-latest\summary.json" | ConvertFrom-Json
   
   $changeNotes = @"
   Repair completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm')
   DCs processed: $($summary.TotalDCs)
   Actions performed: $($summary.ActionsPerformed)
   Final status: $($summary.HealthyDCs) healthy, $($summary.DegradedDCs) degraded
   Exit code: $($summary.ExitCode)
   Transcript: C:\Reports\ADReplication\ADRepl-latest\transcript-*.log
   "@
   
   # Add to change ticket
   Add-Content -Path "C:\Changes\CHG-20251018-001.txt" -Value $changeNotes
   ```

**Expected Duration:** 10-15 minutes

**Success Criteria:**
- Exit code = 0 (all issues resolved)
- Post-repair audit shows healthy status
- No new issues introduced

**Rollback:**
- AD replication is self-correcting
- If issues persist, DCs will reconverge to last known good state
- For critical issues, restore from AD backup (escalate to Tier 3)

---

### 3.3 SOP-003: Emergency Repair (High Severity)

**Objective:** Rapidly resolve critical replication failures impacting production.

**Trigger:** 
- Multiple DCs unreachable (exit code 3)
- >50% of DCs degraded
- Replication stopped for >2 hours

**Prerequisites:**
- Incident ticket created (SEV-1 or SEV-2)
- Change approval bypassed (emergency change)
- Incident commander assigned

**Procedure:**

1. **Immediate Assessment**
   ```powershell
   # Quick health check across all DCs
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode Audit `
       -Scope Forest `
       -Confirm:$false
   
   # Capture critical DCs
   $summary = Get-Content "C:\Reports\ADReplication\ADRepl-latest\summary.json" | ConvertFrom-Json
   
   if ($summary.UnreachableDCs -gt 0 -or $summary.DegradedDCs -gt ($summary.TotalDCs * 0.5)) {
       Write-Host "CRITICAL: $($summary.UnreachableDCs) unreachable, $($summary.DegradedDCs) degraded" -ForegroundColor Red
   }
   ```

2. **Escalation Decision Tree**
   ```
   IF UnreachableDCs > 0 THEN
       → Check DC availability (ping, RDP)
       → If DC down, engage infrastructure team
       → If DC up but unreachable, check firewall/network
   
   IF DegradedDCs > 50% THEN
       → Check for common error pattern (Review §9.2)
       → Execute forest-wide repair with approval
   
   IF specific error code pattern THEN
       → Apply targeted fix (see TROUBLESHOOTING-GUIDE.md)
   ```

3. **Execute Emergency Repair**
   ```powershell
   # Forest-wide repair (requires explicit confirmation)
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode AuditRepairVerify `
       -Scope Forest `
       -AutoRepair `
       -AuditTrail `
       -Throttle 16
   ```

4. **Continuous Monitoring**
   ```powershell
   # Monitor repair progress every 5 minutes
   for ($i = 1; $i -le 6; $i++) {
       Start-Sleep -Seconds 300
       
       C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
           -Mode Audit `
           -Scope Forest `
           -Confirm:$false
       
       $summary = Get-Content "C:\Reports\ADReplication\ADRepl-latest\summary.json" | ConvertFrom-Json
       Write-Host "[$i/6] Healthy: $($summary.HealthyDCs)/$($summary.TotalDCs)" -ForegroundColor Cyan
       
       if ($summary.ExitCode -eq 0) {
           Write-Host "Recovery complete" -ForegroundColor Green
           break
       }
   }
   ```

5. **Incident Documentation**
   - Root cause analysis (post-incident)
   - Timeline of events
   - Actions taken and outcomes
   - Lessons learned
   - Preventive measures

**Expected Duration:** 30-60 minutes

**Escalation Path:**
- Tier 1 → Tier 2 (if no improvement after 15 minutes)
- Tier 2 → Tier 3 (if no improvement after 30 minutes)
- Tier 3 → Vendor (Microsoft) (if systemic AD issue)

---

## 4. Monitoring & Alerting

### 4.1 Monitoring Configuration

#### 4.1.1 SIEM Integration

```powershell
# Example: Forward summary to Splunk
$summary = Get-Content "C:\Reports\ADReplication\ADRepl-latest\summary.json" | ConvertFrom-Json

$splunkEvent = @{
    sourcetype = "adrm:health"
    source = "ADReplicationManager"
    time = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    event = $summary
} | ConvertTo-Json -Depth 10

# Send to Splunk HTTP Event Collector
Invoke-RestMethod -Uri "https://splunk.company.com:8088/services/collector" `
    -Method Post `
    -Headers @{"Authorization" = "Splunk $env:SPLUNK_HEC_TOKEN"} `
    -Body $splunkEvent
```

#### 4.1.2 Dashboard Metrics

**Key Performance Indicators (KPIs):**

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| **Health Percentage** | ≥ 98% | < 95% | < 90% |
| **Unreachable DCs** | 0 | 1 | ≥ 2 |
| **Avg Execution Time** | < 2 min | 5 min | 10 min |
| **Failed Repairs** | 0 | 1 | ≥ 3 |
| **Script Errors (exit 4)** | 0 | 1 | ≥ 2 |

**Dashboard Queries (Splunk example):**
```spl
sourcetype="adrm:health" 
| stats latest(HealthyDCs) as Healthy, latest(TotalDCs) as Total, latest(ExitCode) as ExitCode by _time
| eval HealthPct = round((Healthy/Total)*100, 1)
| timechart span=1d avg(HealthPct) as "Health %"
```

---

### 4.2 Alerting Rules

#### 4.2.1 Critical Alerts (Page On-Call)

| Alert ID | Condition | Threshold | Action |
|----------|-----------|-----------|--------|
| **ADRM-001** | Exit code = 3 | 1 occurrence | Page on-call, initiate §5.2 |
| **ADRM-002** | Exit code = 4 | 1 occurrence | Page on-call, initiate §5.5 |
| **ADRM-003** | Health % < 90% | 1 occurrence | Page on-call, initiate §3.3 |
| **ADRM-004** | > 5 DCs degraded | 1 occurrence | Page on-call, review logs |

**Alert Template:**
```
Subject: [CRITICAL] AD Replication Issue - Exit Code 3
Body:
AD Replication Manager detected critical issues:
- Exit Code: 3 (DCs Unreachable)
- Unreachable DCs: 2
- Total DCs: 12
- Time: 2025-10-18 14:23:15

Affected DCs: DC03.domain.com, DC07.domain.com

Action Required: Investigate connectivity immediately (SOP-003)
Report Location: C:\Reports\ADReplication\ADRepl-20251018-142315
```

#### 4.2.2 Warning Alerts (Email)

| Alert ID | Condition | Threshold | Action |
|----------|-----------|-----------|--------|
| **ADRM-W01** | Exit code = 2 | 2 consecutive | Email ops team |
| **ADRM-W02** | Health % 90-95% | 1 occurrence | Email ops team |
| **ADRM-W03** | Same DC degraded | 3 consecutive days | Email ops team, investigate |
| **ADRM-W04** | Execution time > 5 min | 1 occurrence | Email ops team, check performance |

---

### 4.3 Health Checks

#### 4.3.1 Script Health Check

**Frequency:** Weekly

```powershell
# Verify script integrity
$scriptPath = "C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1"

# Check file exists
if (-not (Test-Path $scriptPath)) {
    Write-Error "Script missing: $scriptPath"
}

# Check file hash (compare to known good)
$currentHash = Get-FileHash $scriptPath -Algorithm SHA256
$expectedHash = "ABC123..."  # From deployment manifest

if ($currentHash.Hash -ne $expectedHash) {
    Write-Warning "Script hash mismatch - possible modification"
}

# Check scheduled task
$task = Get-ScheduledTask -TaskName "AD Replication Daily Audit" -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Error "Scheduled task not found"
} elseif ($task.State -ne 'Ready') {
    Write-Warning "Scheduled task in unexpected state: $($task.State)"
}
```

#### 4.3.2 Service Account Health

```powershell
# Verify service account used by scheduled task
$taskPrincipal = (Get-ScheduledTask -TaskName "AD Replication Daily Audit").Principal

# Check account exists
$account = Get-ADUser -Identity $taskPrincipal.UserId -Properties PasswordLastSet, PasswordNeverExpires

# Alerts
if ($account.PasswordNeverExpires -eq $false -and (Get-Date).AddDays(30) -gt $account.PasswordLastSet.AddDays(90)) {
    Write-Warning "Service account password expiring soon"
}

# Check Domain Admin membership
$isDomainAdmin = (Get-ADUser -Identity $taskPrincipal.UserId -Properties MemberOf).MemberOf -match 'Domain Admins'
if (-not $isDomainAdmin) {
    Write-Error "Service account missing Domain Admin rights"
}
```

---

## 5. Incident Response

### 5.1 Incident Classification

| Severity | Definition | Response Time | Escalation |
|----------|------------|---------------|------------|
| **SEV-1** | Complete AD replication failure | Immediate | On-call paged |
| **SEV-2** | >50% DCs degraded or unreachable | 30 minutes | Manager notified |
| **SEV-3** | Isolated DC issues | 4 hours | Standard ticket |
| **SEV-4** | Performance degradation | Next business day | Standard ticket |

---

### 5.2 IR-001: DC Unreachable (Exit Code 3)

**Incident Type:** Connectivity failure

**Response Procedure:**

1. **Triage (0-5 minutes)**
   ```powershell
   # Identify unreachable DCs
   $issues = Import-Csv "C:\Reports\ADReplication\ADRepl-latest\IdentifiedIssues.csv" | 
       Where-Object Category -eq 'Connectivity'
   
   $unreachableDCs = $issues | Select-Object -ExpandProperty DC -Unique
   
   # Quick connectivity check
   foreach ($dc in $unreachableDCs) {
       $ping = Test-Connection -ComputerName $dc -Count 2 -Quiet
       $rdp = Test-NetConnection -ComputerName $dc -Port 3389 -InformationLevel Quiet
       
       Write-Host "$dc - Ping: $ping, RDP: $rdp"
   }
   ```

2. **Root Cause Identification (5-15 minutes)**
   
   | Symptom | Likely Cause | Action |
   |---------|--------------|--------|
   | Ping fails, RDP fails | DC offline | Check virtualization platform, console access |
   | Ping succeeds, RDP fails | Firewall issue | Check Windows Firewall, network ACLs |
   | Ping succeeds, RDP succeeds, AD query fails | Service issue | Check AD DS service status, Event Logs |

3. **Resolution (15-30 minutes)**
   ```powershell
   # If AD DS service stopped
   Invoke-Command -ComputerName $dc -ScriptBlock {
       Get-Service -Name NTDS | Start-Service
       Get-EventLog -LogName "Directory Service" -Newest 20
   }
   
   # Verify resolution
   Start-Sleep -Seconds 60
   C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
       -Mode Audit `
       -DomainControllers $unreachableDCs
   ```

4. **Post-Incident**
   - Document root cause
   - Update monitoring (if new failure mode)
   - Preventive measures (if applicable)

---

### 5.3 IR-002: Persistent Replication Failures (Exit Code 2)

**Incident Type:** Replication degradation

**Response Procedure:**

1. **Pattern Analysis**
   ```powershell
   # Analyze failure patterns over last 7 days
   $last7Days = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
       Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) }
   
   $patterns = $last7Days | ForEach-Object {
       $issues = Import-Csv "$($_.FullName)\IdentifiedIssues.csv"
       $issues | Select-Object DC, Partner, ErrorCode, @{N='Date';E={$_.Name}}
   }
   
   # Find recurring issues
   $recurring = $patterns | Group-Object DC, Partner, ErrorCode | 
       Where-Object Count -ge 3 | 
       Sort-Object Count -Descending
   
   $recurring | Format-Table Count, @{N='DC';E={$_.Group[0].DC}}, @{N='Partner';E={$_.Group[0].Partner}}, @{N='Error';E={$_.Group[0].ErrorCode}}
   ```

2. **Error Code Investigation**
   
   See TROUBLESHOOTING-GUIDE.md for detailed error code resolution procedures.

3. **Targeted Repair**
   ```powershell
   # Apply targeted fix based on error pattern
   # Example: Kerberos authentication issues (error 8453)
   
   if ($errorCode -eq 8453) {
       # Reset secure channel
       Invoke-Command -ComputerName $dc -ScriptBlock {
           nltest /sc_reset:$env:USERDOMAIN
       }
   }
   ```

---

### 5.4 IR-003: Performance Degradation

**Incident Type:** Script execution slow

**Response Procedure:**

1. **Baseline Comparison**
   ```powershell
   # Compare current execution time to baseline
   $recent = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
       Sort-Object LastWriteTime -Descending | 
       Select-Object -First 10
   
   $execTimes = $recent | ForEach-Object {
       $summary = Get-Content "$($_.FullName)\summary.json" | ConvertFrom-Json
       [PSCustomObject]@{
           Date = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
           ExecutionTime = $summary.ExecutionTime
       }
   }
   
   $execTimes | Format-Table -AutoSize
   $avgTime = ($execTimes | Measure-Object -Property ExecutionTime -Average).Average
   Write-Host "Average execution time: $avgTime" -ForegroundColor Cyan
   ```

2. **Performance Tuning**
   - If PS5.1: Consider upgrading to PS7 for parallel processing
   - Adjust `-Throttle` parameter (reduce if RPC limits hit)
   - Increase `-Timeout` if WAN latency high
   - Process site-by-site instead of forest-wide

---

### 5.5 IR-004: Script Execution Failure (Exit Code 4)

**Incident Type:** Fatal error

**Response Procedure:**

1. **Log Analysis**
   ```powershell
   # Review execution log for error details
   $log = Get-Content "C:\Reports\ADReplication\ADRepl-latest\execution.log"
   $errors = $log | Where-Object { $_ -match '\[Error\]' }
   
   Write-Host "Errors detected:" -ForegroundColor Red
   $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
   ```

2. **Common Failures & Resolution**
   
   | Error Message | Cause | Resolution |
   |---------------|-------|------------|
   | "Failed to load ActiveDirectory module" | RSAT not installed | Install RSAT-AD-PowerShell |
   | "Access is denied" | Insufficient permissions | Verify Domain Admin membership |
   | "Cannot bind argument to parameter" | Parameter validation failure | Check parameter syntax |
   | "The term 'repadmin' is not recognized" | RSAT not in PATH | Add to PATH or install RSAT |

3. **Escalation**
   - If unresolved after 30 minutes, escalate to script author
   - Provide: execution log, transcript (if available), environment details

---

## 6. Scheduled Maintenance

### 6.1 Monthly Maintenance Tasks

#### 6.1.1 Report Archive & Cleanup

**Frequency:** Monthly (1st of month)

```powershell
# Archive reports older than 90 days
$archivePath = "\\FileServer\Archives\ADReplication"
$cutoffDate = (Get-Date).AddDays(-90)

$oldReports = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
    Where-Object { $_.LastWriteTime -lt $cutoffDate }

foreach ($report in $oldReports) {
    # Compress
    $zipPath = Join-Path $archivePath "$($report.Name).zip"
    Compress-Archive -Path $report.FullName -DestinationPath $zipPath
    
    # Verify and delete original
    if (Test-Path $zipPath) {
        Remove-Item $report.FullName -Recurse -Force
    }
}

Write-Host "Archived $($oldReports.Count) reports"
```

#### 6.1.2 Metrics Review

```powershell
# Generate monthly metrics report
$lastMonth = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMonths(-1) }

$monthlyStats = $lastMonth | ForEach-Object {
    $summary = Get-Content "$($_.FullName)\summary.json" | ConvertFrom-Json
    [PSCustomObject]@{
        TotalDCs = $summary.TotalDCs
        HealthyDCs = $summary.HealthyDCs
        IssuesFound = $summary.IssuesFound
        ActionsPerformed = $summary.ActionsPerformed
        ExitCode = $summary.ExitCode
    }
}

$report = @{
    TotalRuns = $monthlyStats.Count
    AvgHealthyDCs = ($monthlyStats | Measure-Object -Property HealthyDCs -Average).Average
    TotalIssues = ($monthlyStats | Measure-Object -Property IssuesFound -Sum).Sum
    TotalActions = ($monthlyStats | Measure-Object -Property ActionsPerformed -Sum).Sum
    HealthPercentage = [math]::Round((($monthlyStats | Measure-Object -Property HealthyDCs -Average).Average / ($monthlyStats[0].TotalDCs)) * 100, 1)
}

# Email report to management
$report | ConvertTo-Json | Out-File "C:\Reports\MonthlyReport-$(Get-Date -Format 'yyyy-MM').json"
```

---

### 6.2 Quarterly Maintenance Tasks

#### 6.2.1 Script Update Check

```powershell
# Check for updates (if version control integrated)
$currentVersion = "3.0.0"  # From script metadata
$latestVersion = Invoke-RestMethod -Uri "https://github.com/yourorg/adrm/releases/latest"

if ($latestVersion.tag_name -gt $currentVersion) {
    Write-Host "Update available: $($latestVersion.tag_name)" -ForegroundColor Yellow
    Write-Host "Release notes: $($latestVersion.body)"
}
```

#### 6.2.2 Permissions Audit

```powershell
# Verify service account permissions haven't changed
$serviceAccount = (Get-ScheduledTask -TaskName "AD Replication Daily Audit").Principal.UserId

$permissions = @{
    DomainAdmin = (Get-ADUser -Identity $serviceAccount -Properties MemberOf).MemberOf -match 'Domain Admins'
    OutputPath = Test-Path C:\Reports\ADReplication -PathType Container
    ScriptPath = Test-Path C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1
}

$permissions | Format-Table -AutoSize

# Alert if any false
if ($permissions.Values -contains $false) {
    Write-Error "Permissions audit failed - remediate immediately"
}
```

---

## 7. Reporting

### 7.1 Daily Reports

#### 7.1.1 Health Status Email

**Recipients:** IT Operations Team  
**Frequency:** Daily at 08:00 AM  
**Content:** Previous day's health summary

```powershell
# Generate daily email
$summary = Get-Content "C:\Reports\ADReplication\ADRepl-latest\summary.json" | ConvertFrom-Json

$emailBody = @"
<html>
<body>
<h2>AD Replication Health - $(Get-Date -Format 'yyyy-MM-dd')</h2>

<table border="1" cellpadding="5">
<tr><td><b>Total DCs:</b></td><td>$($summary.TotalDCs)</td></tr>
<tr><td><b>Healthy:</b></td><td style="color:green">$($summary.HealthyDCs)</td></tr>
<tr><td><b>Degraded:</b></td><td style="color:orange">$($summary.DegradedDCs)</td></tr>
<tr><td><b>Unreachable:</b></td><td style="color:red">$($summary.UnreachableDCs)</td></tr>
<tr><td><b>Issues Found:</b></td><td>$($summary.IssuesFound)</td></tr>
<tr><td><b>Actions Performed:</b></td><td>$($summary.ActionsPerformed)</td></tr>
<tr><td><b>Exit Code:</b></td><td>$($summary.ExitCode)</td></tr>
</table>

<p>Report Location: C:\Reports\ADReplication\ADRepl-latest</p>
</body>
</html>
"@

Send-MailMessage `
    -To "itops@company.com" `
    -From "adrm@company.com" `
    -Subject "AD Replication Health - $(Get-Date -Format 'yyyy-MM-dd')" `
    -Body $emailBody `
    -BodyAsHtml `
    -SmtpServer "smtp.company.com"
```

---

### 7.2 Weekly Reports

#### 7.2.1 Trend Analysis

```powershell
# Generate weekly trend report
$last7Days = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
    Sort-Object LastWriteTime

$trend = $last7Days | ForEach-Object {
    $summary = Get-Content "$($_.FullName)\summary.json" | ConvertFrom-Json
    [PSCustomObject]@{
        Date = $_.LastWriteTime.ToString('yyyy-MM-dd')
        HealthPercentage = [math]::Round(($summary.HealthyDCs / $summary.TotalDCs) * 100, 1)
        IssuesFound = $summary.IssuesFound
        ActionsPerformed = $summary.ActionsPerformed
    }
}

# Export to CSV for management review
$trend | Export-Csv "C:\Reports\WeeklyTrend-$(Get-Date -Format 'yyyy-MM-dd').csv" -NoTypeInformation
```

---

### 7.3 Monthly Reports

#### 7.3.1 Executive Summary

**Recipients:** IT Management  
**Frequency:** Monthly (5th of month)

**Content:**
- Overall health trend
- Top 5 issues encountered
- Repair success rate
- Performance metrics
- Recommendations

---

## 8. Emergency Procedures

### 8.1 Emergency Contacts

| Role | Name | Phone | Email |
|------|------|-------|-------|
| **Script Author** | Adrian Johnson | +1-555-0123 | adrian207@gmail.com |
| **IT Operations Manager** | TBD | TBD | TBD |
| **On-Call Engineer** | Rotation | TBD | oncall@company.com |
| **AD Architect** | TBD | TBD | TBD |

---

### 8.2 Emergency Decision Matrix

| Situation | Immediate Action | Approval Required | Escalation |
|-----------|------------------|-------------------|------------|
| **Single DC degraded** | Execute repair per SOP-002 | Change ticket | No |
| **Multiple DCs degraded** | Execute repair per SOP-002 | Manager approval | Manager notified |
| **>50% DCs degraded** | Initiate IR-003 | CTO approval | Incident commander assigned |
| **Complete replication failure** | Initiate major incident | CTO approval | Microsoft support engaged |

---

### 8.3 Rollback Procedures

**Scenario:** Repair operation caused additional issues

**Procedure:**
1. AD replication is self-correcting; no manual rollback needed
2. DCs will reconverge to last known good state within 15-60 minutes
3. Monitor replication status:
   ```powershell
   # Continuous monitoring
   while ($true) {
       C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -Confirm:$false
       Start-Sleep -Seconds 300
   }
   ```
4. If issues persist after 2 hours, escalate to AD architect
5. Last resort: Restore from AD backup (requires CTO approval)

---

## 9. Appendices

### 9.1 Appendix A: Scheduled Task Configuration

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Daily AD Replication Health Audit</Description>
    <Author>Adrian Johnson</Author>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2025-10-18T02:00:00</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal>
      <UserId>DOMAIN\svc_adaudit</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
  </Settings>
  <Actions>
    <Exec>
      <Command>PowerShell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1" -Mode Audit -Scope Site:HQ -OutputPath "C:\Reports\ADReplication"</Arguments>
    </Exec>
  </Actions>
</Task>
```

---

### 9.2 Appendix B: Common Error Patterns

| Error Code | Pattern | Root Cause | Resolution |
|------------|---------|------------|------------|
| **1722** | All DCs | Network outage | Check network infrastructure |
| **1722** | Single DC | DC firewall | Check Windows Firewall settings |
| **8453** | All DCs to specific DC | Kerberos issue on target | Reset secure channel, check time sync |
| **8524** | Multiple DCs | DNS failure | Check DNS servers, SRV records |
| **5** | Specific DC pair | Permission issue | Check replication permissions |

---

### 9.3 Appendix C: Compliance Checklist

**Monthly Compliance Review:**

- [ ] All scheduled tasks executed successfully
- [ ] No unauthorized script modifications (hash check)
- [ ] Service account permissions current
- [ ] Audit trail logs archived
- [ ] No SEV-1 incidents related to replication
- [ ] All incidents documented and resolved
- [ ] Metrics within target ranges
- [ ] Reports available for audit

**Quarterly Compliance Review:**

- [ ] Permissions audit completed
- [ ] Documentation updated
- [ ] Training materials current
- [ ] Disaster recovery plan tested
- [ ] Script version current
- [ ] Security review completed

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2025-10-10 | Adrian Johnson | Initial draft |
| 0.5 | 2025-10-15 | Adrian Johnson | Added SOPs and incident procedures |
| 1.0 | 2025-10-18 | Adrian Johnson | Final release version |

---

**END OF OPERATIONS MANUAL**

---

**Author:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer

**Document Control:**
- **Next Review:** 2026-01-18 (Quarterly)
- **Owner:** IT Operations Manager
- **Distribution:** All IT Operations Staff, On-Call Engineers

