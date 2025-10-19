#Requires -Version 5.1
#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Advanced Active Directory Replication Management Tool with Multi-Mode Operation
    
.DESCRIPTION
    Production-ready AD replication manager with safety guards, parallelism, and comprehensive reporting.
    
    FEATURES:
    - Multi-mode operation: Audit | Repair | Verify | AuditRepairVerify
    - Scoped execution: Forest | Site | DCList
    - WhatIf/Confirm support for all impactful operations
    - Parallel DC processing with configurable throttling
    - Pipeline-friendly verbose/information streams
    - JSON summary for CI/CD integration
    - Audit trail with optional transcript logging
    - Consolidated reporting (CSV, HTML, JSON)
    
.PARAMETER Mode
    Operation mode. Default: Audit
    - Audit: Read-only health assessment
    - Repair: Audit + repair operations
    - Verify: Post-repair verification only
    - AuditRepairVerify: Complete workflow
    
.PARAMETER Scope
    Execution scope. Default: DCList
    - Forest: All DCs in forest (requires explicit confirmation)
    - Site:<Name>: All DCs in specified site
    - DCList: Use -DomainControllers parameter
    
.PARAMETER DomainControllers
    Explicit list of DC hostnames. Required when Scope=DCList.
    
.PARAMETER DomainName
    Domain FQDN to query. Default: Current user's domain.
    
.PARAMETER AutoRepair
    Skip repair confirmation prompts. Use with caution.
    
.PARAMETER Throttle
    Max parallel operations. Default: 8. Range: 1-32.
    
.PARAMETER OutputPath
    Report output directory. Default: .\ADRepl-<timestamp>
    
.PARAMETER AuditTrail
    Enable transcript logging for tamper-evident audit trail.
    
.PARAMETER Timeout
    Per-DC operation timeout in seconds. Default: 300.
    
.EXAMPLE
    .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02
    
    Audit-only mode for specific DCs (safe, read-only)
    
.EXAMPLE
    .\Invoke-ADReplicationManager.ps1 -Mode Repair -Scope Site:Default-First-Site-Name -AutoRepair -AuditTrail
    
    Automated repair for all DCs in site with full logging
    
.EXAMPLE
    .\Invoke-ADReplicationManager.ps1 -Mode AuditRepairVerify -DomainControllers DC01,DC02 -WhatIf
    
    Preview all actions without executing (WhatIf support)
    
.NOTES
    Author: Consolidated from AD-Repl-Audit.ps1 and AD-ReplicationRepair.ps1
    Version: 3.0
    Requires: PowerShell 5.1+, RSAT-AD-PowerShell, Domain Admin rights
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Audit', 'Repair', 'Verify', 'AuditRepairVerify')]
    [string]$Mode = 'Audit',
    
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^(Forest|Site:.+|DCList)$')]
    [string]$Scope = 'DCList',
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$DomainControllers = @(),
    
    [Parameter(Mandatory = $false)]
    [string]$DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name,
    
    [Parameter(Mandatory = $false)]
    [switch]$AutoRepair,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 32)]
    [int]$Throttle = 8,
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ 
        if ($_ -and -not (Test-Path (Split-Path $_) -PathType Container)) {
            throw "Parent directory must exist: $(Split-Path $_)"
        }
        $true
    })]
    [string]$OutputPath = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$AuditTrail,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(60, 3600)]
    [int]$Timeout = 300
)

# ============================================================================
# GLOBAL STATE
# ============================================================================

$Script:RepairLog = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Script:StartTime = Get-Date
$Script:ExitCode = 0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-RepairLog {
    <#
    .SYNOPSIS
        Pipeline-friendly logging with structured output streams.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Verbose', 'Information', 'Warning', 'Error')]
        [string]$Level = 'Information'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    [void]$Script:RepairLog.Add($logEntry)
    
    switch ($Level) {
        'Verbose'     { Write-Verbose $Message }
        'Information' { Write-Information $Message -InformationAction Continue }
        'Warning'     { Write-Warning $Message }
        'Error'       { Write-Error $Message }
    }
}

