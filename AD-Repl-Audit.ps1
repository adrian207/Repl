 # Active Directory Replication Kickoff and Validation Script
# Initiates replication to all DCs in all sites and validates results

#region Helper Functions

function Get-SafeValue {
    param($Value, $Default = "Unknown")
    if ($null -eq $Value -or $Value -eq "") { return $Default } else { return $Value }
}

function Get-SafeCount {
    param($Collection)
    if ($Collection) { return $Collection.Count } else { return 0 }
}

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Color = switch ($Level) {
        "INFO" { "White" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
    }
    
    Write-Host "[$Timestamp] [$Level] $Message" -ForegroundColor $Color
    
    # Also write to log file if specified
    if ($Script:LogFile) {
        "[$Timestamp] [$Level] $Message" | Out-File -FilePath $Script:LogFile -Append
    }
}

#endregion

#region Core Replication Functions

function Get-AllDomainControllers {
    <#
    .SYNOPSIS
    Gets all domain controllers across all sites in the forest
    #>
    
    Write-LogMessage "Discovering all domain controllers in the forest..." -Level "INFO"
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Get all DCs in the forest
        $ForestDCs = @()
        
        # Get current forest
        $Forest = Get-ADForest -Current LocalComputer
        
        # Get DCs from each domain in the forest
        foreach ($Domain in $Forest.Domains) {
            try {
                Write-LogMessage "Getting DCs from domain: $Domain" -Level "INFO"
                $DomainDCs = Get-ADDomainController -Filter * -Server $Domain
                
                foreach ($DC in $DomainDCs) {
                    $ForestDCs += [PSCustomObject]@{
                        Name = $DC.Name
                        HostName = $DC.HostName
                        Domain = $DC.Domain
                        Forest = $DC.Forest
                        Site = $DC.Site
                        IPv4Address = $DC.IPv4Address
                        OperatingSystem = $DC.OperatingSystem
                        IsGlobalCatalog = $DC.IsGlobalCatalog
                        IsReadOnly = $DC.IsReadOnly
                        Roles = ($DC.OperationMasterRoles -join ", ")
                        Partitions = ($DC.Partitions -join ", ")
                    }
                }
            }
            catch {
                Write-LogMessage "Error getting DCs from domain $Domain : $($_.Exception.Message)" -Level "ERROR"
            }
        }
        
        Write-LogMessage "Found $($ForestDCs.Count) domain controllers across $($Forest.Domains.Count) domains" -Level "SUCCESS"
        
        # Group by site for reporting
        $SiteGroups = $ForestDCs | Group-Object Site
        Write-LogMessage "Domain controllers distributed across $($SiteGroups.Count) sites:" -Level "INFO"
        
        foreach ($SiteGroup in $SiteGroups) {
            Write-LogMessage "  Site: $($SiteGroup.Name) - $($SiteGroup.Count) DCs" -Level "INFO"
        }
        
        return $ForestDCs
    }
    catch {
        Write-LogMessage "Failed to discover domain controllers: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Test-DCConnectivity {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$DomainControllers
    )
    
    <#
    .SYNOPSIS
    Tests connectivity to all domain controllers before initiating replication
    #>
    
    Write-LogMessage "Testing connectivity to all domain controllers..." -Level "INFO"
    
    $ConnectivityResults = @()
    
    foreach ($DC in $DomainControllers) {
        Write-LogMessage "Testing connectivity to $($DC.Name)..." -Level "INFO"
        
        $ConnectivityTest = [PSCustomObject]@{
            DCName = $DC.Name
            Site = $DC.Site
            Domain = $DC.Domain
            IPv4Address = $DC.IPv4Address
            PingTest = $false
            RPC135Test = $false
            LDAP389Test = $false
            GlobalCatalog3268Test = $false
            OverallStatus = "FAIL"
            Details = ""
        }
        
        try {
            # Test ping connectivity
            $PingResult = Test-Connection -ComputerName $DC.IPv4Address -Count 2 -Quiet -ErrorAction SilentlyContinue
            $ConnectivityTest.PingTest = $PingResult
            
            # Test RPC endpoint mapper (port 135)
            $RPC135Result = Test-NetConnection -ComputerName $DC.IPv4Address -Port 135 -InformationLevel Quiet -WarningAction SilentlyContinue
            $ConnectivityTest.RPC135Test = $RPC135Result
            
            # Test LDAP (port 389)
            $LDAP389Result = Test-NetConnection -ComputerName $DC.IPv4Address -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
            $ConnectivityTest.LDAP389Test = $LDAP389Result
            
            # Test Global Catalog (port 3268) if this is a GC
            if ($DC.IsGlobalCatalog) {
                $GC3268Result = Test-NetConnection -ComputerName $DC.IPv4Address -Port 3268 -InformationLevel Quiet -WarningAction SilentlyContinue
                $ConnectivityTest.GlobalCatalog3268Test = $GC3268Result
            } else {
                $ConnectivityTest.GlobalCatalog3268Test = "N/A"
            }
            
            # Determine overall status
            $RequiredTests = $ConnectivityTest.PingTest -and $ConnectivityTest.RPC135Test -and $ConnectivityTest.LDAP389Test
            $GCTestOK = if ($DC.IsGlobalCatalog) { $ConnectivityTest.GlobalCatalog3268Test } else { $true }
            
            if ($RequiredTests -and $GCTestOK) {
                $ConnectivityTest.OverallStatus = "PASS"
                $ConnectivityTest.Details = "All connectivity tests passed"
            } elseif ($ConnectivityTest.PingTest -and $ConnectivityTest.LDAP389Test) {
                $ConnectivityTest.OverallStatus = "WARN"
                $ConnectivityTest.Details = "Basic connectivity OK but some ports failed"
            } else {
                $ConnectivityTest.OverallStatus = "FAIL"
                $ConnectivityTest.Details = "Critical connectivity issues detected"
            }
            
        }
        catch {
            $ConnectivityTest.Details = "Connectivity test failed: $($_.Exception.Message)"
        }
        
        $ConnectivityResults += $ConnectivityTest
        
        $StatusColor = switch ($ConnectivityTest.OverallStatus) {
            "PASS" { "SUCCESS" }
            "WARN" { "WARN" }
            "FAIL" { "ERROR" }
        }
        
        Write-LogMessage "$($DC.Name): $($ConnectivityTest.OverallStatus) - $($ConnectivityTest.Details)" -Level $StatusColor
    }
    
    # Summary
    $PassCount = ($ConnectivityResults | Where-Object OverallStatus -eq "PASS").Count
    $WarnCount = ($ConnectivityResults | Where-Object OverallStatus -eq "WARN").Count
    $FailCount = ($ConnectivityResults | Where-Object OverallStatus -eq "FAIL").Count
    
    Write-LogMessage "Connectivity Summary: $PassCount PASS, $WarnCount WARN, $FailCount FAIL" -Level "INFO"
    
    return $ConnectivityResults
}

