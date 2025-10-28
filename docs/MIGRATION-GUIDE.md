# Migration Guide: v2.0 → v3.0

**Version:** 1.0  
**Last Updated:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** Internal Use

---

## Quick Reference

| Old Command (v2.0) | New Command (v3.0) |
|-------------------|-------------------|
| `.\AD-Repl-Audit.ps1 -DomainName "domain.com" -TargetDCs "DC01","DC02"` | `.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -DomainName "domain.com"` |
| `.\AD-ReplicationRepair.ps1 -AutoRepair` | `.\Invoke-ADReplicationManager.ps1 -Mode Repair -AutoRepair -DomainControllers DC01,DC02` |
| N/A (ran both scripts) | `.\Invoke-ADReplicationManager.ps1 -Mode AuditRepairVerify -DomainControllers DC01,DC02` |

---

## Breaking Changes

### 1. Parameter Name Changes

| Old | New | Notes |
|-----|-----|-------|
| `-TargetDCs` | `-DomainControllers` | More descriptive |
| N/A | `-Mode` | **Required change:** Choose `Audit`, `Repair`, `Verify`, or `AuditRepairVerify` |
| N/A | `-Scope` | New feature: `Forest`, `Site:<name>`, or `DCList` (default) |

### 2. Output Changes

**Console Output**
- Old: `Write-Host` everywhere (colorful but not pipeline-friendly)
- New: `Write-Verbose`, `Write-Information`, `Write-Warning`, `Write-Error`
- **Impact**: Use `-Verbose` to see detailed output, `-InformationAction Continue` for progress

**File Outputs**
- Old: `RepairReport.json`, `RepairSummary.html`, various CSVs
- New: `summary.json` (CI-friendly), CSVs (consistent naming), `execution.log`
- **Impact**: Update any parsing scripts to use `summary.json`

### 3. Behavior Changes

**Default Behavior**
- Old: Audit runs automatically, repair requires prompt
- New: Mode defaults to `Audit` (safe), must explicitly choose `Repair`

**Scope Safety**
- Old: No target = all DCs (risky)
- New: Must specify `-DomainControllers` or `-Scope Forest`/`Site:<name>`
- **Impact**: Prevents accidental forest-wide operations

**Exit Codes**
- Old: `exit 0` or `exit 1`
- New: `0`=healthy, `2`=issues, `3`=unreachable, `4`=error
- **Impact**: Update CI/CD scripts to handle new codes

---

## Step-by-Step Migration

### Step 1: Test in Non-Production

```powershell
# Old way (audit only)
.\AD-Repl-Audit.ps1 -DomainName "test.lab" -TargetDCs "TESTDC01","TESTDC02"

# New way (equivalent)
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -DomainControllers TESTDC01,TESTDC02 `
    -DomainName "test.lab" `
    -Verbose
```

**Validate**:
- Check CSV exports match expected format
- Verify `summary.json` contains expected fields
- Confirm exit code logic (0=healthy, 2=issues)

### Step 2: Preview Production Changes

```powershell
# See what repairs would do without executing
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -DomainControllers DC01,DC02 `
    -WhatIf
```

**Validate**:
- Review all "What if:" messages
- Ensure no unexpected actions
- Confirm targeting is correct

### Step 3: Run Interactive Repairs

```powershell
# Old way
.\AD-ReplicationRepair.ps1 -TargetDCs "DC01","DC02"
# (prompted for approval)

# New way (equivalent)
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -DomainControllers DC01,DC02 `
    -AuditTrail
# (prompted for approval, with transcript)
```

**Validate**:
- Review transcript log in output directory
- Compare repair actions to old script behavior
- Check all issues were addressed

### Step 4: Update Scheduled Tasks

**Old Task:**
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "C:\Scripts\AD-Repl-Audit.ps1" -DomainName "corp.com" -AutoRepair
```

**New Task:**
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Invoke-ADReplicationManager.ps1" `
    -Mode AuditRepairVerify `
    -Scope Site:HQ `
    -AutoRepair `
    -AuditTrail `
    -OutputPath "C:\Reports\AD-Health"
