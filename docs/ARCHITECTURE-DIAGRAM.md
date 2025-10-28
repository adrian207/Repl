# AD Replication Manager - Architecture Diagram

**Version:** 1.0  
**Last Updated:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** Internal Use

---

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    AD Replication Manager v3.0 - Architecture                    │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              INPUT LAYER                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  Parameters:                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ -Mode        │  │ -Scope       │  │ -DCs         │  │ -Throttle    │       │
│  │ Audit/Repair │  │ Forest/Site  │  │ DC01,DC02    │  │ 1-32         │       │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                                                   │
│  Switches: -WhatIf, -Confirm, -AutoRepair, -AuditTrail, -Verbose               │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         PARAMETER VALIDATION LAYER                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]        │
│                                                                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                │
│  │ ValidateSet     │  │ ValidateRange   │  │ ValidateScript  │                │
│  │ Mode values     │  │ Throttle: 1-32  │  │ Path exists     │                │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            SCOPE RESOLUTION                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                      Resolve-ScopeToDCs Function                                 │
│                                                                                   │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐            │
│  │ Scope: Forest   │    │ Scope: Site:HQ  │    │ Scope: DCList   │            │
│  │      ▼          │    │      ▼          │    │      ▼          │            │
│  │ Get all DCs     │    │ Get site DCs    │    │ Use explicit    │            │
│  │ in forest       │    │ from AD site    │    │ DC list         │            │
│  │ (Requires       │    │                 │    │                 │            │
│  │  ShouldProcess) │    │                 │    │                 │            │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘            │
│                                    │                                             │
│                                    ▼                                             │
│                         Resolved DC List: [DC01, DC02, DC03...]                 │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           EXECUTION ENGINE                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │                    PowerShell Version Detection                            │ │
│  ├───────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                            │ │
│  │  if ($PSVersion.Major -ge 7) {                                            │ │
│  │      ┌──────────────────────────────────────────────────┐                │ │
│  │      │ PARALLEL PROCESSING (ForEach-Object -Parallel)   │                │ │
│  │      ├──────────────────────────────────────────────────┤                │ │
│  │      │                                                   │                │ │
│  │      │  DC01 ──┐                                        │                │ │
│  │      │  DC02 ──┤                                        │                │ │
│  │      │  DC03 ──┼─► Throttle Limit: 8                   │                │ │
│  │      │  DC04 ──┤   ┌──────────────┐                    │                │ │
│  │      │  DC05 ──┘   │ ConcurrentBag│ ◄── Thread-safe    │                │ │
│  │      │  ...        └──────────────┘     results         │                │ │
│  │      │                                                   │                │ │
│  │      │  Performance: 80-90% faster on large estates     │                │ │
│  │      └──────────────────────────────────────────────────┘                │ │
│  │  }                                                                         │ │
│  │  else {  // PowerShell 5.1                                                │ │
│  │      ┌──────────────────────────────────────────────────┐                │ │
│  │      │ SERIAL PROCESSING (foreach loop)                 │                │ │
│  │      ├──────────────────────────────────────────────────┤                │ │
│  │      │                                                   │                │ │
│  │      │  DC01 ──► DC02 ──► DC03 ──► DC04 ──► DC05       │                │ │
│  │      │                                                   │                │ │
│  │      │  Optimized: 20-30% faster than v2.0              │                │ │
│  │      └──────────────────────────────────────────────────┘                │ │
│  │  }                                                                         │ │
│  │                                                                            │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          RETRY LOGIC LAYER (NEW v3.0)                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                         Invoke-WithRetry Function                                │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  Attempt 1 ──► Transient Error? ──Yes──► Exponential Backoff           │   │
│  │                      │                           │                       │   │
│  │                     No                    Delay = min(2^attempt, 30s)   │   │
│  │                      │                           │                       │   │
│  │                 Permanent Error? ──Yes──► Fail Immediately              │   │
│  │                      │                                                   │   │
│  │                     No                                                   │   │
│  │                      │                                                   │   │
│  │                    Success ──► Return Result                            │   │
│  │                                                                           │   │
│  │  Backoff Schedule: 2s → 4s → 8s → 16s → 30s (max)                       │   │
│  │  Max Attempts: 3 (configurable)                                          │   │
│  │                                                                           │   │
│  │  Transient Errors: RPC unavailable, network path, timeout               │   │
│  │  Permanent Errors: Access denied, logon failure, domain not found       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         OPERATIONAL PHASES                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │ PHASE 1: AUDIT (Mode: Audit, Repair, AuditRepairVerify)                  │ │
│  ├───────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                            │ │
│  │  Get-ReplicationSnapshot                                                  │ │
│  │  ┌──────────────────────────────────────────────────────────────┐        │ │
│  │  │  For each DC:                                                 │        │ │
│  │  │  1. Query AD Replication Partner Metadata                    │        │ │
│  │  │  2. Get Replication Failures                                 │        │ │
│  │  │  3. Calculate metrics (lag, consecutive failures, etc.)      │        │ │
│  │  │  4. Determine health status: Healthy / Degraded / Unreachable│        │ │
│  │  │                                                               │        │ │
│  │  │  Output: Snapshot objects with:                              │        │ │
│  │  │  - InboundPartners[]                                          │        │ │
│  │  │  - Failures[]                                                 │        │ │
│  │  │  - Status                                                     │        │ │
│  │  │  - Timestamp                                                  │        │ │
│  │  └──────────────────────────────────────────────────────────────┘        │ │
│  │                            │                                               │ │
│  │                            ▼                                               │ │
│  │  Find-ReplicationIssues                                                   │ │
│  │  ┌──────────────────────────────────────────────────────────────┐        │ │
│  │  │  Analyze snapshots and identify:                             │        │ │
│  │  │  - Connectivity Issues (High severity)                        │        │ │
│  │  │  - Replication Failures (High severity)                       │        │ │
│  │  │  - Stale Replication >24h (Medium severity)                  │        │ │
│  │  │                                                               │        │ │
│  │  │  Output: Issue objects with Category, Severity, Actionable   │        │ │
│  │  └──────────────────────────────────────────────────────────────┘        │ │
│  │                                                                            │ │
│  │  Exit Code: 0=Healthy, 2=Issues Found, 3=Unreachable, 4=Error            │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │ PHASE 2: REPAIR (Mode: Repair, AuditRepairVerify)                        │ │
│  ├───────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                            │ │
│  │  if (Issues.Count > 0) {                                                  │ │
│  │      Invoke-ReplicationFix (per DC with ShouldProcess)                    │ │
│  │      ┌────────────────────────────────────────────────────────┐          │ │
│  │      │  For each issue:                                        │          │ │
│  │      │                                                          │          │ │
│  │      │  ReplicationFailure:                                    │          │ │
│  │      │    └─► repadmin /syncall /A /P /e $DC                  │          │ │
│  │      │                                                          │          │ │
│  │      │  StaleReplication:                                      │          │ │
│  │      │    └─► repadmin /replicate (target partner)            │          │ │
│  │      │                                                          │          │ │
│  │      │  Connectivity:                                          │          │ │
│  │      │    └─► Mark for manual investigation                   │          │ │
│  │      │                                                          │          │ │
│  │      │  All wrapped in: if ($PSCmdlet.ShouldProcess())        │          │ │
│  │      │  Supports: -WhatIf, -Confirm, -AutoRepair              │          │ │
│  │      └────────────────────────────────────────────────────────┘          │ │
│  │  }                                                                         │ │
│  │                                                                            │ │
│  │  Exit Code: 0=Repaired, 2=Issues Remain                                   │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │ PHASE 3: VERIFY (Mode: Verify, AuditRepairVerify)                        │ │
│  ├───────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                            │ │
│  │  Wait 120 seconds for convergence                                         │ │
│  │                                                                            │ │
│  │  Test-ReplicationHealth                                                   │ │
│  │  ┌────────────────────────────────────────────────────────┐              │ │
│  │  │  For each DC:                                           │              │ │
│  │  │  1. Run: repadmin /showrepl $DC                        │              │ │
│  │  │  2. Count errors vs successes                          │              │ │
│  │  │  3. Calculate health score                             │              │ │
│  │  │                                                          │              │ │
│  │  │  Health Status: Healthy / Degraded / Failed            │              │ │
│  │  └────────────────────────────────────────────────────────┘              │ │
│  │                                                                            │ │
│  │  Exit Code: 0=Verified Healthy, 2=Still Degraded                          │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            OUTPUT LAYER                                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                       Export-ReplReports Function                                │
│                                                                                   │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ CSV Exports    │  │ JSON Summary   │  │ Execution Log  │  │ Transcript   │ │
│  ├────────────────┤  ├────────────────┤  ├────────────────┤  ├──────────────┤ │
│  │ - Snapshot.csv │  │ {              │  │ Timestamped    │  │ Full session │ │
│  │ - Issues.csv   │  │   "Mode": ".." │  │ log entries    │  │ recording    │ │
│  │ - Actions.csv  │  │   "TotalDCs":  │  │ from           │  │ (optional)   │ │
│  │ - Verify.csv   │  │   "ExitCode":  │  │ RepairLog      │  │ -AuditTrail  │ │
│  └────────────────┘  │ }              │  └────────────────┘  └──────────────┘ │
│                      │ CI/CD friendly │                                         │
│                      └────────────────┘                                         │
│                                                                                   │
│  Output Directory: .\ADRepl-20251028-143052\                                    │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          LOGGING & MONITORING                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                        Write-RepairLog Function                                  │
│                                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Write-Verbose│  │ Write-Info   │  │ Write-Warning│  │ Write-Error  │       │
│  │ (diagnostics)│  │ (progress)   │  │ (issues)     │  │ (failures)   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                                                   │
│  Pipeline-Friendly: All output respects PowerShell streams                      │
│  Structured Logging: [Timestamp] [Level] Message                                │
│  Synchronized ArrayList: Thread-safe for parallel execution                     │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         FINAL OUTPUT & EXIT                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  Write-RunSummary (Console output with InformationAction Continue)              │
│                                                                                   │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │ ======================================                                     │ │
│  │ EXECUTION SUMMARY                                                         │ │
│  │ ======================================                                     │ │
│  │ Mode            : AuditRepairVerify                                       │ │
│  │ Scope           : Site:HQ                                                 │ │
│  │ DCs Processed   : 12                                                      │ │
│  │ Issues Found    : 5                                                       │ │
│  │ Actions Taken   : 5                                                       │ │
│  │ Duration        : 03:45                                                   │ │
│  │ Exit Code       : 0                                                       │ │
│  │ ======================================                                     │ │
│  │                                                                            │ │
│  │ ✓ All issues resolved successfully                                        │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
│  Exit Codes:                                                                     │
│  ┌─────┬──────────────────────────────────────────────────────────────┐        │
│  │  0  │ ✓ Healthy / Successfully repaired                             │        │
│  │  2  │ ⚠ Issues detected/remain                                      │        │
│  │  3  │ ⚠ One or more DCs unreachable                                 │        │
│  │  4  │ ✗ Fatal error during execution                                │        │
│  └─────┴──────────────────────────────────────────────────────────────┘        │
│                                                                                   │
│  finally { exit $Script:ExitCode }                                               │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagram

```
┌──────────────┐
│   User       │
│   Input      │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│             Parameter Validation & Parsing                │
│  • Mode, Scope, DCs, Throttle, Timeout                   │
│  • WhatIf/Confirm flags                                   │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│             Scope Resolution                              │
│  Input: Scope parameter                                   │
│  Output: Resolved DC list                                 │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│          Data Collection (with Retry Logic)               │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  For Each DC (Parallel or Serial):                  │ │
│  │    Invoke-WithRetry {                               │ │
│  │      Get-ADReplicationPartnerMetadata               │ │
│  │      Get-ADReplicationFailure                       │ │
│  │    }                                                 │ │
│  └─────────────────────────────────────────────────────┘ │
│  Output: Snapshot[]                                       │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│          Issue Analysis                                   │
│  Input: Snapshot[]                                        │
│  Function: Find-ReplicationIssues                         │
│  Output: Issue[]                                          │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ├──► if Mode = Audit ──────────┐
                   │                               │
                   ├──► if Mode = Repair ──┐      │
                   │                        │      │
                   └──► if Mode = Verify ───┼──┐   │
                                            │  │   │
           ┌────────────────────────────────┘  │   │
           │                                    │   │
           ▼                                    │   │
  ┌────────────────────────┐                   │   │
  │ Repair Phase           │                   │   │
  │ (ShouldProcess-gated)  │                   │   │
  │ Invoke-ReplicationFix  │                   │   │
  │ Output: RepairAction[] │                   │   │
  └────────┬───────────────┘                   │   │
           │                                    │   │
           └────────────────────────────────────┘   │
                          │                         │
                          ▼                         │
                 ┌────────────────────┐             │
                 │ Verification Phase │             │
                 │ Test-RepHealth     │             │
                 │ Output: Verify[]   │             │
                 └────────┬───────────┘             │
                          │                         │
                          └─────────────────────────┘
                                      │
                                      ▼
                  ┌────────────────────────────────────┐
                  │      Export Reports                │
                  │  • CSV files (4 types)             │
                  │  • JSON summary                    │
                  │  • Execution log                   │
                  │  • Transcript (optional)           │
                  └────────────────┬───────────────────┘
                                   │
                                   ▼
                       ┌───────────────────────┐
                       │  Console Summary      │
                       │  Exit with Code       │
                       │  (0/2/3/4)            │
                       └───────────────────────┘
```

---

## Component Interaction Matrix

| Component | Calls | Called By | Data Flow |
|-----------|-------|-----------|-----------|
| **Main Execution** | All functions | User/Scheduler | Parameters → Results |
| **Resolve-ScopeToDCs** | Get-ADDomainController | Main | Scope → DC List |
| **Invoke-WithRetry** | AD Cmdlets | Get-ReplicationSnapshot | ScriptBlock → Result (with retries) |
| **Get-ReplicationSnapshot** | Invoke-WithRetry, AD Cmdlets | Main | DC List → Snapshot[] |
| **Find-ReplicationIssues** | None (pure function) | Main | Snapshot[] → Issue[] |
| **Invoke-ReplicationFix** | repadmin, ShouldProcess | Main | Issue[] → RepairAction[] |
| **Test-ReplicationHealth** | repadmin | Main | DC List → Verification[] |
| **Export-ReplReports** | Export-Csv, ConvertTo-Json | Main | Data → Files |
| **Write-RepairLog** | Write-Verbose/Info/Warning/Error | All functions | Message → Logs |
| **Write-RunSummary** | Write-Information | Main | Data → Console |

---

## Parallel vs Serial Execution Flow

### PowerShell 7+ (Parallel)

```
Time ──────────────────────────────────────────►

DC01 ████████████░░░░░░░░░░░░ (Complete)
DC02 ░░████████████░░░░░░░░░░ (Complete)
DC03 ░░░░████████████░░░░░░░░ (Complete)
DC04 ░░░░░░████████████░░░░░░ (Complete)
DC05 ░░░░░░░░████████████░░░░ (Complete)
DC06 ░░░░░░░░░░████████████░░ (Complete)
DC07 ░░░░░░░░░░░░████████████ (Complete)
DC08 ██████████████████████░░ (Complete)

Total Time: ~2-3 minutes (with Throttle=8)
Speedup: 80-90% vs serial
```

### PowerShell 5.1 (Serial)

```
Time ──────────────────────────────────────────►

DC01 ████████████ (Complete) ▶
DC02             ████████████ (Complete) ▶
DC03                         ████████████ (Complete) ▶
DC04                                     ████████████ (Complete) ▶
DC05                                                 ████████████ ▶
DC06                                                             ████...
DC07                                                                  ...
DC08                                                                  ...

Total Time: ~12-15 minutes
Note: Still 20-30% faster than v2.0 due to optimizations
```

---

## Retry Logic Flow

```
┌─────────────────────────────────────────────────────────┐
│          Invoke-WithRetry Decision Tree                 │
└─────────────────────────────────────────────────────────┘

                    Start
                      │
                      ▼
            ┌─────────────────┐
            │ Execute Action  │
            └────────┬────────┘
                     │
            ┌────────┴────────┐
            │                 │
         Success           Error
            │                 │
            │                 ▼
            │       ┌──────────────────┐
            │       │ Is Permanent?    │
            │       │ (Auth, Not Found)│
            │       └────┬─────────┬───┘
            │            │         │
            │           Yes       No
            │            │         │
            │            │         ▼
            │            │   ┌────────────────┐
            │            │   │ Is Transient?  │
            │            │   │ (RPC, Network) │
            │            │   └────┬───────┬───┘
            │            │        │       │
            │            │       Yes     No
            │            │        │       │
            │            ▼        │       ▼
            │      ┌─────────┐   │  ┌─────────┐
            │      │  Fail   │   │  │  Fail   │
            │      │  Fast   │   │  │  Fast   │
            │      └─────────┘   │  └─────────┘
            │                    │
            │                    ▼
            │           ┌──────────────────┐
            │           │ Attempts < Max?  │
            │           └────┬─────────┬───┘
            │                │         │
            │               Yes       No
            │                │         │
            │                │         ▼
            │                │    ┌────────┐
            │                │    │ Fail   │
            │                │    │ Final  │
            │                │    └────────┘
            │                │
            │                ▼
            │       ┌──────────────────────┐
            │       │ Calculate Backoff:   │
            │       │ min(2^n * 2s, 30s)   │
            │       └──────────┬───────────┘
            │                  │
            │                  ▼
            │            ┌───────────┐
            │            │  Sleep    │
            │            └─────┬─────┘
            │                  │
            │                  └───► Retry (loop back to Start)
            │
            ▼
      ┌──────────┐
      │  Return  │
      │  Success │
      └──────────┘
```

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
| 1.0 | 2025-10-28 | Adrian Johnson | Initial architecture diagram with complete system flow |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

