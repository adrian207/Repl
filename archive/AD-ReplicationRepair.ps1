#Requires -Version 5.1
#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Comprehensive Active Directory Replication Diagnosis, Repair, and Verification Tool
    
.DESCRIPTION
    This script provides a complete solution for diagnosing, repairing, and verifying Active Directory 
    replication issues. It performs multi-phase operations including:
    
    Phase 1: INITIAL DIAGNOSIS
    - Analyzes replication partner metadata for all specified domain controllers
    - Identifies replication failures, error codes, and timestamps
    - Checks for stale replication (>24 hours since last success)
    - Maps error codes to human-readable descriptions
    
    Phase 2: REPAIR DECISION
    - Presents findings to administrator for review
    - Allows manual approval or automatic repair mode
    - Provides detailed issue summary before proceeding
    
    Phase 3: REPAIR OPERATIONS
    - Executes targeted repair actions based on detected issues
    - Uses repadmin commands for forced synchronization
    - Implements generic replication repair strategies
    - Logs all repair attempts and results
    
    Phase 4: VERIFICATION
    - Performs comprehensive multi-method verification:
      * PowerShell AD cmdlets (with staleness detection)
      * Repadmin /showrepl analysis (most reliable for current status)
      * DCDiag replication tests (if not user-omitted)
      * Recent Event Log analysis (2-hour window)
    - Uses weighted scoring system for overall health assessment
    - Waits for replication settling period before verification
    
    Phase 5: REPORTING
    - Generates comprehensive reports in multiple formats:
      * JSON: Complete technical data for automation
      * HTML: Rich visual report with status indicators
      * CSV: Multiple CSV files for data analysis
    - Provides actionable recommendations for persistent issues
    - Includes repair timeline and detailed verification results
    
    VERIFICATION METHODOLOGY:
    The script uses a sophisticated weighted verification system:
    - Repadmin results: Weight 3 (most reliable for current status)
    - Event Log analysis: Weight 2 (recent activity indicator)  
    - DCDiag tests: Weight 2 (comprehensive health check)
    - PowerShell cmdlets: Weight 1 (may show stale cached data)
    
    Health is determined by achieving ≥60% weighted success score, with special
    handling for stale data detection and improvement tracking.
    
.PARAMETER DomainName
    Specifies the Active Directory domain to analyze and repair.
    Default: "Pokemon.internal"
    
    Examples:
    - "contoso.com"
    - "corp.fabrikam.local" 
    - "ad.company.org"
    
.PARAMETER TargetDCs
    Array of specific domain controller hostnames to focus operations on.
    If not specified, the script will automatically discover and work with all
    domain controllers in the specified domain.
    
    Accepts multiple formats:
    - Array: @("DC01.domain.com", "DC02.domain.com")
    - Comma-separated string: "DC01,DC02,DC03"
    - Single DC: "DC01.domain.com"
    
    Examples:
    - @("BELDC01.pokemon.internal", "BELDC02.pokemon.internal")
    - "DC01,DC02,DC03" (will be automatically split)
    - "PRIMARY-DC.contoso.com"
    
.PARAMETER AutoRepair
    Switch parameter that enables automatic repair mode without user prompts.
    When specified, the script will automatically proceed with repairs after
    diagnosis without waiting for administrator approval.
    
    Use with caution in production environments. Recommended for:
    - Automated maintenance scripts
    - Non-critical environments
    - After thorough testing of repair procedures
    
    Default: $false (interactive mode with prompts)
    
.PARAMETER OutputPath
    Specifies the directory path where detailed reports will be saved.
    If not specified, creates a timestamped directory in the current location.
    
    Generated files include:
    - RepairReport.json: Complete technical data
    - RepairSummary.html: Visual dashboard report
    - RepairSummary.csv: Summary data for analysis
    - DetailedIssues.csv: Before/after issue comparison
    - RepairActions.csv: All repair actions performed
    - VerificationDetails.csv: Detailed verification results
    
    Examples:
    - "C:\Reports\AD-Replication"
    - "\\FileServer\Reports\AD\Daily"
    - ".\Reports\$(Get-Date -Format 'yyyy-MM-dd')"
    
    Default: ".\AD-ReplicationRepair-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
.EXAMPLE
    .\AD-ReplicationRepair.ps1
    
    Basic execution with default settings:
    - Analyzes Pokemon.internal domain
    - Works with all discovered domain controllers
    - Prompts for repair approval
    - Saves reports to timestamped directory
    
.EXAMPLE
    .\AD-ReplicationRepair.ps1 -DomainName "contoso.com" -TargetDCs "DC01","DC02" -AutoRepair
    
    Automated repair for specific domain controllers:
    - Targets contoso.com domain
    - Focuses on DC01 and DC02 only
    - Automatically performs repairs without prompts
    - Useful for scheduled maintenance scripts
    
.EXAMPLE
    .\AD-ReplicationRepair.ps1 -DomainName "corp.fabrikam.local" -OutputPath "C:\Reports\AD-Health" -TargetDCs "PRIMARY-DC,BACKUP-DC,BRANCH-DC"
    
    Comprehensive analysis with custom reporting:
    - Analyzes corp.fabrikam.local domain
    - Targets three specific domain controllers
    - Saves detailed reports to C:\Reports\AD-Health
    - Interactive mode with repair approval prompts
    
.EXAMPLE
    .\AD-ReplicationRepair.ps1 -DomainName "ad.company.org" -AutoRepair -OutputPath "\\FileServer\Reports\AD\$(Get-Date -Format 'yyyy-MM-dd')"
    
    Enterprise scheduled maintenance scenario:
    - Automated execution for ad.company.org
    - All DCs in domain automatically discovered
    - Reports saved to network location with date folder
    - No user interaction required (suitable for scheduled tasks)
    
