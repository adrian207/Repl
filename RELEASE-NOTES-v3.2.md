# Release Notes - v3.2.0

**Release Date:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>

---

## 🎯 Overview

Version 3.2.0 introduces **Auto-Healing** - the most requested feature that transforms AD Replication Manager into an autonomous monitoring and remediation solution. This release implements intelligent, policy-based automated repair with comprehensive safety controls, rollback capability, and detailed audit trails.

---

## 🚀 Major Feature: Auto-Healing

### What is Auto-Healing?

Auto-Healing enables **automated, policy-driven remediation** of AD replication issues without human intervention. It intelligently evaluates issues based on configurable policies, performs safe repairs, tracks all actions, and can automatically rollback failed operations.

### Key Capabilities

#### 1. 🎛️ **Three Healing Policies**

| Policy | Risk Level | Categories | Severities | Use Case |
|--------|-----------|------------|------------|----------|
| **Conservative** | Low | StaleReplication | Low, Medium | Production - minimal risk |
| **Moderate** | Medium | StaleReplication, ReplicationFailure | Low, Medium, High | Balanced automation |
| **Aggressive** | High | All categories | All severities | Maximum automation |

**Conservative Policy:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -AutoHeal `
    -HealingPolicy Conservative `
    -MaxHealingActions 5
```
- Only fixes low-risk stale replication
- Requires manual approval for failures
- 30-minute cooldown between attempts
- Maximum 3 concurrent actions

**Moderate Policy:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -AutoHeal `
    -HealingPolicy Moderate `
    -EnableRollback
```
- Fixes stale replication + replication failures
- Requires manual approval for connectivity issues
- 15-minute cooldown
- Maximum 5 concurrent actions
- Automatic rollback on failure

**Aggressive Policy:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode AuditRepairVerify `
    -AutoHeal `
    -HealingPolicy Aggressive `
    -MaxHealingActions 10 `
    -EnableRollback
```
- Attempts to fix ALL detected issues
- No manual approvals required
- 5-minute cooldown
- Maximum 10 concurrent actions
- Automatic rollback on failure

---

#### 2. 🔄 **Rollback Capability**

Auto-Healing includes intelligent rollback for failed actions:

```powershell
# Enable automatic rollback on failures
.\Invoke-ADReplicationManager.ps1 `
    -Mode Repair `
    -AutoHeal `
    -EnableRollback

# Manual rollback of specific action
# (ActionID from healing-history.csv)
Invoke-HealingRollback -ActionID "abc123de" `
    -HistoryPath "C:\ProgramData\ADReplicationManager\Healing" `
    -Reason "Manual intervention required"
```

**Rollback Features:**
- JSON-based rollback data with pre-action state
- Fresh replication sync to restore state
- Rollback history tracking
- Automatic cleanup of old rollback files (>30 days)

---

#### 3. 🛡️ **Safety Controls**

Multiple layers of protection prevent healing loops and ensure safety:

**Cooldown Period:**
- Prevents repeated healing attempts on same issue
- Configurable per-policy or via `-HealingCooldownMinutes`
- Prevents healing loops and gives time for replication convergence

**Action Limits:**
- `-MaxHealingActions` parameter (1-100, default: 10)
- Policy-specific max concurrent actions
- Protects against runaway automation

**Eligibility Checks:**
- Category must be allowed by policy
- Severity must be allowed by policy
- Manual approval check
- Cooldown period check
- Actionability check

**Audit Trail:**
- Every action logged to CSV (`healing-history.csv`)
- JSON rollback files for detailed records
- Timestamp, DC, category, severity, success/failure
- Rollback history in separate CSV

---

#### 4. 📊 **Healing Statistics**

Track auto-healing effectiveness over time:

```powershell
# Get healing statistics for last 30 days
$stats = Get-HealingStatistics -HistoryPath "C:\ProgramData\ADReplicationManager\Healing" -DaysBack 30

$stats
# Output:
# TotalActions        : 145
# SuccessfulActions   : 138
# FailedActions       : 7
# RolledBackActions   : 3
# SuccessRate         : 95.17
# CategoriesHealed    : {StaleReplication: 89, ReplicationFailure: 56}
# TopDCs              : {DC03: 23, DC07: 19, DC12: 15, DC05: 12, DC01: 10}
```

---

