# Active Directory Replication Manager v3.0
## Troubleshooting Guide

**Document Version:** 1.0  
**Last Updated:** October 18, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Status:** Final  
**Classification:** Internal Use

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Diagnostic Framework](#2-diagnostic-framework)
3. [Common Issues](#3-common-issues)
4. [AD Replication Error Codes](#4-ad-replication-error-codes)
5. [Script Execution Problems](#5-script-execution-problems)
6. [Performance Issues](#6-performance-issues)
7. [Integration Problems](#7-integration-problems)
8. [Advanced Diagnostics](#8-advanced-diagnostics)
9. [Escalation Procedures](#9-escalation-procedures)

---

## 1. Introduction

### 1.1 Purpose

This guide provides systematic troubleshooting procedures for resolving issues with the Active Directory Replication Manager (ADRM) v3.0. It covers both script-related problems and underlying AD replication issues.

### 1.2 Using This Guide

**Quick Reference:**
- Known issue? Jump to §3 (Common Issues)
- AD error code? See §4 (Error Codes)
- Script won't run? Check §5 (Execution Problems)
- Running slow? Review §6 (Performance)

**Systematic Approach:**
1. Follow diagnostic framework (§2)
2. Identify symptoms
3. Apply targeted solution
4. Verify resolution
5. Document for knowledge base

### 1.3 Prerequisites

Before troubleshooting, verify:
- [ ] PowerShell 5.1 or 7.x installed
- [ ] Active Directory module available
- [ ] Domain Admin permissions
- [ ] Network connectivity to DCs
- [ ] Latest script version deployed

---

## 2. Diagnostic Framework

### 2.1 Triage Process

```
┌─────────────────────┐
│ Issue Reported      │
└──────┬──────────────┘
       │
       ├─> Can script execute? ──No──> §5 (Execution Problems)
       │         │
       │        Yes
       │         │
       ├─> Getting exit code? ──No──> §5.2 (Fatal Errors)
       │         │
       │        Yes
       │         │
       ├─> Exit code 0? ─────Yes──> No issue (false alarm)
       │         │
       │         No
       │         │
       ├─> Exit code 2? ─────Yes──> §3.1 (Replication Issues)
       │         │
       ├─> Exit code 3? ─────Yes──> §3.2 (Connectivity Issues)
       │         │
       └─> Exit code 4? ─────Yes──> §5.2 (Script Errors)
```

### 2.2 Information Gathering

**Always collect:**

```powershell
# System Information
$PSVersionTable
Get-Module -ListAvailable ActiveDirectory
[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() | 
    Select-Object @{N='IsAdmin';E={$_.IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")}}

# Script Information
Get-Item C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 | Select-Object FullName, Length, LastWriteTime

# Recent Execution
$latest = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content "$($latest.FullName)\summary.json" | ConvertFrom-Json | Format-List
Get-Content "$($latest.FullName)\execution.log" | Select-Object -Last 50
```

### 2.3 Diagnostic Commands

```powershell
# Quick Health Check
C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -Verbose

# Detailed Replication Status
repadmin /showrepl * /csv | ConvertFrom-Csv | 
    Where-Object { $_.'Number of Failures' -gt 0 } | 
    Format-Table 'Source DSA', 'Naming Context', 'Number of Failures', 'Last Failure Status'

# Network Connectivity
$dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
$dcs | ForEach-Object {
    [PSCustomObject]@{
        DC = $_
        Ping = Test-Connection -ComputerName $_ -Count 2 -Quiet
        RPC = Test-NetConnection -ComputerName $_ -Port 135 -InformationLevel Quiet
        SMB = Test-NetConnection -ComputerName $_ -Port 445 -InformationLevel Quiet
    }
} | Format-Table -AutoSize
```

---

## 3. Common Issues

### 3.1 Issue: Replication Failures Detected (Exit Code 2)

**Symptoms:**
- Script completes but exits with code 2
- CSV shows issues in IdentifiedIssues.csv
- Some DCs marked as "Degraded"

#### 3.1.1 Diagnosis

```powershell
# Review issues
$latest = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$issues = Import-Csv "$($latest.FullName)\IdentifiedIssues.csv"

# Group by error code
$issues | Group-Object ErrorCode | Sort-Object Count -Descending | 
    Select-Object Count, Name, @{N='Sample';E={$_.Group[0].Description}}
```

#### 3.1.2 Resolution by Error Pattern

**Error Code 1722 (RPC Server Unavailable)**

**Cause:** Network connectivity or firewall blocking RPC

**Solution:**
```powershell
# Test RPC connectivity
$dc = "DC01.domain.com"
Test-NetConnection -ComputerName $dc -Port 135

# If blocked, check Windows Firewall
Invoke-Command -ComputerName $dc -ScriptBlock {
    Get-NetFirewallRule -DisplayName "*Remote Procedure Call*" | 
        Where-Object Enabled -eq 'True'
}

# Resolution: Open required ports
# - TCP 135 (RPC Endpoint Mapper)
# - TCP 445 (SMB)
# - Dynamic RPC: TCP 49152-65535 (Windows Server 2008+)
```

**Error Code 8453 (Replication Access Denied)**

**Cause:** Permission issues or Kerberos authentication failure

**Solution:**
```powershell
# Reset secure channel
$dc = "DC01.domain.com"
Invoke-Command -ComputerName $dc -ScriptBlock {
    nltest /sc_reset:$env:USERDOMAIN
}

# Verify Kerberos tickets
klist purge
klist get krbtgt

# Check replication permissions
repadmin /showattr $dc "cn=configuration,dc=domain,dc=com" /filter:"(objectClass=nTDSDSA)" /atts:objectGuid
```

**Error Code 8524 (DNS Lookup Failure)**

**Cause:** DNS resolution problems

**Solution:**
```powershell
# Test DNS resolution
$dc = "DC01.domain.com"
Resolve-DnsName $dc

# Check SRV records
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.domain.com" -Type SRV

# Verify DNS server configuration
Get-DnsClientServerAddress | Where-Object InterfaceAlias -like "Ethernet*"

# Resolution: Fix DNS
# 1. Verify DCs point to correct DNS servers
# 2. Check DNS zone replication
# 3. Manually register SRV records if needed: nltest /dsregdns
```

**Stale Replication (No Error Code)**

**Cause:** Replication hasn't occurred for >24 hours but no active errors

**Solution:**
```powershell
# Force immediate replication
$sourceDC = "DC01.domain.com"
$targetDC = "DC02.domain.com"

# Replicate all partitions
repadmin /syncall /A /P /e $sourceDC

# Or specific partition
$partition = "DC=domain,DC=com"
repadmin /replicate $targetDC $sourceDC $partition

# Verify
repadmin /showrepl $targetDC
```

---

### 3.2 Issue: Domain Controllers Unreachable (Exit Code 3)

**Symptoms:**
- Script completes but exits with code 3
- One or more DCs show Status='Unreachable'
- Connectivity category issues in CSV

#### 3.2.1 Triage

```powershell
# Identify unreachable DCs
$issues = Import-Csv "$($latest.FullName)\IdentifiedIssues.csv"
$unreachable = $issues | Where-Object Category -eq 'Connectivity' | Select-Object -ExpandProperty DC -Unique

# Quick connectivity test
foreach ($dc in $unreachable) {
    Write-Host "`nTesting $dc..." -ForegroundColor Yellow
    
    $ping = Test-Connection -ComputerName $dc -Count 2 -Quiet
    $rdp = Test-NetConnection -ComputerName $dc -Port 3389 -InformationLevel Quiet -WarningAction SilentlyContinue
    $rpc = Test-NetConnection -ComputerName $dc -Port 135 -InformationLevel Quiet -WarningAction SilentlyContinue
    
    [PSCustomObject]@{
        DC = $dc
        Ping = $ping
        RDP = $rdp
        RPC = $rpc
        Diagnosis = if (-not $ping) { "DC offline or network issue" }
                    elseif (-not $rpc) { "Firewall blocking RPC" }
                    elseif (-not $rdp) { "RDP service issue" }
                    else { "AD service issue" }
    } | Format-List
}
```

#### 3.2.2 Resolution by Diagnosis

**DC Offline**

```powershell
# Check DC status via virtualization platform
# VMware example:
Get-VM -Name "DC01" | Select-Object Name, PowerState

# If powered off, start DC
Start-VM -Name "DC01"

# Verify services after boot
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Get-Service -Name NTDS, DNS, Netlogon | Select-Object Name, Status, StartType
}
```

**Firewall Blocking**

```powershell
# Check Windows Firewall status
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Get-NetFirewallProfile | Select-Object Name, Enabled
}

# If enabled, verify required rules exist
Invoke-Command -ComputerName DC01 -ScriptBlock {
    $requiredRules = @(
        "*Active Directory Domain Controller*",
        "*RPC*",
        "*File and Printer Sharing*"
    )
    
    foreach ($rule in $requiredRules) {
        Get-NetFirewallRule -DisplayName $rule | 
            Where-Object Enabled -eq 'True' | 
            Select-Object DisplayName, Enabled
    }
}

# If rules disabled/missing, enable:
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Enable-NetFirewallRule -DisplayGroup "Active Directory Domain Controller"
}
```

**AD Service Stopped**

```powershell
# Check AD DS service
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Get-Service -Name NTDS | Format-List Name, Status, StartType
}

# Start service if stopped
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Start-Service -Name NTDS
    
    # Verify
    Start-Sleep -Seconds 30
    Get-Service -Name NTDS, DNS, Netlogon | Select-Object Name, Status
}

# Check Event Logs for errors
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Get-EventLog -LogName "Directory Service" -Newest 20 -EntryType Error, Warning
}
```

---

### 3.3 Issue: Script Execution Fails (Exit Code 4)

**Symptoms:**
- Script terminates abnormally
- Exit code 4
- Error message in execution log

#### 3.3.1 Common Causes

**Module Not Found**

```
Error: Failed to load ActiveDirectory module
```

**Solution:**
```powershell
# Check if module available
Get-Module -ListAvailable ActiveDirectory

# If missing, install RSAT
# Windows Server:
Install-WindowsFeature -Name RSAT-AD-PowerShell

# Windows Client (Admin PowerShell):
Get-WindowsCapability -Name RSAT.ActiveDirectory.DS-LDS.Tools* -Online | Add-WindowsCapability -Online

# Verify
Import-Module ActiveDirectory
Get-Command -Module ActiveDirectory
```

**Access Denied**

```
Error: Access is denied. Check Domain Admin permissions.
```

**Solution:**
```powershell
# Verify current user
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current User: $currentUser"

# Check Domain Admin membership
$user = Get-ADUser -Identity $env:USERNAME -Properties MemberOf
$isDomainAdmin = $user.MemberOf -match 'CN=Domain Admins'

if (-not $isDomainAdmin) {
    Write-Error "Current user is not a Domain Admin"
    # Run script with appropriate credentials
    $cred = Get-Credential
    Start-Process PowerShell -Credential $cred -ArgumentList "-File C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1"
}
```

**Parameter Validation Failed**

```
Error: Cannot validate argument on parameter 'Mode'
```

**Solution:**
```powershell
# Check parameter syntax
# Valid values:
-Mode Audit              # Correct
-Mode "audit"            # Case-insensitive OK
-Mode InvalidMode        # WRONG - will fail

# Valid scopes:
-Scope DCList            # Correct
-Scope Site:HQ           # Correct (site name required)
-Scope Forest            # Correct
-Scope Site:             # WRONG - site name missing

# Throttle range:
-Throttle 8              # Correct (1-32)
-Throttle 100            # WRONG - out of range
```

---

### 3.4 Issue: Performance Degradation

**Symptoms:**
- Execution time significantly longer than baseline
- Script appears "hung"
- High CPU/memory usage

#### 3.4.1 Diagnosis

```powershell
# Baseline execution times (typical)
<#
Environment     | Typical Time
----------------|--------------
10 DCs, PS7     | 45 seconds
10 DCs, PS5.1   | 2 minutes
50 DCs, PS7     | 2 minutes
50 DCs, PS5.1   | 15 minutes
#>

# Check recent execution times
Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 10 | 
    ForEach-Object {
        $summary = Get-Content "$($_.FullName)\summary.json" | ConvertFrom-Json
        [PSCustomObject]@{
            Date = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            ExecutionTime = $summary.ExecutionTime
            Mode = $summary.Mode
            DCs = $summary.TotalDCs
        }
    } | Format-Table -AutoSize
```

#### 3.4.2 Resolution

**Use PowerShell 7 for Parallelism**

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# If 5.1, upgrade to PS7
# Download from: https://github.com/PowerShell/PowerShell/releases

# After upgrade, use pwsh.exe
pwsh -File C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:HQ
```

**Adjust Throttle**

```powershell
# Too high throttle can cause RPC limits
# Default: 8
# Try reducing if timeouts occur:
-Throttle 4

# Or increase for more parallelism (if network allows):
-Throttle 16
```

**Increase Timeout for WAN**

```powershell
# Default timeout: 300 seconds
# For slow WAN links:
-Timeout 600

# For very slow/high-latency connections:
-Timeout 1200
```

**Process Site-by-Site**

```powershell
# Instead of forest-wide, process per site
$sites = Get-ADReplicationSite -Filter * | Select-Object -ExpandProperty Name

foreach ($site in $sites) {
    Write-Host "Processing site: $site" -ForegroundColor Cyan
    
    C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -Scope "Site:$site" `
        -OutputPath "C:\Reports\ADReplication\$site"
}
```

---

## 4. AD Replication Error Codes

### 4.1 Error Code Reference

| Code | Hex | Description | Resolution |
|------|-----|-------------|------------|
| **0** | 0x0 | Success | No action |
| **5** | 0x5 | Access Denied | Check permissions, Kerberos |
| **58** | 0x3a | Server cannot perform operation | Restart Netlogon service |
| **1256** | 0x4e8 | Remote system unavailable | Check network connectivity |
| **1722** | 0x6ba | RPC server unavailable | Check firewall, RPC service |
| **1753** | 0x6d9 | No endpoints available | Check RPC endpoint mapper |
| **2146893022** | 0x80090322 | Target principal name incorrect | Reset secure channel, check DNS |
| **8439** | 0x20f7 | Invalid distinguished name | Verify partition DN syntax |
| **8453** | 0x2105 | Replication access denied | Grant replication permissions |
| **8524** | 0x214c | DNS lookup failure | Fix DNS, register SRV records |

### 4.2 Error Code Deep Dive

#### Error 1722 (RPC Server Unavailable)

**Full Analysis:**

```powershell
# Detailed RPC diagnostics
$dc = "DC01.domain.com"