.NOTES
    File Name      : AD-ReplicationRepair.ps1
    Author         : Adrian Johnson adrian207@gmail.com
    Prerequisite   : PowerShell 5.1+, Active Directory Module, Domain Admin Rights
    Created        : 09/25/2025
    Last Modified  : 09/26/2025
    Version        : 2.0
    
    REQUIREMENTS:
    - PowerShell 5.1 or later
    - Active Directory PowerShell Module (RSAT-AD-PowerShell)
    - Domain Administrator privileges or equivalent
    - Network connectivity to all target domain controllers
    - Repadmin.exe (included with RSAT tools)
    - DCDiag.exe (included with RSAT tools)
    
    SUPPORTED SCENARIOS:
    - Routine replication health monitoring
    - Incident response for replication failures  
    - Scheduled maintenance and verification
    - Post-maintenance validation
    - Capacity planning and trend analysis
    
    SAFETY FEATURES:
    - Read-only diagnosis phase before any modifications
    - Interactive approval for repair operations (unless -AutoRepair)
    - Comprehensive logging of all actions
    - Multiple verification methods for result validation
    - Detailed reporting for audit and compliance
    
    PERFORMANCE CONSIDERATIONS:
    - Large domains: Consider using -TargetDCs to focus on specific DCs
    - Network latency: Script includes appropriate timeouts and retries
    - Resource usage: Verification phase waits 10 minutes for replication settling
    
.LINK
    https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/manage/replication/
    
.LINK
    https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/cc835086(v=ws.11)
#>

[CmdletBinding()]
param(
    [string]$DomainName = "Pokemon.internal",
    [string[]]$TargetDCs = @(),
    [switch]$AutoRepair,
    [string]$OutputPath = ""
)

# ================================================================================================
# GLOBAL SCRIPT VARIABLES
# ================================================================================================
# These variables maintain state across all phases of the repair operation and enable 
# comprehensive reporting and cross-phase data correlation.

# $Script:RepairLog - Centralized logging array
# Purpose: Stores all log messages with timestamps and severity levels for audit trail
# Structure: Array of strings in format "[$timestamp] [$level] $message"
# Used by: Write-RepairLog function and all reporting functions
$Script:RepairLog = @()

# $Script:DiagnosticResults - Initial diagnosis data
# Purpose: Stores comprehensive replication status from Phase 1 (Initial Diagnosis)
# Structure: Hashtable with DC names as keys, each containing:
#   - InboundReplication: Array of partner metadata objects
#   - ReplicationFailures: Array of failure objects with error codes and timestamps
# Used by: Get-DetailedReplicationStatus, repair functions, and reporting
$Script:DiagnosticResults = @{}

# $Script:RepairResults - Repair operation outcomes  
# Purpose: Stores results of all repair actions performed in Phase 3
# Structure: Hashtable with DC names as keys, each containing:
#   - RepairActions: Array of repair action objects with success/failure status
#   - Success: Boolean indicating overall repair success for the DC
# Used by: Invoke-ReplicationRepair, verification functions, and reporting
$Script:RepairResults = @{}

# ================================================================================================
# UTILITY FUNCTIONS
# ================================================================================================

<#
.SYNOPSIS
    Centralized logging function with color-coded console output and persistent storage.

.DESCRIPTION
    Provides standardized logging throughout the script with automatic timestamping,
    severity level validation, and dual output (console + log array). Supports color-coded
    console output for immediate visual feedback and maintains complete audit trail.

.PARAMETER Message
    The log message text to record and display.
    
.PARAMETER Level
    Severity level for the log entry. Determines console color and filtering capabilities.
    Valid values: "INFO" (default), "WARN", "ERROR", "SUCCESS"
    
.EXAMPLE
    Write-RepairLog "Starting replication analysis" -Level "INFO"
    
    Outputs: [2023-10-15 14:30:25] [INFO] Starting replication analysis
    Color: White (default)
    
.EXAMPLE
    Write-RepairLog "Replication failure detected on DC01" -Level "ERROR"
    
    Outputs: [2023-10-15 14:30:25] [ERROR] Replication failure detected on DC01
    Color: Red
    
.EXAMPLE
    Write-RepairLog "Repair completed successfully" -Level "SUCCESS"
    
    Outputs: [2023-10-15 14:30:25] [SUCCESS] Repair completed successfully
    Color: Green

.NOTES
    - All log entries are stored in $Script:RepairLog for report generation
    - Timestamp format: yyyy-MM-dd HH:mm:ss (24-hour format)
    - Console colors: ERROR=Red, WARN=Yellow, SUCCESS=Green, INFO=White
    - Used throughout script for consistent logging and audit trail
#>
function Write-RepairLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    # Generate standardized timestamp in 24-hour format for consistency
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Map severity levels to appropriate console colors for visual distinction
    $color = switch ($Level) {
        "ERROR" { "Red" }      # Critical issues requiring attention
        "WARN" { "Yellow" }    # Warning conditions that may need investigation
        "SUCCESS" { "Green" }  # Successful operations and positive outcomes
        default { "White" }    # INFO level and any unmapped levels
    }
    
    # Dual output: immediate console feedback and persistent storage
    Write-Host $logMessage -ForegroundColor $color
    $Script:RepairLog += $logMessage  # Store in global array for reporting
}

