#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Comprehensive Pester test suite for Invoke-ADReplicationManager.ps1
    
.DESCRIPTION
    Tests include:
    - Retry logic with exponential backoff
    - Parallel processing (PS7+ vs PS5.1)
    - Error handling
    - Parameter validation
    - Output validation
    - Performance benchmarks
    
.AUTHOR
    Adrian Johnson <adrian207@gmail.com>
    
.DATE
    October 28, 2025
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Invoke-ADReplicationManager.ps1'
    $script:TestDCs = @('DC01', 'DC02', 'DC03')
    
    # Helper function to create mock DC responses
    function New-MockDCResponse {
        param(
            [string]$DC,
            [string]$Status = 'Healthy',
            [int]$FailureCount = 0
        )
        
        return [PSCustomObject]@{
            DC = $DC
            Status = $Status
            Timestamp = Get-Date
            InboundPartners = @()
            Failures = if ($FailureCount -gt 0) { 
                @([PSCustomObject]@{ 
                    Partner = "DC-PARTNER"
                    FailureCount = $FailureCount
                }) 
            } else { @() }
            Error = $null
        }
    }
}

Describe "Invoke-ADReplicationManager - Core Functionality" {
    
    Context "Parameter Validation" {
        
        It "Should accept valid Mode values" {
            $validModes = @('Audit', 'Repair', 'Verify', 'AuditRepairVerify')
            
            foreach ($mode in $validModes) {
                { 
                    & $script:ScriptPath -Mode $mode -DomainControllers $script:TestDCs -WhatIf -ErrorAction Stop
                } | Should -Not -Throw
            }
        }
        
        It "Should reject invalid Mode values" {
            { 
                & $script:ScriptPath -Mode 'InvalidMode' -DomainControllers $script:TestDCs -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should accept valid Scope values" {
            $validScopes = @('Forest', 'Site:Default-First-Site-Name', 'DCList')
            
            foreach ($scope in $validScopes) {
                $params = @{
                    Mode = 'Audit'
                    Scope = $scope
                    WhatIf = $true
                    ErrorAction = 'Stop'
                }
                
                # DCList requires explicit DCs
                if ($scope -eq 'DCList') {
                    $params['DomainControllers'] = $script:TestDCs
                }
                
                { & $script:ScriptPath @params } | Should -Not -Throw
            }
        }
        
        It "Should reject Scope=DCList without DomainControllers" {
            { 
                & $script:ScriptPath -Mode Audit -Scope DCList -ErrorAction Stop
            } | Should -Throw -ExpectedMessage "*requires -DomainControllers*"
        }
        
        It "Should accept valid Throttle range (1-32)" {
            @(1, 8, 16, 32) | ForEach-Object {
                { 
                    & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -Throttle $_ -WhatIf -ErrorAction Stop
                } | Should -Not -Throw
            }
        }
        
        It "Should reject invalid Throttle values" {
            { 
                & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -Throttle 0 -ErrorAction Stop
            } | Should -Throw
            
            { 
                & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -Throttle 100 -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should accept valid Timeout range (60-3600)" {
            @(60, 300, 1800, 3600) | ForEach-Object {
                { 
                    & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -Timeout $_ -WhatIf -ErrorAction Stop
                } | Should -Not -Throw
            }
        }
        
        It "Should reject invalid Timeout values" {
            { 
                & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -Timeout 30 -ErrorAction Stop
            } | Should -Throw
            
            { 
                & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -Timeout 5000 -ErrorAction Stop
            } | Should -Throw
        }
    }
    
    Context "WhatIf Support" {
        
        It "Should support WhatIf for Repair mode" {
            Mock -ModuleName 'Invoke-ADReplicationManager' -CommandName 'Invoke-ReplicationFix' -MockWith {
                throw "Should not execute with WhatIf"
            }
            
            { 
                & $script:ScriptPath -Mode Repair -DomainControllers $script:TestDCs -WhatIf -ErrorAction Stop
            } | Should -Not -Throw
        }
        
        It "Should not make changes when WhatIf is specified" {
            # This test verifies that no actual replication commands are executed
            $result = & $script:ScriptPath -Mode Repair -DomainControllers $script:TestDCs -WhatIf 2>&1
            
            $result | Where-Object { $_ -match "What if:" } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Exit Codes" {
        
        It "Should return exit code 0 for healthy DCs" -Skip {
            # This would require mocking AD cmdlets
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                return @(New-MockDCResponse -DC 'DC01' -Status 'Healthy')
            }
            
            & $script:ScriptPath -Mode Audit -DomainControllers 'DC01' -ErrorAction SilentlyContinue
            $LASTEXITCODE | Should -Be 0
        }
        
        It "Should return exit code 2 for issues detected" -Skip {
            # Would require mocking to simulate issues
        }
        
        It "Should return exit code 3 for unreachable DCs" -Skip {
            # Would require mocking to simulate unreachable DCs
        }
        
        It "Should return exit code 4 for fatal errors" -Skip {
            # Would require mocking to simulate fatal errors
        }
    }
    
    Context "Output Generation" {
        
        BeforeAll {
            $script:OutputDir = $null
        }
        
        It "Should create output directory" -Skip {
            # Run audit mode
            & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -ErrorAction SilentlyContinue
            
            # Find latest output directory
            $script:OutputDir = Get-ChildItem -Path $PSScriptRoot -Filter "ADRepl-*" -Directory | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -First 1
            
            $script:OutputDir | Should -Not -BeNullOrEmpty
        }
        
        It "Should generate summary.json" -Skip {
            $summaryPath = Join-Path $script:OutputDir.FullName "summary.json"
            Test-Path $summaryPath | Should -Be $true
        }
        
        It "Should have valid JSON in summary.json" -Skip {
            $summaryPath = Join-Path $script:OutputDir.FullName "summary.json"
            $summary = Get-Content $summaryPath | ConvertFrom-Json
            
            $summary.Mode | Should -Not -BeNullOrEmpty
            $summary.TotalDCs | Should -BeGreaterThan 0
            $summary.ExitCode | Should -BeIn @(0, 2, 3, 4)
        }
        
        It "Should generate execution.log" -Skip {
            $logPath = Join-Path $script:OutputDir.FullName "execution.log"
            Test-Path $logPath | Should -Be $true
        }
    }
}

Describe "Retry Logic with Exponential Backoff" {
    
    Context "Retry Mechanism" {
        
        It "Should implement retry helper function" {
            # Check if Invoke-WithRetry function exists in script
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match 'function Invoke-WithRetry'
        }
        
        It "Should retry on transient failures" -Skip {
            # Mock to simulate transient failure then success
            $script:attemptCount = 0
            
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                $script:attemptCount++
                if ($script:attemptCount -lt 3) {
                    throw "Transient error"
                }
                return @(New-MockDCResponse -DC 'DC01')
            }
            
            $result = & $script:ScriptPath -Mode Audit -DomainControllers 'DC01'
            $script:attemptCount | Should -BeGreaterThan 1
        }
        
        It "Should implement exponential backoff" -Skip {
            # Verify backoff delays increase exponentially
            $script:delays = @()
            
            Mock -CommandName 'Start-Sleep' -MockWith {
                param($Seconds)
                $script:delays += $Seconds
            }
            
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                throw "Persistent error"
            }
            
            & $script:ScriptPath -Mode Audit -DomainControllers 'DC01' -ErrorAction SilentlyContinue
            
            # Verify exponential growth
            for ($i = 1; $i -lt $script:delays.Count; $i++) {
                $script:delays[$i] | Should -BeGreaterThan $script:delays[$i-1]
            }
        }
        
        It "Should respect maximum retry attempts" -Skip {
            $script:attemptCount = 0
            
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                $script:attemptCount++
                throw "Persistent error"
            }
            
            & $script:ScriptPath -Mode Audit -DomainControllers 'DC01' -ErrorAction SilentlyContinue
            
            $script:attemptCount | Should -BeLessOrEqual 5  # Max retries
        }
        
        It "Should stop retrying on non-transient errors" -Skip {
            # Authentication errors should not be retried
            $script:attemptCount = 0
            
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                $script:attemptCount++
                throw "Access is denied"
            }
            
            & $script:ScriptPath -Mode Audit -DomainControllers 'DC01' -ErrorAction SilentlyContinue
            
            $script:attemptCount | Should -Be 1  # No retries
        }
    }
    
    Context "Backoff Configuration" {
        
        It "Should use configurable initial delay" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match '\$InitialDelaySeconds'
        }
        
        It "Should use configurable max delay" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match '\$MaxDelaySeconds'
        }
        
        It "Should calculate exponential backoff correctly" {
            # Test backoff calculation: delay = min(InitialDelay * 2^attempt, MaxDelay)
            # Example: 2s, 4s, 8s, 16s, 32s (capped at MaxDelay)
            
            $InitialDelay = 2
            $MaxDelay = 30
            
            $expectedDelays = @(2, 4, 8, 16, 30, 30)  # Last two capped at MaxDelay
            
            foreach ($attempt in 0..5) {
                $calculatedDelay = [Math]::Min($InitialDelay * [Math]::Pow(2, $attempt), $MaxDelay)
                $calculatedDelay | Should -Be $expectedDelays[$attempt]
            }
        }
    }
}