function Start-ADReplicationToAllDCs {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$DomainControllers,
        [switch]$ForceReplication
    )
    
    <#
    .SYNOPSIS
    Initiates Active Directory replication to all domain controllers
    #>
    
    Write-LogMessage "Starting AD replication to all domain controllers..." -Level "INFO"
    
    $ReplicationResults = @()
    
    foreach ($DC in $DomainControllers) {
        Write-LogMessage "Initiating replication on $($DC.Name)..." -Level "INFO"
        
        $ReplicationResult = [PSCustomObject]@{
            DCName = $DC.Name
            Site = $DC.Site
            Domain = $DC.Domain
            ReplicationStatus = "PENDING"
            InboundReplication = "PENDING"
            OutboundReplication = "PENDING"
            Details = ""
            StartTime = Get-Date
            EndTime = $null
            Duration = $null
        }
        
        try {
            # Method 1: Use repadmin for comprehensive replication
            Write-LogMessage "Running repadmin /syncall on $($DC.Name)..." -Level "INFO"
            
            $SyncAllCommand = if ($ForceReplication) {
                "repadmin /syncall $($DC.Name) /A /e /P /q"
            } else {
                "repadmin /syncall $($DC.Name) /A /e /q"
            }
            
            $SyncAllResult = Invoke-Expression $SyncAllCommand 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $ReplicationResult.InboundReplication = "SUCCESS"
                Write-LogMessage "Inbound replication initiated successfully on $($DC.Name)" -Level "SUCCESS"
            } else {
                $ReplicationResult.InboundReplication = "FAILED"
                Write-LogMessage "Inbound replication failed on $($DC.Name): $SyncAllResult" -Level "ERROR"
            }
            
            # Method 2: Sync individual naming contexts
            Write-LogMessage "Synchronizing individual naming contexts on $($DC.Name)..." -Level "INFO"
            
            $OutboundSuccess = 0
            $OutboundTotal = 0
            
            # Get replication partners
            $ReplSummary = & repadmin /showrepl $($DC.Name) /csv 2>$null | ConvertFrom-Csv
            
            if ($ReplSummary) {
                $UniquePartners = $ReplSummary | Select-Object "Source DSA", "Naming Context" -Unique
                
                foreach ($Partner in $UniquePartners) {
                    $OutboundTotal++
                    try {
                        $SyncResult = & repadmin /sync $($DC.Name) $($Partner."Source DSA") $($Partner."Naming Context") 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $OutboundSuccess++
                        }
                    }
                    catch {
                        Write-LogMessage "Failed to sync with partner $($Partner.'Source DSA'): $($_.Exception.Message)" -Level "WARN"
                    }
                }
            }
            
            $ReplicationResult.OutboundReplication = if ($OutboundTotal -eq 0) { "NO_PARTNERS" } 
                                                   elseif ($OutboundSuccess -eq $OutboundTotal) { "SUCCESS" }
                                                   elseif ($OutboundSuccess -gt 0) { "PARTIAL" }
                                                   else { "FAILED" }
            
            # Overall status
            if ($ReplicationResult.InboundReplication -eq "SUCCESS" -and $ReplicationResult.OutboundReplication -in @("SUCCESS", "NO_PARTNERS")) {
                $ReplicationResult.ReplicationStatus = "SUCCESS"
                $ReplicationResult.Details = "Replication completed successfully"
            } elseif ($ReplicationResult.InboundReplication -eq "SUCCESS" -or $ReplicationResult.OutboundReplication -eq "PARTIAL") {
                $ReplicationResult.ReplicationStatus = "PARTIAL"
                $ReplicationResult.Details = "Replication partially successful"
            } else {
                $ReplicationResult.ReplicationStatus = "FAILED"
                $ReplicationResult.Details = "Replication failed"
            }
            
        }
        catch {
            $ReplicationResult.ReplicationStatus = "ERROR"
            $ReplicationResult.InboundReplication = "ERROR"
            $ReplicationResult.OutboundReplication = "ERROR"
            $ReplicationResult.Details = "Replication error: $($_.Exception.Message)"
            Write-LogMessage "Error initiating replication on $($DC.Name): $($_.Exception.Message)" -Level "ERROR"
        }
        
        $ReplicationResult.EndTime = Get-Date
        $ReplicationResult.Duration = ($ReplicationResult.EndTime - $ReplicationResult.StartTime).TotalSeconds
        
        $ReplicationResults += $ReplicationResult
        
        $StatusColor = switch ($ReplicationResult.ReplicationStatus) {
            "SUCCESS" { "SUCCESS" }
            "PARTIAL" { "WARN" }
            "FAILED" { "ERROR" }
            "ERROR" { "ERROR" }
        }
        
        Write-LogMessage "$($DC.Name): $($ReplicationResult.ReplicationStatus) - $($ReplicationResult.Details)" -Level $StatusColor
    }
    
    return $ReplicationResults
}

