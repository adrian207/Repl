# Test Suite for AD Replication Manager
# Tests syntax, parameters, and functionality without requiring AD environment

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AD Replication Manager - Test Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ErrorCount = 0
$WarningCount = 0
$TestCount = 0

function Test-Result {
    param($TestName, $Result, $Message = "")
    $script:TestCount++
    if ($Result) {
        Write-Host "✓ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "  └─ $Message" -ForegroundColor Gray }
    }
    else {
        Write-Host "✗ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "  └─ $Message" -ForegroundColor Red }
        $script:ErrorCount++
    }
}

# Test 1: Script File Exists
Write-Host "`n[1/10] Testing Script Existence..." -ForegroundColor Yellow
$scriptExists = Test-Path ".\Invoke-ADReplicationManager.ps1"
Test-Result "Script file exists" $scriptExists "File: Invoke-ADReplicationManager.ps1"

if (-not $scriptExists) {
    Write-Host "`nERROR: Script file not found!" -ForegroundColor Red
    exit 1
}

# Test 2: PowerShell Syntax
Write-Host "`n[2/10] Testing PowerShell Syntax..." -ForegroundColor Yellow
try {
    $syntaxErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content ".\Invoke-ADReplicationManager.ps1" -Raw), [ref]$syntaxErrors
    )
    
    if ($syntaxErrors.Count -eq 0) {
        Test-Result "PowerShell syntax valid" $true "No syntax errors found"
    }
    else {
        Test-Result "PowerShell syntax valid" $false "$($syntaxErrors.Count) syntax errors found"
        $syntaxErrors | ForEach-Object {
            Write-Host "  Line $($_.StartLine): $($_.Message)" -ForegroundColor Red
        }
    }
}
catch {
    Test-Result "PowerShell syntax check" $false $_.Exception.Message
}

# Test 3: Script Metadata
Write-Host "`n[3/10] Testing Script Metadata..." -ForegroundColor Yellow
try {
    $scriptContent = Get-Content ".\Invoke-ADReplicationManager.ps1" -Raw
    
    Test-Result "Has version number" ($scriptContent -match "\.VERSION\s+3\.3\.0") "Version: 3.3.0"
    Test-Result "Has author" ($scriptContent -match "Adrian Johnson") "Author: Adrian Johnson"
    Test-Result "Has synopsis" ($scriptContent -match "\.SYNOPSIS") "Synopsis section present"
    Test-Result "Has examples" ($scriptContent -match "\.EXAMPLE") "Example section present"
}
catch {
    Test-Result "Script metadata check" $false $_.Exception.Message
}

# Test 4: Required Parameters
Write-Host "`n[4/10] Testing Parameters..." -ForegroundColor Yellow
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        ".\Invoke-ADReplicationManager.ps1", [ref]$null, [ref]$null
    )
    
    $params = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.ParameterAst]}, $true)
    
    $expectedParams = @(
        'Mode', 'Scope', 'DomainControllers', 'DomainName', 'AutoRepair', 'Throttle',
        'OutputPath', 'AuditTrail', 'Timeout', 'FastMode',
        'SlackWebhook', 'TeamsWebhook', 'EmailTo', 'EmailFrom', 'SmtpServer', 'EmailNotification',
        'CreateScheduledTask', 'TaskSchedule', 'TaskName', 'TaskTime',
        'EnableHealthScore', 'HealthHistoryPath',
        'AutoHeal', 'HealingPolicy', 'MaxHealingActions', 'EnableRollback', 'HealingHistoryPath', 'HealingCooldownMinutes',
        'DeltaMode', 'DeltaThresholdMinutes', 'DeltaCachePath', 'ForceFull'
    )
    
    $actualParamNames = $params | ForEach-Object { $_.Name.VariablePath.UserPath }
    
    $missingParams = $expectedParams | Where-Object { $_ -notin $actualParamNames }
    
    if ($missingParams.Count -eq 0) {
        Test-Result "All expected parameters present" $true "$($actualParamNames.Count) parameters found"
    }
    else {
        Test-Result "All expected parameters present" $false "Missing: $($missingParams -join ', ')"
    }
    
    # Check specific new parameters
    Test-Result "Has AutoHeal parameter" ($actualParamNames -contains 'AutoHeal') "v3.2 Auto-Healing"
    Test-Result "Has DeltaMode parameter" ($actualParamNames -contains 'DeltaMode') "v3.3 Delta Mode"
}
catch {
    Test-Result "Parameter check" $false $_.Exception.Message
}

# Test 5: Functions
Write-Host "`n[5/10] Testing Functions..." -ForegroundColor Yellow
try {
    $expectedFunctions = @(
        'Write-RepairLog', 'Invoke-WithRetry', 'Resolve-ScopeToDCs', 'Get-ReplicationSnapshot',
        'Find-ReplicationIssues', 'Invoke-ReplicationFix', 'Test-ReplicationHealth',
        'Export-ReplReports', 'Write-RunSummary',
        'Send-SlackAlert', 'Send-TeamsAlert', 'Send-EmailAlert',
        'Get-HealthScore', 'Save-HealthHistory',
        'Get-HealingPolicy', 'Test-HealingEligibility', 'Save-HealingAction',
        'Invoke-HealingRollback', 'Get-HealingStatistics',
        'Get-DeltaCache', 'Save-DeltaCache', 'Get-DeltaTargetDCs'
    )
    
    $functionMatches = $expectedFunctions | Where-Object { $scriptContent -match "function $_\s*\{" }
    
    Test-Result "Core functions present" ($functionMatches.Count -ge 20) "$($functionMatches.Count)/$($expectedFunctions.Count) functions found"
    Test-Result "Has auto-healing functions" ($scriptContent -match "function Get-HealingPolicy") "Auto-healing framework"
    Test-Result "Has delta mode functions" ($scriptContent -match "function Get-DeltaCache") "Delta mode framework"
}
catch {
    Test-Result "Function check" $false $_.Exception.Message
}