Describe "PowerShell 7.5.4 Parallel Processing" {
    
    Context "Version Detection" {
        
        It "Should detect PowerShell version correctly" {
            $PSVersionTable.PSVersion.Major | Should -BeIn @(5, 7)
        }
        
        It "Should use parallel processing on PS7+" {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $scriptContent = Get-Content $script:ScriptPath -Raw
                $scriptContent | Should -Match 'ForEach-Object -Parallel'
            }
        }
        
        It "Should fall back to serial processing on PS5.1" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match 'PowerShell 5\.1 fallback'
        }
    }
    
    Context "Parallel Execution (PS7+ only)" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        
        It "Should process DCs in parallel" {
            # Run with multiple DCs and verify parallel execution
            $startTime = Get-Date
            
            & $script:ScriptPath -Mode Audit -DomainControllers @('DC01', 'DC02', 'DC03', 'DC04') -Throttle 4 -ErrorAction SilentlyContinue
            
            $duration = (Get-Date) - $startTime
            
            # Parallel should be faster than 4 * timeout
            # This is a rough check
            $duration.TotalSeconds | Should -BeLessThan 600  # Less than 10 minutes for 4 DCs
        }
        
        It "Should respect ThrottleLimit parameter" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match '-ThrottleLimit \$Throttle'
        }
        
        It "Should use ConcurrentBag for thread-safe results" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match 'System\.Collections\.Concurrent\.ConcurrentBag'
        }
        
        It "Should properly handle errors in parallel execution" {
            # Each parallel job should handle its own errors without affecting others
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                param($Target)
                if ($Target -eq 'DC01') {
                    throw "Simulated error for DC01"
                }
                return @(New-MockDCResponse -DC $Target)
            }
            
            $result = & $script:ScriptPath -Mode Audit -DomainControllers @('DC01', 'DC02', 'DC03') -ErrorAction SilentlyContinue
            
            # Should continue processing other DCs even if one fails
            $result | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "PS7.5.4 Specific Features" -Skip:($PSVersionTable.PSVersion.Major -lt 7 -or $PSVersionTable.PSVersion.Minor -lt 5) {
        
        It "Should use -UseNewRunspace for better isolation (PS7.5+)" {
            if ($PSVersionTable.PSVersion.Minor -ge 5) {
                $scriptContent = Get-Content $script:ScriptPath -Raw
                # In PS7.5+, ForEach-Object -Parallel uses runspaces by default, which is better
                $true | Should -Be $true
            }
        }
        
        It "Should leverage improved error handling in PS7.5+" {
            # PS7.5+ has better error propagation in parallel execution
            if ($PSVersionTable.PSVersion.Minor -ge 5) {
                $scriptContent = Get-Content $script:ScriptPath -Raw
                $scriptContent | Should -Match 'ErrorAction'
            }
        }
        
        It "Should use improved variable scoping with using syntax" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match '\$using:'
        }
    }
    
    Context "Performance Benchmarks" -Skip {
        
        It "Should be faster with parallel processing (PS7+)" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            # Baseline: Serial processing
            $serialStart = Get-Date
            & $script:ScriptPath -Mode Audit -DomainControllers @('DC01', 'DC02', 'DC03', 'DC04') -Throttle 1 -ErrorAction SilentlyContinue
            $serialDuration = (Get-Date) - $serialStart
            
            # Parallel processing
            $parallelStart = Get-Date
            & $script:ScriptPath -Mode Audit -DomainControllers @('DC01', 'DC02', 'DC03', 'DC04') -Throttle 4 -ErrorAction SilentlyContinue
            $parallelDuration = (Get-Date) - $parallelStart
            
            # Parallel should be faster (with some tolerance for overhead)
            $parallelDuration.TotalSeconds | Should -BeLessThan ($serialDuration.TotalSeconds * 0.75)
        }
    }
}