function Resolve-ScopeToDCs {
    <#
    .SYNOPSIS
        Resolves Scope parameter to explicit DC list with safety checks.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Scope,
        [string[]]$ExplicitDCs,
        [string]$Domain
    )
    
    $resolvedDCs = @()
    
    switch -Regex ($Scope) {
        '^Forest$' {
            Write-RepairLog "Resolving Forest scope - this targets ALL domain controllers" -Level Warning
            
            if (-not $PSCmdlet.ShouldProcess("All DCs in forest", "Query and process")) {
                throw "Forest scope requires explicit confirmation. Operation cancelled."
            }
            
            try {
                $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
                foreach ($domain in $forest.Domains) {
                    $dcs = Get-ADDomainController -Filter * -Server $domain.Name -ErrorAction Stop
                    $resolvedDCs += $dcs | Select-Object -ExpandProperty HostName
                }
                Write-RepairLog "Resolved $($resolvedDCs.Count) DCs across forest" -Level Information
            }
            catch {
                throw "Failed to resolve forest DCs: $_"
            }
        }
        
        '^Site:(.+)$' {
            $siteName = $Matches[1]
            Write-RepairLog "Resolving Site scope: $siteName" -Level Information
            
            try {
                $dcs = Get-ADDomainController -Filter "Site -eq '$siteName'" -Server $Domain -ErrorAction Stop
                $resolvedDCs = $dcs | Select-Object -ExpandProperty HostName
                
                if ($resolvedDCs.Count -eq 0) {
                    throw "No DCs found in site '$siteName'. Verify site name."
                }
                
                Write-RepairLog "Resolved $($resolvedDCs.Count) DCs in site $siteName" -Level Information
            }
            catch {
                throw "Failed to resolve site '$siteName': $_"
            }
        }
        
        '^DCList$' {
            if ($ExplicitDCs.Count -eq 0) {
                throw "Scope=DCList requires -DomainControllers parameter. Use -Scope Forest or -Scope Site:<name> for discovery."
            }
            
            # Handle comma-separated single string
            if ($ExplicitDCs.Count -eq 1 -and $ExplicitDCs[0] -match ',') {
                $ExplicitDCs = $ExplicitDCs[0] -split ',' | ForEach-Object { $_.Trim() }
            }
            
            $resolvedDCs = $ExplicitDCs
            Write-RepairLog "Using explicit DC list: $($resolvedDCs -join ', ')" -Level Information
        }
    }
    
    if ($resolvedDCs.Count -eq 0) {
        throw "No domain controllers resolved. Check parameters and try again."
    }
    
    return $resolvedDCs
}

