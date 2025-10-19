#Requires -Version 5.1
#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Active Directory Replication Diagnosis, Repair, and Verification Tool
    
.DESCRIPTION
    Performs deep diagnosis of AD replication issues, attempts automatic repairs,
    and verifies the success of repair operations
    
.PARAMETER DomainName
    Domain name to check (defaults to Pokemon.internal)
    
.PARAMETER TargetDCs
    Specific domain controllers to focus on (comma-separated)
    
.PARAMETER AutoRepair
    Automatically attempt repairs without prompting
    
.PARAMETER OutputPath
    Path to save detailed reports
    
.EXAMPLE
    .\AD-ReplicationRepair-Fixed.ps1 -DomainName "Pokemon.internal" -TargetDCs "BELDC02","BELDC01" -AutoRepair
#>

[CmdletBinding()]
param(
    [string]$DomainName = "Pokemon.internal",
    [string[]]$TargetDCs = @(),
    [switch]$AutoRepair,
    [string]$OutputPath = ""
)

# Global variables
$Script:RepairLog = @()
$Script:DiagnosticResults = @{}
$Script:RepairResults = @{}

function Write-RepairLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    $Script:RepairLog += $logMessage
}

function Get-DetailedReplicationStatus {
    param([string[]]$DomainControllers)
    
    Write-RepairLog "Performing detailed replication analysis..." -Level "INFO"
    
    $replicationStatus = @{}
    
    foreach ($dc in $DomainControllers) {
        Write-RepairLog "Analyzing replication for $dc" -Level "INFO"
        
        $dcStatus = @{
            InboundReplication = @()
            ReplicationFailures = @()
        }
        
        try {
            # Get inbound replication partner metadata
            $inboundPartners = Get-ADReplicationPartnerMetadata -Target $dc -ErrorAction Stop
            foreach ($partner in $inboundPartners) {
                $partnerInfo = @{
                    Partner = $partner.Partner
                    Partition = $partner.Partition
                    LastReplicationAttempt = $partner.LastReplicationAttempt
                    LastReplicationSuccess = $partner.LastReplicationSuccess
                    LastReplicationResult = $partner.LastReplicationResult
                    ConsecutiveReplicationFailures = $partner.ConsecutiveReplicationFailures
                    LastReplicationResultText = Get-ReplicationErrorText -ErrorCode $partner.LastReplicationResult
                    TimeSinceLastSuccess = if ($partner.LastReplicationSuccess) { 
                        (Get-Date) - $partner.LastReplicationSuccess 
                    } else { 
                        $null 
                    }
                }
                $dcStatus.InboundReplication += $partnerInfo
            }
            
            # Get replication failures
            $failures = Get-ADReplicationFailure -Target $dc -ErrorAction SilentlyContinue
            if ($failures) {
                $dcStatus.ReplicationFailures = $failures | ForEach-Object {
                    @{
                        Server = $_.Server
                        Partner = $_.Partner
                        FailureType = $_.FailureType
                        FailureCount = $_.FailureCount
                        FirstFailureTime = $_.FirstFailureTime
                        LastError = $_.LastError
                        LastErrorText = Get-ReplicationErrorText -ErrorCode $_.LastError
                    }
                }
            }
            
        } catch {
            Write-RepairLog "Failed to get detailed replication status for $dc : $($_.Exception.Message)" -Level "ERROR"
        }
        
        $replicationStatus[$dc] = $dcStatus
    }
    
    return $replicationStatus
}

function Get-ReplicationErrorText {
    param([int]$ErrorCode)
    
    $errorMappings = @{
        0 = "Success"
        5 = "Access Denied"
        58 = "The specified server cannot perform the requested operation"
        1256 = "The remote system is not available (network connectivity issue)"
        1722 = "RPC server unavailable"
        1753 = "There are no more endpoints available from the endpoint mapper"
        8439 = "The distinguished name specified for this replication operation is invalid"
        8453 = "Replication access was denied"
        8524 = "The DSA operation is unable to proceed because of a DNS lookup failure"
        -2146893022 = "Target principal name is incorrect (Kerberos authentication issue)"
        2146893022 = "Target principal name is incorrect (Kerberos authentication issue)"
    }
    
    if ($errorMappings.ContainsKey($ErrorCode)) {
        return $errorMappings[$ErrorCode]
    } else {
        return "Unknown error (code: $ErrorCode)"
    }
}

function Invoke-ReplicationRepair {
    param([string[]]$DomainControllers, [hashtable]$ReplicationStatus)
    
    Write-RepairLog "Starting replication repair operations..." -Level "INFO"
    
    $repairResults = @{}
    
    foreach ($dc in $DomainControllers) {
        Write-RepairLog "Attempting repairs for $dc" -Level "INFO"
        
        $dcRepairResults = @{
            RepairActions = @()
            Success = $true
        }
        
        $dcStatus = $ReplicationStatus[$dc]
        
        # Check for replication failures
        if ($dcStatus.ReplicationFailures.Count -gt 0) {
            Write-RepairLog "Found $($dcStatus.ReplicationFailures.Count) replication failures on $dc" -Level "WARN"
            
            foreach ($failure in $dcStatus.ReplicationFailures) {
                $repairAction = @{
                    Type = "ReplicationFailure"
                    Partner = $failure.Partner
                    Error = $failure.LastError
                    ErrorText = $failure.LastErrorText
                    RepairAttempts = @()
                    Success = $false
                }
                
                # Generic repair attempt
                $repairResult = Repair-GenericReplication -SourceDC $dc -TargetDC $failure.Partner
                $repairAction.RepairAttempts += $repairResult
                $repairAction.Success = $repairResult.Success
                
                $dcRepairResults.RepairActions += $repairAction
            }
        }
        
        # Force replication sync for all partners
        Write-RepairLog "Forcing replication sync for all partners of $dc" -Level "INFO"
        $syncResult = Invoke-ForceReplicationSync -DomainController $dc
        $dcRepairResults.RepairActions += $syncResult
        
        $dcRepairResults.Success = ($dcRepairResults.RepairActions | Where-Object { -not $_.Success }).Count -eq 0
        $repairResults[$dc] = $dcRepairResults
    }
    
    return $repairResults
}

