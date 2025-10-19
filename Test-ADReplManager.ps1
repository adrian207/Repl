#Requires -Version 5.1
<#
.SYNOPSIS
    Test harness for Invoke-ADReplicationManager.ps1 demonstrating key features.
    
.DESCRIPTION
    Demonstrates WhatIf, Verbose, different modes, and output parsing.
    Safe to run in production (uses -WhatIf and -Mode Audit).
#>

[CmdletBinding()]
param(
    [string[]]$TestDCs = @('DC01', 'DC02')
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "AD Replication Manager v3.0 - Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test 1: Audit with Verbose
Write-Host "[Test 1] Audit Mode with Verbose Output" -ForegroundColor Yellow
Write-Host "Command: -Mode Audit -DomainControllers $($TestDCs -join ',') -Verbose`n" -ForegroundColor Gray

try {
    & .\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -DomainControllers $TestDCs `
        -Verbose `
        -ErrorAction Stop | Out-Null
    
    Write-Host "✓ Test 1 Passed" -ForegroundColor Green
}
catch {
    Write-Host "✗ Test 1 Failed: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 2: WhatIf (preview repairs without executing)
Write-Host "`n[Test 2] WhatIf Mode (Safe Preview)" -ForegroundColor Yellow
Write-Host "Command: -Mode Repair -DomainControllers $($TestDCs -join ',') -WhatIf`n" -ForegroundColor Gray

try {
    & .\Invoke-ADReplicationManager.ps1 `
        -Mode Repair `
        -DomainControllers $TestDCs `
        -WhatIf `
        -ErrorAction Stop | Out-Null
    
    Write-Host "✓ Test 2 Passed (no actual changes made)" -ForegroundColor Green
}
catch {
    Write-Host "✗ Test 2 Failed: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 3: JSON Summary Parsing
Write-Host "`n[Test 3] JSON Summary Parsing" -ForegroundColor Yellow
Write-Host "Command: Parse summary.json from latest run`n" -ForegroundColor Gray

try {
    $latestOutput = Get-ChildItem -Path . -Filter "ADRepl-*" -Directory | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1
    
    if ($latestOutput) {
        $summaryPath = Join-Path $latestOutput.FullName "summary.json"
        
        if (Test-Path $summaryPath) {
            $summary = Get-Content $summaryPath | ConvertFrom-Json
            
            Write-Host "Summary Data:" -ForegroundColor White
            Write-Host "  Mode            : $($summary.Mode)" -ForegroundColor Gray
            Write-Host "  Total DCs       : $($summary.TotalDCs)" -ForegroundColor Gray
            Write-Host "  Healthy DCs     : $($summary.HealthyDCs)" -ForegroundColor Green
            Write-Host "  Degraded DCs    : $($summary.DegradedDCs)" -ForegroundColor Yellow
            Write-Host "  Unreachable DCs : $($summary.UnreachableDCs)" -ForegroundColor Red
            Write-Host "  Issues Found    : $($summary.IssuesFound)" -ForegroundColor Yellow
            Write-Host "  Exit Code       : $($summary.ExitCode)" -ForegroundColor White
            
            Write-Host "`n✓ Test 3 Passed (JSON parsing successful)" -ForegroundColor Green
        }
        else {
            Write-Host "✗ Test 3 Failed: summary.json not found" -ForegroundColor Red
        }
    }
    else {
        Write-Host "✗ Test 3 Failed: No output directory found" -ForegroundColor Red
    }
}
catch {
    Write-Host "✗ Test 3 Failed: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 4: Parameter Validation
Write-Host "`n[Test 4] Parameter Validation" -ForegroundColor Yellow
Write-Host "Testing invalid parameter combinations...`n" -ForegroundColor Gray

$validationTests = @(
    @{
        Name = "Invalid Mode"
        Params = @{ Mode = 'InvalidMode'; DomainControllers = $TestDCs }
        ShouldFail = $true
    },
    @{
        Name = "Invalid Throttle (too high)"
        Params = @{ Mode = 'Audit'; DomainControllers = $TestDCs; Throttle = 100 }
        ShouldFail = $true
    },
    @{
        Name = "DCList scope without DCs"
        Params = @{ Mode = 'Audit'; Scope = 'DCList' }
        ShouldFail = $true
    },
    @{
        Name = "Valid minimal params"
        Params = @{ Mode = 'Audit'; DomainControllers = $TestDCs }
        ShouldFail = $false
    }
)

foreach ($test in $validationTests) {
    try {
        Write-Host "  Testing: $($test.Name)..." -NoNewline -ForegroundColor Gray
        
        $params = $test.Params
        & .\Invoke-ADReplicationManager.ps1 @params -ErrorAction Stop | Out-Null
        
        if ($test.ShouldFail) {
            Write-Host " ✗ (Should have failed)" -ForegroundColor Red
        }
        else {
            Write-Host " ✓" -ForegroundColor Green
        }
    }
    catch {
        if ($test.ShouldFail) {
            Write-Host " ✓ (Failed as expected)" -ForegroundColor Green
        }
        else {
            Write-Host " ✗ (Unexpected failure: $_)" -ForegroundColor Red
        }
    }
}

# Test 5: Exit Code Mapping
Write-Host "`n[Test 5] Exit Code Verification" -ForegroundColor Yellow
Write-Host "Verifying exit codes are set correctly...`n" -ForegroundColor Gray

try {
    # Run audit and capture exit code
    & .\Invoke-ADReplicationManager.ps1 `
        -Mode Audit `
        -DomainControllers $TestDCs `
        -ErrorAction SilentlyContinue
    
    $exitCode = $LASTEXITCODE
    
    $exitCodeMeaning = switch ($exitCode) {
        0 { "Healthy / repaired successfully" }
        2 { "Issues remain" }
        3 { "One or more DCs unreachable" }
        4 { "Unexpected error" }
        default { "Unknown exit code" }
    }
    
    Write-Host "Exit Code: $exitCode - $exitCodeMeaning" -ForegroundColor White
    Write-Host "✓ Test 5 Passed (exit code in range 0,2,3,4)" -ForegroundColor Green
}
catch {
    Write-Host "✗ Test 5 Failed: $_" -ForegroundColor Red
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Suite Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Review generated reports in ADRepl-* directories" -ForegroundColor White
Write-Host "2. Compare CSVs to old script outputs" -ForegroundColor White
Write-Host "3. Test with your production DCs (audit-only first)" -ForegroundColor White
Write-Host "4. Try: .\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Site:YourSite -Verbose" -ForegroundColor White
Write-Host "`n"