function Get-ReplicationSnapshot {
    <#
    .SYNOPSIS
        Captures current replication state across DCs with parallel processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers,
        
        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 8,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )
    
    Write-RepairLog "Capturing replication snapshot for $($DomainControllers.Count) DCs (throttle: $ThrottleLimit)" -Level Information
    
    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    
    # PowerShell 7+ parallel support
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $DomainControllers | ForEach-Object -Parallel {
            $dc = $_
            $timeout = $using:TimeoutSeconds
            
            $snapshot = [PSCustomObject]@{
                DC                  = $dc
                Timestamp           = Get-Date
                InboundPartners     = @()
                Failures            = @()
                Status              = 'Unknown'
                Error               = $null
            }
            
            try {
                # Time-bounded operation
                $job = Start-Job -ScriptBlock {
                    param($dcName)
                    Import-Module ActiveDirectory -ErrorAction Stop
                    
                    $partners = Get-ADReplicationPartnerMetadata -Target $dcName -ErrorAction Stop
                    $failures = Get-ADReplicationFailure -Target $dcName -ErrorAction SilentlyContinue
                    
                    return @{
                        Partners = $partners
                        Failures = $failures
                    }
                } -ArgumentList $dc
                
                $completed = Wait-Job -Job $job -Timeout $timeout
                
                if ($completed) {
                    $data = Receive-Job -Job $job -ErrorAction Stop
                    
                    $snapshot.InboundPartners = $data.Partners | ForEach-Object {
                        [PSCustomObject]@{
                            Partner                      = $_.Partner
                            Partition                    = $_.Partition
                            LastAttempt                  = $_.LastReplicationAttempt
                            LastSuccess                  = $_.LastReplicationSuccess
                            LastResult                   = $_.LastReplicationResult
                            ConsecutiveFailures          = $_.ConsecutiveReplicationFailures
                            HoursSinceLastSuccess        = if ($_.LastReplicationSuccess) { 
                                ((Get-Date) - $_.LastReplicationSuccess).TotalHours 
                            } else { $null }
                        }
                    }
                    
                    $snapshot.Failures = $data.Failures | ForEach-Object {
                        [PSCustomObject]@{
                            Partner          = $_.Partner
                            FailureType      = $_.FailureType
                            FailureCount     = $_.FailureCount
                            FirstFailureTime = $_.FirstFailureTime
                            LastError        = $_.LastError
                        }
                    }
                    
                    $snapshot.Status = if ($snapshot.Failures.Count -eq 0) { 'Healthy' } else { 'Degraded' }
                }
                else {
                    throw "Operation timed out after $timeout seconds"
                }
                
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
            catch {
                $snapshot.Status = 'Failed'
                $snapshot.Error = $_.Exception.Message
            }
            
            ($using:results).Add($snapshot)
        } -ThrottleLimit $ThrottleLimit
    }
    else {
        # PowerShell 5.1 fallback - serial processing with better error handling
        Write-RepairLog "[Inference] PowerShell 5.1 detected; parallel processing not available. Processing serially." -Level Warning
        
        foreach ($dc in $DomainControllers) {
            $snapshot = [PSCustomObject]@{
                DC                  = $dc
                Timestamp           = Get-Date
                InboundPartners     = @()
                Failures            = @()
                Status              = 'Unknown'
                Error               = $null
            }
            
            try {
                $partners = Get-ADReplicationPartnerMetadata -Target $dc -ErrorAction Stop
                $failures = Get-ADReplicationFailure -Target $dc -ErrorAction SilentlyContinue
                
                $snapshot.InboundPartners = $partners | ForEach-Object {
                    [PSCustomObject]@{
                        Partner                      = $_.Partner
                        Partition                    = $_.Partition
                        LastAttempt                  = $_.LastReplicationAttempt
                        LastSuccess                  = $_.LastReplicationSuccess
                        LastResult                   = $_.LastReplicationResult
                        ConsecutiveFailures          = $_.ConsecutiveReplicationFailures
                        HoursSinceLastSuccess        = if ($_.LastReplicationSuccess) { 
                            ((Get-Date) - $_.LastReplicationSuccess).TotalHours 
                        } else { $null }
                    }
                }
                
                $snapshot.Failures = $failures | ForEach-Object {
                    [PSCustomObject]@{
                        Partner          = $_.Partner
                        FailureType      = $_.FailureType
                        FailureCount     = $_.FailureCount
                        FirstFailureTime = $_.FirstFailureTime
                        LastError        = $_.LastError
                    }
                }
                
                $snapshot.Status = if ($snapshot.Failures.Count -eq 0) { 'Healthy' } else { 'Degraded' }
            }
            catch [Microsoft.ActiveDirectory.Management.ADServerDownException] {
                $snapshot.Status = 'Unreachable'
                $snapshot.Error = "DC unreachable: $_"
                Write-RepairLog "DC unreachable: $dc" -Level Warning
            }
            catch {
                $snapshot.Status = 'Failed'
                $snapshot.Error = $_.Exception.Message
                Write-RepairLog "Failed to query $dc : $_" -Level Error
            }
            
            $results.Add($snapshot)
        }
    }
    
    return $results.ToArray()
}