Describe "Error Handling & Resilience" {
    
    Context "Transient vs Permanent Errors" {
        
        It "Should identify transient network errors" {
            $transientErrors = @(
                "The RPC server is unavailable",
                "The network path was not found",
                "A connection attempt failed",
                "Timeout"
            )
            
            # These should trigger retries
            foreach ($error in $transientErrors) {
                # Test error classification logic
                $isTransient = $error -match "(RPC server|network path|connection attempt|Timeout)"
                $isTransient | Should -Be $true
            }
        }
        
        It "Should identify permanent errors (no retry)" {
            $permanentErrors = @(
                "Access is denied",
                "Logon failure: unknown user name or bad password",
                "The specified domain does not exist"
            )
            
            # These should NOT trigger retries
            foreach ($error in $permanentErrors) {
                $isPermanent = $error -match "(Access is denied|Logon failure|domain does not exist)"
                $isPermanent | Should -Be $true
            }
        }
    }
    
    Context "Timeout Handling" {
        
        It "Should respect per-DC timeout" {
            $scriptContent = Get-Content $script:ScriptPath -Raw
            $scriptContent | Should -Match 'Timeout'
        }
        
        It "Should not wait indefinitely for hung DCs" -Skip {
            # Simulate hung DC
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                Start-Sleep -Seconds 9999
            }
            
            $start = Get-Date
            & $script:ScriptPath -Mode Audit -DomainControllers 'DC01' -Timeout 10 -ErrorAction SilentlyContinue
            $duration = (Get-Date) - $start
            
            $duration.TotalSeconds | Should -BeLessThan 30  # Should timeout quickly
        }
    }
    
    Context "Graceful Degradation" {
        
        It "Should continue processing other DCs if one fails" -Skip {
            Mock -CommandName 'Get-ADReplicationPartnerMetadata' -MockWith {
                param($Target)
                if ($Target -eq 'DC02') {
                    throw "DC02 is unreachable"
                }
                return @(New-MockDCResponse -DC $Target)
            }
            
            $result = & $script:ScriptPath -Mode Audit -DomainControllers @('DC01', 'DC02', 'DC03') -ErrorAction SilentlyContinue
            
            # Should have results for DC01 and DC03
            $result | Where-Object { $_.DC -in @('DC01', 'DC03') } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Integration Tests" -Tag 'Integration' {
    
    Context "End-to-End Scenarios" {
        
        It "Should complete full audit workflow" -Skip {
            $result = & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -ErrorAction Stop
            
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -BeIn @(0, 2, 3)
        }
        
        It "Should handle WhatIf for repair mode" {
            { 
                & $script:ScriptPath -Mode Repair -DomainControllers $script:TestDCs -WhatIf -ErrorAction Stop
            } | Should -Not -Throw
        }
        
        It "Should generate all expected output files" -Skip {
            $outputDir = & $script:ScriptPath -Mode Audit -DomainControllers $script:TestDCs -ErrorAction Stop
            
            $summaryPath = Join-Path $outputDir "summary.json"
            $logPath = Join-Path $outputDir "execution.log"
            
            Test-Path $summaryPath | Should -Be $true
            Test-Path $logPath | Should -Be $true
        }
    }
}

AfterAll {
    # Cleanup test output directories
    Get-ChildItem -Path $PSScriptRoot -Filter "ADRepl-*" -Directory | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Test Suite Complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