function Repair-GenericReplication {
    param([string]$SourceDC, [string]$TargetDC)
    
    $repairResult = @{
        Type = "Generic Replication Repair"
        Description = "Attempting generic replication repair"
        Actions = @()
        Success = $false
    }
    
    try {
        # Use repadmin to force synchronization
        Write-RepairLog "Forcing replication sync from $TargetDC to $SourceDC" -Level "INFO"
        
        $repadminSync = & repadmin /syncall /A /P /e $SourceDC 2>&1
        $repairResult.Actions += "Repadmin sync executed"
        
        if ($LASTEXITCODE -eq 0) {
            $repairResult.Success = $true
        }
        
    } catch {
        $repairResult.Actions += "Generic repair failed: $($_.Exception.Message)"
    }
    
    return $repairResult
}

function Invoke-ForceReplicationSync {
    param([string]$DomainController)
    
    $syncResult = @{
        Type = "Force Replication Sync"
        Description = "Forcing replication synchronization"
        Actions = @()
        Success = $false
    }
    
    try {
        Write-RepairLog "Forcing replication synchronization on $DomainController" -Level "INFO"
        
        # Use repadmin for comprehensive sync
        $repadminResult = & repadmin /syncall /A /P /e $DomainController 2>&1
        $syncResult.Actions += "Repadmin syncall executed"
        
        if ($LASTEXITCODE -eq 0) {
            $syncResult.Success = $true
        }
        
    } catch {
        $syncResult.Actions += "Force sync failed: $($_.Exception.Message)"
    }
    
    return $syncResult
}

