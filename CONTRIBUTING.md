# Contributing to AD Replication Manager

Thank you for your interest in contributing to the AD Replication Manager project! This document provides guidelines and instructions for contributing.

**Project Author:** Adrian Johnson <adrian207@gmail.com>

---

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Guidelines](#development-guidelines)
- [Testing Requirements](#testing-requirements)
- [Documentation Standards](#documentation-standards)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)
- [Contact](#contact)

---

## 📜 Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inspiring community for all. Please be respectful and professional in all interactions.

### Expected Behavior

- ✅ Use welcoming and inclusive language
- ✅ Be respectful of differing viewpoints and experiences
- ✅ Gracefully accept constructive criticism
- ✅ Focus on what is best for the community
- ✅ Show empathy towards other community members

### Unacceptable Behavior

- ❌ Trolling, insulting/derogatory comments, and personal or political attacks
- ❌ Public or private harassment
- ❌ Publishing others' private information without permission
- ❌ Other conduct which could reasonably be considered inappropriate

---

## 🚀 Getting Started

### Prerequisites

- **PowerShell**: 5.1+ or 7+ (7+ recommended for parallel processing)
- **Git**: For version control
- **Active Directory Module**: `Install-WindowsFeature RSAT-AD-PowerShell`
- **Test Environment**: Access to a test AD environment with multiple DCs
- **Visual Studio Code** (recommended) with PowerShell extension

### Development Setup

1. **Fork the Repository**
   ```bash
   # Fork via GitHub UI, then clone your fork
   git clone https://github.com/YOUR-USERNAME/Repl.git
   cd Repl
   ```

2. **Create a Branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b bugfix/issue-number-description
   ```

3. **Install Development Tools**
   ```powershell
   # Install PSScriptAnalyzer for linting
   Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
   
   # Install Pester for testing (if not already installed)
   Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force
   ```

4. **Verify Setup**
   ```powershell
   # Run existing test suite
   .\Test-ADReplManager.ps1 -TestDCs "DC01","DC02"
   
   # Run PSScriptAnalyzer
   Invoke-ScriptAnalyzer -Path .\Invoke-ADReplicationManager.ps1
   ```

---

## 🤝 How to Contribute

### Types of Contributions

We welcome various types of contributions:

| Type | Examples |
|------|----------|
| **Bug Fixes** | Fix issues, resolve errors, improve stability |
| **Features** | New functionality, enhancements, optimizations |
| **Documentation** | Improve docs, add examples, fix typos |
| **Tests** | Add test cases, improve coverage |
| **Performance** | Optimize code, reduce execution time |
| **Refactoring** | Code cleanup, improve maintainability |

---

## 💻 Development Guidelines

### PowerShell Style Guide

#### 1. **Code Formatting**

```powershell
# ✅ GOOD: PascalCase for functions
function Get-ReplicationSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainController
    )
}

# ❌ BAD: lowercase or camelCase
function get_replication_snapshot {
    param($dc)
}
```

#### 2. **Parameter Validation**

```powershell
# ✅ GOOD: Comprehensive validation
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ })]
    [string]$Path,
    
    [ValidateSet('Audit', 'Repair', 'Verify')]
    [string]$Mode = 'Audit',
    
    [ValidateRange(1, 32)]
    [int]$Throttle = 8
)

# ❌ BAD: No validation
param($Path, $Mode, $Throttle)
```

#### 3. **Error Handling**

```powershell
# ✅ GOOD: Specific error handling
try {
    $result = Get-ADReplicationFailure -Target $dc -ErrorAction Stop
} catch [Microsoft.ActiveDirectory.Management.ADServerDownException] {
    Write-Warning "DC unreachable: $dc"
    return
} catch {
    Write-Error "Unexpected error: $_"
    throw
}

# ❌ BAD: Silent continuation
$result = Get-ADReplicationFailure -Target $dc -ErrorAction SilentlyContinue
```

#### 4. **Logging & Output**

```powershell
# ✅ GOOD: Pipeline-friendly streams
Write-Verbose "Processing DC: $dc"
Write-Information "Found $count issues"
Write-Warning "DC01 is degraded"
Write-Error "Failed to connect to DC02"

# ❌ BAD: Write-Host everywhere
Write-Host "Processing DC: $dc" -ForegroundColor Yellow
```

#### 5. **ShouldProcess Support**

```powershell
# ✅ GOOD: Wrap all changes with ShouldProcess
function Invoke-ReplicationFix {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$DC)
    
    if ($PSCmdlet.ShouldProcess($DC, "Force replication sync")) {
        & repadmin /syncall $DC 2>&1
    }
}