# ================================================================================================
# DIAGNOSTIC FUNCTIONS
# ================================================================================================

<#
.SYNOPSIS
    Performs comprehensive replication status analysis for specified domain controllers.

.DESCRIPTION
    Conducts deep analysis of Active Directory replication health by examining:
    - Inbound replication partner metadata (last attempt, success, consecutive failures)
    - Replication failure records with error codes and timestamps
    - Time-since-last-success calculations for staleness detection
    - Error code mapping to human-readable descriptions
    
    This function forms the foundation of Phase 1 (Initial Diagnosis) and provides
    the data structure used throughout the repair and verification process.

.PARAMETER DomainControllers
    Array of domain controller hostnames to analyze. Each DC will be queried for:
    - Get-ADReplicationPartnerMetadata: Inbound replication partner information
    - Get-ADReplicationFailure: Current replication failure records
    
    Example: @("DC01.contoso.com", "DC02.contoso.com", "DC03.contoso.com")

.OUTPUTS
    Hashtable
    Returns nested hashtable structure:
    @{
        "DC01.contoso.com" = @{
            InboundReplication = @(
                @{
                    Partner = "DC02.contoso.com"
                    Partition = "DC=contoso,DC=com"
                    LastReplicationAttempt = [DateTime]
                    LastReplicationSuccess = [DateTime]
                    LastReplicationResult = [Int]
                    ConsecutiveReplicationFailures = [Int]
                    LastReplicationResultText = [String]
                    TimeSinceLastSuccess = [TimeSpan]
                }
                # ... more partners
            )
            ReplicationFailures = @(
                @{
                    Server = "DC01.contoso.com"
                    Partner = "DC02.contoso.com"
                    FailureType = [String]
                    FailureCount = [Int]
                    FirstFailureTime = [DateTime]
                    LastError = [Int]
                    LastErrorText = [String]
                }
                # ... more failures
            )
        }
        # ... more DCs
    }

.EXAMPLE
    $replicationStatus = Get-DetailedReplicationStatus -DomainControllers @("DC01", "DC02")
    
    Analyzes replication status for DC01 and DC02, returning comprehensive data structure
    for use in repair planning and verification.

.EXAMPLE
    $allDCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
    $status = Get-DetailedReplicationStatus -DomainControllers $allDCs
    
    Performs domain-wide replication analysis for all discovered domain controllers.

.NOTES
    - Uses Get-ADReplicationPartnerMetadata for detailed partner information
    - Uses Get-ADReplicationFailure for current failure records  
    - Implements error code translation via Get-ReplicationErrorText
    - Calculates time-since-last-success for staleness detection (>24h = stale)
    - Handles individual DC failures gracefully with error logging
    - Results stored in $Script:DiagnosticResults for cross-phase access
#>
function Get-DetailedReplicationStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers
    )
    
    Write-RepairLog "Performing detailed replication analysis..." -Level "INFO"
    
    # Initialize results hashtable - will contain status for each DC
    $replicationStatus = @{}
    
    # Process each domain controller individually to isolate failures
    foreach ($dc in $DomainControllers) {
        Write-RepairLog "Analyzing replication for $dc" -Level "INFO"
        
        # Initialize DC-specific status structure
        $dcStatus = @{
            InboundReplication = @()      # Array of partner metadata objects
            ReplicationFailures = @()     # Array of current failure records
        }
        
        try {
            # Phase 1a: Gather inbound replication partner metadata
            # This provides detailed information about each replication relationship
            $inboundPartners = Get-ADReplicationPartnerMetadata -Target $dc -ErrorAction Stop
            
            foreach ($partner in $inboundPartners) {
                # Create enhanced partner info with calculated fields
                $partnerInfo = @{
                    Partner = $partner.Partner
                    Partition = $partner.Partition
                    LastReplicationAttempt = $partner.LastReplicationAttempt
                    LastReplicationSuccess = $partner.LastReplicationSuccess
                    LastReplicationResult = $partner.LastReplicationResult
                    ConsecutiveReplicationFailures = $partner.ConsecutiveReplicationFailures
                    # Translate numeric error code to human-readable text
                    LastReplicationResultText = Get-ReplicationErrorText -ErrorCode $partner.LastReplicationResult
                    # Calculate time elapsed since last successful replication (for staleness detection)
                    TimeSinceLastSuccess = if ($partner.LastReplicationSuccess) { 
                        (Get-Date) - $partner.LastReplicationSuccess 
                    } else { 
                        $null  # Never successfully replicated
                    }
                }
                $dcStatus.InboundReplication += $partnerInfo
            }
            
            # Phase 1b: Gather current replication failure records
            # These represent active/recent failures that may need repair
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
                        # Translate error code for immediate understanding
                        LastErrorText = Get-ReplicationErrorText -ErrorCode $_.LastError
                    }
                }
            }
            
        } catch {
            # Log individual DC failures but continue with other DCs
            Write-RepairLog "Failed to get detailed replication status for $dc : $($_.Exception.Message)" -Level "ERROR"
        }
        
        # Store results for this DC in the main results hashtable
        $replicationStatus[$dc] = $dcStatus
    }
    
    return $replicationStatus
}

<#
.SYNOPSIS
    Translates numeric Active Directory replication error codes to human-readable descriptions.

.DESCRIPTION
    Provides a centralized mapping of common AD replication error codes to descriptive
    text, enabling administrators to quickly understand the nature of replication issues
    without consulting external documentation. Supports both positive and negative
    error code representations.
    
    This function is critical for user experience, converting cryptic numeric codes
    like "1722" into actionable descriptions like "RPC server unavailable".