```

**Key Changes**:
- Add `-Mode AuditRepairVerify` for full workflow
- Use `-Scope` for better targeting
- Add `-AuditTrail` for compliance
- Specify `-OutputPath` for consistent location

### Step 5: Update CI/CD Integration

**Old CI Script:**
```powershell
.\AD-Repl-Audit.ps1 -DomainName "prod.com"
if ($LASTEXITCODE -ne 0) { 
    throw "Audit failed" 
}
```

**New CI Script:**
```powershell
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:Production
$summary = Get-Content ".\ADRepl-*\summary.json" | ConvertFrom-Json

# Rich exit code handling
switch ($summary.ExitCode) {
    0 { Write-Host "✓ All DCs healthy" }
    2 { throw "Issues detected: $($summary.IssuesFound)" }
    3 { throw "Unreachable DCs: $($summary.UnreachableDCs)" }
    4 { throw "Execution error" }
}
```

---

## Feature Equivalency Matrix

| Feature | v2.0 Scripts | v3.0 Script | Notes |
|---------|-------------|-------------|-------|
| Audit-only mode | ✓ (AD-Repl-Audit.ps1) | ✓ `-Mode Audit` | |
| Repair operations | ✓ (AD-ReplicationRepair.ps1) | ✓ `-Mode Repair` | Now with ShouldProcess |
| Verification | ✓ (built into repair) | ✓ `-Mode Verify` | Can run standalone |
| Auto-repair | ✓ `-AutoRepair` | ✓ `-AutoRepair` | |
| Custom output path | ✓ `-OutputPath` | ✓ `-OutputPath` | |
| Target specific DCs | ✓ `-TargetDCs` | ✓ `-DomainControllers` | Renamed |
| CSV export | ✓ | ✓ | Improved consistency |
| JSON export | ✓ (complex) | ✓ (CI-friendly) | Simplified for automation |
| HTML report | ✓ | ⚠ Removed | Use CSV + BI tools |
| Verbose logging | ⚠ Write-Host only | ✓ Write-Verbose | Pipeline-friendly |
| WhatIf support | ✗ | ✓ | Preview changes |
| Confirm prompts | ⚠ Custom | ✓ Built-in | Standard PowerShell |
| Transcript logging | ✗ | ✓ `-AuditTrail` | Compliance feature |
| Parallel processing | ✗ | ✓ (PS7+) | 80-90% faster |
| Scope controls | ✗ | ✓ `-Scope` | Safety feature |
| Exit codes | ⚠ 0/1 only | ✓ 0/2/3/4 | Richer status |
| Error handling | ⚠ Basic | ✓ Comprehensive | Targeted try/catch |
| Parameter validation | ⚠ Limited | ✓ Extensive | ValidateSet, Range, Script |

---

## Common Migration Scenarios

### Scenario 1: Daily Health Check

**Before:**
```powershell
# Cron job / Task Scheduler
.\AD-Repl-Audit.ps1 -DomainName "company.com" -OutputPath "C:\Reports\Daily"
```

**After:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Forest `
    -OutputPath "C:\Reports\Daily\$(Get-Date -Format 'yyyy-MM-dd')" `
    -Confirm:$false
```

**Benefits:** Explicit scope, date-stamped folders, cleaner exit codes

---

### Scenario 2: Emergency Repair

**Before:**
```powershell
# Manual run during incident
.\AD-ReplicationRepair.ps1 -TargetDCs "DC01","DC02" -AutoRepair -OutputPath "C:\Incidents\Case123"
```

**After:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode AuditRepairVerify `
    -DomainControllers DC01,DC02 `
    -AutoRepair `
    -AuditTrail `
    -OutputPath "C:\Incidents\Case123"