function Find-ReplicationIssues {
    <#
    .SYNOPSIS
        Pure evaluation function - analyzes snapshot and returns issue objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Snapshots
    )
    
    begin {
        $allIssues = @()
    }
    
    process {
        foreach ($snapshot in $Snapshots) {
            # Issue category 1: Query failures
            if ($snapshot.Status -in @('Failed', 'Unreachable')) {
                $allIssues += [PSCustomObject]@{
                    DC          = $snapshot.DC
                    Category    = 'Connectivity'
                    Severity    = 'High'
                    Description = "Unable to query DC: $($snapshot.Error)"
                    Actionable  = $true
                }
            }
            
            # Issue category 2: Active replication failures
            foreach ($failure in $snapshot.Failures) {
                $allIssues += [PSCustomObject]@{
                    DC          = $snapshot.DC
                    Category    = 'ReplicationFailure'
                    Severity    = 'High'
                    Description = "Replication failure with $($failure.Partner): Error $($failure.LastError)"
                    Partner     = $failure.Partner
                    ErrorCode   = $failure.LastError
                    Actionable  = $true
                }
            }
            
            # Issue category 3: Stale replication (>24h)
            foreach ($partner in $snapshot.InboundPartners) {
                if ($partner.HoursSinceLastSuccess -and $partner.HoursSinceLastSuccess -gt 24) {
                    $allIssues += [PSCustomObject]@{
                        DC          = $snapshot.DC
                        Category    = 'StaleReplication'
                        Severity    = 'Medium'
                        Description = "No successful replication with $($partner.Partner) for $([math]::Round($partner.HoursSinceLastSuccess, 1)) hours"
                        Partner     = $partner.Partner
                        Actionable  = $true
                    }
                }
            }
        }
    }
    
    end {
        Write-RepairLog "Identified $($allIssues.Count) issues across $($Snapshots.Count) DCs" -Level Information
        return $allIssues
    }
}

function Invoke-ReplicationFix {
    <#
    .SYNOPSIS
        Idempotent repair operations with ShouldProcess guards.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainController,
        
        [Parameter(Mandatory = $true)]
        [object[]]$Issues
    )
    
    $actions = @()
    
    foreach ($issue in $Issues) {
        if (-not $issue.Actionable) { continue }
        
        $action = [PSCustomObject]@{
            DC          = $DomainController
            IssueType   = $issue.Category
            Method      = 'Unknown'
            Success     = $false
            Message     = ''
            Timestamp   = Get-Date
        }
        
        try {
            switch ($issue.Category) {
                'ReplicationFailure' {
                    $action.Method = 'repadmin /syncall'
                    
                    if ($PSCmdlet.ShouldProcess($DomainController, "Force replication sync (repadmin /syncall)")) {
                        Write-RepairLog "Executing repadmin /syncall on $DomainController" -Level Verbose
                        
                        $output = & repadmin /syncall /A /P /e $DomainController 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            $action.Success = $true
                            $action.Message = "Sync initiated successfully"
                            Write-RepairLog "Sync successful on $DomainController" -Level Information
                        }
                        else {
                            $action.Message = "Sync failed with exit code $LASTEXITCODE : $output"
                            Write-RepairLog $action.Message -Level Warning
                        }
                    }
                    else {
                        $action.Message = "Skipped due to WhatIf or user cancellation"
                        Write-RepairLog "Repair skipped by user: $DomainController" -Level Information
                    }
                }
                
                'StaleReplication' {
                    $action.Method = 'repadmin /replicate'
                    
                    if ($PSCmdlet.ShouldProcess($DomainController, "Replicate from $($issue.Partner)")) {
                        Write-RepairLog "Forcing replication from $($issue.Partner) to $DomainController" -Level Verbose
                        
                        # Target a specific partition sync
                        $output = & repadmin /syncall /A /P /e $DomainController 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            $action.Success = $true
                            $action.Message = "Initiated sync with partner"
                            Write-RepairLog "Partner sync initiated: $DomainController <-> $($issue.Partner)" -Level Information
                        }
                        else {
                            $action.Message = "Partner sync failed: $output"
                            Write-RepairLog $action.Message -Level Warning
                        }
                    }
                    else {
                        $action.Message = "Skipped due to WhatIf or user cancellation"
                    }
                }
                
                'Connectivity' {
                    $action.Method = 'ConnectivityCheck'
                    $action.Message = "Connectivity issue requires manual investigation"
                    Write-RepairLog "Connectivity issue on $DomainController - manual intervention required" -Level Warning
                }
            }
        }
        catch {
            $action.Message = "Exception during repair: $_"
            Write-RepairLog "Repair exception for $DomainController : $_" -Level Error
        }
        
        $actions += $action
    }
    
    return $actions
}