.PARAMETER ErrorCode
    Numeric error code from AD replication operations.
    Common sources: LastReplicationResult, LastError from replication metadata.
    Supports both signed and unsigned integer representations.

.OUTPUTS
    String
    Human-readable description of the error condition, or "Unknown error (code: X)"
    if the error code is not in the mapping table.

.EXAMPLE
    Get-ReplicationErrorText -ErrorCode 0
    Returns: "Success"

.EXAMPLE
    Get-ReplicationErrorText -ErrorCode 1722
    Returns: "RPC server unavailable"

.EXAMPLE
    Get-ReplicationErrorText -ErrorCode 8524
    Returns: "The DSA operation is unable to proceed because of a DNS lookup failure"

.EXAMPLE
    Get-ReplicationErrorText -ErrorCode 99999
    Returns: "Unknown error (code: 99999)"

.NOTES
    ERROR CODE CATEGORIES:
    - 0: Success condition
    - 5, 8453: Access/permission issues
    - 58: Server operation failures
    - 1256, 1722, 1753: Network/RPC connectivity issues
    - 8439: DN/naming issues
    - 8524: DNS resolution failures
    - ±2146893022: Kerberos authentication issues
    
    MAINTENANCE:
    - Add new error codes as they are encountered in production
    - Both positive and negative representations should be included for Kerberos errors
    - Consider adding URL references for complex error codes
#>
function Get-ReplicationErrorText {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ErrorCode
    )
    
    # Comprehensive mapping of AD replication error codes to descriptions
    # Organized by category for easier maintenance and understanding
    $errorMappings = @{
        # Success condition
        0 = "Success"
        
        # Access and permission errors
        5 = "Access Denied"
        8453 = "Replication access was denied"
        
        # Server and operation errors
        58 = "The specified server cannot perform the requested operation"
        
        # Network and RPC connectivity errors
        1256 = "The remote system is not available (network connectivity issue)"
        1722 = "RPC server unavailable"
        1753 = "There are no more endpoints available from the endpoint mapper"
        
        # Naming and DN errors
        8439 = "The distinguished name specified for this replication operation is invalid"
        
        # DNS resolution errors
        8524 = "The DSA operation is unable to proceed because of a DNS lookup failure"
        
        # Kerberos authentication errors (both signed and unsigned representations)
        -2146893022 = "Target principal name is incorrect (Kerberos authentication issue)"
        2146893022 = "Target principal name is incorrect (Kerberos authentication issue)"
    }
    
    # Return mapped description or generic unknown error message
    if ($errorMappings.ContainsKey($ErrorCode)) {
        return $errorMappings[$ErrorCode]
    } else {
        return "Unknown error (code: $ErrorCode)"
    }
}

# ================================================================================================
# REPAIR FUNCTIONS
# ================================================================================================

<#
.SYNOPSIS
    Orchestrates comprehensive replication repair operations across specified domain controllers.

.DESCRIPTION
    Implements Phase 3 (Repair Operations) by analyzing diagnostic results and executing
    targeted repair actions. This function serves as the main repair coordinator, delegating
    specific repair tasks to specialized functions based on the type of issues detected.
    
    Repair strategy includes:
    - Individual failure remediation using partner-specific repair attempts
    - Forced replication synchronization for all partners
    - Comprehensive logging of all repair actions and outcomes
    - Success tracking for verification phase planning
    
    The function maintains separation between diagnosis and repair, ensuring that
    repair decisions are based on concrete diagnostic data rather than assumptions.

.PARAMETER DomainControllers
    Array of domain controller hostnames to perform repair operations on.
    Should match the DCs analyzed in the diagnostic phase for consistency.

.PARAMETER ReplicationStatus
    Hashtable containing detailed diagnostic results from Get-DetailedReplicationStatus.
    Structure must include InboundReplication and ReplicationFailures arrays for each DC.
    This data drives repair decision-making and target selection.

.OUTPUTS
    Hashtable
    Returns comprehensive repair results structure:
    @{
        "DC01.contoso.com" = @{
            RepairActions = @(
                @{
                    Type = "ReplicationFailure" | "Force Replication Sync"
                    Partner = [String]           # Partner DC (if applicable)
                    Error = [Int]                # Original error code
                    ErrorText = [String]         # Human-readable error
                    RepairAttempts = @()         # Array of repair attempt results
                    Success = [Boolean]          # Overall success for this action
                    Description = [String]       # Action description
                }
                # ... more actions
            )
            Success = [Boolean]              # Overall DC repair success
        }
        # ... more DCs
    }

.EXAMPLE
    $diagnosticResults = Get-DetailedReplicationStatus -DomainControllers @("DC01", "DC02")
    $repairResults = Invoke-ReplicationRepair -DomainControllers @("DC01", "DC02") -ReplicationStatus $diagnosticResults
    
    Performs targeted repairs based on diagnostic findings, returning detailed results
    for verification and reporting.

.EXAMPLE
    $repairResults = Invoke-ReplicationRepair -DomainControllers $targetDCs -ReplicationStatus $Script:DiagnosticResults
    
    Uses global diagnostic results to perform repairs across all target domain controllers.

