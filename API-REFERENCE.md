# Active Directory Replication Manager v3.0
## API Reference

**Document Version:** 1.0  
**Last Updated:** October 18, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Status:** Final  
**Classification:** Internal Use

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core Functions](#2-core-functions)
3. [Helper Functions](#3-helper-functions)
4. [Data Types](#4-data-types)
5. [Error Handling](#5-error-handling)
6. [Examples](#6-examples)

---

## 1. Overview

### 1.1 Purpose

This document provides complete API specifications for all public functions in the Active Directory Replication Manager (ADRM) v3.0. It is intended for developers, scripters, and advanced administrators who need to integrate ADRM into custom solutions.

### 1.2 Function Categories

| Category | Functions | Purpose |
|----------|-----------|---------|
| **Core Data Collection** | Get-ReplicationSnapshot | Query AD replication state |
| **Analysis** | Find-ReplicationIssues | Evaluate health and identify problems |
| **Repair** | Invoke-ReplicationFix | Execute remediation actions |
| **Verification** | Test-ReplicationHealth | Post-repair validation |
| **Reporting** | Export-ReplReports | Generate outputs |
| **Utility** | Write-RepairLog, Resolve-ScopeToDCs | Supporting functions |

### 1.3 Common Parameters

All functions support PowerShell common parameters:
- `-Verbose`: Detailed operational output
- `-Debug`: Internal troubleshooting information
- `-ErrorAction`: Error handling behavior
- `-WarningAction`: Warning handling behavior
- `-InformationAction`: Information stream behavior

Functions that modify state also support:
- `-WhatIf`: Preview without execution
- `-Confirm`: Interactive confirmation prompts

---

## 2. Core Functions

### 2.1 Get-ReplicationSnapshot

**Synopsis:** Captures current replication state across specified domain controllers.

#### Syntax

```powershell
Get-ReplicationSnapshot
    [-DomainControllers] <string[]>
    [-ThrottleLimit <int>]
    [-TimeoutSeconds <int>]
    [<CommonParameters>]
```

#### Parameters

**-DomainControllers** `<string[]>`
- **Required:** Yes
- **Position:** 1
- **Pipeline:** Yes (ByValue)
- **Validation:** Not null or empty
- **Description:** Array of domain controller FQDNs to query

**-ThrottleLimit** `<int>`
- **Required:** No
- **Default:** 8
- **Range:** 1-32
- **Description:** Maximum number of parallel operations (PowerShell 7+ only)

**-TimeoutSeconds** `<int>`
- **Required:** No
- **Default:** 300
- **Range:** 60-3600
- **Description:** Per-DC query timeout in seconds

#### Return Value

**Type:** `PSCustomObject[]`

**Schema:**
```powershell
[PSCustomObject]@{
    DC                  : string              # DC FQDN
    Timestamp           : DateTime            # Capture time
    InboundPartners     : PSCustomObject[]    # Replication partners
    Failures            : PSCustomObject[]    # Active failures
    Status              : string              # Healthy|Degraded|Unreachable|Failed
    Error               : string              # Error message (if applicable)
}
```

#### Exceptions

| Exception | Condition | Mitigation |
|-----------|-----------|------------|
| `ArgumentException` | Invalid DC name format | Validate FQDN before calling |
| `TimeoutException` | Operation exceeded timeout | Increase `-TimeoutSeconds` |
| `UnauthorizedAccessException` | Insufficient permissions | Verify Domain Admin rights |

#### Examples

**Example 1: Query specific DCs**
```powershell
$snapshot = Get-ReplicationSnapshot -DomainControllers "DC01.domain.com","DC02.domain.com" -Verbose

# Access results
$snapshot | ForEach-Object {
    Write-Host "$($_.DC): $($_.Status) - $($_.Failures.Count) failures"
}
```

**Example 2: Pipeline input**
```powershell
$dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
$snapshot = $dcs | Get-ReplicationSnapshot -ThrottleLimit 16
```

**Example 3: With timeout**
```powershell
# For slow WAN links
$snapshot = Get-ReplicationSnapshot -DomainControllers "REMOTE-DC01" -TimeoutSeconds 600
```

#### Performance Characteristics

| DCs | PS7 (Throttle=8) | PS5.1 (Serial) |
|-----|------------------|----------------|
| 5 | ~15 seconds | ~40 seconds |
| 10 | ~25 seconds | ~80 seconds |
| 20 | ~45 seconds | ~160 seconds |

#### Notes

- PowerShell 7+: Uses `ForEach-Object -Parallel` for concurrent queries
- PowerShell 5.1: Falls back to serial processing with progress indicator
- Unreachable DCs do not fail the entire operation
- Results are thread-safe (ConcurrentBag) in parallel mode

---

### 2.2 Find-ReplicationIssues

**Synopsis:** Analyzes replication snapshots and identifies actionable issues.

#### Syntax

```powershell
Find-ReplicationIssues
    [-Snapshots] <object[]>
    [<CommonParameters>]
```

#### Parameters

**-Snapshots** `<object[]>`
- **Required:** Yes
- **Position:** 1
- **Pipeline:** Yes (ByValue)
- **Description:** Array of snapshot objects from `Get-ReplicationSnapshot`

#### Return Value

**Type:** `PSCustomObject[]`

**Schema:**
```powershell
[PSCustomObject]@{
    DC          : string      # Affected DC
    Category    : string      # Connectivity|ReplicationFailure|StaleReplication
    Severity    : string      # High|Medium|Low
    Description : string      # Human-readable description
    Partner     : string      # Partner DC (if applicable)
    ErrorCode   : int         # AD error code (if applicable)
    Actionable  : boolean     # Can be auto-repaired?
}
```

#### Issue Categories

| Category | Trigger | Severity | Actionable |
|----------|---------|----------|------------|
| **Connectivity** | DC query failed | High | No (manual investigation) |
| **ReplicationFailure** | Active failures detected | High | Yes (repadmin sync) |
| **StaleReplication** | No success for >24 hours | Medium | Yes (force sync) |

#### Examples

**Example 1: Basic usage**
```powershell
$snapshot = Get-ReplicationSnapshot -DomainControllers "DC01","DC02"
$issues = $snapshot | Find-ReplicationIssues

# Display issues
$issues | Format-Table DC, Category, Severity, Description -AutoSize
```

**Example 2: Filter high-severity issues**
```powershell
$issues = $snapshot | Find-ReplicationIssues
$critical = $issues | Where-Object Severity -eq 'High'

if ($critical.Count -gt 0) {
    Write-Warning "Critical issues detected: $($critical.Count)"
    $critical | Export-Csv "C:\Reports\CriticalIssues.csv" -NoTypeInformation
}
```

**Example 3: Group by category**
```powershell
$issues = $snapshot | Find-ReplicationIssues
$grouped = $issues | Group-Object Category

foreach ($group in $grouped) {
    Write-Host "$($group.Name): $($group.Count) issues"
}
```

#### Performance Characteristics

- **Time Complexity:** O(n) where n = number of DCs
- **Memory Usage:** Minimal (< 10 MB for 100 DCs)
- **Typical Execution:** < 1 second for any snapshot size

#### Notes

- Pure function (no side effects)
- Safe to call multiple times on same snapshot
- Returns empty array if no issues found (not $null)
- Stale replication threshold: 24 hours (hardcoded)

---

### 2.3 Invoke-ReplicationFix

**Synopsis:** Executes repair operations for identified replication issues.

#### Syntax

```powershell
Invoke-ReplicationFix
    [-DomainController] <string>
    [-Issues] <object[]>
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

#### Parameters

**-DomainController** `<string>`
- **Required:** Yes
- **Position:** 1
- **Description:** Target DC FQDN for repair operations

**-Issues** `<object[]>`
- **Required:** Yes
- **Position:** 2
- **Description:** Array of issue objects from `Find-ReplicationIssues`

**-WhatIf** `<SwitchParameter>`
- **Description:** Preview actions without execution

**-Confirm** `<SwitchParameter>`
- **Description:** Prompt for confirmation before each action

#### Return Value

**Type:** `PSCustomObject[]`

**Schema:**
```powershell
[PSCustomObject]@{
    DC          : string      # Target DC
    IssueType   : string      # Issue category being repaired
    Method      : string      # Repair method (e.g., "repadmin /syncall")
    Success     : boolean     # Repair successful?
    Message     : string      # Result description
    Timestamp   : DateTime    # When action was performed
}
```

#### Repair Methods

| Issue Category | Repair Method | Command |
|----------------|---------------|---------|
| **ReplicationFailure** | Force sync | `repadmin /syncall /A /P /e $DC` |
| **StaleReplication** | Force sync | `repadmin /syncall /A /P /e $DC` |
| **Connectivity** | Manual investigation | (no automatic repair) |

#### Examples

**Example 1: Interactive repair**
```powershell
$snapshot = Get-ReplicationSnapshot -DomainControllers "DC01"
$issues = $snapshot | Find-ReplicationIssues

if ($issues.Count -gt 0) {
    $actions = Invoke-ReplicationFix -DomainController "DC01" -Issues $issues
    $actions | Format-Table DC, Method, Success, Message
}
```

**Example 2: WhatIf (preview)**
```powershell
$actions = Invoke-ReplicationFix -DomainController "DC01" -Issues $issues -WhatIf
# Shows what would happen without executing
```

**Example 3: Automated repair**
```powershell
$actions = Invoke-ReplicationFix -DomainController "DC01" -Issues $issues -Confirm:$false
$successful = ($actions | Where-Object Success).Count
Write-Host "$successful/$($actions.Count) repairs successful"
```

#### Side Effects

- **Executes:** `repadmin.exe` commands against target DC
- **Modifies:** AD replication schedule (temporary)
- **Logs:** All actions to `$Script:RepairLog`

#### Notes

- Requires Domain Admin or replication management permissions
- ShouldProcess enabled (respects `-WhatIf` and `-Confirm`)
- Actions are idempotent (safe to retry)
- Does not fix connectivity issues (manual intervention required)
- Maximum execution time: ~30 seconds per DC

---

### 2.4 Test-ReplicationHealth

**Synopsis:** Verifies replication health after repair operations.

#### Syntax

```powershell
Test-ReplicationHealth
    [-DomainControllers] <string[]>
    [-WaitSeconds <int>]
    [<CommonParameters>]
```

#### Parameters

**-DomainControllers** `<string[]>`
- **Required:** Yes
- **Position:** 1
- **Description:** Array of DC FQDNs to verify

**-WaitSeconds** `<int>`
- **Required:** No
- **Default:** 120
- **Range:** 0-600
- **Description:** Seconds to wait for replication convergence before verification

#### Return Value

**Type:** `PSCustomObject[]`

**Schema:**
```powershell
[PSCustomObject]@{
    DC              : string      # Verified DC
    RepadminCheck   : string      # Pass|Fail|Inconclusive|Error
    FailureCount    : int         # Active errors detected
    SuccessCount    : int         # Successful replication links
    OverallHealth   : string      # Healthy|Degraded|Unknown|Failed
}
```

#### Verification Logic

```
IF FailureCount = 0 AND SuccessCount > 0 THEN
    RepadminCheck = 'Pass'
    OverallHealth = 'Healthy'
ELSE IF FailureCount > 0 THEN
    RepadminCheck = 'Fail'
    OverallHealth = 'Degraded'
ELSE
    RepadminCheck = 'Inconclusive'
    OverallHealth = 'Unknown'
END IF
```

#### Examples

**Example 1: Basic verification**
```powershell
$verification = Test-ReplicationHealth -DomainControllers "DC01","DC02"
$verification | Format-Table DC, OverallHealth, FailureCount, SuccessCount
```

**Example 2: No convergence wait**
```powershell
# Immediate verification (not recommended)
$verification = Test-ReplicationHealth -DomainControllers "DC01" -WaitSeconds 0
```

**Example 3: Extended wait for WAN**
```powershell
# Allow 5 minutes for WAN replication
$verification = Test-ReplicationHealth -DomainControllers "REMOTE-DC01" -WaitSeconds 300
```

#### Performance Characteristics

- **Wait time:** Configurable (0-600 seconds)
- **Verification time:** ~10-15 seconds per DC
- **Total time:** WaitSeconds + (DCs × 15 seconds)

#### Notes

- Read-only operation (no modifications)
- Uses `repadmin /showrepl` for verification
- Analyzes error patterns and success indicators
- Also checks replication queue depth
- Recommended wait time: 120 seconds (default)

---

### 2.5 Export-ReplReports

**Synopsis:** Generates all output reports (CSV, JSON, logs).

#### Syntax

```powershell
Export-ReplReports
    [-Data] <hashtable>
    [-OutputDirectory] <string>
    [<CommonParameters>]
```

#### Parameters

**-Data** `<hashtable>`
- **Required:** Yes
- **Position:** 1
- **Description:** Execution data including snapshots, issues, actions, verification

**-OutputDirectory** `<string>`
- **Required:** Yes
- **Position:** 2
- **Description:** Directory path for report output

#### Data Hashtable Schema

```powershell
@{
    Mode            = "AuditRepairVerify"
    Scope           = "Site:HQ"
    Snapshots       = @(...)    # From Get-ReplicationSnapshot
    Issues          = @(...)    # From Find-ReplicationIssues
    RepairActions   = @(...)    # From Invoke-ReplicationFix
    Verification    = @(...)    # From Test-ReplicationHealth
}
```

#### Generated Files

| File | Format | Purpose |
|------|--------|---------|
| **ReplicationSnapshot.csv** | CSV | Current replication state |
| **IdentifiedIssues.csv** | CSV | All detected issues |
| **RepairActions.csv** | CSV | Actions performed |
| **VerificationResults.csv** | CSV | Post-repair validation |
| **summary.json** | JSON | Machine-readable summary |
| **execution.log** | Text | Complete execution log |

#### Return Value

**Type:** `hashtable`

**Schema:**
```powershell
@{
    SnapshotCSV     = "C:\Reports\...\ReplicationSnapshot.csv"
    IssuesCSV       = "C:\Reports\...\IdentifiedIssues.csv"
    ActionsCSV      = "C:\Reports\...\RepairActions.csv"
    VerificationCSV = "C:\Reports\...\VerificationResults.csv"
    SummaryJSON     = "C:\Reports\...\summary.json"
    LogTXT          = "C:\Reports\...\execution.log"
}
```

#### Examples

**Example 1: Export complete execution**
```powershell
$data = @{
    Mode = "Audit"
    Scope = "DCList"
    Snapshots = $snapshot
    Issues = $issues
    RepairActions = @()
    Verification = @()
}

$paths = Export-ReplReports -Data $data -OutputDirectory "C:\Reports\ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Reports generated:"
$paths.Values | ForEach-Object { Write-Host "  $_" }
```

**Example 2: Parse generated JSON**
```powershell
$paths = Export-ReplReports -Data $data -OutputDirectory $outputDir
$summary = Get-Content $paths.SummaryJSON | ConvertFrom-Json

Write-Host "Exit Code: $($summary.ExitCode)"
Write-Host "Health: $($summary.HealthyDCs)/$($summary.TotalDCs)"
```

#### Notes

- Creates output directory if it doesn't exist
- CSV encoding: UTF-8 with BOM
- JSON depth: 5 levels
- Existing files are overwritten
- All exports are atomic (no partial writes)

---

## 3. Helper Functions

### 3.1 Write-RepairLog

**Synopsis:** Pipeline-friendly logging with structured output streams.

#### Syntax

```powershell
Write-RepairLog
    [-Message] <string>
    [-Level <string>]
    [<CommonParameters>]
```

#### Parameters

**-Message** `<string>`
- **Required:** Yes
- **Position:** 1
- **Description:** Log message text

**-Level** `<string>`
- **Required:** No
- **Default:** "Information"
- **ValidSet:** "Verbose", "Information", "Warning", "Error"
- **Description:** Message severity level

#### Behavior by Level

| Level | PowerShell Stream | Visible By Default |
|-------|-------------------|-------------------|
| **Verbose** | Verbose (5) | No (use `-Verbose`) |
| **Information** | Information (6) | Yes |
| **Warning** | Warning (3) | Yes |
| **Error** | Error (2) | Yes |

#### Examples

```powershell
# Verbose detail
Write-RepairLog "Querying DC01.domain.com" -Level Verbose

# Progress information
Write-RepairLog "Snapshot captured for 5 DCs" -Level Information

# Non-critical issue
Write-RepairLog "DC03 response slow" -Level Warning

# Critical failure
Write-RepairLog "Failed to contact DC05" -Level Error
```

#### Notes

- All messages appended to `$Script:RepairLog`
- Respects PowerShell preference variables (`$VerbosePreference`, etc.)
- Thread-safe (synchronized collection)
- Automatic timestamping (format: yyyy-MM-dd HH:mm:ss)

---

### 3.2 Resolve-ScopeToDCs

**Synopsis:** Resolves `-Scope` parameter to explicit DC list with safety checks.

#### Syntax

```powershell
Resolve-ScopeToDCs
    [-Scope] <string>
    [-ExplicitDCs] <string[]>
    [-Domain] <string>
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

#### Parameters

**-Scope** `<string>`
- **Required:** Yes
- **Position:** 1
- **Pattern:** `^(Forest|Site:.+|DCList)$`
- **Description:** Scope definition

**-ExplicitDCs** `<string[]>`
- **Required:** No (required if Scope=DCList)
- **Position:** 2
- **Description:** Explicit DC list

**-Domain** `<string>`
- **Required:** Yes
- **Position:** 3
- **Description:** Domain FQDN

#### Scope Types

| Scope | Behavior | Confirmation Required |
|-------|----------|----------------------|
| **Forest** | All DCs across all domains | Yes (ShouldProcess) |
| **Site:<Name>** | All DCs in specified site | No |
| **DCList** | Use ExplicitDCs parameter | No |

#### Return Value

**Type:** `string[]` (Array of DC FQDNs)

#### Examples

```powershell
# Forest scope (requires confirmation)
$dcs = Resolve-ScopeToDCs -Scope "Forest" -Domain "contoso.com"

# Site scope
$dcs = Resolve-ScopeToDCs -Scope "Site:HQ" -Domain "contoso.com"

# Explicit list
$dcs = Resolve-ScopeToDCs -Scope "DCList" -ExplicitDCs @("DC01","DC02") -Domain "contoso.com"
```

#### Exceptions

| Exception | Condition |
|-----------|-----------|
| `ArgumentException` | Scope=DCList but ExplicitDCs empty |
| `System.DirectoryServices.ActiveDirectory.ActiveDirectoryObjectNotFoundException` | Site not found |

---

## 4. Data Types

### 4.1 Snapshot Object

**Fully Qualified Type:** `PSCustomObject` (dynamic)

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `DC` | string | Domain controller FQDN |
| `Timestamp` | DateTime | When snapshot was captured |
| `InboundPartners` | PSCustomObject[] | Array of partner objects |
| `Failures` | PSCustomObject[] | Array of failure objects |
| `Status` | string | Healthy\|Degraded\|Unreachable\|Failed |
| `Error` | string | Error message (if Status != Healthy) |

**Partner Object Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Partner` | string | Partner DC FQDN |
| `Partition` | string | AD partition DN |
| `LastAttempt` | DateTime | Last replication attempt |
| `LastSuccess` | DateTime | Last successful replication |
| `LastResult` | int | Error code (0 = success) |
| `ConsecutiveFailures` | int | Consecutive failure count |
| `HoursSinceLastSuccess` | decimal | Calculated staleness |

---

### 4.2 Issue Object

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `DC` | string | Affected DC |
| `Category` | string | Connectivity\|ReplicationFailure\|StaleReplication |
| `Severity` | string | High\|Medium\|Low |
| `Description` | string | Human-readable description |
| `Partner` | string | Partner DC (if applicable) |
| `ErrorCode` | int | AD error code (if applicable) |
| `Actionable` | boolean | Can be auto-repaired? |

---

### 4.3 Repair Action Object

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `DC` | string | Target DC |
| `IssueType` | string | Category of issue |
| `Method` | string | Repair method used |
| `Success` | boolean | Repair successful? |
| `Message` | string | Result description |
| `Timestamp` | DateTime | When performed |

---

### 4.4 Verification Result Object

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `DC` | string | Verified DC |
| `RepadminCheck` | string | Pass\|Fail\|Inconclusive\|Error |
| `FailureCount` | int | Active errors |
| `SuccessCount` | int | Successful links |
| `OverallHealth` | string | Healthy\|Degraded\|Unknown\|Failed |

---

## 5. Error Handling

### 5.1 Exception Hierarchy

```
System.Exception
├── System.ArgumentException
│   ├── ArgumentNullException (null parameters)
│   └── ArgumentOutOfRangeException (parameter validation)
├── System.TimeoutException (operation timeout)
├── System.UnauthorizedAccessException (insufficient permissions)
└── Microsoft.ActiveDirectory.Management.*
    ├── ADServerDownException (DC unreachable)
    ├── ADIdentityNotFoundException (DC not found)
    └── ADException (general AD error)
```

### 5.2 Error Action Guidance

| Function | Recommended ErrorAction | Rationale |
|----------|------------------------|-----------|
| Get-ReplicationSnapshot | Continue | Partial results useful |
| Find-ReplicationIssues | Stop | No analysis without input |
| Invoke-ReplicationFix | Continue | Fix what can be fixed |
| Test-ReplicationHealth | Continue | Partial verification useful |
| Export-ReplReports | Stop | Report must be complete |

### 5.3 Try-Catch Patterns

**Pattern 1: Specific exception handling**
```powershell
try {
    $snapshot = Get-ReplicationSnapshot -DomainControllers $dcs -ErrorAction Stop
}
catch [Microsoft.ActiveDirectory.Management.ADServerDownException] {
    Write-Warning "DC unreachable - check connectivity"
    # Handle gracefully
}
catch {
    Write-Error "Unexpected error: $_"
    throw
}
```

**Pattern 2: Suppress specific errors**
```powershell
$snapshot = Get-ReplicationSnapshot -DomainControllers $dcs -ErrorAction SilentlyContinue -ErrorVariable snapErrors

if ($snapErrors.Count -gt 0) {
    Write-Warning "$($snapErrors.Count) DCs failed to query"
}
```

---

## 6. Examples

### 6.1 Complete Audit Workflow

```powershell
# Step 1: Capture replication state
$snapshot = Get-ReplicationSnapshot -DomainControllers "DC01","DC02","DC03" -Verbose

# Step 2: Analyze issues
$issues = $snapshot | Find-ReplicationIssues

# Step 3: Display results
Write-Host "`nHealth Summary:" -ForegroundColor Cyan
$summary = $snapshot | Group-Object Status | Select-Object Name, Count
$summary | Format-Table -AutoSize

Write-Host "`nIssues Detected: $($issues.Count)" -ForegroundColor $(if ($issues.Count -eq 0) {'Green'} else {'Yellow'})
$issues | Format-Table DC, Category, Severity, Description -AutoSize

# Step 4: Export reports
$data = @{
    Mode = "Audit"
    Scope = "DCList"
    Snapshots = $snapshot
    Issues = $issues
    RepairActions = @()
    Verification = @()
}

$paths = Export-ReplReports -Data $data -OutputDirectory "C:\Reports\ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`nReports available:"
$paths.Values | ForEach-Object { Write-Host "  $_" }
```

---

### 6.2 Complete Repair Workflow

```powershell
# Step 1: Audit
$snapshot = Get-ReplicationSnapshot -DomainControllers "DC01","DC02"
$issues = $snapshot | Find-ReplicationIssues

if ($issues.Count -eq 0) {
    Write-Host "No issues detected" -ForegroundColor Green
    return
}

# Step 2: Preview repairs
Write-Host "`nPreviewing repairs:" -ForegroundColor Yellow
$dcs = $issues | Select-Object -ExpandProperty DC -Unique

foreach ($dc in $dcs) {
    $dcIssues = $issues | Where-Object DC -eq $dc
    Write-Host "  $dc - $($dcIssues.Count) issues"
    Invoke-ReplicationFix -DomainController $dc -Issues $dcIssues -WhatIf
}

# Step 3: Execute repairs (with confirmation)
$allActions = @()
foreach ($dc in $dcs) {
    $dcIssues = $issues | Where-Object DC -eq $dc
    $actions = Invoke-ReplicationFix -DomainController $dc -Issues $dcIssues
    $allActions += $actions
}

# Step 4: Verify
$verification = Test-ReplicationHealth -DomainControllers $dcs -WaitSeconds 120

# Step 5: Report
$data = @{
    Mode = "Repair"
    Scope = "DCList"
    Snapshots = $snapshot
    Issues = $issues
    RepairActions = $allActions
    Verification = $verification
}

$paths = Export-ReplReports -Data $data -OutputDirectory "C:\Reports\ADRepl-Repair-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Display summary
Write-Host "`nRepair Summary:" -ForegroundColor Cyan
Write-Host "  Issues detected: $($issues.Count)"
Write-Host "  Actions performed: $($allActions.Count)"
Write-Host "  Successful: $(($allActions | Where-Object Success).Count)"
Write-Host "  Failed: $(($allActions | Where-Object {-not $_.Success}).Count)"

Write-Host "`nPost-Repair Health:"
$verification | Format-Table DC, OverallHealth, FailureCount, SuccessCount
```

---

### 6.3 Custom Integration Example

```powershell
# Custom function to integrate ADRM into monitoring system
function Monitor-ADReplication {
    param(
        [string[]]$DomainControllers,
        [string]$AlertEmail
    )
    
    # Capture state
    $snapshot = Get-ReplicationSnapshot -DomainControllers $DomainControllers
    $issues = $snapshot | Find-ReplicationIssues
    
    # Calculate health metrics
    $healthy = ($snapshot | Where-Object Status -eq 'Healthy').Count
    $total = $snapshot.Count
    $healthPct = [math]::Round(($healthy / $total) * 100, 1)
    
    # Determine alert severity
    $severity = if ($healthPct -ge 95) { 'Normal' }
                 elseif ($healthPct -ge 90) { 'Warning' }
                 else { 'Critical' }
    
    # Send alert if needed
    if ($severity -ne 'Normal') {
        $body = @"
AD Replication Health Alert

Severity: $severity
Health: $healthPct% ($healthy/$total DCs)
Issues: $($issues.Count)

Details:
$(($issues | Format-Table DC, Category, Severity | Out-String))

Timestamp: $(Get-Date)
"@
        
        Send-MailMessage -To $AlertEmail -Subject "AD Replication Alert - $severity" -Body $body -SmtpServer "smtp.company.com"
    }
    
    # Return metrics for monitoring system
    return [PSCustomObject]@{
        Timestamp = Get-Date
        TotalDCs = $total
        HealthyDCs = $healthy
        HealthPercentage = $healthPct
        IssuesCount = $issues.Count
        Severity = $severity
    }
}

# Usage
$metrics = Monitor-ADReplication -DomainControllers "DC01","DC02","DC03" -AlertEmail "admins@company.com"
```

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2025-10-10 | Adrian Johnson | Initial draft |
| 0.5 | 2025-10-15 | Adrian Johnson | Added all core functions |
| 1.0 | 2025-10-18 | Adrian Johnson | Final release |

---

**END OF API REFERENCE**

---

**Author:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer

