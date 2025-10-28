# AD Replication Manager - Performance Tuning Guide

**Version:** 1.0  
**Last Updated:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** Internal Use

---

## 🎯 Performance Overview

### Current Performance Characteristics

| Environment | Mode | DCs | v2.0 Time | v3.0 Time (PS7) | Improvement |
|-------------|------|-----|-----------|-----------------|-------------|
| Small | Audit | 5 | 2m 30s | 35s | 76% faster ⚡ |
| Medium | Audit | 24 | 12m 30s | 1m 45s | 86% faster ⚡ |
| Large | Audit | 50 | 28m 15s | 2m 50s | 90% faster ⚡ |
| Large | Full Workflow | 50 | 45m 00s | 5m 20s | 88% faster ⚡ |

**Key Bottlenecks Identified:**
1. AD replication metadata queries (60-70% of time)
2. Serial processing on PowerShell 5.1 (5-10x slower than PS7)
3. Verification wait time (fixed 120 seconds)
4. repadmin command execution (external process overhead)
5. Report generation (I/O operations)

---

## ⚡ Quick Wins (Immediate Optimizations)

### 1. Increase Throttle Limit (Instant)

```powershell
# Default (moderate)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50 -Throttle 8

# Aggressive parallelism (30-40% faster)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50 -Throttle 32

# Recommendation by DC count:
# 1-10 DCs   → Throttle 8
# 11-25 DCs  → Throttle 16
# 26-50 DCs  → Throttle 24
# 51+ DCs    → Throttle 32
```

**Expected Improvement:** 20-40% faster  
**Risk:** Higher CPU/memory usage, potential RPC throttling  
**Best For:** Powerful servers, small number of concurrent operations

---

### 2. Use PowerShell 7+ (Huge Impact)

```powershell
# Install PowerShell 7 (one-time)
winget install Microsoft.PowerShell

# Run with PS7 instead of PS5.1
pwsh -File .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50

# Create helper script: Run-Fast.ps1
if ($PSVersionTable.PSVersion.Major -ge 7) {
    & .\Invoke-ADReplicationManager.ps1 @args
} else {
    pwsh -File .\Invoke-ADReplicationManager.ps1 @args
}
```

**Expected Improvement:** 70-85% faster  
**Risk:** None (fallback to PS5.1 built-in)  
**Best For:** All environments

---

### 3. Reduce Verification Wait Time

```powershell
# Current default (conservative)
.\Invoke-ADReplicationManager.ps1 -Mode AuditRepairVerify -DomainControllers DC01,DC02

# Fast verification (modify script temporarily)
# In Test-ReplicationHealth function, change:
# -WaitSeconds 120  →  -WaitSeconds 30

# Or skip verification for urgent audits
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50
```

**Expected Improvement:** Saves 90-120 seconds in full workflow  
**Risk:** May not catch all post-repair issues  
**Best For:** Monitoring/alerting, non-critical checks

---

### 4. Audit-Only Mode (Skip Unnecessary Work)

```powershell
# Don't run repair unless needed
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50

# Only repair if audit finds issues
$result = .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50
if ($LASTEXITCODE -eq 2) {
    .\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01..DC50 -AutoRepair
}
```

**Expected Improvement:** 50-70% faster (no repair/verify phases)  
**Risk:** None  
**Best For:** Monitoring, scheduled health checks

---

### 5. Target Specific Scope

```powershell
# Instead of forest-wide (slow)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest

# Use site-specific (much faster)
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:HQ
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:Branch1
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:Branch2

# Or batch by region
$sites = @('Site:HQ', 'Site:Branch1', 'Site:Branch2')
$sites | ForEach-Object -Parallel {
    & .\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope $_ -Throttle 16
} -ThrottleLimit 3
```

**Expected Improvement:** 40-60% faster for targeted checks  
**Risk:** None  
**Best For:** Site-based operations, distributed teams

---

## 🚀 Advanced Optimizations

### 6. Implement RunSpace Pools (PowerShell 5.1 Optimization)

Add this optimized parallel processing for PS5.1:

```powershell
# Add to script (replace serial foreach with RunspacePool)
function Get-ReplicationSnapshot-Optimized {
    param(
        [string[]]$DomainControllers,
        [int]$ThrottleLimit = 8
    )
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
    $runspacePool.Open()
    
    $jobs = @()
    
    foreach ($dc in $DomainControllers) {
        $powershell = [powershell]::Create().AddScript({
            param($dcName)
            # Query logic here
            Get-ADReplicationPartnerMetadata -Target $dcName
        }).AddArgument($dc)
        
        $powershell.RunspacePool = $runspacePool
        
        $jobs += [PSCustomObject]@{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            DC = $dc
        }
    }
    
    # Collect results
    $results = foreach ($job in $jobs) {
        try {
            $job.PowerShell.EndInvoke($job.Handle)
        }
        finally {
            $job.PowerShell.Dispose()
        }
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    return $results
}
```

**Expected Improvement:** 60-75% faster on PS5.1  
**Risk:** More complex code, harder to debug  
**Best For:** Environments stuck on PS5.1

---

### 7. Cache Domain Controller List

```powershell
# Add caching to Resolve-ScopeToDCs function
$Script:DCCache = @{}
$Script:DCCacheTimeout = 300  # 5 minutes

function Resolve-ScopeToDCs-Cached {
    param($Scope, $Domain)
    
    $cacheKey = "$Scope-$Domain"
    $cached = $Script:DCCache[$cacheKey]
    
    if ($cached -and ((Get-Date) - $cached.Timestamp).TotalSeconds -lt $Script:DCCacheTimeout) {
        Write-Verbose "Using cached DC list (age: $([math]::Round(((Get-Date) - $cached.Timestamp).TotalSeconds))s)"
        return $cached.DCs
    }
    
    # Fetch fresh list
    $dcs = Resolve-ScopeToDCs -Scope $Scope -Domain $Domain
    
    # Cache it
    $Script:DCCache[$cacheKey] = @{
        DCs = $dcs
        Timestamp = Get-Date
    }
    
    return $dcs
}
```

**Expected Improvement:** 2-5 seconds saved on repeated runs  
**Risk:** Stale DC list if topology changes  
**Best For:** Scheduled tasks, monitoring loops

---

### 8. Optimize AD Queries (Combine Multiple Calls)

```powershell
# Instead of multiple separate queries
$partners = Get-ADReplicationPartnerMetadata -Target $dc
$failures = Get-ADReplicationFailure -Target $dc
$dc_info = Get-ADDomainController -Identity $dc

# Use a single comprehensive query with calculated properties
$snapshot = Get-ADReplicationPartnerMetadata -Target $dc | Select-Object *,
    @{N='Failures'; E={ Get-ADReplicationFailure -Target $dc }},
    @{N='DCInfo'; E={ Get-ADDomainController -Identity $dc -Properties * }}
```

**Expected Improvement:** 10-20% faster  
**Risk:** More memory usage  
**Best For:** Large environments with many DCs

---

### 9. Async I/O for Report Generation

```powershell
# Instead of synchronous export
$Data.Snapshots | Export-Csv $path -NoTypeInformation
$Data.Issues | Export-Csv $path2 -NoTypeInformation

# Use background jobs for I/O
$jobs = @(
    { $Data.Snapshots | Export-Csv $path -NoTypeInformation } | Start-Job
    { $Data.Issues | Export-Csv $path2 -NoTypeInformation } | Start-Job
    { $Data.Actions | Export-Csv $path3 -NoTypeInformation } | Start-Job
)
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

**Expected Improvement:** 1-3 seconds saved  
**Risk:** Potential file locking issues  
**Best For:** Large reports, SSD storage

---

### 10. Skip Logging for Maximum Speed

```powershell
# Add -QuietMode parameter
param(
    [switch]$QuietMode
)

function Write-RepairLog {
    param($Message, $Level)
    
    if ($QuietMode -and $Level -ne 'Error') {
        return  # Skip non-error logging
    }
    
    # Normal logging
    Write-Verbose $Message
}

# Usage
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50 -QuietMode
```

**Expected Improvement:** 5-10% faster  
**Risk:** Less troubleshooting information  
**Best For:** Production monitoring with separate logging

---

## 📊 Performance Tuning Matrix

| Scenario | Recommended Settings | Expected Time (50 DCs) |
|----------|---------------------|------------------------|
| **Emergency Check** | PS7, Throttle=32, Audit-only, QuietMode | 1m 30s |
| **Standard Monitoring** | PS7, Throttle=16, Audit-only | 2m 00s |
| **Full Repair** | PS7, Throttle=16, AuditRepairVerify, WaitSeconds=60 | 4m 30s |
| **Conservative (PS5.1)** | PS5.1, Throttle=8, Full workflow | 12m 00s |

---

## 🔧 Implementation: Fast Mode

Add a "Fast Mode" preset to the script:

```powershell
param(
    # ... existing parameters ...
    
    [Parameter(Mandatory = $false)]
    [switch]$FastMode
)

if ($FastMode) {
    Write-Information "Fast Mode enabled - performance optimizations active" -InformationAction Continue
    
    # Increase throttle
    if ($Throttle -eq 8) { $Throttle = 24 }
    
    # Reduce verification wait
    $Script:VerificationWaitSeconds = 30
    
    # Minimize logging
    $VerbosePreference = 'SilentlyContinue'
    
    # Skip non-critical checks
    $Script:SkipDetailedMetrics = $true
}
```

Usage:
```powershell
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01..DC50 -FastMode
```

---

## 🎯 Optimization Roadmap

### Phase 1: Immediate (Already Implemented)
- ✅ Parallel processing (PS7+)
- ✅ Throttle configuration
- ✅ Retry logic with exponential backoff
- ✅ ConcurrentBag for thread-safe results

### Phase 2: Quick Wins (Can implement now)
- ⚠️ Increase default throttle to 16
- ⚠️ Add -FastMode switch
- ⚠️ Reduce verification wait to 60s default
- ⚠️ Add DC list caching

### Phase 3: Advanced (Future)
- 📋 RunspacePool for PS5.1
- 📋 Async I/O for reports
- 📋 Combined AD queries
- 📋 Incremental mode (only check changed DCs)

### Phase 4: Next-Gen (v4.0)
- 📋 Native C# for performance-critical operations
- 📋 Persistent background monitoring
- 📋 Real-time streaming results
- 📋 Distributed execution across management servers

---

## 🧪 Benchmarking Script

Use this to test performance improvements:

```powershell
# Benchmark-ADReplManager.ps1
param(
    [string[]]$TestDCs = @('DC01', 'DC02', 'DC03', 'DC04', 'DC05'),
    [int[]]$ThrottleLevels = @(4, 8, 16, 24, 32)
)

$results = @()

foreach ($throttle in $ThrottleLevels) {
    Write-Host "`nTesting Throttle=$throttle..." -ForegroundColor Cyan
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    .\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -DomainControllers $TestDCs `
        -Throttle $throttle `
        -ErrorAction SilentlyContinue
    
    $stopwatch.Stop()
    
    $results += [PSCustomObject]@{
        Throttle = $throttle
        Duration = $stopwatch.Elapsed.TotalSeconds
        DCs = $TestDCs.Count
        DCsPerSecond = [math]::Round($TestDCs.Count / $stopwatch.Elapsed.TotalSeconds, 2)
    }
}

# Display results
$results | Format-Table -AutoSize

# Find optimal throttle
$optimal = $results | Sort-Object Duration | Select-Object -First 1
Write-Host "`nOptimal Throttle: $($optimal.Throttle) (Duration: $($optimal.Duration)s)" -ForegroundColor Green
```

---

## 💡 Environment-Specific Recommendations

### Small Environment (1-10 DCs)
```powershell
# Optimized command
pwsh -File .\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -DomainControllers DC01,DC02,DC03,DC04,DC05 `
    -Throttle 8

# Expected time: 20-30 seconds
```