# 1. Ping test
Test-Connection -ComputerName $dc -Count 4

# 2. Port tests
$ports = @(135, 445, 389, 636, 3268, 3269, 88, 53)
$ports | ForEach-Object {
    $result = Test-NetConnection -ComputerName $dc -Port $_ -InformationLevel Quiet -WarningAction SilentlyContinue
    [PSCustomObject]@{
        Port = $_
        Open = $result
        Service = switch ($_) {
            135 { "RPC Endpoint Mapper" }
            445 { "SMB/CIFS" }
            389 { "LDAP" }
            636 { "LDAPS" }
            3268 { "Global Catalog" }
            3269 { "Global Catalog SSL" }
            88 { "Kerberos" }
            53 { "DNS" }
        }
    }
} | Format-Table -AutoSize

# 3. Check RPC service
Invoke-Command -ComputerName $dc -ScriptBlock {
    Get-Service -Name RpcSs, RpcEptMapper | Select-Object Name, Status, StartType
}

# 4. Verify firewall
Invoke-Command -ComputerName $dc -ScriptBlock {
    $profiles = Get-NetFirewallProfile
    $profiles | Select-Object Name, Enabled
    
    if ($profiles.Enabled -contains $true) {
        Get-NetFirewallRule -DisplayGroup "Active Directory Domain Controller" | 
            Select-Object DisplayName, Enabled, Direction | 
            Format-Table -AutoSize
    }
}
```

**Resolution Steps:**

1. **Verify RPC Service Running**
   ```powershell
   Invoke-Command -ComputerName $dc -ScriptBlock {
       Start-Service -Name RpcSs -ErrorAction SilentlyContinue
       Start-Service -Name RpcEptMapper -ErrorAction SilentlyContinue
   }
   ```

2. **Configure Firewall**
   ```powershell
   # Enable AD Domain Controller firewall rules
   Invoke-Command -ComputerName $dc -ScriptBlock {
       Enable-NetFirewallRule -DisplayGroup "Active Directory Domain Controller"
       Enable-NetFirewallRule -DisplayGroup "RPC"
       Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
   }
   ```

3. **Test Replication**
   ```powershell
   repadmin /replicate DC02.domain.com DC01.domain.com "DC=domain,DC=com"
   ```

#### Error 8453 (Replication Access Denied)

**Full Analysis:**

```powershell
# Check replication permissions
$dc = "DC01.domain.com"
$configNC = (Get-ADRootDSE).configurationNamingContext

