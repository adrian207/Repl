# Release Notes - v3.1.0

**Release Date:** October 28, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>

---

## 🎯 Overview

Version 3.1.0 is a **feature release** focused on **proactive monitoring, automated alerting, and health tracking**. This release adds three major capabilities that transform AD Replication Manager from a diagnostic tool into a complete monitoring solution.

---

## 🚀 Three Major Features

### 1. 📬 Slack & Microsoft Teams Integration

**Real-time notifications** delivered directly to your team collaboration tools.

#### Slack Features
- Rich message attachments with color coding
- Emoji indicators for status (✅ ⚠️ 🚫 ❌)
- Detailed metrics breakdown
- Clickable fields with short formatting
- Automatic timestamp

**Example:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Forest `
    -FastMode `
    -SlackWebhook "https://hooks.slack.com/services/T00/B00/XXXX"
```

#### Teams Features
- Adaptive card format
- Theme color based on severity
- Structured facts display
- Activity title and subtitle
- Professional formatting

**Example:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Site:Production `
    -TeamsWebhook "https://outlook.office.com/webhook/..."
```

#### Email Features
- Standard SMTP support
- Configurable notification triggers
- Severity-based priority
- Plain text summary format

**Example:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -EmailTo "ad-admins@company.com" `
    -EmailFrom "ad-monitor@company.com" `
    -SmtpServer "smtp.company.com" `
    -EmailNotification OnIssues  # OnError | OnIssues | Always | Never
```

---

### 2. ⏰ Scheduled Task Auto-Setup

**One command** to create a fully configured Windows scheduled task.

#### Features
- Automatic task registration
- Runs as SYSTEM with highest privileges
- Multiple schedule options (Hourly, Every4Hours, Daily, Weekly)
- Preserves all script parameters including notifications
- Easy management commands included

**Example:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -CreateScheduledTask `
    -Mode Audit `
    -Scope Forest `
    -TaskSchedule Daily `
    -TaskTime "02:00" `
    -TaskName "AD Replication Health Check" `
    -SlackWebhook "https://hooks.slack.com/..." `
    -EmailTo "admin@company.com"
```

#### Management Commands
```powershell
# View task
Get-ScheduledTask -TaskName "AD Replication Health Check"

# Run manually
Start-ScheduledTask -TaskName "AD Replication Health Check"

# Remove task
Unregister-ScheduledTask -TaskName "AD Replication Health Check" -Confirm:$false
```

---

### 3. 📊 Health Score & Historical Trends

**Quantitative assessment** of AD replication health with trend tracking.

#### Scoring System
- **0-100 numerical score** (higher is better)
- **Letter grades:** A+ (95-100), A (90-94), B+ (85-89), B (80-84), C+ (75-79), C (70-74), D (60-69), F (<60)
- **Penalty system** based on severity:
  - Unreachable DC: -10 points
  - Degraded DC: -5 points
  - Critical issue: -3 points
  - High issue: -2 points
  - Medium issue: -1 point
  - Stale replication (>24h): -1 point
  - Very stale replication (>48h): -2 points

#### Historical Tracking
- **CSV format** for easy analysis in Excel/Power BI
- **JSON snapshots** for detailed records
- **Automatic cleanup** of snapshots older than 90 days
- **Trend analysis ready** with timestamp, score, grade, and metrics

**Example:**
```powershell
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -EnableHealthScore `
    -HealthHistoryPath "C:\Reports\ADHealth"
```

**Output:**
```
Health Score: 95.5/100 (A - Excellent)
```

**History File:** `C:\Reports\ADHealth\health-history.csv`
```csv
Timestamp,HealthScore,Grade,TotalDCs,HealthyDCs,DegradedDCs,UnreachableDCs,IssuesFound
2025-10-28 14:30:00,95.5,A - Excellent,24,24,0,0,0
2025-10-27 14:30:00,88.0,B+ - Very Good,24,22,2,0,3
2025-10-26 14:30:00,92.5,A - Excellent,24,23,1,0,1
```

---

## ⚡ Performance Enhancements

### Fast Mode
New `-FastMode` switch provides instant performance tuning:
- **Throttle:** 8 → 24 (3x more parallel operations)
- **Verification wait:** 120s → 30s (4x faster convergence check)
- **Retry attempts:** 3 → 2 (faster failure detection)
- **Expected improvement:** 40-60% faster execution

**Example:**
```powershell
.\Invoke-ADReplicationManager.ps1 -Mode Audit -Scope Forest -FastMode
```

### Retry Logic
Exponential backoff with intelligent error classification:
- **Transient errors:** Automatic retry with backoff (2s, 4s, 8s, 16s, 30s)
- **Permanent errors:** Immediate failure (no wasted retries)
- **Configurable:** MaxRetryAttempts, InitialDelaySeconds, MaxDelaySeconds

---

## 📋 Complete Feature List

