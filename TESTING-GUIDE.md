# Testing Guide - AD Replication Manager

## Quick Start

Run the automated test suite first:

```powershell
.\Test-Script.ps1
```

This validates:
- ✓ Script syntax and structure
- ✓ All parameters (87 total)
- ✓ All functions (22 core functions)
- ✓ Help documentation
- ✓ Version consistency
- ✓ Safety features (WhatIf/Confirm)

---

## Testing Without Active Directory

### 1. View Help Documentation

```powershell
# Quick help
Get-Help .\Invoke-ADReplicationManager.ps1

# Detailed help with examples
Get-Help .\Invoke-ADReplicationManager.ps1 -Full

# Parameter reference
Get-Help .\Invoke-ADReplicationManager.ps1 -Parameter *
```

### 2. Test Parameter Validation

```powershell
# Test Mode validation (should show valid values)
.\Invoke-ADReplicationManager.ps1 -Mode InvalidMode

# Test Throttle range (should fail)
.\Invoke-ADReplicationManager.ps1 -Throttle 99 -DomainControllers DC01

# Test HealingPolicy validation
.\Invoke-ADReplicationManager.ps1 -AutoHeal -HealingPolicy InvalidPolicy
```

---

## Testing With Active Directory

### Level 1: Safe Read-Only Tests (No Changes)

```powershell
# Test 1: Single DC audit with WhatIf
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01 -WhatIf

# Test 2: Multiple DCs audit (read-only, no changes)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -Verbose

# Test 3: Site-scoped audit
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:Default-First-Site-Name -Verbose

# Test 4: Delta Mode (fast monitoring)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -DeltaMode -Verbose
```

### Level 2: WhatIf Testing (Preview Changes)

```powershell
# Test 1: Repair mode with WhatIf (shows what would be repaired)
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -WhatIf

# Test 2: Auto-healing preview
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -AutoHeal -HealingPolicy Conservative -WhatIf

# Test 3: Full workflow preview
.\Invoke-ADReplicationManager.ps1 -Mode AuditRepairVerify -DomainControllers DC01 -AutoRepair -WhatIf
```

### Level 3: Actual Repairs (Requires Confirmation)

```powershell
# Test 1: Single DC repair with manual confirmation
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01

# Test 2: Auto-healing with conservative policy (safest)
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -AutoHeal -HealingPolicy Conservative

# Test 3: Full workflow with audit trail
.\Invoke-ADReplicationManager.ps1 -Mode AuditRepairVerify -DomainControllers DC01,DC02 -AutoRepair -AuditTrail
```

### Level 4: Advanced Features

```powershell
# Test 1: Delta Mode for faster monitoring
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -DeltaMode -DeltaThresholdMinutes 120

# Test 2: Auto-healing with moderate policy
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01,DC02 -AutoHeal -HealingPolicy Moderate -EnableRollback

# Test 3: Health scoring and trending
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -EnableHealthScore -HealthHistoryPath "C:\ADHealth"

# Test 4: Fast mode with parallelism
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02,DC03,DC04 -FastMode

# Test 5: Notifications (Slack example)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01 -SlackWebhook "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Test 6: Create scheduled task
.\Invoke-ADReplicationManager.ps1 -CreateScheduledTask -TaskSchedule Daily -TaskTime "03:00" -Mode Audit -Scope Forest
```

---

## Performance Testing

### Benchmark: Standard vs FastMode

```powershell
# Standard mode (baseline)
Measure-Command {
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02,DC03,DC04 -Verbose
}

# Fast mode (should be faster)
Measure-Command {
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02,DC03,DC04 -FastMode -Verbose
}
```

### Benchmark: Full Scan vs Delta Mode

```powershell
# First run (full scan, creates cache)
Measure-Command {
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -DeltaMode
}

# Second run (delta mode, uses cache - should be much faster)
Measure-Command {
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -DeltaMode
}

# Force full scan (bypass cache)
Measure-Command {
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -DeltaMode -ForceFull
}
```

---

## Testing Auto-Healing

### Safe Auto-Healing Tests

```powershell
# Conservative policy (safest, limited actions)
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -AutoHeal -HealingPolicy Conservative -EnableRollback

# View healing statistics
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -AutoHeal -HealingPolicy Conservative
# Check: $env:ProgramData\ADReplicationManager\Healing\healing-log.json
```

### Rollback Testing