# Verify NTDS Settings object
$ntdsSettings = Get-ADObject -Filter {objectClass -eq 'nTDSDSA'} -SearchBase "CN=Sites,$configNC" -Properties objectGUID | 
    Where-Object {$_.DistinguishedName -match $dc.Split('.')[0]}

if ($ntdsSettings) {
    Write-Host "NTDS Settings found: $($ntdsSettings.DistinguishedName)"
} else {
    Write-Error "NTDS Settings not found for $dc"
}

# Check replication rights
$acl = Get-Acl "AD:\$($ntdsSettings.DistinguishedName)"
$acl.Access | Where-Object {$_.ActiveDirectoryRights -match 'Replicat'} | 
    Select-Object IdentityReference, ActiveDirectoryRights, AccessControlType
```

**Resolution Steps:**

1. **Reset Secure Channel**
   ```powershell
   Invoke-Command -ComputerName $dc -ScriptBlock {
       nltest /sc_reset:$env:USERDOMAIN
   }
   ```

2. **Check Time Sync**
   ```powershell
   # Time skew can cause Kerberos auth failures
   Invoke-Command -ComputerName $dc -ScriptBlock {
       w32tm /query /status
   }
   
   # If time is off, sync:
   Invoke-Command -ComputerName $dc -ScriptBlock {
       w32tm /resync /force
   }
   ```

3. **Verify SPN Registration**
   ```powershell
   # Check DC SPNs
   setspn -L $dc.Split('.')[0]
   
   # Should include:
   # - ldap/<DC FQDN>
   # - E3514235-4B06-11D1-AB04-00C04FC2DCD2/<DC GUID>/<domain FQDN>
   # - HOST/<DC NetBIOS>
   ```

---

## 5. Script Execution Problems

### 5.1 Script Won't Start

**Issue:** Double-clicking script does nothing

**Cause:** Execution policy or file association

**Solution:**
```powershell
# Check execution policy
Get-ExecutionPolicy