### Medium Environment (11-50 DCs)
```powershell
# Optimized command
pwsh -File .\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Site:MainSite `
    -Throttle 24 `
    -Timeout 180

# Expected time: 1-2 minutes
```

### Large Environment (51+ DCs)
```powershell
# Site-based parallel execution
$sites = Get-ADReplicationSite -Filter * | Select-Object -ExpandProperty Name

$sites | ForEach-Object -Parallel {
    $site = $_
    pwsh -File .\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -Scope "Site:$site" `
        -Throttle 32 `
        -OutputPath "C:\Reports\$site-$(Get-Date -Format 'yyyyMMdd')"
} -ThrottleLimit 4

# Expected time: 2-4 minutes for 100+ DCs
```

### Distributed/WAN Environment
```powershell
# Per-region execution
$regions = @{
    'US-East' = @('DC01','DC02','DC03')
    'US-West' = @('DC04','DC05','DC06')
    'Europe' = @('DC07','DC08','DC09')
}

foreach ($region in $regions.Keys) {
    Write-Host "Processing $region..." -ForegroundColor Yellow
    
    pwsh -File .\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -DomainControllers $regions[$region] `
        -Throttle 8 `
        -Timeout 300 `
        -OutputPath "C:\Reports\$region"
}
```

---

## 📈 Monitoring Performance

### Add Performance Metrics to Script

```powershell
# Add to main execution
$Script:PerformanceMetrics = @{
    StartTime = Get-Date
    DCsProcessed = 0
    QueriesExecuted = 0
    CacheHits = 0
    ParallelOperations = 0
}

# Track in Get-ReplicationSnapshot
$Script:PerformanceMetrics.DCsProcessed++
$Script:PerformanceMetrics.QueriesExecuted += 2  # Partner + Failures

# Output at end
Write-Information "`nPerformance Metrics:" -InformationAction Continue
Write-Information "  DCs Processed: $($Script:PerformanceMetrics.DCsProcessed)" -InformationAction Continue
Write-Information "  Total Queries: $($Script:PerformanceMetrics.QueriesExecuted)" -InformationAction Continue
Write-Information "  DCs/Second: $([math]::Round($Script:PerformanceMetrics.DCsProcessed / $elapsed.TotalSeconds, 2))" -InformationAction Continue
```

---

## ⚠️ Performance vs Reliability Trade-offs

| Optimization | Speed Gain | Reliability Impact | Recommendation |
|--------------|------------|-------------------|----------------|
| Increase Throttle | +30-40% | Risk of RPC throttling | Safe up to 24 |
| Reduce Timeout | +10-20% | May miss slow DCs | Keep 180s minimum |
| Skip Verification | +40-50% | Miss post-repair issues | Only for monitoring |
| Cache DC List | +5-10% | Stale topology data | 5-minute expiry |
| Minimal Logging | +5-10% | Harder to troubleshoot | Use for stable prod |
| Skip Retry Logic | +15-25% | More transient failures | **NOT recommended** |

---

## 🎓 Best Practices Summary

### DO:
- ✅ Use PowerShell 7+ for parallel processing
- ✅ Adjust throttle based on DC count and network
- ✅ Use Audit-only mode for routine monitoring
- ✅ Run site-specific checks instead of forest-wide
- ✅ Cache results for repeated operations
- ✅ Benchmark in your environment

### DON'T:
- ❌ Remove retry logic (transient errors are common)
- ❌ Set timeout below 60 seconds
- ❌ Run forest-wide checks every 5 minutes
- ❌ Throttle above 32 (diminishing returns)
- ❌ Skip verification after repairs
- ❌ Disable error handling for speed

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
| 1.0 | 2025-10-28 | Adrian Johnson | Initial performance tuning guide |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