# Test 6: Help Documentation
Write-Host "`n[6/10] Testing Help Documentation..." -ForegroundColor Yellow
try {
    $help = Get-Help ".\Invoke-ADReplicationManager.ps1" -ErrorAction Stop
    
    Test-Result "Help available" ($null -ne $help) "Get-Help works"
    
    # Check if help content exists in script file (more reliable than Get-Help parsing)
    $hasSynopsis = $scriptContent -match "\.SYNOPSIS\s+[\r\n]+\s+\w+"
    $hasDescription = $scriptContent -match "\.DESCRIPTION\s+[\r\n]+"
    $hasExamples = ([regex]::Matches($scriptContent, "\.EXAMPLE")).Count
    
    Test-Result "Has synopsis in script" $hasSynopsis "Synopsis section present"
    Test-Result "Has description in script" $hasDescription "Description section present"
    Test-Result "Has examples in script" ($hasExamples -ge 5) "$hasExamples examples documented"
}
catch {
    Test-Result "Help documentation check" $false $_.Exception.Message
}

# Test 7: Version Files
Write-Host "`n[7/10] Testing Version Files..." -ForegroundColor Yellow
try {
    $versionFile = Get-Content ".\VERSION" -ErrorAction Stop
    Test-Result "VERSION file exists" $true "Content: $versionFile"
    Test-Result "VERSION is 3.3.0" ($versionFile -match "3\.3\.0") "Version: $versionFile"
    
    $changelogExists = Test-Path ".\CHANGELOG.md"
    Test-Result "CHANGELOG.md exists" $changelogExists
    
    if ($changelogExists) {
        $changelog = Get-Content ".\CHANGELOG.md" -Raw
        Test-Result "CHANGELOG has v3.3.0" ($changelog -match "\[3\.3\.0\]") "Latest version documented"
    }
}
catch {
    Test-Result "Version files check" $false $_.Exception.Message
}

# Test 8: WhatIf Support
Write-Host "`n[8/10] Testing WhatIf Support..." -ForegroundColor Yellow
try {
    $supportsShouldProcess = $scriptContent -match "\[CmdletBinding\(.*SupportsShouldProcess\s*=\s*\`$true"
    Test-Result "SupportsShouldProcess enabled" $supportsShouldProcess "WhatIf/Confirm support"
    
    $psCmdletCheck = $scriptContent -match "\`$PSCmdlet\.ShouldProcess"
    Test-Result "Uses ShouldProcess checks" $psCmdletCheck "Safety guards present"
}
catch {
    Test-Result "WhatIf support check" $false $_.Exception.Message
}

# Test 9: Validation Attributes
Write-Host "`n[9/10] Testing Parameter Validation..." -ForegroundColor Yellow
try {
    Test-Result "Has ValidateSet for Mode" ($scriptContent -match "ValidateSet.*Audit.*Repair.*Verify") "Mode parameter validation"
    Test-Result "Has ValidateSet for HealingPolicy" ($scriptContent -match "ValidateSet.*Conservative.*Moderate.*Aggressive") "Healing policy validation"
    Test-Result "Has ValidateRange" ($scriptContent -match "ValidateRange") "Numeric range validation"
    Test-Result "Has ValidatePattern" ($scriptContent -match "ValidatePattern") "Pattern validation"
}
catch {
    Test-Result "Validation check" $false $_.Exception.Message
}

# Test 10: Documentation Files
Write-Host "`n[10/10] Testing Documentation Files..." -ForegroundColor Yellow
$docFiles = @(
    "README.md",
    "CHANGELOG.md",
    "RELEASE-NOTES-v3.1.md",
    "RELEASE-NOTES-v3.2.md",
    "RELEASE-NOTES-v3.3.md",
    "docs\DOCUMENTATION-INDEX.md",
    "docs\AUTO-HEALING-GUIDE.md",
    "docs\DELTA-MODE-GUIDE.md"
)

foreach ($doc in $docFiles) {
    $exists = Test-Path $doc
    if ($exists) {
        $script:TestCount++
        Write-Host "  ✓ $doc" -ForegroundColor Green
    }
    else {
        Test-Result "Documentation: $doc" $false "File not found"
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $TestCount" -ForegroundColor White
Write-Host "Passed: $($TestCount - $ErrorCount)" -ForegroundColor Green
Write-Host "Failed: $ErrorCount" -ForegroundColor $(if ($ErrorCount -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($ErrorCount -eq 0) {
    Write-Host "✓ ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Script is ready for testing with:" -ForegroundColor Cyan
    Write-Host "  1. WhatIf mode (safe, no changes):" -ForegroundColor White
    Write-Host "     .\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01 -WhatIf" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Help documentation:" -ForegroundColor White
    Write-Host "     Get-Help .\Invoke-ADReplicationManager.ps1 -Full" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Parameter exploration:" -ForegroundColor White
    Write-Host "     Get-Help .\Invoke-ADReplicationManager.ps1 -Parameter *" -ForegroundColor Gray
    Write-Host ""
    exit 0
}
else {
    Write-Host "✗ TESTS FAILED!" -ForegroundColor Red
    Write-Host "Please fix the errors above before proceeding." -ForegroundColor Yellow
    exit 1
}