function Test-RepairSuccess {
    param([string[]]$DomainControllers, [int]$WaitMinutes = 10)
    
    Write-RepairLog "Waiting $WaitMinutes minutes for replication to settle..." -Level "INFO"
    
    # Show countdown for user feedback
    for ($i = $WaitMinutes; $i -gt 0; $i--) {
        Write-Host "`rWaiting for replication to settle... $i minutes remaining" -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 60
    }
    Write-Host "`rWaiting complete. Testing replication status...                    " -ForegroundColor Green
    
    Write-RepairLog "Testing repair success with multiple verification methods..." -Level "INFO"
    
    $repairSuccess = @{
        OverallSuccess = $true
        DomainControllers = @{}
        Summary = @{
            TotalDCs = $DomainControllers.Count
            HealthyDCs = 0
            ImprovedDCs = 0
            StillFailingDCs = 0
        }
    }
    
    foreach ($dc in $DomainControllers) {
        Write-RepairLog "Comprehensive verification for $dc" -Level "INFO"
        
        $dcResult = @{
            ReplicationFailures = 0
            HealthStatus = "Unknown"
            Improvements = @()
            VerificationDetails = @{
                PowerShellCheck = @{}
                RepadminCheck = @{}
                DCDiagCheck = @{}
                EventLogCheck = @{}
            }
        }
        
        # Method 1: PowerShell AD cmdlets (with staleness warning)
        try {
            $postRepairStatus = Get-DetailedReplicationStatus -DomainControllers @($dc)
            $dcResult.ReplicationFailures = $postRepairStatus[$dc].ReplicationFailures.Count
            
            # Check for stale data by examining failure timestamps
            $hasOldFailures = $false
            $recentFailures = 0
            
            if ($postRepairStatus[$dc].ReplicationFailures.Count -gt 0) {
                foreach ($failure in $postRepairStatus[$dc].ReplicationFailures) {
                    if ($failure.FirstFailureTime -and $failure.FirstFailureTime -lt (Get-Date).AddDays(-7)) {
                        $hasOldFailures = $true
                    } else {
                        $recentFailures++
                    }
                }
            }
            
            $dcResult.VerificationDetails.PowerShellCheck = @{
                Method = "PowerShell AD Cmdlets"
                FailureCount = $postRepairStatus[$dc].ReplicationFailures.Count
                RecentFailureCount = $recentFailures
                HasStaleData = $hasOldFailures
                Success = ($recentFailures -eq 0)  # Only count recent failures
                Details = if ($postRepairStatus[$dc].ReplicationFailures.Count -gt 0) {
                    $details = @()
                    foreach ($failure in $postRepairStatus[$dc].ReplicationFailures) {
                        $ageInfo = if ($failure.FirstFailureTime) {
                            $age = (Get-Date) - $failure.FirstFailureTime
                            if ($age.TotalDays -gt 7) { " (>7 days old - likely stale)" } 
                            elseif ($age.TotalHours -gt 1) { " ($([math]::Round($age.TotalHours, 1))h ago)" }
                            else { " (recent)" }
                        } else { "" }
                        
                        $details += "Error $($failure.LastError): $(Get-ReplicationErrorText -ErrorCode $failure.LastError)$ageInfo"
                    }
                    $details
                } else {
                    @("No replication failures detected")
                }
            }
            
            if ($hasOldFailures) {
                $dcResult.VerificationDetails.PowerShellCheck.Details += "WARNING: Some failures appear to be stale data from old issues"
            }
            
        } catch {
            $dcResult.VerificationDetails.PowerShellCheck = @{
                Method = "PowerShell AD Cmdlets"
                Success = $false
                Error = $_.Exception.Message
            }
        }
        
        # Method 2: Repadmin verification (most reliable for current status)
        try {
            Write-RepairLog "Running repadmin /showrepl for $dc" -Level "INFO"
            $repadminOutput = & repadmin /showrepl $dc 2>&1
            
            # Look for actual error patterns, not just any mention of "error"
            $actualErrors = @()
            $successfulReplications = 0
            
            foreach ($line in $repadminOutput) {
                # Count successful replications
                if ($line -match "Last attempt.*was successful" -or $line -match "SYNC EACH WRITE") {
                    $successfulReplications++
                }
                
                # Look for actual error codes (not 0x0 which is success)
                if ($line -match "Last error: (\d+) \(0x[0-9a-f]+\)" -and $matches[1] -ne "0") {
                    $actualErrors += $line.Trim()
                }
                
                # Look for specific failure indicators
                if ($line -match "Access is denied|RPC server is unavailable|DNS.*fail" -and $line -notmatch "successful") {
                    $actualErrors += $line.Trim()
                }
            }
            
            $dcResult.VerificationDetails.RepadminCheck = @{
                Method = "Repadmin /showrepl"
                ErrorCount = $actualErrors.Count
                SuccessCount = $successfulReplications
                Success = ($actualErrors.Count -eq 0 -and $successfulReplications -gt 0)
                Details = if ($actualErrors.Count -gt 0) {
                    $actualErrors | ForEach-Object { $_.ToString().Trim() }
                } else {
                    @("No active replication errors found", "Found $successfulReplications successful replication links")
                }
                LastExitCode = $LASTEXITCODE
            }
            
            # Additional replication queue check
            $queueOutput = & repadmin /queue $dc 2>&1
            $queuedItems = ($queueOutput | Where-Object { $_ -match "repl" -and $_ -notmatch "0 entries" }).Count
            
            if ($queuedItems -eq 0) {
                $dcResult.VerificationDetails.RepadminCheck.Details += "Replication queue is empty (good)"
            } else {
                $dcResult.VerificationDetails.RepadminCheck.Details += "Replication queue has $queuedItems pending items"
            }
            
        } catch {
            $dcResult.VerificationDetails.RepadminCheck = @{
                Method = "Repadmin"
                Success = $false
                Error = $_.Exception.Message
            }
        }
        
        # Method 3: DCDiag replication test (skip if user requested omission)
        try {
            Write-RepairLog "Running dcdiag /test:replications for $dc" -Level "INFO"
            $dcdiaOutput = & dcdiag /s:$dc /test:replications 2>&1
            
            # Check if test was omitted by user
            $testOmitted = $dcdiaOutput | Where-Object { $_ -match "omitted by user request" }
            
            if ($testOmitted) {
                $dcResult.VerificationDetails.DCDiagCheck = @{
                    Method = "DCDiag Replications Test"
                    Success = $null  # Neither success nor failure
                    Skipped = $true
                    Details = @("Test was omitted by user request - check dcdiag configuration")
                }
            } else {
                $dcdiaFailed = $dcdiaOutput | Where-Object { $_ -match "failed|error" -and $_ -notmatch "passed|0 error" }
                $dcdiaPassed = $dcdiaOutput | Where-Object { $_ -match "passed" }
                
                $dcResult.VerificationDetails.DCDiagCheck = @{
                    Method = "DCDiag Replications Test"
                    FailureCount = $dcdiaFailed.Count
                    PassCount = $dcdiaPassed.Count
                    Success = ($dcdiaFailed.Count -eq 0 -and $dcdiaPassed.Count -gt 0)
                    Details = if ($dcdiaFailed.Count -gt 0) {
                        $dcdiaFailed | ForEach-Object { $_.ToString().Trim() }
                    } else {
                        @("DCDiag replication test completed without errors")
                    }
                }
            }
            
        } catch {
            $dcResult.VerificationDetails.DCDiagCheck = @{
                Method = "DCDiag"
                Success = $false
                Error = $_.Exception.Message
            }
        }
        
        # Method 4: Recent Event Log check
        try {
            Write-RepairLog "Checking recent Event Log entries for $dc" -Level "INFO"
            $recentErrors = Get-WinEvent -FilterHashtable @{
                LogName='Directory Service'
                ID=1311,1388,1925,2042,1084,1586
                StartTime=(Get-Date).AddHours(-2)
            } -ComputerName $dc -ErrorAction SilentlyContinue
            
            $dcResult.VerificationDetails.EventLogCheck = @{
                Method = "Recent Event Log Check (2 hours)"
                ErrorCount = if ($recentErrors) { $recentErrors.Count } else { 0 }
                Success = (-not $recentErrors -or $recentErrors.Count -eq 0)
                Details = if ($recentErrors -and $recentErrors.Count -gt 0) {
                    $recentErrors | ForEach-Object { 
                        "Event $($_.Id) at $($_.TimeCreated): $($_.LevelDisplayName)" 
                    }
                } else {
                    @("No recent replication errors in Event Log")
                }
            }
            
        } catch {
            $dcResult.VerificationDetails.EventLogCheck = @{
                Method = "Event Log Check"
                Success = $null
                Error = $_.Exception.Message
            }
        }
        
        # Determine overall health with weighted scoring
        $verificationResults = @()
        $weights = @()
        
        # Repadmin gets highest weight (most reliable for current status)
        if ($dcResult.VerificationDetails.RepadminCheck.Success -ne $null) {
            $verificationResults += $dcResult.VerificationDetails.RepadminCheck.Success
            $weights += 3
        }
        
        # Event log gets high weight for recent status
        if ($dcResult.VerificationDetails.EventLogCheck.Success -ne $null) {
            $verificationResults += $dcResult.VerificationDetails.EventLogCheck.Success
            $weights += 2
        }
        
        # PowerShell gets lower weight due to potential staleness
        if ($dcResult.VerificationDetails.PowerShellCheck.Success -ne $null) {
            $verificationResults += $dcResult.VerificationDetails.PowerShellCheck.Success
            $weights += 1
        }
        
        # DCDiag gets medium weight if not skipped
        if ($dcResult.VerificationDetails.DCDiagCheck.Success -ne $null) {
            $verificationResults += $dcResult.VerificationDetails.DCDiagCheck.Success
            $weights += 2
        }
        
        # Calculate weighted success score
        $totalWeight = ($weights | Measure-Object -Sum).Sum
        $successWeight = 0
        for ($i = 0; $i -lt $verificationResults.Count; $i++) {
            if ($verificationResults[$i]) {
                $successWeight += $weights[$i]
            }
        }
        
        $successRatio = if ($totalWeight -gt 0) { $successWeight / $totalWeight } else { 0 }
        $dcHealthy = $successRatio -ge 0.6  # 60% weighted success threshold
        
        if ($dcHealthy) {
            $dcResult.HealthStatus = "Healthy"
            $repairSuccess.Summary.HealthyDCs++
            $dcResult.Improvements += "Replication is now healthy (weighted score: $([math]::Round($successRatio * 100, 1))%)"
            
            # Add specific methods that passed
            $passedMethods = @()
            if ($dcResult.VerificationDetails.PowerShellCheck.Success) { $passedMethods += "PowerShell" }
            if ($dcResult.VerificationDetails.RepadminCheck.Success) { $passedMethods += "Repadmin" }
            if ($dcResult.VerificationDetails.DCDiagCheck.Success) { $passedMethods += "DCDiag" }
            if ($dcResult.VerificationDetails.EventLogCheck.Success) { $passedMethods += "EventLog" }
            
            if ($passedMethods.Count -gt 0) {
                $dcResult.Improvements += "Verification successful by: $($passedMethods -join ', ')"
            }
            
        } else {
            # Check for improvement even if not fully healthy
            if ($Script:DiagnosticResults[$dc].ReplicationFailures) {
                $beforeFailures = $Script:DiagnosticResults[$dc].ReplicationFailures.Count
                $afterFailures = $dcResult.ReplicationFailures
                
                if ($successRatio -gt 0.3) {  # Some improvement
                    $dcResult.HealthStatus = "Improved but needs attention"
                    $dcResult.Improvements += "Partial improvement detected (score: $([math]::Round($successRatio * 100, 1))%)"
                    $repairSuccess.Summary.ImprovedDCs++
                } else {
                    $dcResult.HealthStatus = "Still has issues"
                }
            } else {
                $dcResult.HealthStatus = "Needs attention"
            }
            
            $repairSuccess.Summary.StillFailingDCs++
            $repairSuccess.OverallSuccess = $false
            
            # Provide specific guidance
            if ($dcResult.VerificationDetails.PowerShellCheck.HasStaleData) {
                $dcResult.Improvements += "NOTE: PowerShell cmdlets show old failures - current status may be better"
            }
        }
        
        $repairSuccess.DomainControllers[$dc] = $dcResult
    }
    
    return $repairSuccess
}