```powershell
# Perform healing with rollback enabled
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -AutoHeal -HealingPolicy Moderate -EnableRollback

# If something goes wrong, the script will attempt automatic rollback
# Manual rollback can be triggered by examining the healing log
```

---

## Testing Delta Mode

### Delta Mode Workflow

```powershell
# Step 1: Initial run (creates cache)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02,DC03,DC04 -DeltaMode -Verbose

# Step 2: Wait a bit, then run again (should skip healthy DCs)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02,DC03,DC04 -DeltaMode -Verbose

# Step 3: View cache
Get-Content "$env:ProgramData\ADReplicationManager\Cache\delta-cache.json" | ConvertFrom-Json | Format-List

# Step 4: Force full scan
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02,DC03,DC04 -DeltaMode -ForceFull -Verbose
```

---

## Validating Output

### Check Reports

```powershell
# Find latest report directory
$latestReport = Get-ChildItem -Directory -Filter "ADRepl-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

# View CSV report
Import-Csv "$latestReport\replication-issues.csv" | Format-Table

# View JSON summary
Get-Content "$latestReport\replication-summary.json" | ConvertFrom-Json | ConvertTo-Json -Depth 5

# Open HTML report
Invoke-Item "$latestReport\replication-report.html"
```

### Check Logs

```powershell
# View transcript (if -AuditTrail was used)
$latestTranscript = Get-ChildItem "$latestReport" -Filter "*.log" | Select-Object -First 1
Get-Content $latestTranscript.FullName -Tail 50
```

---

## Troubleshooting Tests

### Test 1: Verify Prerequisites

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Check Active Directory module
Get-Module -ListAvailable ActiveDirectory

# Check if you're in a domain
$env:USERDNSDOMAIN

# Check current user permissions
whoami /groups
```

### Test 2: Test AD Connectivity

```powershell
# Test DC reachability
Test-NetConnection -ComputerName DC01 -Port 389

# Test AD cmdlets
Get-ADDomainController -Filter * | Select-Object Name, Site, IsGlobalCatalog
```

### Test 3: Test with Maximum Verbosity

```powershell
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01 -Verbose -Debug -InformationAction Continue
```

---

## CI/CD Integration Testing

### Test Exit Codes

```powershell
# Test success (should return 0)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01
echo "Exit code: $LASTEXITCODE"

# Test with failure injection (if issues exist, should return non-zero)
.\Invoke-ADReplicationManager.ps1 -Mode Verify -DomainControllers DC01
echo "Exit code: $LASTEXITCODE"
```

### Test JSON Output for Parsing

```powershell
# Run and capture JSON
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01 -OutputPath "C:\Temp\ADRepl"
$summary = Get-Content "C:\Temp\ADRepl\replication-summary.json" | ConvertFrom-Json

# Validate structure
$summary.Mode
$summary.ExecutionTime
$summary.IssuesFound
$summary.DomainControllers
```

---

## Expected Results

### Successful Test Indicators

✓ **Test Suite (Test-Script.ps1)**: 34/34 tests pass  
✓ **Audit Mode**: Completes with exit code 0 (if no issues) or 2 (if issues found)  
✓ **WhatIf Mode**: Shows proposed actions without making changes  
✓ **Reports Generated**: CSV, HTML, and JSON files created  
✓ **Delta Cache**: Created in `$env:ProgramData\ADReplicationManager\Cache`  
✓ **Healing Log**: Created in `$env:ProgramData\ADReplicationManager\Healing` (if auto-healing used)  

### Common Issues

⚠️ **"Cannot find domain controller"**: Verify DC name and network connectivity  
⚠️ **"Access denied"**: Requires Domain Admin or equivalent permissions  
⚠️ **"Module ActiveDirectory not found"**: Install RSAT-AD-PowerShell  
⚠️ **"Execution policy"**: Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`  

---

## Next Steps

1. **Start with automated tests**: `.\Test-Script.ps1`
2. **View help documentation**: `Get-Help .\Invoke-ADReplicationManager.ps1 -Full`
3. **Test in audit mode (read-only)**: `.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01`
4. **Preview repairs with WhatIf**: `.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01 -WhatIf`
5. **Perform actual repairs**: `.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01`

---

**Author**: Adrian Johnson <adrian207@gmail.com>  
**Version**: 3.3.0  
**Last Updated**: October 28, 2025