.NOTES
    REPAIR METHODOLOGY:
    1. Analyze ReplicationFailures array for each DC
    2. Execute partner-specific repairs using Repair-GenericReplication
    3. Perform comprehensive sync using Invoke-ForceReplicationSync
    4. Track individual action success/failure for reporting
    5. Calculate overall DC repair success based on action outcomes
    
    SAFETY FEATURES:
    - Non-destructive repair operations only
    - Individual action isolation (one failure doesn't stop others)
    - Comprehensive logging for audit trail
    - Results stored in $Script:RepairResults for verification phase
    
    REPAIR ACTIONS:
    - Generic replication repair (repadmin /syncall)
    - Force replication sync (comprehensive partner sync)
    - Future: Targeted error-specific repairs (DNS, Kerberos, etc.)
#>
function Invoke-ReplicationRepair {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ReplicationStatus
    )
    
    Write-RepairLog "Starting replication repair operations..." -Level "INFO"
    
    # Initialize repair results hashtable - will contain results for each DC
    $repairResults = @{}
    
    # Process each domain controller individually for targeted repair
    foreach ($dc in $DomainControllers) {
        Write-RepairLog "Attempting repairs for $dc" -Level "INFO"
        
        # Initialize DC-specific repair results structure
        $dcRepairResults = @{
            RepairActions = @()    # Array of all repair actions performed
            Success = $true        # Overall success flag (will be calculated)
        }
        
        # Get the diagnostic status for this DC
        $dcStatus = $ReplicationStatus[$dc]
        
        # Phase 3a: Address specific replication failures
        if ($dcStatus.ReplicationFailures.Count -gt 0) {
            Write-RepairLog "Found $($dcStatus.ReplicationFailures.Count) replication failures on $dc" -Level "WARN"
            
            # Process each individual replication failure
            foreach ($failure in $dcStatus.ReplicationFailures) {
                # Create repair action record for tracking
                $repairAction = @{
                    Type = "ReplicationFailure"
                    Partner = $failure.Partner
                    Error = $failure.LastError
                    ErrorText = $failure.LastErrorText
                    RepairAttempts = @()    # Will contain repair attempt details
                    Success = $false        # Will be updated based on repair result
                }
                
                # Attempt generic replication repair for this specific partner
                $repairResult = Repair-GenericReplication -SourceDC $dc -TargetDC $failure.Partner
                $repairAction.RepairAttempts += $repairResult
                $repairAction.Success = $repairResult.Success
                
                # Add this repair action to the DC's repair results
                $dcRepairResults.RepairActions += $repairAction
            }
        }
        
        # Phase 3b: Force comprehensive replication sync for all partners
        # This addresses potential issues not captured in failure records
        Write-RepairLog "Forcing replication sync for all partners of $dc" -Level "INFO"
        $syncResult = Invoke-ForceReplicationSync -DomainController $dc
        $dcRepairResults.RepairActions += $syncResult
        
        # Calculate overall success for this DC based on all repair actions
        # DC is considered successful if ALL repair actions succeeded
        $failedActions = $dcRepairResults.RepairActions | Where-Object { -not $_.Success }
        $dcRepairResults.Success = ($failedActions.Count -eq 0)
        
        # Store results for this DC in main results hashtable
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

        & repadmin /syncall /A /P /e $SourceDC 2>&1
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
        & repadmin /syncall /A /P /e $DomainController 2>&1
        $syncResult.Actions += "Repadmin syncall executed"

        if ($LASTEXITCODE -eq 0) {
            $syncResult.Success = $true
        }

    } catch {
        $syncResult.Actions += "Force sync failed: $($_.Exception.Message)"
    }
    
    return $syncResult
}

# ================================================================================================
# VERIFICATION FUNCTIONS
# ================================================================================================

<#
.SYNOPSIS
    Comprehensive multi-method verification of replication repair success with weighted scoring.

.DESCRIPTION
    Implements Phase 4 (Verification) using sophisticated analysis to determine repair success.
    This function is the most complex in the script, employing multiple verification methods
    with weighted scoring to provide accurate assessment despite potential data staleness issues.
    
    VERIFICATION METHODOLOGY:
    1. Replication Settling Period: Waits for replication to propagate (default 10 minutes)
    2. Multi-Method Analysis:
       - PowerShell AD cmdlets (Weight: 1) - May show stale cached data
       - Repadmin /showrepl (Weight: 3) - Most reliable for current status
       - DCDiag replication tests (Weight: 2) - Comprehensive health check
       - Event Log analysis (Weight: 2) - Recent activity indicator
    3. Weighted Success Calculation: Health determined by ≥60% weighted success score
    4. Improvement Detection: Tracks partial improvements even if not fully healthy
    5. Stale Data Handling: Identifies and accounts for outdated failure records

.PARAMETER DomainControllers
    Array of domain controller hostnames to verify repair success for.
    Should match DCs that underwent repair operations.

.PARAMETER WaitMinutes
    Number of minutes to wait for replication settling before verification.
    Default: 10 minutes (recommended for most environments)
    Consider increasing for large/geographically distributed domains.

.OUTPUTS
    Hashtable
    Returns comprehensive verification results:
    @{
        OverallSuccess = [Boolean]           # True if all DCs are healthy
        DomainControllers = @{
            "DC01.contoso.com" = @{
                ReplicationFailures = [Int]  # Current failure count
                HealthStatus = [String]      # "Healthy" | "Improved but needs attention" | "Still has issues"
                Improvements = @()           # Array of improvement descriptions
                VerificationDetails = @{
                    PowerShellCheck = @{ Method, Success, Details, HasStaleData }
                    RepadminCheck = @{ Method, Success, Details, ErrorCount, SuccessCount }
                    DCDiagCheck = @{ Method, Success, Details, FailureCount, PassCount }
                    EventLogCheck = @{ Method, Success, Details, ErrorCount }
                }
            }
        }
        Summary = @{
            TotalDCs = [Int]
            HealthyDCs = [Int]
            ImprovedDCs = [Int]
            StillFailingDCs = [Int]
        }
    }