function Test-ADReplicationHealth {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$DomainControllers
    )
    
    <#
    .SYNOPSIS
    Validates AD replication health across all domain controllers
    #>
    
    Write-LogMessage "Validating AD replication health across all domain controllers..." -Level "INFO"
    
    $ReplicationHealthResults = @()
    
    foreach ($DC in $DomainControllers) {
        Write-LogMessage "Checking replication health on $($DC.Name)..." -Level "INFO"
        
        $HealthResult = [PSCustomObject]@{
            DCName = $DC.Name
            Site = $DC.Site
            Domain = $DC.Domain
            LastReplicationSuccess = $null
            LastReplicationAttempt = $null
            FailedReplications = 0
            ReplicationErrors = @()
            OverallHealth = "UNKNOWN"
            Details = ""
            HighestUSN = $null
            ReplicationPartners = 0
        }
        
        try {
            # Check replication status using repadmin
            Write-LogMessage "Running repadmin /showrepl on $($DC.Name)..." -Level "INFO"
            
            $ReplStatus = & repadmin /showrepl $($DC.Name) /csv 2>$null | ConvertFrom-Csv
            
            if ($ReplStatus) {
                $HealthResult.ReplicationPartners = ($ReplStatus | Select-Object "Source DSA" -Unique).Count
                
                # Check for replication failures
                $FailedReplications = $ReplStatus | Where-Object { $_."Last Failure Status" -ne "0" }
                $HealthResult.FailedReplications = Get-SafeCount $FailedReplications
                
                if ($FailedReplications) {
                    $HealthResult.ReplicationErrors = $FailedReplications | ForEach-Object {
                        "$($_.'Source DSA'): $($_.'Last Failure Status') - $($_.'Last Failure Time')"
                    }
                }
                
                # Get most recent successful replication
                $SuccessfulReplications = $ReplStatus | Where-Object { $_."Last Success Time" -ne $null }
                if ($SuccessfulReplications) {
                    $MostRecentSuccess = $SuccessfulReplications | Sort-Object "Last Success Time" -Descending | Select-Object -First 1
                    $HealthResult.LastReplicationSuccess = $MostRecentSuccess."Last Success Time"
                }
                
                # Get most recent replication attempt
                $AllReplications = $ReplStatus | Where-Object { $_."Last Attempt Time" -ne $null }
                if ($AllReplications) {
                    $MostRecentAttempt = $AllReplications | Sort-Object "Last Attempt Time" -Descending | Select-Object -First 1
                    $HealthResult.LastReplicationAttempt = $MostRecentAttempt."Last Attempt Time"
                }
            }
            
            # Check for replication errors in event log
            try {
                $ReplEvents = Get-WinEvent -ComputerName $DC.Name -FilterHashtable @{
                    LogName = 'Directory Service'
                    Level = 2  # Error
                    StartTime = (Get-Date).AddHours(-24)
                } -MaxEvents 10 -ErrorAction SilentlyContinue
                
                if ($ReplEvents) {
                    $ReplErrorCount = ($ReplEvents | Where-Object { $_.Message -like "*replication*" }).Count
                    if ($ReplErrorCount -gt 0) {
                        $HealthResult.ReplicationErrors += "Found $ReplErrorCount replication-related errors in event log (24h)"
                    }
                }
            }
            catch {
                Write-LogMessage "Could not check event log on $($DC.Name): $($_.Exception.Message)" -Level "WARN"
            }
            
            # Get highest USN for replication currency check
            try {
                $USNResult = & repadmin /showutdvec $($DC.Name) $DC.Domain 2>$null
                if ($USNResult) {
                    $USNNumbers = $USNResult | Where-Object { $_ -match "USN" } | ForEach-Object {
                        if ($_ -match "(\d+)") { [long]$matches[1] }
                    }
                    if ($USNNumbers) {
                        $HealthResult.HighestUSN = ($USNNumbers | Measure-Object -Maximum).Maximum
                    }
                }
            }
            catch {
                Write-LogMessage "Could not get USN information from $($DC.Name)" -Level "WARN"
            }
            
            # Determine overall health
            if ($HealthResult.FailedReplications -eq 0 -and $HealthResult.ReplicationPartners -gt 0) {
                $HealthResult.OverallHealth = "HEALTHY"
                $HealthResult.Details = "All replication partners healthy"
            } elseif ($HealthResult.FailedReplications -gt 0 -and $HealthResult.FailedReplications -le 2) {
                $HealthResult.OverallHealth = "WARNING"
                $HealthResult.Details = "Some replication failures detected"
            } elseif ($HealthResult.FailedReplications -gt 2) {
                $HealthResult.OverallHealth = "CRITICAL"
                $HealthResult.Details = "Multiple replication failures detected"
            } elseif ($HealthResult.ReplicationPartners -eq 0) {
                $HealthResult.OverallHealth = "ISOLATED"
                $HealthResult.Details = "No replication partners found"
            } else {
                $HealthResult.OverallHealth = "UNKNOWN"
                $HealthResult.Details = "Could not determine replication health"
            }
            
        }
        catch {
            $HealthResult.OverallHealth = "ERROR"
            $HealthResult.Details = "Health check error: $($_.Exception.Message)"
            Write-LogMessage "Error checking replication health on $($DC.Name): $($_.Exception.Message)" -Level "ERROR"
        }
        
        $ReplicationHealthResults += $HealthResult
        
        $StatusColor = switch ($HealthResult.OverallHealth) {
            "HEALTHY" { "SUCCESS" }
            "WARNING" { "WARN" }
            "CRITICAL" { "ERROR" }
            "ISOLATED" { "ERROR" }
            "ERROR" { "ERROR" }
            "UNKNOWN" { "WARN" }
        }
        
        Write-LogMessage "$($DC.Name): $($HealthResult.OverallHealth) - Partners: $($HealthResult.ReplicationPartners), Failed: $($HealthResult.FailedReplications)" -Level $StatusColor
    }
    
    return $ReplicationHealthResults
}