# ❌ BAD: No WhatIf support
function Invoke-ReplicationFix {
    param([string]$DC)
    & repadmin /syncall $DC
}
```

### Code Quality Standards

- ✅ **No PSScriptAnalyzer warnings** (run `Invoke-ScriptAnalyzer` before committing)
- ✅ **Comment complex logic** (why, not just what)
- ✅ **Use meaningful variable names** (`$domainController` not `$dc1`)
- ✅ **Keep functions focused** (single responsibility principle)
- ✅ **Avoid magic numbers** (use named constants)
- ✅ **Use parameter splatting** for long parameter lists

### Example: Adding a New Repair Method

```powershell
# In Invoke-ReplicationFix function, add to switch statement:
'NewIssueType' {
    $action.Method = 'CustomFix'
    
    if ($PSCmdlet.ShouldProcess($DC, "Apply custom fix for $($issue.Description)")) {
        try {
            # Your fix logic here
            $result = Invoke-CustomFix -DC $DC -ErrorAction Stop
            
            $action.Success = $true
            $action.Message = "Custom fix applied successfully"
            
            Write-RepairLog -Severity 'Information' `
                -Message "Applied custom fix to $DC" `
                -DC $DC
        }
        catch {
            $action.Success = $false
            $action.Message = "Custom fix failed: $_"
            
            Write-RepairLog -Severity 'Error' `
                -Message "Failed to apply custom fix to $DC: $_" `
                -DC $DC
        }
    }
    else {
        $action.Skipped = $true
        $action.Message = "User declined custom fix"
    }
}

# In Find-ReplicationIssues function, add detection:
if ($snapshot.CustomMetric -gt $threshold) {
    $allIssues += [PSCustomObject]@{
        DC = $snapshot.DC
        Category = 'NewIssueType'
        Severity = 'Medium'
        Description = "Custom metric exceeded threshold"
        Detail = "Value: $($snapshot.CustomMetric)"
        Actionable = $true
        Timestamp = Get-Date
    }
}
```

---

## 🧪 Testing Requirements

### Test All Changes

Every code change MUST include tests:

```powershell
# Add test case to Test-ADReplManager.ps1

Describe "New Feature Tests" {
    It "Should handle new scenario" {
        $result = .\Invoke-ADReplicationManager.ps1 `
            -Mode Audit `
            -DomainControllers "DC01" `
            -YourNewParameter "Value"
        
        $result | Should -Not -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 0
    }
    
    It "Should validate new parameter" {
        {
            .\Invoke-ADReplicationManager.ps1 `
                -Mode Audit `
                -DomainControllers "DC01" `
                -YourNewParameter "InvalidValue"
        } | Should -Throw
    }
}
```

### Run Tests Before Committing

```powershell
# Run full test suite
.\Test-ADReplManager.ps1 -TestDCs "DC01","DC02"

# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\Invoke-ADReplicationManager.ps1

# Test WhatIf functionality
.\Invoke-ADReplicationManager.ps1 -Mode Repair -DomainControllers DC01,DC02 -WhatIf

# Test with Verbose
.\Invoke-ADReplicationManager.ps1 -Mode Audit -DomainControllers DC01,DC02 -Verbose
```

### Test Coverage Requirements

- ✅ **New functions**: 100% test coverage
- ✅ **Modified functions**: Test all affected code paths
- ✅ **Bug fixes**: Add regression test
- ✅ **Error handling**: Test both success and failure cases
- ✅ **Parameters**: Test validation rules

---

## 📚 Documentation Standards

### Update Documentation for All Changes

When contributing, update relevant documentation:

| Change Type | Documentation to Update |
|-------------|------------------------|
| **New Feature** | README.md, docs/API-REFERENCE.md, CHANGELOG.md |
| **Bug Fix** | CHANGELOG.md, docs/TROUBLESHOOTING-GUIDE.md (if applicable) |
| **Parameter Change** | README.md, docs/API-REFERENCE.md, docs/MIGRATION-GUIDE.md |
| **New Function** | docs/API-REFERENCE.md, inline help comments |
| **Performance** | README.md (benchmarks), CHANGELOG.md |

### Documentation Authorship

Per [docs/DOCUMENTATION-STANDARDS.md](docs/DOCUMENTATION-STANDARDS.md):

```markdown
# Your Document Title

**Version:** 1.1  
**Last Updated:** YYYY-MM-DD  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Contributors:**  
- Your Name <your-email@example.com> - Contribution description
**Classification:** Internal Use