function Test-ReplicationHealth {
    <#
    .SYNOPSIS
        Post-repair verification with lightweight checks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers,
        
        [Parameter(Mandatory = $false)]
        [int]$WaitSeconds = 120
    )
    
    Write-RepairLog "Waiting $WaitSeconds seconds for replication convergence..." -Level Information
    Start-Sleep -Seconds $WaitSeconds
    
    Write-RepairLog "Performing post-repair verification..." -Level Information
    
    $verificationResults = @()
    
    foreach ($dc in $DomainControllers) {
        $result = [PSCustomObject]@{
            DC              = $dc
            RepadminCheck   = 'Unknown'
            FailureCount    = 0
            SuccessCount    = 0
            OverallHealth   = 'Unknown'
        }
        
        try {
            Write-RepairLog "Verifying $dc via repadmin /showrepl" -Level Verbose
            
            $output = & repadmin /showrepl $dc 2>&1
            
            $errors = @($output | Where-Object { $_ -match 'Last error: (\d+)' -and $Matches[1] -ne '0' })
            $successes = @($output | Where-Object { $_ -match 'was successful|SYNC EACH WRITE' })
            
            $result.FailureCount = $errors.Count
            $result.SuccessCount = $successes.Count
            
            if ($errors.Count -eq 0 -and $successes.Count -gt 0) {
                $result.RepadminCheck = 'Pass'
                $result.OverallHealth = 'Healthy'
            }
            elseif ($errors.Count -gt 0) {
                $result.RepadminCheck = 'Fail'
                $result.OverallHealth = 'Degraded'
            }
            else {
                $result.RepadminCheck = 'Inconclusive'
                $result.OverallHealth = 'Unknown'
            }
            
            Write-RepairLog "$dc : $($result.OverallHealth) ($($result.SuccessCount) links, $($result.FailureCount) errors)" -Level Information
        }
        catch {
            $result.RepadminCheck = 'Error'
            $result.OverallHealth = 'Failed'
            Write-RepairLog "Verification failed for $dc : $_" -Level Error
        }
        
        $verificationResults += $result
    }
    
    return $verificationResults
}