function Export-RepairReport {
    param([hashtable]$DiagnosticResults, [hashtable]$RepairResults, [hashtable]$PostRepairResults)
    
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputPath = ".\AD-ReplicationRepair-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    
    try {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        
        # Export comprehensive JSON report
        $report = @{
            Timestamp = Get-Date
            DiagnosticResults = $DiagnosticResults
            RepairResults = $RepairResults
            PostRepairResults = $PostRepairResults
            RepairLog = $Script:RepairLog
        }
        
        $report | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputPath\RepairReport.json" -Encoding UTF8
        
        # Generate HTML Report
        Generate-RepairHTMLReport -ReportData $report -OutputPath "$OutputPath\RepairSummary.html"
        
        # Generate CSV Reports
        Generate-RepairCSVReports -ReportData $report -OutputPath $OutputPath
        
        Write-RepairLog "Repair report exported to: $OutputPath" -Level "SUCCESS"
        Write-RepairLog "Reports generated: JSON, HTML, and CSV files" -Level "SUCCESS"
        
        # List generated files
        $generatedFiles = Get-ChildItem -Path $OutputPath -File | Select-Object Name, Length
        Write-Host "`nGenerated Report Files:" -ForegroundColor Cyan
        $generatedFiles | ForEach-Object {
            Write-Host "  $($_.Name) ($([math]::Round($_.Length / 1KB, 1)) KB)" -ForegroundColor White
        }
        
    } catch {
        Write-RepairLog "Failed to export report: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Generate-RepairHTMLReport {
    param([hashtable]$ReportData, [string]$OutputPath)
    
    $timestamp = $ReportData.Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
    $overallStatus = if ($ReportData.PostRepairResults.OverallSuccess) { "SUCCESS" } else { "ISSUES DETECTED" }
    $statusColor = if ($ReportData.PostRepairResults.OverallSuccess) { "#27ae60" } else { "#e74c3c" }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Replication Repair Report - $timestamp</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f8f9fa; }
        .header { background: linear-gradient(135deg, #2c3e50, #34495e); color: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .header h1 { margin: 0; font-size: 2.5em; }
        .header .subtitle { opacity: 0.9; font-size: 1.1em; margin-top: 10px; }
        .summary { background: white; padding: 25px; border-radius: 10px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary h2 { color: #2c3e50; margin-top: 0; }
        .status-overall { font-size: 1.5em; font-weight: bold; color: $statusColor; text-align: center; padding: 15px; background: #f8f9fa; border-radius: 5px; margin: 15px 0; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .stat-card { background: white; padding: 20px; border-radius: 8px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat-number { font-size: 2em; font-weight: bold; margin-bottom: 5px; }
        .stat-label { color: #7f8c8d; text-transform: uppercase; font-size: 0.9em; }
        .healthy { color: #27ae60; }
        .improved { color: #f39c12; }
        .failed { color: #e74c3c; }
        .warning { color: #f39c12; }
        .dc-section { background: white; border: 1px solid #dee2e6; margin: 15px 0; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .dc-header { padding: 15px 20px; font-size: 1.2em; font-weight: bold; }
        .dc-header.healthy { background: #d4edda; color: #155724; }
        .dc-header.improved { background: #fff3cd; color: #856404; }
        .dc-header.failed { background: #f8d7da; color: #721c24; }
        .dc-content { padding: 20px; }
        .verification-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin: 15px 0; }
        .verification-method { border: 1px solid #dee2e6; border-radius: 5px; padding: 15px; }
        .verification-method h4 { margin: 0 0 10px 0; display: flex; align-items: center; }
        .verification-method .status-icon { margin-right: 8px; font-size: 1.2em; }
        .verification-method.passed { border-left: 4px solid #28a745; }
        .verification-method.failed { border-left: 4px solid #dc3545; }
        .verification-method.skipped { border-left: 4px solid #6c757d; }
        .details-list { margin: 10px 0; padding-left: 20px; }
        .details-list li { margin: 5px 0; font-size: 0.9em; color: #6c757d; }
        .improvements { background: #d4edda; border-radius: 5px; padding: 15px; margin: 15px 0; }
        .improvements h4 { color: #155724; margin: 0 0 10px 0; }
        .improvements ul { margin: 0; color: #155724; }
        .timeline { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .timeline h3 { color: #2c3e50; }
        .timeline-item { padding: 10px; border-left: 3px solid #007bff; margin: 10px 0; background: #f8f9fa; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { border: 1px solid #dee2e6; padding: 12px; text-align: left; }
        th { background: #f8f9fa; font-weight: 600; }
        .repair-action { background: #e3f2fd; border-radius: 5px; padding: 15px; margin: 10px 0; border-left: 4px solid #2196f3; }
        .footer { text-align: center; color: #6c757d; padding: 20px; margin-top: 40px; border-top: 1px solid #dee2e6; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔄 AD Replication Repair Report</h1>
        <div class="subtitle">Generated on $timestamp</div>
    </div>
    
    <div class="summary">
        <div class="status-overall">Overall Status: $overallStatus</div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number healthy">$($ReportData.PostRepairResults.Summary.HealthyDCs)</div>
                <div class="stat-label">Healthy DCs</div>
            </div>
            <div class="stat-card">
                <div class="stat-number improved">$($ReportData.PostRepairResults.Summary.ImprovedDCs)</div>
                <div class="stat-label">Improved DCs</div>
            </div>
            <div class="stat-card">
                <div class="stat-number failed">$($ReportData.PostRepairResults.Summary.StillFailingDCs)</div>
                <div class="stat-label">Still Failing</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($ReportData.PostRepairResults.Summary.TotalDCs)</div>
                <div class="stat-label">Total DCs</div>
            </div>
        </div>
    </div>
    
    <h2>📊 Domain Controller Details</h2>
"@

    # Add detailed DC information
    foreach ($dc in $ReportData.PostRepairResults.DomainControllers.Keys) {
        $dcResult = $ReportData.PostRepairResults.DomainControllers[$dc]
        $headerClass = switch -Regex ($dcResult.HealthStatus) {
            "Healthy" { "healthy" }
            "Improved" { "improved" }
            default { "failed" }
        }
        
        $statusIcon = switch -Regex ($dcResult.HealthStatus) {
            "Healthy" { "✅" }
            "Improved" { "⚠️" }
            default { "❌" }
        }
        
        $html += @"
    <div class="dc-section">
        <div class="dc-header $headerClass">
            $statusIcon $dc - $($dcResult.HealthStatus)
        </div>
        <div class="dc-content">
"@
        
        # Verification Results
        if ($dcResult.VerificationDetails) {
            $html += "<h3>🔍 Verification Results</h3><div class='verification-grid'>"
            
            foreach ($method in $dcResult.VerificationDetails.Keys) {
                $methodResult = $dcResult.VerificationDetails[$method]
                
                $methodClass = if ($methodResult.Success -eq $true) { "passed" }
                              elseif ($methodResult.Success -eq $false) { "failed" }
                              else { "skipped" }
                
                $statusIcon = if ($methodResult.Success -eq $true) { "✅" }
                             elseif ($methodResult.Success -eq $false) { "❌" }
                             else { "⏭️" }
                
                $html += @"
                <div class="verification-method $methodClass">
                    <h4><span class="status-icon">$statusIcon</span>$($methodResult.Method)</h4>
"@
                
                if ($methodResult.Error) {
                    $html += "<p><strong>Error:</strong> $($methodResult.Error)</p>"
                } elseif ($methodResult.Details -and $methodResult.Details.Count -gt 0) {
                    $html += "<ul class='details-list'>"
                    $methodResult.Details | Select-Object -First 5 | ForEach-Object {
                        $html += "<li>$_</li>"
                    }
                    $html += "</ul>"
                }
                
                # Add method-specific metrics
                if ($methodResult.SuccessCount -gt 0) {
                    $html += "<p><strong>Successful Links:</strong> $($methodResult.SuccessCount)</p>"
                }
                if ($methodResult.ErrorCount -gt 0) {
                    $html += "<p><strong>Error Count:</strong> $($methodResult.ErrorCount)</p>"
                }
                
                $html += "</div>"
            }
            $html += "</div>"
        }
        
        # Improvements
        if ($dcResult.Improvements.Count -gt 0) {
            $html += @"
            <div class="improvements">
                <h4>📈 Improvements Detected</h4>
                <ul>
"@
            $dcResult.Improvements | ForEach-Object {
                $html += "<li>$_</li>"
            }
            $html += "</ul></div>"
        }
        
        # Repair Actions
        if ($ReportData.RepairResults[$dc] -and $ReportData.RepairResults[$dc].RepairActions.Count -gt 0) {
            $html += "<h3>🔧 Repair Actions Performed</h3>"
            
            foreach ($action in $ReportData.RepairResults[$dc].RepairActions) {
                $actionIcon = if ($action.Success) { "✅" } else { "❌" }
                $html += @"
                <div class="repair-action">
                    <h4>$actionIcon $($action.Type)</h4>
                    <p>$($action.Description)</p>
"@
                if ($action.Actions -and $action.Actions.Count -gt 0) {
                    $html += "<ul>"
                    $action.Actions | ForEach-Object {
                        $html += "<li>$_</li>"
                    }
                    $html += "</ul>"
                }
                $html += "</div>"
            }
        }
        
        $html += "</div></div>"
    }
    
    # Timeline
    if ($ReportData.RepairLog.Count -gt 0) {
        $html += @"
    <div class="timeline">
        <h3>⏱️ Repair Timeline</h3>
"@
        $ReportData.RepairLog | Select-Object -Last 20 | ForEach-Object {
            $logClass = if ($_ -like "*ERROR*") { "failed" }
                       elseif ($_ -like "*WARN*") { "warning" }
                       elseif ($_ -like "*SUCCESS*") { "healthy" }
                       else { "" }
            
            $html += "<div class='timeline-item $logClass'>$_</div>"
        }
        $html += "</div>"
    }
    
    $html += @"
    <div class="footer">
        <p>Report generated by AD Replication Repair Tool</p>
        <p>For technical support, contact your system administrator</p>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $OutputPath -Encoding UTF8
}

function Generate-RepairCSVReports {
    param([hashtable]$ReportData, [string]$OutputPath)
    
    # CSV 1: Summary Report
    $summaryData = @()
    foreach ($dc in $ReportData.PostRepairResults.DomainControllers.Keys) {
        $dcResult = $ReportData.PostRepairResults.DomainControllers[$dc]
        
        # Calculate verification scores
        $verificationScore = 0
        $totalMethods = 0
        if ($dcResult.VerificationDetails) {
            foreach ($method in $dcResult.VerificationDetails.Values) {
                if ($method.Success -ne $null) {
                    $totalMethods++
                    if ($method.Success) { $verificationScore++ }
                }
            }
        }
        
        $summaryData += [PSCustomObject]@{
            DomainController = $dc
            HealthStatus = $dcResult.HealthStatus
            ReplicationFailures = $dcResult.ReplicationFailures
            VerificationScore = if ($totalMethods -gt 0) { "$verificationScore/$totalMethods" } else { "N/A" }
            PowerShellCheck = if ($dcResult.VerificationDetails.PowerShellCheck.Success -ne $null) { 
                if ($dcResult.VerificationDetails.PowerShellCheck.Success) { "PASS" } else { "FAIL" }
            } else { "N/A" }
            RepadminCheck = if ($dcResult.VerificationDetails.RepadminCheck.Success -ne $null) {
                if ($dcResult.VerificationDetails.RepadminCheck.Success) { "PASS" } else { "FAIL" }
            } else { "N/A" }
            DCDiagCheck = if ($dcResult.VerificationDetails.DCDiagCheck.Success -ne $null) {
                if ($dcResult.VerificationDetails.DCDiagCheck.Success) { "PASS" } else { "FAIL" }
            } else { "SKIPPED" }
            EventLogCheck = if ($dcResult.VerificationDetails.EventLogCheck.Success -ne $null) {
                if ($dcResult.VerificationDetails.EventLogCheck.Success) { "PASS" } else { "FAIL" }
            } else { "N/A" }
            Improvements = ($dcResult.Improvements -join "; ")
            RepairActions = if ($ReportData.RepairResults[$dc]) { 
                $ReportData.RepairResults[$dc].RepairActions.Count 
            } else { 0 }
            RepairSuccess = if ($ReportData.RepairResults[$dc]) {
                if ($ReportData.RepairResults[$dc].Success) { "YES" } else { "NO" }
            } else { "N/A" }
        }
    }
    
    $summaryData | Export-Csv -Path "$OutputPath\RepairSummary.csv" -NoTypeInformation -Encoding UTF8
    
    # CSV 2: Detailed Issues Report
    $issuesData = @()
    foreach ($dc in $ReportData.DiagnosticResults.Keys) {
        $dcDiag = $ReportData.DiagnosticResults[$dc]
        
        if ($dcDiag.ReplicationFailures -and $dcDiag.ReplicationFailures.Count -gt 0) {
            foreach ($failure in $dcDiag.ReplicationFailures) {
                $issuesData += [PSCustomObject]@{
                    DomainController = $dc
                    Partner = $failure.Partner
                    FailureType = $failure.FailureType
                    ErrorCode = $failure.LastError
                    ErrorDescription = $failure.LastErrorText
                    FailureCount = $failure.FailureCount
                    FirstFailureTime = $failure.FirstFailureTime
                    Status = "BEFORE_REPAIR"
                }
            }
        }
        
        # Add post-repair issues if any
        if ($ReportData.PostRepairResults.DomainControllers[$dc].VerificationDetails.PowerShellCheck.Details) {
            foreach ($detail in $ReportData.PostRepairResults.DomainControllers[$dc].VerificationDetails.PowerShellCheck.Details) {
                if ($detail -like "Error *") {
                    $errorMatch = $detail -match "Error (\d+):(.*)"
                    if ($errorMatch) {
                        $issuesData += [PSCustomObject]@{
                            DomainController = $dc
                            Partner = "Various"
                            FailureType = "Post-Repair Check"
                            ErrorCode = $matches[1]
                            ErrorDescription = $matches[2].Trim()
                            FailureCount = 1
                            FirstFailureTime = $ReportData.Timestamp
                            Status = "AFTER_REPAIR"
                        }
                    }
                }
            }
        }
    }
    
    if ($issuesData.Count -gt 0) {
        $issuesData | Export-Csv -Path "$OutputPath\DetailedIssues.csv" -NoTypeInformation -Encoding UTF8
    }
    
    # CSV 3: Repair Actions Log
    $actionsData = @()
    foreach ($dc in $ReportData.RepairResults.Keys) {
        $dcRepair = $ReportData.RepairResults[$dc]
        
        foreach ($action in $dcRepair.RepairActions) {
            $actionsData += [PSCustomObject]@{
                DomainController = $dc
                ActionType = $action.Type
                Description = $action.Description
                Success = if ($action.Success) { "YES" } else { "NO" }
                Details = ($action.Actions -join "; ")
                Partner = if ($action.Partner) { $action.Partner } else { "N/A" }
                ErrorCode = if ($action.Error) { $action.Error } else { "N/A" }
            }
        }
    }
    
    if ($actionsData.Count -gt 0) {
        $actionsData | Export-Csv -Path "$OutputPath\RepairActions.csv" -NoTypeInformation -Encoding UTF8
    }
    
    # CSV 4: Verification Details
    $verificationData = @()
    foreach ($dc in $ReportData.PostRepairResults.DomainControllers.Keys) {
        $dcResult = $ReportData.PostRepairResults.DomainControllers[$dc]
        
        if ($dcResult.VerificationDetails) {
            foreach ($methodName in $dcResult.VerificationDetails.Keys) {
                $method = $dcResult.VerificationDetails[$methodName]
                
                $verificationData += [PSCustomObject]@{
                    DomainController = $dc
                    VerificationMethod = $method.Method
                    Result = if ($method.Success -eq $true) { "PASS" } 
                            elseif ($method.Success -eq $false) { "FAIL" } 
                            else { "SKIPPED" }
                    ErrorCount = if ($method.ErrorCount) { $method.ErrorCount } else { 0 }
                    SuccessCount = if ($method.SuccessCount) { $method.SuccessCount } else { 0 }
                    Details = if ($method.Details) { ($method.Details -join "; ") } else { "" }
                    Error = if ($method.Error) { $method.Error } else { "" }
                    HasStaleData = if ($method.HasStaleData) { "YES" } else { "NO" }
                }
            }
        }
    }
    
    if ($verificationData.Count -gt 0) {
        $verificationData | Export-Csv -Path "$OutputPath\VerificationDetails.csv" -NoTypeInformation -Encoding UTF8
    }
}

# Main execution
Write-Host "=== AD Replication Diagnosis and Repair Tool ===" -ForegroundColor Cyan
Write-Host "Domain: $DomainName" -ForegroundColor Cyan

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-RepairLog "Failed to import Active Directory module. Please install RSAT tools." -Level "ERROR"
    exit 1
}

# Handle comma-separated TargetDCs parameter
if ($TargetDCs.Count -eq 1 -and $TargetDCs[0].Contains(",")) {
    $TargetDCs = $TargetDCs[0].Split(",").Trim()
}

# Get domain controllers to work with
if ($TargetDCs.Count -eq 0) {
    try {
        $allDCs = Get-ADDomainController -Filter * -Server $DomainName | Select-Object -ExpandProperty HostName
        $TargetDCs = $allDCs
        Write-RepairLog "No specific DCs specified. Working with all $($TargetDCs.Count) domain controllers." -Level "INFO"
    } catch {
        Write-RepairLog "Failed to retrieve domain controllers: $($_.Exception.Message)" -Level "ERROR"
        exit 1
    }
}

Write-RepairLog "Target Domain Controllers: $($TargetDCs -join ', ')" -Level "INFO"

# Phase 1: Initial Diagnosis
Write-Host "`n=== PHASE 1: INITIAL DIAGNOSIS ===" -ForegroundColor Yellow

# Get detailed replication status
$Script:DiagnosticResults = Get-DetailedReplicationStatus -DomainControllers $TargetDCs

# Analyze results
$issuesFound = @()
foreach ($dc in $TargetDCs) {
    $dcStatus = $Script:DiagnosticResults[$dc]
    if ($dcStatus.ReplicationFailures.Count -gt 0) {
        $issuesFound += "$dc has $($dcStatus.ReplicationFailures.Count) replication failures"
        
        foreach ($failure in $dcStatus.ReplicationFailures) {
            Write-RepairLog "ISSUE: $dc -> $($failure.Partner): Error $($failure.LastError) ($($failure.LastErrorText))" -Level "ERROR"
        }
    }
    
    # Check for stale replication
    foreach ($partner in $dcStatus.InboundReplication) {
        if ($partner.TimeSinceLastSuccess -and $partner.TimeSinceLastSuccess.TotalHours -gt 24) {
            $issuesFound += "$dc hasn't replicated with $($partner.Partner) for $([math]::Round($partner.TimeSinceLastSuccess.TotalHours, 1)) hours"
            Write-RepairLog "ISSUE: $dc -> $($partner.Partner): Last successful replication $([math]::Round($partner.TimeSinceLastSuccess.TotalHours, 1)) hours ago" -Level "WARN"
        }
    }
}

if ($issuesFound.Count -eq 0) {
    Write-RepairLog "No replication issues detected. All domain controllers appear healthy." -Level "SUCCESS"
    exit 0
}

Write-RepairLog "Found $($issuesFound.Count) replication issues total" -Level "WARN"

# Phase 2: Repair Decision
Write-Host "`n=== PHASE 2: REPAIR DECISION ===" -ForegroundColor Yellow

if (-not $AutoRepair) {
    Write-Host "Issues found that can be repaired:" -ForegroundColor Yellow
    $issuesFound | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    
    do {
        $response = Read-Host "`nProceed with automatic repair? (Y/N)"
    } while ($response -notmatch "^[YNyn]$")
    
    if ($response -match "^[Nn]$") {
        Write-RepairLog "Repair cancelled by user. Diagnostic results available." -Level "INFO"
        Export-RepairReport -DiagnosticResults $Script:DiagnosticResults -RepairResults @{} -PostRepairResults @{}
        exit 0
    }
}

# Phase 3: Repair Operations
Write-Host "`n=== PHASE 3: REPAIR OPERATIONS ===" -ForegroundColor Yellow

$Script:RepairResults = Invoke-ReplicationRepair -DomainControllers $TargetDCs -ReplicationStatus $Script:DiagnosticResults

# Phase 4: Verification
Write-Host "`n=== PHASE 4: VERIFICATION ===" -ForegroundColor Yellow

$postRepairResults = Test-RepairSuccess -DomainControllers $TargetDCs

# Phase 5: Reporting
Write-Host "`n=== PHASE 5: FINAL REPORT ===" -ForegroundColor Yellow

Write-Host "`n=== REPAIR SUMMARY ===" -ForegroundColor Cyan
if ($postRepairResults.OverallSuccess) {
    Write-Host "✓ Overall repair was SUCCESSFUL!" -ForegroundColor Green
} else {
    Write-Host "✗ Overall repair had some issues" -ForegroundColor Red
}

Write-Host "Domain Controllers Status:" -ForegroundColor White
Write-Host "  Healthy DCs: $($postRepairResults.Summary.HealthyDCs)" -ForegroundColor Green
Write-Host "  Improved DCs: $($postRepairResults.Summary.ImprovedDCs)" -ForegroundColor Yellow
Write-Host "  Still failing DCs: $($postRepairResults.Summary.StillFailingDCs)" -ForegroundColor Red

# Detailed DC status with verification methods
foreach ($dc in $TargetDCs) {
    $dcResult = $postRepairResults.DomainControllers[$dc]
    $color = switch ($dcResult.HealthStatus) {
        "Healthy" { "Green" }
        { $_ -like "*Improved*" } { "Yellow" }
        "Still has issues" { "Red" }
        default { "Yellow" }
    }
    
    Write-Host "`n$dc - $($dcResult.HealthStatus)" -ForegroundColor $color
    
    # Show verification details
    if ($dcResult.VerificationDetails) {
        Write-Host "  Verification Results:" -ForegroundColor Gray
        
        foreach ($method in $dcResult.VerificationDetails.Keys) {
            $methodResult = $dcResult.VerificationDetails[$method]
            $methodColor = if ($methodResult.Success) { "Green" } else { "Red" }
            $statusIcon = if ($methodResult.Success) { "✓" } else { "✗" }
            
            Write-Host "    $statusIcon $($methodResult.Method): " -NoNewline -ForegroundColor $methodColor
            
            if ($methodResult.Success) {
                Write-Host "PASSED" -ForegroundColor $methodColor
            } else {
                Write-Host "FAILED" -ForegroundColor $methodColor
                if ($methodResult.Error) {
                    Write-Host "      Error: $($methodResult.Error)" -ForegroundColor Red
                }
            }
            
            # Show relevant details
            if ($methodResult.Details -and $methodResult.Details.Count -gt 0) {
                $methodResult.Details | Select-Object -First 3 | ForEach-Object {
                    Write-Host "      $_" -ForegroundColor Gray
                }
                if ($methodResult.Details.Count -gt 3) {
                    Write-Host "      ... and $($methodResult.Details.Count - 3) more" -ForegroundColor Gray
                }
            }
        }
    }
    
    if ($dcResult.ReplicationFailures -gt 0) {
        Write-Host "  Current failures detected: $($dcResult.ReplicationFailures)" -ForegroundColor Red
    }
    
    if ($dcResult.Improvements.Count -gt 0) {
        Write-Host "  Improvements:" -ForegroundColor Green
        $dcResult.Improvements | ForEach-Object { 
            Write-Host "    • $_" -ForegroundColor Green 
        }
    }
}

# Export detailed report
Export-RepairReport -DiagnosticResults $Script:DiagnosticResults -RepairResults $Script:RepairResults -PostRepairResults $postRepairResults

Write-Host "`n=== ADDITIONAL RECOMMENDATIONS ===" -ForegroundColor Cyan

if ($postRepairResults.Summary.StillFailingDCs -gt 0) {
    Write-Host "For persistent issues, consider:" -ForegroundColor Yellow
    Write-Host "  1. Check Event Logs on failing DCs (Event IDs: 1311, 1388, 1925)" -ForegroundColor White
    Write-Host "  2. Verify time synchronization (w32tm /query /status)" -ForegroundColor White
    Write-Host "  3. Check DNS configuration and SRV records" -ForegroundColor White
    Write-Host "  4. Verify firewall settings and port connectivity" -ForegroundColor White
    Write-Host "  5. Run 'dcdiag /test:replications /v' for detailed diagnostics" -ForegroundColor White
}

Write-Host "`nReplication repair completed!" -ForegroundColor Green

# Additional diagnostic commands
Write-Host "`n=== ADDITIONAL DIAGNOSTIC COMMANDS ===" -ForegroundColor Cyan
Write-Host "Run these commands for deeper investigation:" -ForegroundColor White
Write-Host "  repadmin /showrepl * /csv > replication-status.csv" -ForegroundColor Gray
Write-Host "  repadmin /replsummary" -ForegroundColor Gray
Write-Host "  dcdiag /test:replications /v" -ForegroundColor Gray