# If Restricted, change:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

# Run from PowerShell console
cd C:\Scripts\ADReplicationManager
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02
```

---

### 5.2 Fatal Errors During Execution

**Issue:** Script terminates with exit code 4

**Diagnostic Steps:**

```powershell
# 1. Review execution log
$latest = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content "$($latest.FullName)\execution.log" | Select-String -Pattern '\[Error\]' -Context 2,5

# 2. Check transcript (if -AuditTrail was used)
$transcript = Get-ChildItem "$($latest.FullName)" -Filter "transcript-*.log"
if ($transcript) {
    Get-Content $transcript.FullName | Select-Object -Last 100
}

# 3. Verify prerequisites
Get-Module -ListAvailable ActiveDirectory
[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() | 
    Select-Object @{N='IsAdmin';E={$_.IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")}}
```

---

## 6. Performance Issues

### 6.1 Slow Parallel Processing

**Issue:** PowerShell 7 parallel mode slower than expected

**Diagnosis:**
```powershell
# Check if actually using PS7
$PSVersionTable.PSVersion
# Should be 7.x

# Check throttle setting
# Too high = RPC throttling
# Too low = underutilization

# Optimal: 8-16 for most environments
```

**Solution:**
```powershell
# Adjust throttle based on environment
# Start with 8, increase if no timeouts:
-Throttle 8   # Conservative
-Throttle 16  # Aggressive

# If timeouts occur, reduce:
-Throttle 4
```

---

### 6.2 High Memory Usage

**Issue:** Script consuming >1 GB RAM

**Diagnosis:**
```powershell
# Monitor during execution
while ($true) {
    $process = Get-Process -Name pwsh | Where-Object {$_.CommandLine -like "*ADReplicationManager*"}
    if ($process) {
        [PSCustomObject]@{
            Time = Get-Date -Format "HH:mm:ss"
            MemoryMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
        }
    }
    Start-Sleep -Seconds 5
}
```

**Solution:**
```powershell
# Process site-by-site instead of forest-wide
$sites = Get-ADReplicationSite -Filter * | Select-Object -ExpandProperty Name

foreach ($site in $sites) {
    # Each site processed in isolation (memory released between)
    C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -Scope "Site:$site"
}
```

---

## 7. Integration Problems

### 7.1 Scheduled Task Fails

**Issue:** Task shows "Last Result: 0x1" (error)

**Diagnosis:**
```powershell
# Get task details
$task = Get-ScheduledTask -TaskName "AD Replication Daily Audit"
$task | Select-Object TaskName, State, LastRunTime, LastTaskResult

# Check task history
Get-ScheduledTaskInfo -TaskName "AD Replication Daily Audit" | Format-List

# View task execution log
$taskLog = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-TaskScheduler/Operational'
    ID = 201  # Task executed
} -MaxEvents 10

$taskLog | Where-Object {$_.Message -like "*AD Replication*"}
```

**Common Solutions:**

**Solution 1: Wrong Execution Policy**
```powershell
# Modify task action to include bypass:
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\ADReplicationManager\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:HQ"

Set-ScheduledTask -TaskName "AD Replication Daily Audit" -Action $action
```

**Solution 2: Service Account Permissions**
```powershell
# Verify service account
$principal = (Get-ScheduledTask -TaskName "AD Replication Daily Audit").Principal
Write-Host "Running as: $($principal.UserId)"

# Check Domain Admin membership
Get-ADUser -Identity $principal.UserId -Properties MemberOf | 
    Select-Object -ExpandProperty MemberOf | 
    Where-Object {$_ -match 'Domain Admins'}
```

---

### 7.2 CI/CD Pipeline Integration

**Issue:** JSON parsing fails in pipeline

**Diagnosis:**
```powershell
# Test JSON validity
$summary = Get-Content C:\Reports\ADReplication\ADRepl-latest\summary.json
try {
    $summary | ConvertFrom-Json | Format-List
    Write-Host "JSON valid" -ForegroundColor Green
} catch {
    Write-Error "JSON invalid: $_"
    Write-Host "Raw content:"
    $summary
}
```

**Solution:**
```powershell
# Robust pipeline parsing
$summaryPath = "C:\Reports\ADReplication\ADRepl-latest\summary.json"

if (Test-Path $summaryPath) {
    try {
        $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
        
        # Validate required properties
        $requiredProps = @('ExitCode', 'TotalDCs', 'HealthyDCs', 'Mode')
        $missing = $requiredProps | Where-Object {-not ($summary.PSObject.Properties.Name -contains $_)}
        
        if ($missing.Count -gt 0) {
            throw "Missing properties: $($missing -join ', ')"
        }
        
        # Use in pipeline
        switch ($summary.ExitCode) {
            0 { Write-Host "##vso[task.complete result=Succeeded]All DCs healthy" }
            2 { Write-Warning "##vso[task.complete result=SucceededWithIssues]Issues detected" }
            3 { Write-Error "##vso[task.complete result=Failed]DCs unreachable"; exit 1 }
            4 { Write-Error "##vso[task.complete result=Failed]Script error"; exit 1 }
        }
    }
    catch {
        Write-Error "Failed to process summary: $_"
        exit 1
    }
} else {
    Write-Error "Summary not found: $summaryPath"
    exit 1
}
```

---

## 8. Advanced Diagnostics

### 8.1 Deep Replication Analysis

```powershell
# Comprehensive replication report
$dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName

$fullReport = $dcs | ForEach-Object {
    $dc = $_
    
    # Repadmin data
    $showrepl = & repadmin /showrepl $dc /csv | ConvertFrom-Csv
    $queue = & repadmin /queue $dc
    
    # Partner metadata
    $partners = Get-ADReplicationPartnerMetadata -Target $dc -ErrorAction SilentlyContinue
    
    [PSCustomObject]@{
        DC = $dc
        InboundPartners = $partners.Count
        Failures = ($showrepl | Where-Object {$_.'Number of Failures' -gt 0}).Count
        QueueDepth = if ($queue -match '(\d+) operations') {$Matches[1]} else {0}
        LastSuccess = ($partners | Measure-Object -Property LastReplicationSuccess -Maximum).Maximum
    }
}

$fullReport | Format-Table -AutoSize
$fullReport | Export-Csv "C:\Reports\DeepReplicationAnalysis-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation
```

### 8.2 Network Trace

```powershell
# Capture network traffic during replication
# Run on source DC
netsh trace start capture=yes tracefile=C:\Temp\repl-trace.etl maxsize=500 overwrite=yes

# Trigger replication
repadmin /replicate DC02 DC01 "DC=domain,DC=com"

# Stop trace
netsh trace stop

# Convert to text (requires Message Analyzer or Network Monitor)
# Or analyze .etl file with Event Viewer
```

### 8.3 Verbose Repadmin Diagnostics

```powershell
# Detailed replication status
repadmin /showrepl DC01 /verbose /all

# Connection objects
repadmin /showconn DC01

# Replication metadata
repadmin /showmeta "DC=domain,DC=com" /guid

# KCC (Knowledge Consistency Checker) status
repadmin /kcc DC01 /async

# Bridgehead servers
repadmin /bridgeheads

# Site links
repadmin /viewlist *
```

---

## 9. Escalation Procedures

### 9.1 When to Escalate

| Condition | Escalation Level | Contact |
|-----------|------------------|---------|
| Cannot resolve after 1 hour | Tier 2 Support | Senior AD Admin |
| Forest-wide replication failure | Tier 3 / Incident | AD Architect / Manager |
| Data integrity concerns | Tier 3 / Emergency | CTO / Microsoft Support |
| Script defect confirmed | Development | Script Author (adrian207@gmail.com) |

### 9.2 Escalation Information Package

**Provide to next level:**

```powershell
# Create escalation package
$escalationPath = "C:\Escalation\ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -Path $escalationPath -ItemType Directory -Force

# 1. System info
$PSVersionTable | Out-File "$escalationPath\SystemInfo.txt"
Get-Module -ListAvailable ActiveDirectory | Out-File "$escalationPath\Modules.txt" -Append

# 2. Recent reports
$latest = Get-ChildItem C:\Reports\ADReplication -Filter "ADRepl-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item -Path $latest.FullName -Destination $escalationPath -Recurse

# 3. Repadmin output
& repadmin /showrepl * /csv | Out-File "$escalationPath\Repadmin-ShowRepl.csv"
& repadmin /replsummary | Out-File "$escalationPath\Repadmin-ReplSummary.txt"

# 4. Event logs
Get-EventLog -LogName "Directory Service" -Newest 100 | Export-Csv "$escalationPath\EventLog-DirectoryService.csv" -NoTypeInformation

# 5. Compress package
Compress-Archive -Path $escalationPath -DestinationPath "$escalationPath.zip"

Write-Host "Escalation package ready: $escalationPath.zip"
```

### 9.3 Contacting Microsoft Support

**Before calling:**

- [ ] Escalation package prepared
- [ ] SR (Service Request) number obtained
- [ ] Business impact documented
- [ ] Recent changes documented

**Information Microsoft will need:**

1. **Environment Details**
   - Forest functional level
   - Number of DCs and sites
   - Network topology (WAN/LAN)

2. **Issue Details**
   - When did problem start?
   - What changed recently?
   - Error messages and codes
   - Replication topology diagram

3. **Diagnostic Data**
   - Repadmin output
   - Event logs (Directory Service, System, Application)
   - Network traces (if connectivity issue)
   - ADDS database status

**Microsoft Support Portal:**
- https://support.microsoft.com
- Phone: 1-800-936-5800 (US)

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2025-10-10 | Adrian Johnson | Initial draft |
| 0.5 | 2025-10-15 | Adrian Johnson | Added error code reference |
| 1.0 | 2025-10-18 | Adrian Johnson | Final release |

---

**END OF TROUBLESHOOTING GUIDE**

---

**Author:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer

**Support:**  
For script issues: adrian207@gmail.com  
For AD issues: Microsoft Support (1-800-936-5800)

