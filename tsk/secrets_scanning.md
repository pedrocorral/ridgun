# Secrets Scanning

Continuous and ongoing monitoring is crucial given how often things change within a given environment. By regularly scanning scripts and source code for improper secrets usage or unintended secret exposures, vulnerabilities can be identified and remediated before they are exploited. Automated scanning is an efficient and proactive measure for securing secrets.

---

## Scope for Ridgun

Secrets can leak at every layer of the project:

| Layer | Risk Examples |
|---|---|
| **Source code** (`src/`) | Hardcoded API keys, database credentials, signing keys |
| **Test fixtures** (`tst/`) | Test credentials committed by accident, real API tokens in integration tests |
| **Documentation** (`doc/`) | Example configs with real secrets, copy-pasted terminal output containing tokens |
| **CI/CD configuration** | Pipeline secrets in plaintext, environment variables logged in build output |
| **Git history** | Secrets committed and then "deleted" — still recoverable from past commits |
| **Ridgun programs** (`.rg` files) | User programs containing embedded credentials passed to FFI or Python bridge |

---

## Tool: TruffleHog

[TruffleHog](https://github.com/trufflesecurity/trufflehog) is a secrets scanning tool that digs deep into code repositories to find secrets, passwords, and sensitive keys across the SDLC — from Git repos to ticket systems.

### Why TruffleHog for Ridgun

| Capability | Benefit |
|---|---|
| **Git history scanning** | Scans every commit, branch, and tag — catches secrets that were "deleted" but remain in history |
| **600+ secret detectors** | Pre-built detectors for AWS, GCP, Azure, GitHub, Slack, database URLs, private keys, and more |
| **Verification** | Actively checks if a detected secret is still valid (live credential vs. revoked) |
| **Multi-source** | Scans Git repos, filesystems, S3 buckets, CI logs, and more |
| **Low false-positive rate** | Pattern + entropy + verification reduces noise |

### Installation

```bash
# Via prebuilt binary
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# Via Docker
docker pull trufflesecurity/trufflehog:latest
```

### Usage for Ridgun

```bash
# Scan the entire Git history of the Ridgun repository
trufflehog git file://. --only-verified

# Scan the filesystem (catches untracked files)
trufflehog filesystem --directory . --only-verified

# Scan with all results (including unverified potential secrets)
trufflehog git file://. --results=verified,unknown
```

### Integration Points

```
Developer Workstation                CI Pipeline
       │                                  │
       ▼                                  ▼
  Pre-commit hook                   CI job (every push)
  ┌──────────────┐              ┌──────────────────┐
  │ trufflehog   │              │ trufflehog git    │
  │ filesystem   │              │ --since-commit    │
  │ --directory . │              │ $LAST_CLEAN       │
  └──────┬───────┘              └──────┬────────────┘
         │                             │
         ▼                             ▼
  Block commit if                Fail pipeline if
  secrets found                  secrets found
```

### Pre-commit Hook Setup

```bash
# .git/hooks/pre-commit (or via pre-commit framework)
#!/bin/bash
trufflehog filesystem --directory . --only-verified --fail
if [ $? -ne 0 ]; then
    echo "ERROR: Secrets detected. Remove them before committing."
    exit 1
fi
```

### When to Scan

| Trigger | Scan Type |
|---|---|
| **Every commit** (pre-commit hook) | Filesystem scan of staged changes |
| **Every CI build** | Incremental Git scan (since last clean commit) |
| **Weekly / scheduled** | Full Git history scan (catches historical leaks) |
| **New spiral starts** | Full scan as part of SAMM security verification |
| **Before any public release** | Full scan + manual review of results |

### Remediation Workflow

When a secret is detected:

```
 1. VERIFY
    └── Is it a real secret? Is it still active?

 2. REVOKE
    └── Immediately rotate/revoke the credential at the source
        (API provider, database, service)

 3. REMOVE
    └── Remove from codebase. If in Git history:
        git filter-branch or BFG Repo-Cleaner

 4. REPLACE
    └── Use environment variables, secret managers, or
        Ridgun's runtime config (never hardcode)

 5. REPORT
    └── Document as a security finding per the
        Secure Code Review report template
```

---

## Relationship to Other Process Documents

- **[process.md](../doc/process.md)** — OWASP SAMM "Secure Build" and "Environment Hardening" practices cover secrets management
- **[secure_code_review_workflow.md](secure_code_review_workflow.md)** — Step 4 "Configuration Review" includes checking for hardcoded secrets
- **[software_composition_analysis.md](software_composition_analysis.md)** — Complements SCA; SCA tracks vulnerable dependencies, secrets scanning tracks leaked credentials