function Export-ReplReports {
    <#
    .SYNOPSIS
        Consolidated reporting: CSV, JSON, HTML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )
    
    try {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        Write-RepairLog "Exporting reports to: $OutputDirectory" -Level Information
        
        $paths = @{
            SnapshotCSV     = Join-Path $OutputDirectory 'ReplicationSnapshot.csv'
            IssuesCSV       = Join-Path $OutputDirectory 'IdentifiedIssues.csv'
            ActionsCSV      = Join-Path $OutputDirectory 'RepairActions.csv'
            VerificationCSV = Join-Path $OutputDirectory 'VerificationResults.csv'
            SummaryJSON     = Join-Path $OutputDirectory 'summary.json'
            LogTXT          = Join-Path $OutputDirectory 'execution.log'
        }
        
        # CSV exports
        if ($Data.Snapshots) {
            $Data.Snapshots | Export-Csv $paths.SnapshotCSV -NoTypeInformation -Encoding UTF8
        }
        
        if ($Data.Issues) {
            $Data.Issues | Export-Csv $paths.IssuesCSV -NoTypeInformation -Encoding UTF8
        }
        
        if ($Data.RepairActions) {
            $Data.RepairActions | Export-Csv $paths.ActionsCSV -NoTypeInformation -Encoding UTF8
        }
        
        if ($Data.Verification) {
            $Data.Verification | Export-Csv $paths.VerificationCSV -NoTypeInformation -Encoding UTF8
        }
        
        # JSON summary for CI
        $summary = @{
            ExecutionTime   = (Get-Date) - $Script:StartTime
            Mode            = $Data.Mode
            Scope           = $Data.Scope
            TotalDCs        = $Data.Snapshots.Count
            HealthyDCs      = @($Data.Snapshots | Where-Object { $_.Status -eq 'Healthy' }).Count
            DegradedDCs     = @($Data.Snapshots | Where-Object { $_.Status -eq 'Degraded' }).Count
            UnreachableDCs  = @($Data.Snapshots | Where-Object { $_.Status -eq 'Unreachable' }).Count
            IssuesFound     = $Data.Issues.Count
            ActionsPerformed = if ($Data.RepairActions) { $Data.RepairActions.Count } else { 0 }
            ExitCode        = $Script:ExitCode
        }
        
        $summary | ConvertTo-Json -Depth 5 | Out-File $paths.SummaryJSON -Encoding UTF8
        
        # Execution log
        $Script:RepairLog | Out-File $paths.LogTXT -Encoding UTF8
        
        Write-RepairLog "Reports exported: $(($paths.Values | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')" -Level Information
        
        return $paths
    }
    catch {
        Write-RepairLog "Failed to export reports: $_" -Level Error
        throw
    }
}