| Feature | Parameter | Description |
|---------|-----------|-------------|
| **Slack Alerts** | `-SlackWebhook` | Send formatted alerts to Slack channel |
| **Teams Alerts** | `-TeamsWebhook` | Send adaptive cards to Teams channel |
| **Email Alerts** | `-EmailTo`, `-SmtpServer` | Send email notifications via SMTP |
| **Email Triggers** | `-EmailNotification` | When to send: OnError, OnIssues, Always, Never |
| **Scheduled Task** | `-CreateScheduledTask` | Auto-create Windows scheduled task |
| **Task Schedule** | `-TaskSchedule` | Frequency: Hourly, Every4Hours, Daily, Weekly |
| **Task Timing** | `-TaskTime` | Time of day (e.g., "02:00") |
| **Task Name** | `-TaskName` | Custom task name (default: "AD Replication Health Check") |
| **Health Score** | `-EnableHealthScore` | Calculate 0-100 health score with letter grade |
| **History Path** | `-HealthHistoryPath` | Where to store historical health data |
| **Fast Mode** | `-FastMode` | Enable all performance optimizations |

---

## 🔧 Technical Details

### New Functions
1. **`Send-SlackAlert`** - Sends formatted Slack notifications
2. **`Send-TeamsAlert`** - Sends Teams adaptive cards
3. **`Send-EmailAlert`** - Sends SMTP email notifications
4. **`Get-HealthScore`** - Calculates 0-100 health score
5. **`Save-HealthHistory`** - Persists health data to CSV/JSON
6. **`Invoke-WithRetry`** - Exponential backoff retry logic

### Script Statistics
- **Lines of Code:** ~1,580 (was ~1,000 in v3.0)
- **Functions:** 14 total (5 new in v3.1)
- **Parameters:** 30 total (13 new in v3.1)
- **Exit Codes:** 0/2/3/4 (unchanged)

### Backward Compatibility
- ✅ **100% compatible** with v3.0
- ✅ All existing parameters work unchanged
- ✅ New parameters are optional
- ✅ Default behavior unchanged

---

## 📦 Installation

### Upgrade from v3.0
```powershell
# Backup existing script
Copy-Item .\Invoke-ADReplicationManager.ps1 .\Invoke-ADReplicationManager-v3.0.ps1.bak

# Download v3.1
Invoke-WebRequest -Uri "https://github.com/adrian207/Repl/releases/download/v3.1.0/Invoke-ADReplicationManager.ps1" `
    -OutFile ".\Invoke-ADReplicationManager.ps1"

# Verify version
.\Invoke-ADReplicationManager.ps1 -? | Select-String "Version"
```

### Fresh Install
```powershell
# Clone repository
git clone https://github.com/adrian207/Repl.git
cd Repl

# Check version
git checkout v3.1.0
```

---

## 🎯 Quick Start Examples

### Example 1: Complete Monitoring Setup
```powershell
# One-time setup: Create scheduled task with all notifications
.\Invoke-ADReplicationManager.ps1 `
    -CreateScheduledTask `
    -TaskSchedule Daily `
    -TaskTime "02:00" `
    -Mode AuditRepairVerify `
    -Scope Forest `
    -AutoRepair `
    -EnableHealthScore `
    -SlackWebhook "https://hooks.slack.com/services/YOUR/WEBHOOK" `
    -TeamsWebhook "https://outlook.office.com/webhook/YOUR/WEBHOOK" `
    -EmailTo "ad-admins@company.com" `
    -SmtpServer "smtp.company.com" `
    -EmailNotification OnIssues
```

### Example 2: Manual Audit with Notifications
```powershell
# Ad-hoc health check with immediate alerts
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Site:Production `
    -FastMode `
    -EnableHealthScore `
    -SlackWebhook "https://hooks.slack.com/..." `
    -Verbose
```

### Example 3: Track Health Trends
```powershell
# Daily audit with health tracking
.\Invoke-ADReplicationManager.ps1 `
    -Mode Audit `
    -Scope Forest `
    -EnableHealthScore `
    -HealthHistoryPath "C:\Reports\ADHealth" `
    -OutputPath "C:\Reports\ADHealth\$(Get-Date -Format 'yyyy-MM-dd')"

# Analyze trends
Import-Csv "C:\Reports\ADHealth\health-history.csv" | 
    Select-Object Timestamp, HealthScore, Grade, DegradedDCs |
    Format-Table -AutoSize
```

---

## 🐛 Bug Fixes

- Fixed unused variable warning in scheduled task creation
- Improved error handling in notification functions (fail gracefully)
- Enhanced summary object structure for better JSON serialization

---

## 📚 Documentation Updates

- ✅ Updated `README.md` with v3.1 features
- ✅ Created `RELEASE-NOTES-v3.1.md` (this file)
- ✅ Updated `CHANGELOG.md` with detailed v3.1 entry
- ✅ Created `docs/FEATURE-BACKLOG.md` with future roadmap
- ✅ Updated version badges and links

---

## 🔮 Coming in v3.2

Based on the feature backlog, here's what's planned:

1. **Delta Mode** - Only check DCs with previous issues (40-80% faster for monitoring)
2. **Excel Export** - Rich XLSX reports with multiple worksheets
3. **Comparison Reports** - Before/after analysis
4. **Custom Repair Actions** - Extensible repair framework
5. **Webhook Integration** - Generic webhook support for any system

See `docs/FEATURE-BACKLOG.md` for full roadmap.

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

*Built with ❤️ by Adrian Johnson*