```

**Benefits:** Full workflow in one run, audit trail for incident review

---

### Scenario 3: Post-Patching Verification

**Before:**
```powershell
# Run audit after Windows updates
.\AD-Repl-Audit.ps1 -DomainName "domain.com"
# Manually inspect output
```

**After:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Site:HQ `
    -OutputPath "C:\Maintenance\Post-Patch-$(Get-Date -Format 'yyyyMMdd')"

# Parse results programmatically
$summary = Get-Content "C:\Maintenance\Post-Patch-*\summary.json" | ConvertFrom-Json
if ($summary.IssuesFound -gt 0) {
    Send-MailMessage -To "admins@company.com" -Subject "Post-patch issues detected" -Body "Review: $($summary.OutputPath)"
}
```

**Benefits:** Machine-readable output, automation-friendly

---

## Troubleshooting Migration Issues

### Issue: "Parameter set cannot be resolved"

**Cause:** Conflicting parameters (old script names still in command)

**Solution:**
```powershell
# Wrong
.\Invoke-ADReplicationManager.ps1 -TargetDCs DC01,DC02

# Correct
.\Invoke-ADReplicationManager.ps1 -DomainControllers DC01,DC02
```

---

### Issue: "No output to console"

**Cause:** New script uses proper output streams, not `Write-Host`

**Solution:**
```powershell
# Add -Verbose for detailed output
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -Verbose

# Or enable Information stream
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -InformationAction Continue
```

---

### Issue: "Scope=DCList requires -DomainControllers"

**Cause:** Default scope requires explicit DC list

**Solution:**
```powershell
# Option 1: Provide DC list
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02

# Option 2: Use discovery scope
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest

# Option 3: Target specific site
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:Default-First-Site-Name
```

---

### Issue: Exit code 2 in CI pipeline (was 0 before)

**Cause:** New script has richer exit codes (2 = issues detected but handled)

**Solution:**
```powershell
# Old CI logic
if ($LASTEXITCODE -ne 0) { throw "Failed" }

# New CI logic (accept 0 or 2)
if ($LASTEXITCODE -in @(3,4)) { 
    throw "Critical failure" 
} elseif ($LASTEXITCODE -eq 2) {
    Write-Warning "Issues detected but handled"
}
```

---

## Rollback Plan

If migration encounters issues:

1. **Keep old scripts** in place with `-v2` suffix:
   ```powershell
   Rename-Item AD-Repl-Audit.ps1 AD-Repl-Audit-v2.ps1
   Rename-Item AD-ReplicationRepair.ps1 AD-ReplicationRepair-v2.ps1
   ```

2. **Update scheduled tasks** to point to v2 scripts temporarily

3. **Document issues** encountered for resolution

4. **Test v3 in isolation** until stable

5. **Gradually migrate** one use case at a time

---

## Support & Resources

- **Script Location:** `Invoke-ADReplicationManager.ps1`
- **Documentation:** `README-ADReplicationManager.md`
- **This Guide:** `MIGRATION-GUIDE.md`

For questions or issues during migration:
1. Review `execution.log` in output directory
2. Check `summary.json` for structured data
3. Use `-WhatIf` to preview behavior
4. Test with `-Verbose` for detailed logging

---

## Timeline Recommendation

- **Week 1:** Lab testing, validate outputs
- **Week 2:** Production testing (audit-only, manual runs)
- **Week 3:** Interactive repairs with `-AuditTrail`
- **Week 4:** Update scheduled tasks with `-AutoRepair`
- **Week 5:** CI/CD integration with `summary.json`
- **Week 6:** Decommission old scripts

---

## Success Criteria

Migration is complete when:
- [ ] All scheduled tasks use new script
- [ ] CI/CD pipelines parse `summary.json`
- [ ] No dependencies on old script outputs
- [ ] Team trained on new parameters
- [ ] Documentation updated
- [ ] Old scripts archived (not deleted)

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
| 1.0 | 2025-10-28 | Adrian Johnson | Initial migration guide for v2.0 to v3.0 |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