## 📋 New Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| **`-AutoHeal`** | Switch | `$false` | Enable automatic healing with policy-based decisions |
| **`-HealingPolicy`** | String | `Conservative` | Policy: Conservative, Moderate, or Aggressive |
| **`-MaxHealingActions`** | Int | `10` | Maximum actions per execution (1-100) |
| **`-EnableRollback`** | Switch | `$false` | Automatically rollback failed healing actions |
| **`-HealingHistoryPath`** | String | `$env:ProgramData\...` | Directory for healing audit trail |
| **`-HealingCooldownMinutes`** | Int | `15` | Minutes before re-attempting same issue (1-60) |

---

## 🔧 New Functions

### Public Functions

| Function | Purpose |
|----------|---------|
| `Get-HealingPolicy` | Retrieves policy definitions (Conservative/Moderate/Aggressive) |
| `Test-HealingEligibility` | Checks if issue qualifies for auto-healing |
| `Save-HealingAction` | Records action to audit trail with rollback data |
| `Invoke-HealingRollback` | Rolls back a healing action by ID |
| `Get-HealingStatistics` | Retrieves healing metrics from history |

---

## 💡 Usage Examples

### Example 1: Conservative Auto-Healing with Scheduled Task
```powershell
# Setup: Create daily monitoring with safe auto-healing
.\Invoke-ADReplicationManager.ps1 `
    -CreateScheduledTask `
    -TaskSchedule Daily `
    -TaskTime "02:00" `
    -Mode AuditRepairVerify `
    -Scope Forest `
    -AutoHeal `
    -HealingPolicy Conservative `
    -EnableHealthScore `
    -SlackWebhook "https://hooks.slack.com/..." `
    -EmailTo "ad-admins@company.com" `
    -SmtpServer "smtp.company.com"
```

**What it does:**
- Runs daily at 2 AM
- Audits all DCs in forest
- Auto-heals only stale replication (low risk)
- Tracks health score trends
- Sends Slack + email notifications
- Full audit trail

---

### Example 2: Moderate Policy for Production
```powershell
# Production monitoring with balanced automation
.\Invoke-ADReplicationManager.ps1 `
    -Mode AuditRepairVerify `
    -Scope Site:Production `
    -AutoHeal `
    -HealingPolicy Moderate `
    -MaxHealingActions 5 `
    -EnableRollback `
    -FastMode `
    -AuditTrail `
    -EnableHealthScore
```

**What it does:**
- Audits Production site DCs
- Auto-heals stale replication + failures
- Limits to 5 actions max
- Automatic rollback if repairs fail
- Fast execution (40-60% faster)
- Complete transcript logging
- Health score tracking

---

### Example 3: Aggressive Policy for Test Environment
```powershell
# Test/Dev environment with maximum automation
.\Invoke-ADReplicationManager.ps1 `
    -Mode AuditRepairVerify `
    -Scope Forest `
    -AutoHeal `
    -HealingPolicy Aggressive `
    -MaxHealingActions 20 `
    -EnableRollback `
    -HealingCooldownMinutes 5 `
    -FastMode `
    -AutoRepair
```

**What it does:**
- Attempts to fix ALL issues automatically
- No manual prompts (fully automated)
- Up to 20 actions per run
- Short 5-minute cooldown
- Automatic rollback capability
- Fast Mode enabled

---

### Example 4: Review Healing History
```powershell
# Analyze healing effectiveness
$history = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\healing-history.csv"

# Last 7 days of healing actions
$recentActions = $history | Where-Object {
    ([DateTime]$_.Timestamp) -gt (Get-Date).AddDays(-7)
}

# Success rate by DC
$recentActions | Group-Object DC | Select-Object Name, Count, @{
    Name='SuccessRate'
    Expression={[Math]::Round((($_.Group | Where-Object {$_.Success -eq 'True'}).Count / $_.Count) * 100, 2)}
} | Sort-Object SuccessRate

# Most common issues healed
$recentActions | Group-Object Category | Sort-Object Count -Descending
```

---

### Example 5: Manual Rollback
```powershell
# View recent healing actions
$history = Import-Csv "C:\ProgramData\ADReplicationManager\Healing\healing-history.csv" |
    Sort-Object Timestamp -Descending | Select-Object -First 10

# Rollback a specific action
Invoke-HealingRollback -ActionID "abc123de" `
    -HistoryPath "C:\ProgramData\ADReplicationManager\Healing" `
    -Reason "DC experiencing issues after healing"