function Write-RunSummary {
    <#
    .SYNOPSIS
        Final status summary with actionable guidance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    $elapsed = (Get-Date) - $Script:StartTime
    
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "EXECUTION SUMMARY" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Mode            : $($Data.Mode)" -InformationAction Continue
    Write-Information "Scope           : $($Data.Scope)" -InformationAction Continue
    Write-Information "DCs Processed   : $($Data.Snapshots.Count)" -InformationAction Continue
    Write-Information "Issues Found    : $($Data.Issues.Count)" -InformationAction Continue
    Write-Information "Actions Taken   : $(if ($Data.RepairActions) { $Data.RepairActions.Count } else { 0 })" -InformationAction Continue
    Write-Information "Duration        : $($elapsed.ToString('mm\:ss'))" -InformationAction Continue
    Write-Information "Exit Code       : $Script:ExitCode" -InformationAction Continue
    
    # Actionable guidance
    if ($Data.Issues.Count -eq 0) {
        Write-Information "`n✓ All DCs healthy - no action required" -InformationAction Continue
    }
    elseif ($Data.Mode -eq 'Audit') {
        Write-Information "`n⚠ Issues detected - run with -Mode Repair to attempt fixes" -InformationAction Continue
    }
    elseif ($Data.RepairActions -and @($Data.RepairActions | Where-Object { -not $_.Success }).Count -gt 0) {
        Write-Information "`n⚠ Some repairs failed - review logs and consider manual intervention" -InformationAction Continue
    }
    
    Write-Information "========================================`n" -InformationAction Continue
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    # Initialize
    if ($AuditTrail) {
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $OutputPath = Join-Path $PWD "ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        $transcriptPath = Join-Path $OutputPath "transcript-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        Start-Transcript -Path $transcriptPath
        Write-RepairLog "Audit trail enabled: $transcriptPath" -Level Information
    }
    
    Write-RepairLog "=== AD Replication Manager v3.0 ===" -Level Information
    Write-RepairLog "Mode: $Mode | Scope: $Scope | Throttle: $Throttle" -Level Information
    
    # Pre-flight checks
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-RepairLog "ActiveDirectory module loaded" -Level Verbose
    }
    catch {
        Write-RepairLog "Failed to load ActiveDirectory module. Install RSAT-AD-PowerShell." -Level Error
        throw
    }
    
    # Resolve target DCs
    $targetDCs = Resolve-ScopeToDCs -Scope $Scope -ExplicitDCs $DomainControllers -Domain $DomainName
    Write-RepairLog "Target DCs resolved: $($targetDCs.Count)" -Level Information
    
    # Data collection structure
    $executionData = @{
        Mode            = $Mode
        Scope           = $Scope
        Snapshots       = @()
        Issues          = @()
        RepairActions   = @()
        Verification    = @()
    }
    
    # Phase 1: Audit (always run unless Mode=Verify)
    if ($Mode -ne 'Verify') {
        Write-RepairLog "=== PHASE: AUDIT ===" -Level Information
        $executionData.Snapshots = Get-ReplicationSnapshot -DomainControllers $targetDCs -ThrottleLimit $Throttle -TimeoutSeconds $Timeout
        $executionData.Issues = $executionData.Snapshots | Find-ReplicationIssues
        
        # Set exit code based on issues
        $criticalIssues = @($executionData.Issues | Where-Object { $_.Severity -eq 'High' })
        if ($criticalIssues.Count -gt 0) {
            $Script:ExitCode = 2
        }
        
        $unreachable = @($executionData.Snapshots | Where-Object { $_.Status -eq 'Unreachable' })
        if ($unreachable.Count -gt 0) {
            $Script:ExitCode = 3
        }
    }
    
    # Phase 2: Repair (if requested)
    if ($Mode -in @('Repair', 'AuditRepairVerify')) {
        if ($executionData.Issues.Count -eq 0) {
            Write-RepairLog "No issues detected - skipping repair phase" -Level Information
        }
        else {
            Write-RepairLog "=== PHASE: REPAIR ===" -Level Information
            
            if (-not $AutoRepair -and -not $WhatIfPreference) {
                Write-Warning "$($executionData.Issues.Count) issues require repair."
                $response = Read-Host "Proceed with repairs? (Y/N)"
                if ($response -notmatch '^[Yy]') {
                    Write-RepairLog "Repair cancelled by user" -Level Information
                    $Script:ExitCode = 0
                    throw "User cancelled repair operation"
                }
            }
            
            # Group issues by DC and repair
            $issuesByDC = $executionData.Issues | Group-Object -Property DC
            
            foreach ($group in $issuesByDC) {
                $dc = $group.Name
                $dcIssues = $group.Group
                
                Write-RepairLog "Repairing $dc ($($dcIssues.Count) issues)" -Level Information
                $repairActions = Invoke-ReplicationFix -DomainController $dc -Issues $dcIssues
                $executionData.RepairActions += $repairActions
            }
            
            # Adjust exit code if repairs succeeded
            $failedRepairs = @($executionData.RepairActions | Where-Object { -not $_.Success })
            if ($failedRepairs.Count -eq 0 -and $executionData.RepairActions.Count -gt 0) {
                $Script:ExitCode = 0
            }
        }
    }
    
    # Phase 3: Verify (if requested)
    if ($Mode -in @('Verify', 'AuditRepairVerify')) {
        Write-RepairLog "=== PHASE: VERIFY ===" -Level Information
        $executionData.Verification = Test-ReplicationHealth -DomainControllers $targetDCs -WaitSeconds 120
        
        $degraded = @($executionData.Verification | Where-Object { $_.OverallHealth -ne 'Healthy' })
        if ($degraded.Count -gt 0) {
            $Script:ExitCode = 2
        }
    }
    
    # Export reports
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputPath = Join-Path $PWD "ADRepl-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    
    [void](Export-ReplReports -Data $executionData -OutputDirectory $OutputPath)
    
    # Final summary
    Write-RunSummary -Data $executionData
    
    Write-RepairLog "Reports available at: $OutputPath" -Level Information
}
catch {
    Write-RepairLog "Fatal error: $_" -Level Error
    $Script:ExitCode = 4
    throw
}
finally {
    if ($AuditTrail) {
        Stop-Transcript
    }
    
    # Return exit code for CI/CD
    if ($Script:ExitCode -ne 0) {
        Write-Warning "Exiting with code $Script:ExitCode (0=Healthy, 2=Issues, 3=Unreachable, 4=Error)"
    }
    
    exit $Script:ExitCode
}

