# Auto-Healing Guide

**Version:** 1.0  
**Last Updated:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** Internal Use

---

## 📋 Table of Contents

- [Overview](#overview)
- [Healing Policies](#healing-policies)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Safety Controls](#safety-controls)
- [Monitoring & Statistics](#monitoring--statistics)
- [Rollback Operations](#rollback-operations)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Auto-Healing is a policy-based automated remediation system introduced in v3.2.0. It intelligently evaluates and repairs AD replication issues without human intervention, while maintaining multiple layers of safety controls.

### Key Capabilities

- **Policy-Based Decision Making**: Conservative, Moderate, or Aggressive policies
- **Intelligent Eligibility Checks**: Category, severity, cooldown evaluation
- **Automatic Rollback**: Failed actions can be automatically rolled back
- **Complete Audit Trail**: CSV and JSON-based history tracking
- **Statistics & Reporting**: Success rates, trends, and top DCs

---

## Healing Policies

### Conservative Policy (Recommended for Production)

**Risk Level:** Low  
**Use Case:** Production environments requiring maximum safety

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -AutoHeal `
    -HealingPolicy Conservative `
    -EnableRollback
```

**What It Heals:**
- ✅ Stale replication (>24h without sync)
- ❌ Replication failures (requires manual approval)
- ❌ Connectivity issues (requires manual approval)

**Configuration:**
- Allowed Severities: Low, Medium
- Cooldown Period: 30 minutes
- Max Concurrent Actions: 3
- Rollback on Failure: Enabled (recommended)

---

### Moderate Policy (Balanced Automation)

**Risk Level:** Medium  
**Use Case:** Environments with skilled AD team and good monitoring

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode AuditRepairVerify `
    -AutoHeal `
    -HealingPolicy Moderate `
    -MaxHealingActions 5 `
    -EnableRollback
```

**What It Heals:**
- ✅ Stale replication
- ✅ Replication failures
- ❌ Connectivity issues (requires manual approval)

**Configuration:**
- Allowed Severities: Low, Medium, High
- Cooldown Period: 15 minutes
- Max Concurrent Actions: 5
- Rollback on Failure: Enabled (recommended)

---

### Aggressive Policy (Maximum Automation)

**Risk Level:** High  
**Use Case:** Test/dev environments or with extensive monitoring

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode AuditRepairVerify `
    -AutoHeal `
    -HealingPolicy Aggressive `
    -MaxHealingActions 10 `
    -EnableRollback `
    -FastMode
```

**What It Heals:**
- ✅ Stale replication
- ✅ Replication failures
- ✅ Connectivity issues
- ✅ All detected problems

**Configuration:**
- Allowed Severities: All (Low, Medium, High, Critical)
- Cooldown Period: 5 minutes
- Max Concurrent Actions: 10
- Rollback on Failure: Enabled (recommended)

---

## Quick Start

### Step 1: Test with WhatIf

Always test first with `-WhatIf`:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -AutoHeal `
    -HealingPolicy Conservative `
    -WhatIf `
    -Verbose
```

### Step 2: Run with Audit Trail

Enable full logging for first production run:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -Scope Site:Production `
    -AutoHeal `
    -HealingPolicy Conservative `
    -EnableRollback `
    -AuditTrail `
    -EnableHealthScore
```

### Step 3: Schedule for Automation

Create daily automated task:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -CreateScheduledTask `
    -TaskSchedule Daily `
    -TaskTime "02:00" `
    -Mode AuditRepairVerify `
    -AutoHeal `
    -HealingPolicy Conservative `
    -SlackWebhook "https://hooks.slack.com/..." `
    -EmailTo "ad-admins@company.com"
```

---

## Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-AutoHeal` | Switch | `$false` | Enable auto-healing |
| `-HealingPolicy` | String | `Conservative` | Policy name |
| `-MaxHealingActions` | Int | `10` | Max actions per run (1-100) |
| `-EnableRollback` | Switch | `$false` | Auto-rollback failures |
| `-HealingHistoryPath` | String | `$env:ProgramData\...` | History directory |
| `-HealingCooldownMinutes` | Int | `15` | Cooldown period (1-60) |

### Custom Cooldown

Override policy cooldown:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -HealingPolicy Moderate `
    -HealingCooldownMinutes 30  # Override default 15 minutes
```

### Action Limits

Limit actions even further:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -HealingPolicy Aggressive `
    -MaxHealingActions 3  # Only 3 actions even though policy allows 10
```

---

## Safety Controls

### 1. Cooldown Periods

Prevents healing loops by blocking repeated attempts on same issue:

```
Issue detected → Healing attempt → Cooldown starts → Cannot heal same issue until cooldown expires
```

**Default Cooldowns:**
- Conservative: 30 minutes
- Moderate: 15 minutes
- Aggressive: 5 minutes

### 2. Eligibility Checks

Every issue must pass 5 checks:

1. **Category Check**: Is category allowed by policy?
2. **Severity Check**: Is severity allowed by policy?
3. **Manual Approval Check**: Does policy require manual approval?
4. **Cooldown Check**: Has cooldown period expired?
5. **Actionability Check**: Is issue marked as actionable?

### 3. Action Limits

Two layers of limits:

- **Policy Limit**: Built into policy definition
- **Parameter Limit**: `-MaxHealingActions` parameter

The **more restrictive** limit wins.

### 4. Rollback Capability

If enabled with `-EnableRollback`:

- Failed actions trigger automatic rollback
- Fresh replication sync restores pre-action state
- Rollback recorded in `rollback-history.csv`

---

## Monitoring & Statistics

### View Healing History

```powershell
# View all healing actions
$history = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\healing-history.csv"

# Last 24 hours
$recent = $history | Where-Object {
    ([DateTime]$_.Timestamp) -gt (Get-Date).AddHours(-24)
}

$recent | Format-Table Timestamp, DC, Category, Success, Message
```

### Calculate Success Rate

```powershell
$stats = Get-HealingStatistics `
    -HistoryPath "C:\ProgramData\ADReplicationManager\Healing" `
    -DaysBack 7

Write-Host "7-Day Healing Statistics:" -ForegroundColor Cyan
Write-Host "  Total Actions: $($stats.TotalActions)"
Write-Host "  Successful: $($stats.SuccessfulActions)"
Write-Host "  Failed: $($stats.FailedActions)"
Write-Host "  Success Rate: $($stats.SuccessRate)%"
Write-Host ""
Write-Host "Categories Healed:"
$stats.CategoriesHealed.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value)"
}
```

### Top DCs Requiring Healing

```powershell
$stats = Get-HealingStatistics -HistoryPath "C:\ProgramData\ADReplicationManager\Healing"

Write-Host "Top 5 DCs with Most Healing Actions:" -ForegroundColor Yellow
$stats.TopDCs.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value) actions"
}
```

---

## Rollback Operations

### Automatic Rollback

Enable with `-EnableRollback`:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -EnableRollback  # Automatically rollback failures
```

### Manual Rollback

Rollback specific action by ID:

```powershell
# View recent actions
$history = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\healing-history.csv" |
    Sort-Object Timestamp -Descending | Select-Object -First 10

# Rollback specific action (use ActionID from history)
Invoke-HealingRollback `
    -ActionID "abc123de" `
    -HistoryPath "C:\ProgramData\ADReplicationManager\Healing" `
    -Reason "DC experiencing issues after healing"
```

### View Rollback History

```powershell
$rollbacks = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\rollback-history.csv"

$rollbacks | Format-Table Timestamp, ActionID, DC, RollbackSuccess, Reason
```

---

## Best Practices

### 1. Start Conservative

Always start with Conservative policy in production:

```powershell
# First production deployment
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -HealingPolicy Conservative `
    -EnableRollback `
    -AuditTrail
```

### 2. Monitor for One Week

Run Conservative policy manually for one week, review statistics:

```powershell
$stats = Get-HealingStatistics -DaysBack 7

if ($stats.SuccessRate -gt 95) {
    Write-Host "✅ Ready to consider Moderate policy" -ForegroundColor Green
}
```

### 3. Enable All Notifications

Get visibility into auto-healing actions:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -HealingPolicy Conservative `
    -SlackWebhook "https://..." `
    -EmailTo "ad-admins@company.com" `
    -EmailNotification Always  # Get notified of all runs
```

### 4. Use Fast Mode for Scheduled Tasks

Combine auto-healing with fast mode for efficient monitoring:

```powershell
.\Invoke-ADReplicationManager.ps1 `
    -CreateScheduledTask `
    -TaskSchedule Every4Hours `
    -AutoHeal `
    -FastMode  # 40-60% faster
```

### 5. Regular Statistics Review

Weekly review of healing effectiveness:

```powershell
# Create weekly report
$stats = Get-HealingStatistics -DaysBack 7

$report = @"
Weekly Auto-Healing Report
==========================
Period: Last 7 days
Total Actions: $($stats.TotalActions)
Success Rate: $($stats.SuccessRate)%
Failed Actions: $($stats.FailedActions)
Rollbacks: $($stats.RolledBackActions)

Top Categories:
$(($stats.CategoriesHealed.GetEnumerator() | Sort-Object Value -Descending | 
    ForEach-Object { "- $($_.Key): $($_.Value)" }) -join "`n")

Top DCs:
$(($stats.TopDCs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 |
    ForEach-Object { "- $($_.Key): $($_.Value) actions" }) -join "`n")
"@

$report | Out-File "C:\Reports\Weekly-Healing-Report.txt"
Send-MailMessage -To "ad-admins@company.com" -Subject "Weekly Auto-Healing Report" -Body $report
```

---

## Troubleshooting

### Issue: No Actions Being Taken

**Symptoms:** Auto-healing enabled but no actions performed

**Diagnosis:**
```powershell
# Check eligibility
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Verbose

# Look for messages like:
# "✗ Issue skipped: DC01 - StaleReplication - Reason: Cooldown period active"
```

**Solutions:**
1. **Cooldown Active**: Wait for cooldown period to expire
2. **Policy Too Restrictive**: Use Moderate or Aggressive policy
3. **No Eligible Issues**: Issues don't match policy criteria

### Issue: Too Many Actions

**Symptoms:** Hundreds of healing actions in short time

**Solutions:**
```powershell
# Reduce max actions
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -MaxHealingActions 3  # Limit to 3 per run

# Increase cooldown
.\Invoke-ADReplicationManager.ps1 `
    -AutoHeal `
    -HealingCooldownMinutes 60  # 1 hour cooldown
```

### Issue: Healing Loops

**Symptoms:** Same DC healed repeatedly without success

**Diagnosis:**
```powershell
$history = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\healing-history.csv"

# Check for repeated failures on same DC
$dcHistory = $history | Where-Object { $_.DC -eq "DC01" } | Sort-Object Timestamp
$dcHistory | Format-Table Timestamp, Category, Success
```

**Solutions:**
1. **Increase Cooldown**: Give more time between attempts
2. **Investigate Root Cause**: Issue may require manual intervention
3. **Use Rollback**: Enable `-EnableRollback` to undo failed attempts

### Issue: Rollback Failures

**Symptoms:** Rollback attempts fail

**Diagnosis:**
```powershell
$rollbacks = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\rollback-history.csv"

$failed = $rollbacks | Where-Object { $_.RollbackSuccess -eq 'False' }
$failed | Format-Table
```

**Solutions:**
1. **Check DC Connectivity**: Ensure DC is reachable
2. **Check Permissions**: Ensure account has replication rights
3. **Manual Intervention**: Some issues require manual fixing

---

## See Also

- [RELEASE-NOTES-v3.2.md](../RELEASE-NOTES-v3.2.md) - Complete v3.2 documentation
- [API-REFERENCE.md](API-REFERENCE.md) - Function reference
- [OPERATIONS-MANUAL.md](OPERATIONS-MANUAL.md) - Operational procedures
- [TROUBLESHOOTING-GUIDE.md](TROUBLESHOOTING-GUIDE.md) - Common issues

---

**Document Information**

**Prepared by:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer  
Organization: Enterprise IT Operations

**Version History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-28 | Adrian Johnson | Initial Auto-Healing guide |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