```

---

## 🎯 Benefits

### For Operations Teams
- ✅ **Reduced MTTR** - Issues fixed in minutes instead of hours
- ✅ **24/7 Monitoring** - Auto-healing works while you sleep
- ✅ **Consistent Remediation** - Same fix applied every time
- ✅ **Detailed Audit Trail** - Complete history for compliance

### For Administrators
- ✅ **Policy-Based Control** - Choose your risk tolerance
- ✅ **Safety First** - Multiple protections against runaway automation
- ✅ **Rollback Capability** - Undo actions if needed
- ✅ **Learning System** - Cooldowns prevent healing loops

### For Management
- ✅ **Reduced Incidents** - Catch issues before users notice
- ✅ **Lower Operational Costs** - Less manual intervention
- ✅ **Improved SLAs** - Faster issue resolution
- ✅ **Compliance Ready** - Full audit trail with timestamps

---

## 🔍 How Auto-Healing Works

```
┌─────────────────────────────────────────────────────────────┐
│                     1. AUDIT PHASE                          │
│   Discover DCs → Collect snapshots → Identify issues       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  2. POLICY EVALUATION                       │
│   Load healing policy → Check eligibility for each issue   │
│   • Category allowed?                                       │
│   • Severity allowed?                                       │
│   • Manual approval required?                               │
│   • Cooldown period expired?                                │
│   • Issue actionable?                                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  3. HEALING EXECUTION                       │
│   Apply fixes to eligible issues (respecting max limit)    │
│   • Invoke repair action                                    │
│   • Save to audit trail                                     │
│   • Record rollback data                                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  4. ROLLBACK (if needed)                    │
│   If action fails and rollback enabled:                    │
│   • Force fresh replication sync                            │
│   • Record rollback in history                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  5. VERIFICATION & REPORTING                │
│   Verify replication health → Generate reports →           │
│   Send notifications → Update statistics                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Script Statistics

| Metric | Value |
|--------|-------|
| **Version** | 3.2.0 |
| **Lines of Code** | ~2,050 (+470 from v3.1) |
| **New Parameters** | 6 |
| **New Functions** | 5 |
| **Total Functions** | 19 |
| **Backward Compatible** | ✅ 100% |

---

## 🔄 Migration from v3.1

**100% Backward Compatible** - All v3.1 scripts continue to work unchanged.

### Upgrading
```powershell
# Backup current version
Copy-Item .\Invoke-ADReplicationManager.ps1 .\Invoke-ADReplicationManager-v3.1.ps1.bak

# Download v3.2
Invoke-WebRequest -Uri "https://github.com/adrian207/Repl/releases/download/v3.2.0/Invoke-ADReplicationManager.ps1" `
    -OutFile ".\Invoke-ADReplicationManager.ps1"
```

### Enabling Auto-Healing
Add `-AutoHeal` to existing scripts:
```powershell
# Before (v3.1)
.\Invoke-ADReplicationManager.ps1 -Mode Repair -Scope Forest -AutoRepair

# After (v3.2 with Auto-Healing)
.\Invoke-ADReplicationManager.ps1 -Mode Repair -Scope Forest -AutoHeal -HealingPolicy Conservative
```

---

## 🐛 Bug Fixes

- Improved error handling in healing eligibility checks
- Fixed issue with healing history CSV creation on first run
- Enhanced rollback file cleanup to prevent disk space issues
- Better handling of concurrent healing actions

---

## 📚 Documentation

- ✅ Updated `README.md` with Auto-Healing examples
- ✅ Created `RELEASE-NOTES-v3.2.md` (this file)
- ✅ Updated `CHANGELOG.md` with detailed v3.2.0 entry
- ✅ Added Auto-Healing section to API Reference
- ✅ Updated troubleshooting guide with healing scenarios

---

## 🔮 What's Next (v3.3)

Based on the feature backlog:
1. **Delta Mode** - Only check DCs with previous issues (40-80% faster)
2. **Multi-Forest Support** - Cross-forest replication monitoring
3. **Excel Export** - Rich XLSX reports with charts
4. **Comparison Reports** - Before/after analysis

---

## 💬 Feedback & Support

- **Issues:** [GitHub Issues](https://github.com/adrian207/Repl/issues)
- **Discussions:** [GitHub Discussions](https://github.com/adrian207/Repl/discussions)
- **Email:** adrian207@gmail.com

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

**Thank you for using AD Replication Manager!** 🎉

With Auto-Healing, your AD replication is now **self-maintaining**. Set it, monitor it, and let it work for you.

*Built with ❤️ by Adrian Johnson*