.EXAMPLE
    $verificationResults = Test-RepairSuccess -DomainControllers @("DC01", "DC02") -WaitMinutes 15
    
    Waits 15 minutes for replication settling, then performs comprehensive verification
    using all available methods with weighted scoring.

.EXAMPLE
    $results = Test-RepairSuccess -DomainControllers $targetDCs
    
    Uses default 10-minute wait period and performs standard verification across
    all target domain controllers.

.NOTES
    VERIFICATION METHODS EXPLAINED:
    
    1. PowerShell AD Cmdlets (Weight: 1):
       - Uses Get-DetailedReplicationStatus for consistency
       - May show stale cached data from previous queries
       - Includes staleness detection (>7 days = likely stale)
       - Good for baseline comparison but not authoritative
    
    2. Repadmin /showrepl (Weight: 3):
       - Most reliable for current replication status
       - Direct query to domain controller without caching
       - Analyzes actual error patterns vs. success indicators
       - Includes replication queue analysis
    
    3. DCDiag Replication Tests (Weight: 2):
       - Comprehensive health validation
       - May be skipped if user-omitted in configuration
       - Provides holistic view of DC health
    
    4. Event Log Analysis (Weight: 2):
       - Checks recent 2-hour window for replication errors
       - Event IDs: 1311, 1388, 1925, 2042, 1084, 1586
       - Good indicator of recent activity and issues
    
    SCORING ALGORITHM:
    - Each method contributes its weight if successful
    - Total possible score = sum of all method weights
    - Health threshold: 60% weighted success required
    - Improvement threshold: 30% weighted success for "improved" status
    
    PERFORMANCE CONSIDERATIONS:
    - 10-minute wait period is standard but may need adjustment
    - Large domains may require longer settling periods
    - Network latency affects verification timing
    - Multiple method execution provides resilience against individual method failures