function Test-ADReplicationConsistency {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$DomainControllers
    )
    
    <#
    .SYNOPSIS
    Tests replication consistency by comparing key objects across DCs
    #>
    
    Write-LogMessage "Testing AD replication consistency across domain controllers..." -Level "INFO"
    
    $ConsistencyResults = @()
    
    # Group DCs by domain for consistency testing
    $DCsByDomain = $DomainControllers | Group-Object Domain
    
    foreach ($DomainGroup in $DCsByDomain) {
        $DomainName = $DomainGroup.Name
        $DomainDCs = $DomainGroup.Group
        
        Write-LogMessage "Testing consistency in domain: $DomainName" -Level "INFO"
        
        # Use first DC as baseline
        $BaselineDC = $DomainDCs[0]
        
        try {
            # Get baseline object counts and timestamps
            Write-LogMessage "Getting baseline data from $($BaselineDC.Name)..." -Level "INFO"
            
            $BaselineUsers = (Get-ADUser -Filter * -Server $BaselineDC.Name).Count
            $BaselineComputers = (Get-ADComputer -Filter * -Server $BaselineDC.Name).Count
            $BaselineGroups = (Get-ADGroup -Filter * -Server $BaselineDC.Name).Count
            
            # Test each DC against baseline
            foreach ($DC in $DomainDCs) {
                if ($DC.Name -eq $BaselineDC.Name) { continue }
                
                Write-LogMessage "Comparing $($DC.Name) against baseline $($BaselineDC.Name)..." -Level "INFO"
                
                $ConsistencyResult = [PSCustomObject]@{
                    DCName = $DC.Name
                    BaselineDC = $BaselineDC.Name
                    Domain = $DomainName
                    Site = $DC.Site
                    UserCountDiff = 0
                    ComputerCountDiff = 0
                    GroupCountDiff = 0
                    OverallConsistency = "UNKNOWN"
                    Details = ""
                    TestTime = Get-Date
                }
                
                try {
                    $DCUsers = (Get-ADUser -Filter * -Server $DC.Name).Count
                    $DCComputers = (Get-ADComputer -Filter * -Server $DC.Name).Count
                    $DCGroups = (Get-ADGroup -Filter * -Server $DC.Name).Count
                    
                    $ConsistencyResult.UserCountDiff = $DCUsers - $BaselineUsers
                    $ConsistencyResult.ComputerCountDiff = $DCComputers - $BaselineComputers
                    $ConsistencyResult.GroupCountDiff = $DCGroups - $BaselineGroups
                    
                    $MaxDiff = [Math]::Max([Math]::Abs($ConsistencyResult.UserCountDiff), 
                                          [Math]::Max([Math]::Abs($ConsistencyResult.ComputerCountDiff), 
                                                     [Math]::Abs($ConsistencyResult.GroupCountDiff)))
                    
                    if ($MaxDiff -eq 0) {
                        $ConsistencyResult.OverallConsistency = "PERFECT"
                        $ConsistencyResult.Details = "Object counts match perfectly"
                    } elseif ($MaxDiff -le 5) {
                        $ConsistencyResult.OverallConsistency = "GOOD"
                        $ConsistencyResult.Details = "Minor differences in object counts (≤5)"
                    } elseif ($MaxDiff -le 20) {
                        $ConsistencyResult.OverallConsistency = "ACCEPTABLE"
                        $ConsistencyResult.Details = "Moderate differences in object counts (≤20)"
                    } else {
                        $ConsistencyResult.OverallConsistency = "POOR"
                        $ConsistencyResult.Details = "Significant differences in object counts (>20)"
                    }
                    
                }
                catch {
                    $ConsistencyResult.OverallConsistency = "ERROR"
                    $ConsistencyResult.Details = "Consistency check error: $($_.Exception.Message)"
                }
                
                $ConsistencyResults += $ConsistencyResult
                
                $StatusColor = switch ($ConsistencyResult.OverallConsistency) {
                    "PERFECT" { "SUCCESS" }
                    "GOOD" { "SUCCESS" }
                    "ACCEPTABLE" { "WARN" }
                    "POOR" { "ERROR" }
                    "ERROR" { "ERROR" }
                }
                
                Write-LogMessage "$($DC.Name) vs $($BaselineDC.Name): $($ConsistencyResult.OverallConsistency) - Users: $($ConsistencyResult.UserCountDiff), Computers: $($ConsistencyResult.ComputerCountDiff), Groups: $($ConsistencyResult.GroupCountDiff)" -Level $StatusColor
            }
        }
        catch {
            Write-LogMessage "Error testing consistency in domain $DomainName : $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    return $ConsistencyResults
}

#endregion

#region Reporting Functions

function Generate-ReplicationReport {
    param(
        [Parameter(Mandatory=$true)]
        $ConnectivityResults,
        [Parameter(Mandatory=$true)]
        $ReplicationResults,
        [Parameter(Mandatory=$true)]
        $HealthResults,
        [Parameter(Mandatory=$true)]
        $ConsistencyResults,
        [Parameter(Mandatory=$true)]
        [string]$ExportPath
    )
    
    Write-LogMessage "Generating comprehensive replication reports..." -Level "INFO"
    
    $TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Export individual reports
    $ConnectivityResults | Export-Csv "$ExportPath\AD_Connectivity_$TimeStamp.csv" -NoTypeInformation
    $ReplicationResults | Export-Csv "$ExportPath\AD_Replication_$TimeStamp.csv" -NoTypeInformation
    $HealthResults | Export-Csv "$ExportPath\AD_ReplicationHealth_$TimeStamp.csv" -NoTypeInformation
    $ConsistencyResults | Export-Csv "$ExportPath\AD_ReplicationConsistency_$TimeStamp.csv" -NoTypeInformation
    
    # Generate summary report
    $Summary = @()
    
    # Connectivity Summary
    $ConnStats = $ConnectivityResults | Group-Object OverallStatus
    $Summary += [PSCustomObject]@{
        TestCategory = "Connectivity"
        TotalTests = $ConnectivityResults.Count
        PassCount = Get-SafeValue ($ConnStats | Where-Object Name -eq "PASS" | Select-Object -ExpandProperty Count) 0
        WarnCount = Get-SafeValue ($ConnStats | Where-Object Name -eq "WARN" | Select-Object -ExpandProperty Count) 0
        FailCount = Get-SafeValue ($ConnStats | Where-Object Name -eq "FAIL" | Select-Object -ExpandProperty Count) 0
        SuccessRate = if ($ConnectivityResults.Count -gt 0) { [math]::Round((Get-SafeValue ($ConnStats | Where-Object Name -eq "PASS" | Select-Object -ExpandProperty Count) 0) / $ConnectivityResults.Count * 100, 1) } else { 0 }
    }
    
    # Replication Summary
    $ReplStats = $ReplicationResults | Group-Object ReplicationStatus
    $Summary += [PSCustomObject]@{
        TestCategory = "Replication Kickoff"
        TotalTests = $ReplicationResults.Count
        PassCount = Get-SafeValue ($ReplStats | Where-Object Name -eq "SUCCESS" | Select-Object -ExpandProperty Count) 0
        WarnCount = Get-SafeValue ($ReplStats | Where-Object Name -eq "PARTIAL" | Select-Object -ExpandProperty Count) 0
        FailCount = Get-SafeValue ($ReplStats | Where-Object Name -in @("FAILED", "ERROR") | Select-Object -ExpandProperty Count) 0
        SuccessRate = if ($ReplicationResults.Count -gt 0) { [math]::Round((Get-SafeValue ($ReplStats | Where-Object Name -eq "SUCCESS" | Select-Object -ExpandProperty Count) 0) / $ReplicationResults.Count * 100, 1) } else { 0 }
    }
    
    # Health Summary
    $HealthStats = $HealthResults | Group-Object OverallHealth
    $HealthyCount = Get-SafeValue ($HealthStats | Where-Object Name -eq "HEALTHY" | Select-Object -ExpandProperty Count) 0
    $WarningCount = Get-SafeValue ($HealthStats | Where-Object Name -eq "WARNING" | Select-Object -ExpandProperty Count) 0
    $CriticalCount = Get-SafeValue ($HealthStats | Where-Object Name -in @("CRITICAL", "ISOLATED", "ERROR") | Select-Object -ExpandProperty Count) 0
    
    $Summary += [PSCustomObject]@{
        TestCategory = "Replication Health"
        TotalTests = $HealthResults.Count
        PassCount = $HealthyCount
        WarnCount = $WarningCount
        FailCount = $CriticalCount
        SuccessRate = if ($HealthResults.Count -gt 0) { [math]::Round($HealthyCount / $HealthResults.Count * 100, 1) } else { 0 }
    }
    
    # Export summary
    $Summary | Export-Csv "$ExportPath\AD_ReplicationSummary_$TimeStamp.csv" -NoTypeInformation
    
    # Display summary
    Write-LogMessage "=== REPLICATION TEST SUMMARY ===" -Level "INFO"
    $Summary | Format-Table -AutoSize
    
    # Calculate overall health score
    $TotalTests = ($Summary | Measure-Object TotalTests -Sum).Sum
    $TotalPassed = ($Summary | Measure-Object PassCount -Sum).Sum
    $OverallScore = if ($TotalTests -gt 0) { [math]::Round($TotalPassed / $TotalTests * 100, 1) } else { 0 }
    
    Write-LogMessage "=== OVERALL AD REPLICATION HEALTH SCORE: $OverallScore% ===" -Level $(
        if ($OverallScore -ge 90) { "SUCCESS" }
        elseif ($OverallScore -ge 75) { "WARN" }
        else { "ERROR" }
    )
    
    # Show critical issues
    $CriticalIssues = @()
    $CriticalIssues += $ConnectivityResults | Where-Object OverallStatus -eq "FAIL"
    $CriticalIssues += $ReplicationResults | Where-Object ReplicationStatus -in @("FAILED", "ERROR")
    $CriticalIssues += $HealthResults | Where-Object OverallHealth -in @("CRITICAL", "ISOLATED", "ERROR")
    $CriticalIssues += $ConsistencyResults | Where-Object OverallConsistency -in @("POOR", "ERROR")
    
    if ($CriticalIssues.Count -gt 0) {
        Write-LogMessage "=== CRITICAL REPLICATION ISSUES FOUND ($($CriticalIssues.Count)) ===" -Level "ERROR"
        $CriticalIssues | Select-Object DCName, Site, Details | Format-Table -AutoSize
    } else {
        Write-LogMessage "✓ No critical replication issues detected!" -Level "SUCCESS"
    }
    
    # Performance statistics
    if ($ReplicationResults -and $ReplicationResults.Count -gt 0) {
        $AvgDuration = ($ReplicationResults | Where-Object Duration | Measure-Object Duration -Average).Average
        $MaxDuration = ($ReplicationResults | Where-Object Duration | Measure-Object Duration -Maximum).Maximum
        $MinDuration = ($ReplicationResults | Where-Object Duration | Measure-Object Duration -Minimum).Minimum
        
        Write-LogMessage "=== REPLICATION PERFORMANCE ===" -Level "INFO"
        Write-LogMessage "Average Replication Time: $([math]::Round($AvgDuration, 2)) seconds" -Level "INFO"
        Write-LogMessage "Fastest Replication: $([math]::Round($MinDuration, 2)) seconds" -Level "INFO"
        Write-LogMessage "Slowest Replication: $([math]::Round($MaxDuration, 2)) seconds" -Level "INFO"
    }
    
    Write-LogMessage "Reports saved to: $ExportPath" -Level "SUCCESS"
    Write-LogMessage "Files generated:" -Level "INFO"
    Write-LogMessage "  - AD_Connectivity_$TimeStamp.csv" -Level "INFO"
    Write-LogMessage "  - AD_Replication_$TimeStamp.csv" -Level "INFO"
    Write-LogMessage "  - AD_ReplicationHealth_$TimeStamp.csv" -Level "INFO"
    Write-LogMessage "  - AD_ReplicationConsistency_$TimeStamp.csv" -Level "INFO"
    Write-LogMessage "  - AD_ReplicationSummary_$TimeStamp.csv" -Level "INFO"
}

#endregion

#region Main Execution Function

function Start-ADReplicationKickoffAndValidation {
    param(
        [string[]]$SpecificDCs = @(),
        [string[]]$SpecificSites = @(),
        [string[]]$ExcludeDCs = @(),
        [switch]$ForceReplication,
        [switch]$SkipConnectivityTest,
        [switch]$SkipConsistencyTest,
        [int]$MaxConcurrentJobs = 5,
        [string]$ExportPath = "C:\ADReplication",
        [string]$LogFile = ""
    )
    
    <#
    .SYNOPSIS
    Main function to kickoff replication to all DCs and validate results
    #>
    
    $StartTime = Get-Date
    
    # Set up logging
    if ($LogFile) {
        $Script:LogFile = $LogFile
        "=== AD Replication Kickoff and Validation - $(Get-Date) ===" | Out-File -FilePath $LogFile
    }
    
    Write-LogMessage "=== AD REPLICATION KICKOFF AND VALIDATION ===" -Level "INFO"
    Write-LogMessage "Start Time: $StartTime" -Level "INFO"
    Write-LogMessage "Force Replication: $ForceReplication" -Level "INFO"
    
    # Create export directory
    if (!(Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
        Write-LogMessage "Created export directory: $ExportPath" -Level "SUCCESS"
    }
    
    # Step 1: Discover all domain controllers
    Write-LogMessage "Step 1: Discovering domain controllers..." -Level "INFO"
    $AllDCs = Get-AllDomainControllers
    
    if ($AllDCs.Count -eq 0) {
        Write-LogMessage "No domain controllers found. Exiting." -Level "ERROR"
        return
    }
    
    # Filter DCs based on parameters
    $FilteredDCs = $AllDCs
    
    if ($SpecificDCs.Count -gt 0) {
        $FilteredDCs = $FilteredDCs | Where-Object { $_.Name -in $SpecificDCs }
        Write-LogMessage "Filtered to specific DCs: $($SpecificDCs -join ', ')" -Level "INFO"
    }
    
    if ($SpecificSites.Count -gt 0) {
        $FilteredDCs = $FilteredDCs | Where-Object { $_.Site -in $SpecificSites }
        Write-LogMessage "Filtered to specific sites: $($SpecificSites -join ', ')" -Level "INFO"
    }
    
    if ($ExcludeDCs.Count -gt 0) {
        $FilteredDCs = $FilteredDCs | Where-Object { $_.Name -notin $ExcludeDCs }
        Write-LogMessage "Excluded DCs: $($ExcludeDCs -join ', ')" -Level "INFO"
    }
    
    Write-LogMessage "Final DC list: $($FilteredDCs.Count) domain controllers" -Level "INFO"
    
    if ($FilteredDCs.Count -eq 0) {
        Write-LogMessage "No domain controllers match the specified criteria. Exiting." -Level "ERROR"
        return
    }
    
    # Step 2: Test connectivity (if not skipped)
    $ConnectivityResults = @()
    if (!$SkipConnectivityTest) {
        Write-LogMessage "Step 2: Testing connectivity to domain controllers..." -Level "INFO"
        $ConnectivityResults = Test-DCConnectivity -DomainControllers $FilteredDCs
        
        # Filter out unreachable DCs for replication
        $ReachableDCs = $FilteredDCs | Where-Object { 
            $ConnResult = $ConnectivityResults | Where-Object DCName -eq $_.Name
            $ConnResult.OverallStatus -in @("PASS", "WARN")
        }
        
        Write-LogMessage "Reachable DCs for replication: $($ReachableDCs.Count)" -Level "INFO"
    } else {
        Write-LogMessage "Step 2: Skipping connectivity test" -Level "WARN"
        $ReachableDCs = $FilteredDCs
    }
    
    # Step 3: Initiate replication
    Write-LogMessage "Step 3: Initiating AD replication..." -Level "INFO"
    $ReplicationResults = Start-ADReplicationToAllDCs -DomainControllers $ReachableDCs -ForceReplication:$ForceReplication
    
    # Wait for replication to settle
    Write-LogMessage "Waiting 30 seconds for replication to settle..." -Level "INFO"
    Start-Sleep -Seconds 30
    
    # Step 4: Validate replication health
    Write-LogMessage "Step 4: Validating replication health..." -Level "INFO"
    $HealthResults = Test-ADReplicationHealth -DomainControllers $ReachableDCs
    
    # Step 5: Test replication consistency (if not skipped)
    $ConsistencyResults = @()
    if (!$SkipConsistencyTest) {
        Write-LogMessage "Step 5: Testing replication consistency..." -Level "INFO"
        $ConsistencyResults = Test-ADReplicationConsistency -DomainControllers $ReachableDCs
    } else {
        Write-LogMessage "Step 5: Skipping consistency test" -Level "WARN"
    }
    
    # Step 6: Generate comprehensive report
    Write-LogMessage "Step 6: Generating reports..." -Level "INFO"
    Generate-ReplicationReport -ConnectivityResults $ConnectivityResults -ReplicationResults $ReplicationResults -HealthResults $HealthResults -ConsistencyResults $ConsistencyResults -ExportPath $ExportPath
    
    # Final summary
    $EndTime = Get-Date
    $TotalDuration = ($EndTime - $StartTime).TotalMinutes
    
    Write-LogMessage "=== AD REPLICATION PROCESS COMPLETE ===" -Level "SUCCESS"
    Write-LogMessage "End Time: $EndTime" -Level "INFO"
    Write-LogMessage "Total Duration: $([math]::Round($TotalDuration, 2)) minutes" -Level "INFO"
    Write-LogMessage "Domain Controllers Processed: $($FilteredDCs.Count)" -Level "INFO"
    Write-LogMessage "Replication Attempts: $($ReplicationResults.Count)" -Level "INFO"
    
    $SuccessfulReplications = ($ReplicationResults | Where-Object ReplicationStatus -eq "SUCCESS").Count
    $PartialReplications = ($ReplicationResults | Where-Object ReplicationStatus -eq "PARTIAL").Count
    $FailedReplications = ($ReplicationResults | Where-Object ReplicationStatus -in @("FAILED", "ERROR")).Count
    
    Write-LogMessage "Replication Results: $SuccessfulReplications SUCCESS, $PartialReplications PARTIAL, $FailedReplications FAILED" -Level "INFO"
    
    return @{
        DomainControllers = $FilteredDCs
        ConnectivityResults = $ConnectivityResults
        ReplicationResults = $ReplicationResults
        HealthResults = $HealthResults
        ConsistencyResults = $ConsistencyResults
        TotalDuration = $TotalDuration
    }
}

function Test-SingleDCReplication {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DCName,
        [switch]$ForceReplication
    )
    
    <#
    .SYNOPSIS
    Quick test for a single domain controller
    #>
    
    Write-LogMessage "Testing replication on single DC: $DCName" -Level "INFO"
    
    try {
        # Create a minimal DC object for testing
        $SingleDC = [PSCustomObject]@{
            Name = $DCName
            HostName = $DCName
            Domain = $env:USERDNSDOMAIN
            Site = "Unknown"
            IPv4Address = (Resolve-DnsName $DCName -Type A).IPAddress
        }
        
        # Test connectivity
        $ConnResult = Test-DCConnectivity -DomainControllers @($SingleDC)
        
        if ($ConnResult.OverallStatus -eq "FAIL") {
            Write-LogMessage "Cannot reach $DCName - skipping replication test" -Level "ERROR"
            return $false
        }
        
        # Initiate replication
        $ReplResult = Start-ADReplicationToAllDCs -DomainControllers @($SingleDC) -ForceReplication:$ForceReplication
        
        # Wait and check health
        Start-Sleep -Seconds 10
        $HealthResult = Test-ADReplicationHealth -DomainControllers @($SingleDC)
        
        Write-LogMessage "Single DC test complete for $DCName" -Level "SUCCESS"
        Write-LogMessage "Replication Status: $($ReplResult[0].ReplicationStatus)" -Level "INFO"
        Write-LogMessage "Health Status: $($HealthResult[0].OverallHealth)" -Level "INFO"
        
        return $ReplResult[0].ReplicationStatus -eq "SUCCESS" -and $HealthResult[0].OverallHealth -eq "HEALTHY"
    }
    catch {
        Write-LogMessage "Error testing single DC $DCName : $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

#endregion

# ===================================================================
# CONFIGURATION AND EXECUTION
# ===================================================================

Write-Host "=== AD REPLICATION KICKOFF AND VALIDATION SCRIPT ===" -ForegroundColor Cyan
Write-Host "This script will initiate replication to all domain controllers" -ForegroundColor Yellow
Write-Host "in every site and validate the results comprehensively." -ForegroundColor Yellow

# CONFIGURATION SETTINGS
$ReplicationConfig = @{
    SpecificDCs = @()           # Leave empty for all DCs, or specify: @("DC1", "DC2")
    SpecificSites = @()         # Leave empty for all sites, or specify: @("Site1", "Site2")
    ExcludeDCs = @()            # DCs to exclude: @("DC3", "DC4")
    ForceReplication = $false   # Set to $true to force immediate replication
    SkipConnectivityTest = $false
    SkipConsistencyTest = $false
    MaxConcurrentJobs = 5
    ExportPath = "C:\ADReplication"
    LogFile = "C:\ADReplication\ReplicationLog.txt"
}

Write-Host "`nCurrent Configuration:" -ForegroundColor Green
Write-Host "Target DCs: $(if($ReplicationConfig.SpecificDCs.Count -eq 0){'All DCs'}else{$ReplicationConfig.SpecificDCs -join ', '})" -ForegroundColor White
Write-Host "Target Sites: $(if($ReplicationConfig.SpecificSites.Count -eq 0){'All Sites'}else{$ReplicationConfig.SpecificSites -join ', '})" -ForegroundColor White
Write-Host "Force Replication: $($ReplicationConfig.ForceReplication)" -ForegroundColor White
Write-Host "Export Path: $($ReplicationConfig.ExportPath)" -ForegroundColor White
Write-Host "Log File: $($ReplicationConfig.LogFile)" -ForegroundColor White

Write-Host "`nThis script will:" -ForegroundColor Cyan
Write-Host "1. Discover all domain controllers in the forest" -ForegroundColor White
Write-Host "2. Test connectivity to each DC" -ForegroundColor White
Write-Host "3. Initiate replication using repadmin /syncall" -ForegroundColor White
Write-Host "4. Validate replication health and status" -ForegroundColor White
Write-Host "5. Test replication consistency across DCs" -ForegroundColor White
Write-Host "6. Generate comprehensive reports" -ForegroundColor White

Write-Host "`nRequired tools:" -ForegroundColor Yellow
Write-Host "- Active Directory PowerShell module" -ForegroundColor White
Write-Host "- repadmin.exe (part of AD DS tools)" -ForegroundColor White
Write-Host "- Administrative privileges on domain controllers" -ForegroundColor White

Write-Host "`nPress Enter to start AD replication kickoff and validation, or Ctrl+C to cancel..." -ForegroundColor Yellow
Read-Host

# EXECUTE REPLICATION KICKOFF AND VALIDATION
try {
    $Results = Start-ADReplicationKickoffAndValidation @ReplicationConfig
    
    if ($Results) {
        Write-Host "`n=== PROCESS COMPLETED SUCCESSFULLY ===" -ForegroundColor Green
        Write-Host "Check the export directory for detailed reports: $($ReplicationConfig.ExportPath)" -ForegroundColor Cyan
        
        # Quick summary
        $TotalDCs = $Results.DomainControllers.Count
        $SuccessfulReplications = ($Results.ReplicationResults | Where-Object ReplicationStatus -eq "SUCCESS").Count
        $HealthyDCs = ($Results.HealthResults | Where-Object OverallHealth -eq "HEALTHY").Count
        
        Write-Host "`nQuick Summary:" -ForegroundColor Yellow
        Write-Host "Total DCs: $TotalDCs" -ForegroundColor White
        Write-Host "Successful Replications: $SuccessfulReplications" -ForegroundColor White
        Write-Host "Healthy DCs: $HealthyDCs" -ForegroundColor White
        Write-Host "Total Time: $([math]::Round($Results.TotalDuration, 2)) minutes" -ForegroundColor White
    }
}
catch {
    Write-Error "AD replication process failed: $($_.Exception.Message)"
    Write-Host "`nCommon issues:" -ForegroundColor Yellow
    Write-Host "1. Insufficient administrative privileges" -ForegroundColor White
    Write-Host "2. repadmin.exe not available (install AD DS tools)" -ForegroundColor White
    Write-Host "3. Network connectivity issues to domain controllers" -ForegroundColor White
    Write-Host "4. Active Directory module not installed" -ForegroundColor White
    Write-Host "5. Firewall blocking required ports (135, 389, 3268, 445)" -ForegroundColor White
}

Write-Host "`n=== ADDITIONAL FUNCTIONS AVAILABLE ===" -ForegroundColor Cyan
Write-Host "For quick single DC testing:" -ForegroundColor Yellow
Write-Host 'Test-SingleDCReplication -DCName "DC01.domain.com"' -ForegroundColor White -BackgroundColor DarkBlue

Write-Host "`nFor custom execution:" -ForegroundColor Yellow
Write-Host 'Start-ADReplicationKickoffAndValidation -SpecificSites @("MainSite") -ForceReplication' -ForegroundColor White -BackgroundColor DarkGreen

Write-Host "`nScript completed." -ForegroundColor Cyan 