---
```

### Comment-Based Help

All functions must include comment-based help:

```powershell
function Get-YourFunction {
    <#
    .SYNOPSIS
        Brief description of what the function does.
    
    .DESCRIPTION
        Detailed description with examples.
    
    .PARAMETER ParameterName
        Description of the parameter.
    
    .EXAMPLE
        Get-YourFunction -ParameterName "Value"
        Description of what this example does.
    
    .OUTPUTS
        System.Object
        Description of return value/object.
    
    .NOTES
        Author: Your Name <your-email@example.com>
        Date: YYYY-MM-DD
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )
    
    # Function implementation
}
```

---

## 🔄 Pull Request Process

### 1. **Before Submitting**

- [ ] Code follows PowerShell style guidelines
- [ ] All tests pass (`Test-ADReplManager.ps1`)
- [ ] No PSScriptAnalyzer warnings
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated
- [ ] Commit messages are clear and descriptive

### 2. **Commit Message Format**

Use conventional commits:

```
type(scope): brief description

Detailed description if needed

- Bullet points for multiple changes
- Reference issues: Fixes #123, Closes #456
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code formatting (no functional changes)
- `refactor`: Code restructuring (no functional changes)
- `perf`: Performance improvement
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```bash
git commit -m "feat(repair): add automatic DC restart for critical failures"
git commit -m "fix(audit): handle null replication metadata correctly"
git commit -m "docs(api): add examples for Get-ReplicationSnapshot"
git commit -m "perf(parallel): optimize throttle mechanism for PS7+"
```

### 3. **Submit Pull Request**

1. Push your branch to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. Open a Pull Request via GitHub UI

3. Fill out the PR template:
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Breaking change
   - [ ] Documentation update
   
   ## Testing
   - [ ] Tested in lab environment
   - [ ] All tests pass
   - [ ] No PSScriptAnalyzer warnings
   
   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Documentation updated
   - [ ] CHANGELOG.md updated
   - [ ] Tests added/updated
   
   ## Related Issues
   Fixes #123
   ```

### 4. **Code Review**

- Expect feedback and be prepared to make changes
- Address all review comments
- Keep the discussion professional and constructive
- Update documentation if requested
- Squash commits if requested before merge

### 5. **After Merge**

- Delete your feature branch
- Pull latest changes from main
- Celebrate! 🎉

---

## 🐛 Reporting Bugs

### Before Reporting

1. **Check existing issues**: Search [GitHub Issues](https://github.com/adrian207/Repl/issues)
2. **Verify it's a bug**: Test in a clean environment
3. **Collect information**: Error messages, logs, environment details

### Bug Report Template

```markdown
**Describe the Bug**
Clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Run command: `.\Invoke-ADReplicationManager.ps1 ...`
2. With parameters: `-Mode Audit -DomainControllers DC01,DC02`
3. See error: `...`

**Expected Behavior**
What you expected to happen.

**Actual Behavior**
What actually happened.

**Screenshots/Logs**
If applicable, add screenshots or log excerpts.

**Environment:**
 - OS: [e.g., Windows Server 2022]
 - PowerShell Version: [e.g., 7.4.0]
 - AD Forest/Domain: [e.g., contoso.com]
 - DC Count: [e.g., 5 DCs]

**Additional Context**
Any other context about the problem.

**Error Messages**
```powershell
# Paste full error messages here
```

**Related Configuration**
- Mode: Audit/Repair/Verify/AuditRepairVerify
- Scope: Forest/Site/DCList
- Other relevant parameters
```

---

## 💡 Suggesting Enhancements

### Enhancement Request Template

```markdown
**Is your feature request related to a problem?**
Clear and concise description of the problem. Ex. "I'm always frustrated when [...]"

**Describe the solution you'd like**
Clear and concise description of what you want to happen.

**Describe alternatives you've considered**
Alternative solutions or features you've considered.

**Use Cases**
Describe specific scenarios where this would be useful.

**Implementation Ideas**
If you have ideas on how to implement this, share them!

**Additional Context**
Any other context, screenshots, or examples about the feature request.

**Would you be willing to implement this?**
- [ ] Yes, I can submit a PR
- [ ] No, but I can help test
- [ ] No, just suggesting
```

---

## 📞 Contact

### Project Maintainer

**Adrian Johnson**  
📧 Email: adrian207@gmail.com  
🔗 GitHub: [@adrian207](https://github.com/adrian207)

### Communication Channels

- **GitHub Issues**: For bugs and feature requests
- **Pull Requests**: For code contributions
- **Discussions**: For questions and general discussions
- **Email**: For private/security concerns

---

## 🏆 Recognition

Contributors will be recognized in:
- Project README.md (Contributors section)
- CHANGELOG.md (for significant contributions)
- Documentation (for doc contributions)

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

## 🙏 Thank You!

Thank you for considering contributing to the AD Replication Manager project! Your contributions help make this tool better for the entire Active Directory admin community.

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