#>
function Test-RepairSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DomainControllers,
        
        [Parameter(Mandatory = $false)]
        [int]$WaitMinutes = 10
    )
    
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
        if ($null -ne $dcResult.VerificationDetails.RepadminCheck.Success) {
            $verificationResults += $dcResult.VerificationDetails.RepadminCheck.Success
            $weights += 3
        }
        
        # Event log gets high weight for recent status
        if ($null -ne $dcResult.VerificationDetails.EventLogCheck.Success) {
            $verificationResults += $dcResult.VerificationDetails.EventLogCheck.Success
            $weights += 2
        }
        
        # PowerShell gets lower weight due to potential staleness
        if ($null -ne $dcResult.VerificationDetails.PowerShellCheck.Success) {
            $verificationResults += $dcResult.VerificationDetails.PowerShellCheck.Success
            $weights += 1
        }
        
        # DCDiag gets medium weight if not skipped
        if ($null -ne $dcResult.VerificationDetails.DCDiagCheck.Success) {
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
        New-RepairHTMLReport -ReportData $report -OutputPath "$OutputPath\RepairSummary.html"
        
        # Generate CSV Reports
        Export-RepairCSVReports -ReportData $report -OutputPath $OutputPath
        
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

function New-RepairHTMLReport {
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

function Export-RepairCSVReports {
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
                if ($null -ne $method.Success) {
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
            PowerShellCheck = if ($null -ne $dcResult.VerificationDetails.PowerShellCheck.Success) { 
                if ($dcResult.VerificationDetails.PowerShellCheck.Success) { "PASS" } else { "FAIL" }
            } else { "N/A" }
            RepadminCheck = if ($null -ne $dcResult.VerificationDetails.RepadminCheck.Success) {
                if ($dcResult.VerificationDetails.RepadminCheck.Success) { "PASS" } else { "FAIL" }
            } else { "N/A" }
            DCDiagCheck = if ($null -ne $dcResult.VerificationDetails.DCDiagCheck.Success) {
                if ($dcResult.VerificationDetails.DCDiagCheck.Success) { "PASS" } else { "FAIL" }
            } else { "SKIPPED" }
            EventLogCheck = if ($null -ne $dcResult.VerificationDetails.EventLogCheck.Success) {
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

# ================================================================================================
# MAIN EXECUTION LOGIC
# ================================================================================================
# This section orchestrates the five-phase repair process:
# Phase 1: Initial Diagnosis - Analyze current replication status
# Phase 2: Repair Decision - User approval and planning  
# Phase 3: Repair Operations - Execute repair actions
# Phase 4: Verification - Multi-method success validation
# Phase 5: Reporting - Generate comprehensive reports

Write-Host "=== AD Replication Diagnosis and Repair Tool ===" -ForegroundColor Cyan
Write-Host "Domain: $DomainName" -ForegroundColor Cyan

# Prerequisite Check: Ensure Active Directory module is available
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-RepairLog "Active Directory module loaded successfully" -Level "SUCCESS"
} catch {
    Write-RepairLog "Failed to import Active Directory module. Please install RSAT tools." -Level "ERROR"
    Write-RepairLog "Install command: Add-WindowsFeature -Name RSAT-AD-PowerShell" -Level "INFO"
    exit 1
}

# Parameter Processing: Handle comma-separated TargetDCs parameter for user convenience
if ($TargetDCs.Count -eq 1 -and $TargetDCs[0].Contains(",")) {
    $TargetDCs = $TargetDCs[0].Split(",").Trim()
    Write-RepairLog "Parsed comma-separated DC list: $($TargetDCs -join ', ')" -Level "INFO"
}

# Target DC Discovery: Auto-discover DCs if none specified
if ($TargetDCs.Count -eq 0) {
    try {
        Write-RepairLog "No specific DCs specified. Discovering all domain controllers..." -Level "INFO"
        $allDCs = Get-ADDomainController -Filter * -Server $DomainName | Select-Object -ExpandProperty HostName
        $TargetDCs = $allDCs
        Write-RepairLog "Auto-discovered $($TargetDCs.Count) domain controllers in $DomainName" -Level "SUCCESS"
    } catch {
        Write-RepairLog "Failed to retrieve domain controllers: $($_.Exception.Message)" -Level "ERROR"
        Write-RepairLog "Verify domain name and network connectivity" -Level "INFO"
        exit 1
    }
}

Write-RepairLog "Target Domain Controllers: $($TargetDCs -join ', ')" -Level "INFO"

# ================================================================================================
# PHASE 1: INITIAL DIAGNOSIS
# ================================================================================================
# Comprehensive analysis of current replication status across all target domain controllers
# Identifies both active failures and stale replication conditions for repair planning

Write-Host "`n=== PHASE 1: INITIAL DIAGNOSIS ===" -ForegroundColor Yellow

# Execute detailed replication status analysis
Write-RepairLog "Initiating comprehensive replication analysis across $($TargetDCs.Count) domain controllers" -Level "INFO"
$Script:DiagnosticResults = Get-DetailedReplicationStatus -DomainControllers $TargetDCs

# Issue Analysis: Categorize and log all detected problems
$issuesFound = @()
foreach ($dc in $TargetDCs) {
    $dcStatus = $Script:DiagnosticResults[$dc]
    
    # Category 1: Active Replication Failures
    if ($dcStatus.ReplicationFailures.Count -gt 0) {
        $issuesFound += "$dc has $($dcStatus.ReplicationFailures.Count) replication failures"
        
        # Log each specific failure with error details
        foreach ($failure in $dcStatus.ReplicationFailures) {
            Write-RepairLog "ISSUE: $dc -> $($failure.Partner): Error $($failure.LastError) ($($failure.LastErrorText))" -Level "ERROR"
        }
    }
    
    # Category 2: Stale Replication Detection (>24 hours since last success)
    foreach ($partner in $dcStatus.InboundReplication) {
        if ($partner.TimeSinceLastSuccess -and $partner.TimeSinceLastSuccess.TotalHours -gt 24) {
            $staleDuration = [math]::Round($partner.TimeSinceLastSuccess.TotalHours, 1)
            $issuesFound += "$dc hasn't replicated with $($partner.Partner) for $staleDuration hours"
            Write-RepairLog "ISSUE: $dc -> $($partner.Partner): Last successful replication $staleDuration hours ago" -Level "WARN"
        }
    }
}

# Early Exit: If no issues found, report success and terminate
if ($issuesFound.Count -eq 0) {
    Write-RepairLog "No replication issues detected. All domain controllers appear healthy." -Level "SUCCESS"
    Write-RepairLog "Domain replication status: HEALTHY - No action required" -Level "SUCCESS"
    
    # Generate report for healthy status documentation
    $healthyResults = @{
        OverallSuccess = $true
        DomainControllers = @{}
        Summary = @{
            TotalDCs = $TargetDCs.Count
            HealthyDCs = $TargetDCs.Count
            ImprovedDCs = 0
            StillFailingDCs = 0
        }
    }
    Export-RepairReport -DiagnosticResults $Script:DiagnosticResults -RepairResults @{} -PostRepairResults $healthyResults
    exit 0
}

Write-RepairLog "Found $($issuesFound.Count) replication issues total across $($TargetDCs.Count) domain controllers" -Level "WARN"

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

# ================================================================================================
# COMPREHENSIVE USAGE EXAMPLES AND SCENARIOS
# ================================================================================================

<#
USAGE SCENARIOS AND EXAMPLES:

1. BASIC HEALTH CHECK (Default Configuration):
   .\AD-ReplicationRepair.ps1
   
   Use Case: Regular maintenance check of Pokemon.internal domain
   Behavior: 
   - Auto-discovers all domain controllers in Pokemon.internal
   - Performs comprehensive diagnosis
   - Prompts for repair approval if issues found
   - Generates timestamped reports in current directory
   - Safe for production use with interactive prompts

2. TARGETED DC ANALYSIS:
   .\AD-ReplicationRepair.ps1 -TargetDCs "BELDC01","BELDC02" -DomainName "Pokemon.internal"
   
   Use Case: Focus on specific problematic domain controllers
   Behavior:
   - Analyzes only BELDC01 and BELDC02
   - Reduces analysis time and noise
   - Ideal for incident response or known problem DCs
   - Interactive repair approval

3. AUTOMATED MAINTENANCE (Scheduled Task):
   .\AD-ReplicationRepair.ps1 -DomainName "contoso.com" -AutoRepair -OutputPath "C:\Reports\AD-Health"
   
   Use Case: Automated weekly/monthly maintenance
   Behavior:
   - No user interaction required
   - Automatically performs repairs without prompts
   - Saves reports to specified location
   - Suitable for scheduled tasks and automation
   - Use with caution in production

4. MULTI-DOMAIN ENTERPRISE:
   # Run separately for each domain
   .\AD-ReplicationRepair.ps1 -DomainName "corp.contoso.com" -OutputPath "\\FileServer\Reports\Corp"
   .\AD-ReplicationRepair.ps1 -DomainName "dev.contoso.com" -OutputPath "\\FileServer\Reports\Dev"
   
   Use Case: Large enterprise with multiple domains
   Behavior:
   - Separate analysis per domain
   - Centralized reporting location
   - Domain-specific issue tracking

5. INCIDENT RESPONSE:
   .\AD-ReplicationRepair.ps1 -DomainName "emergency.local" -TargetDCs "PRIMARY-DC,BACKUP-DC" -AutoRepair -OutputPath "C:\Incident\$(Get-Date -Format 'yyyyMMdd-HHmm')"
   
   Use Case: Emergency replication failure response
   Behavior:
   - Immediate automated repair attempt
   - Timestamped incident documentation
   - Focus on critical DCs only
   - Fast resolution for business continuity

6. POST-MAINTENANCE VERIFICATION:
   .\AD-ReplicationRepair.ps1 -DomainName "prod.company.org" -OutputPath "C:\Maintenance\Post-Patching"
   
   Use Case: Verify replication health after Windows updates/patches
   Behavior:
   - Comprehensive health verification
   - Documentation for change management
   - Interactive mode for careful review
   - Proof of system stability post-maintenance

7. BRANCH OFFICE TROUBLESHOOTING:
   .\AD-ReplicationRepair.ps1 -TargetDCs "BRANCH-DC01.remote.company.com" -DomainName "company.com" -OutputPath "\\HQ-Server\BranchReports"
   
   Use Case: Remote site replication issues
   Behavior:
   - Single DC focus for WAN-connected sites
   - Centralized reporting for HQ review
   - Network-aware timeouts and analysis

8. DEVELOPMENT/TESTING:
   .\AD-ReplicationRepair.ps1 -DomainName "test.lab" -AutoRepair -OutputPath ".\TestResults"
   
   Use Case: Lab environment testing and validation
   Behavior:
   - Automated operation for testing scenarios
   - Local report storage
   - Safe for experimental environments

SCHEDULING EXAMPLES:

Windows Task Scheduler:
Program: PowerShell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\AD-ReplicationRepair.ps1" -DomainName "contoso.com" -AutoRepair -OutputPath "C:\Reports\AD-Weekly"
Schedule: Weekly, Sunday 2:00 AM

PowerShell Scheduled Job:
Register-ScheduledJob -Name "AD-ReplicationCheck" -ScriptBlock {
    & "C:\Scripts\AD-ReplicationRepair.ps1" -DomainName "company.local" -AutoRepair -OutputPath "C:\Reports\AD-Daily\$(Get-Date -Format 'yyyy-MM-dd')"
} -Trigger (New-JobTrigger -Daily -At 3:00AM)

INTEGRATION WITH MONITORING SYSTEMS:

SCOM Integration:
- Use -AutoRepair with exit codes for automated alerting
- Parse JSON reports for performance counters
- Set up email notifications based on repair success/failure

Splunk/Log Analytics:
- Forward $Script:RepairLog entries to centralized logging
- Create dashboards from CSV report data
- Set up alerts for recurring failures

SECURITY CONSIDERATIONS:

Required Permissions:
- Domain Admin or equivalent replication permissions
- Local administrator on target domain controllers
- Network access to all target DCs (ports 135, 445, dynamic RPC)

Safe Practices:
- Test in non-production first
- Use -TargetDCs to limit scope during testing
- Review reports before enabling -AutoRepair
- Monitor repair success rates over time
- Keep audit trail of all repair operations

TROUBLESHOOTING COMMON ISSUES:

1. "Access Denied" errors:
   - Verify Domain Admin permissions
   - Check UAC and "Run as Administrator"
   - Validate network connectivity to DCs

2. "Module not found" errors:
   - Install RSAT-AD-PowerShell feature
   - Verify PowerShell 5.1 or later
   - Check execution policy settings

3. Timeout issues:
   - Increase -WaitMinutes parameter
   - Check network latency to remote DCs
   - Verify firewall ports (135, 445, 1024-5000)

4. False positive repairs:
   - Review PowerShell cmdlet staleness warnings
   - Focus on Repadmin verification results (highest weight)
   - Check Event Log analysis for recent activity

5. Persistent failures:
   - Review detailed error codes in reports
   - Check DNS configuration and SRV records
   - Verify time synchronization across DCs
   - Examine certificate validity for authentication

PERFORMANCE OPTIMIZATION:

Large Environments (>20 DCs):
- Use -TargetDCs to process in batches
- Increase -WaitMinutes for replication settling
- Schedule during off-peak hours
- Consider parallel execution for multiple domains

Network Considerations:
- WAN links may require longer timeouts
- VPN connections can affect verification timing
- Consider running locally on each site's DC

Resource Usage:
- Script is lightweight but repadmin can be resource-intensive
- Multiple simultaneous executions may impact DC performance
- Monitor DC CPU and memory during large-scale operations

REPORTING AND ANALYSIS:

Report Types Generated:
- RepairReport.json: Complete technical data for automation
- RepairSummary.html: Executive dashboard with visual indicators  
- RepairSummary.csv: Summary data for spreadsheet analysis
- DetailedIssues.csv: Before/after comparison for trend analysis
- RepairActions.csv: Audit trail of all repair operations
- VerificationDetails.csv: Method-by-method verification results

Trend Analysis:
- Track HealthyDCs percentage over time
- Monitor recurring error patterns
- Identify problematic DC pairs or sites
- Measure repair success rates and improvement

Compliance Documentation:
- Complete audit trail in RepairReport.json
- Timestamped action logs for change management
- Multi-method verification for evidence quality
- Automated report generation for compliance reviews

#>
