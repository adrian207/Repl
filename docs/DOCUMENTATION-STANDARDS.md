# Documentation Standards & Guidelines

## Document Metadata Requirements

**All documentation files MUST include the following metadata header:**

```markdown
# [Document Title]

**Version:** [X.Y]  
**Last Updated:** [YYYY-MM-DD]  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** [Internal Use | Confidential | Public]

---
```

### Required Fields

| Field | Description | Example |
|-------|-------------|---------|
| **Version** | Document version (semantic) | `1.0`, `1.1`, `2.0` |
| **Last Updated** | ISO 8601 date | `2025-10-28` |
| **Author** | Full name and email | `Adrian Johnson <adrian207@gmail.com>` |
| **Classification** | Data classification level | `Internal Use`, `Confidential`, `Public` |

---

## Document Footer Requirements

**All documentation files SHOULD include a footer with:**

```markdown
---

## Document Information

**Prepared by:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer  
Organization: Enterprise IT Operations

**Version History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | YYYY-MM-DD | Adrian Johnson | Initial release |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**
```

---

## Authorship Attribution Rules

### Primary Author
- **Adrian Johnson <adrian207@gmail.com>** is the primary author of all v3.0 documentation
- All documentation files MUST credit Adrian Johnson as the author
- Email contact MUST be included for support queries

### Contributing Authors
If others contribute significantly:

```markdown
**Primary Author:** Adrian Johnson <adrian207@gmail.com>  
**Contributors:**  
- [Name] <[email]> - [Contribution description]
- [Name] <[email]> - [Contribution description]
```

### Version History
Every document MUST maintain a version history table:

```markdown
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.1 | 2025-10-30 | Adrian Johnson | Added section on XYZ |
| 1.0 | 2025-10-28 | Adrian Johnson | Initial release |
```

---

## Code Attribution

### Script Headers
All PowerShell scripts MUST include:

```powershell
<#
.SYNOPSIS
    [Brief description]

.DESCRIPTION
    [Detailed description]

.AUTHOR
    Adrian Johnson <adrian207@gmail.com>

.VERSION
    3.0

.DATE
    2025-10-28

.COPYRIGHT
    Copyright (c) 2025 Adrian Johnson. All rights reserved.

.LICENSE
    MIT License
#>
```

### Inline Code Attribution
For code examples in documentation:

```markdown
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Date:** 2025-10-28
```

---

## Documentation Types & Classifications

### Core Documentation
**Files:** README.md, Design Documents, API References  
**Classification:** Internal Use  
**Authorship Required:** ✅ Yes (Header + Footer)  
**Version History Required:** ✅ Yes

### Operational Documentation
**Files:** Operations Manual, Troubleshooting Guides, SOPs  
**Classification:** Internal Use  
**Authorship Required:** ✅ Yes (Header + Footer)  
**Version History Required:** ✅ Yes

### Supporting Documentation
**Files:** Migration Guides, Comparison Docs, Summaries  
**Classification:** Internal Use  
**Authorship Required:** ✅ Yes (Header + Footer)  
**Version History Required:** ✅ Yes

### Quick Reference
**Files:** Cheat sheets, Quick starts  
**Classification:** Internal Use  
**Authorship Required:** ✅ Yes (Header only)  
**Version History Required:** ⚠️ Optional

---

## Copyright & Licensing

### Copyright Statement
All documentation:
```markdown
**Copyright © 2025 Adrian Johnson. All rights reserved.**
```

### License
Unless otherwise specified:
```markdown
**License:** MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this documentation and associated files, to deal in the documentation without
restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the documentation, and to
permit persons to whom the documentation is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the documentation.
```

---

## Quality Standards

### Markdown Formatting
- ✅ Use ATX-style headers (`#` not underlines)
- ✅ Include table of contents for docs > 5 pages
- ✅ Use fenced code blocks with language specifiers
- ✅ Use tables for structured data
- ✅ Use emoji sparingly and consistently (✅ ❌ ⚠️ 🔴)

### Writing Style
- ✅ Use active voice ("Run the script" not "The script should be run")
- ✅ Use second person ("You can configure..." not "One can configure...")
- ✅ Use present tense ("The script checks..." not "The script will check...")
- ✅ Be concise and clear
- ✅ Use examples liberally

### Technical Accuracy
- ✅ All code examples must be tested
- ✅ All commands must be validated
- ✅ All parameters must be documented
- ✅ All screenshots must be current

---

## Review & Approval Process

### Document Reviews
| Document Type | Review Frequency | Reviewer | Approver |
|--------------|------------------|----------|----------|
| **Core Docs** | Quarterly | Technical Lead | Adrian Johnson |
| **Operations Docs** | Bi-annually | Operations Manager | Adrian Johnson |
| **Supporting Docs** | Annually | Document Owner | Adrian Johnson |

### Version Increments
| Change Type | Version Increment | Example |
|-------------|-------------------|---------|
| **Typo/formatting** | Patch (x.x.1) | 1.0.0 → 1.0.1 |
| **New section** | Minor (x.1.x) | 1.0.0 → 1.1.0 |
| **Major rewrite** | Major (1.x.x) | 1.0.0 → 2.0.0 |

---

## Document Templates

### Standard Document Template

```markdown
# [Document Title]

**Version:** 1.0  
**Last Updated:** YYYY-MM-DD  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Classification:** Internal Use

---

## Table of Contents
- [Overview](#overview)
- [Section 1](#section-1)
- [Section 2](#section-2)
- [Conclusion](#conclusion)

---

## Overview

[Document overview and purpose]

---

## Section 1

[Content]

---

## Section 2

[Content]

---

## Conclusion

[Summary and next steps]

---

## Document Information

**Prepared by:**  
Adrian Johnson  
Email: adrian207@gmail.com  
Role: Systems Architect / PowerShell Developer  
Organization: Enterprise IT Operations

**Version History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | YYYY-MM-DD | Adrian Johnson | Initial release |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**
```

---

## Enforcement

### Automated Checks
Consider implementing automated checks:

```powershell
# Check for author attribution
$docs = Get-ChildItem .\docs -Filter "*.md"
foreach ($doc in $docs) {
    $content = Get-Content $doc.FullName -Raw
    if ($content -notmatch "Adrian Johnson") {
        Write-Warning "$($doc.Name) missing author attribution"
    }
}
```

### Pre-commit Hooks
Git pre-commit hook to validate documentation:

```bash
#!/bin/bash
# Validate all .md files have author attribution
for file in $(git diff --cached --name-only | grep "\.md$"); do
    if ! grep -q "Adrian Johnson" "$file"; then
        echo "Error: $file missing author attribution"
        exit 1
    fi
done
```

---

## Contact & Support

### Documentation Questions
**Adrian Johnson**  
Email: adrian207@gmail.com  
Role: Primary Author & Documentation Owner

### Style Guide Questions
Refer to this document or contact Adrian Johnson

---

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-28 | Adrian Johnson | Initial documentation standards |

---

**Copyright © 2025 Adrian Johnson. All rights reserved.**

