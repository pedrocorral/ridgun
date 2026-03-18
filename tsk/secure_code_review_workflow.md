# Secure Code Review Workflow

Codebases often have thousands of lines of code. Reviewing each line by hand might not yield the best results. Instead, we leverage a **hybrid approach** that combines automated SAST tools with a manual, risk-based secure code review. As outlined in [process.md](../doc/process.md), their scope is different, but they complement each other.

The following workflow is based on the **Practical Secure Code Review** methodology by AbsoluteAppSec.

---

## Step 1 — Determine Application Purpose

To identify vulnerabilities and plan the level of effort and scrutiny for a code review, the reviewer must understand the application's purpose and risk. This understanding helps develop a **threat model** that can tailor future tests.

For Ridgun, the "application" under review may be:
- The VM and runtime itself (scheduler, GC, bytecode loader)
- The FFI boundary layer
- The Python bridge
- The standard library modules
- User-authored Ridgun programs (when doing review-as-a-service)

## Step 2 — Map the Application

Map out the application's architecture to identify:

| Element | Description |
|---|---|
| **Data sources** | Exposed endpoints and functionality (e.g., bytecode loader input, FFI function signatures, Python bridge entry points, REPL input) |
| **Data sinks** | Externally dependent services (e.g., FFI calls to native libraries, Python interpreter, file system, network sockets) |
| **Data flows** | Relevant paths for each test procedure, ensuring vulnerabilities can be identified along every path from source to sink |

## Step 3 — Brainstorm Risks

Once you understand what is valuable from the technical and functional point of view, address: **what could go wrong?**

Follow a **risk-based approach**, prioritizing threats with higher impact and higher likelihood of exploitation. When calculating likelihood, consider the exposure of the component:

| Exposure Level | Example Components |
|---|---|
| **High** (externally accessible) | Bytecode loader (accepts `.rgc` files), REPL, network-facing stdlib |
| **Medium** (internal but reachable) | FFI layer, Python bridge, channel internals |
| **Low** (internal only) | GC internals, scheduler implementation details |

## Step 4 — Build List of Review Items

Based on the identified threats, define what vulnerabilities could be exploited. Leverage existing templates like the **OWASP ASVS**. Go beyond a static checklist to maximize the review:

- [ ] **Authentication Review** — How does the system verify identity? (relevant for networked Ridgun services)
- [ ] **Authorization Review** — Can a green thread access resources it shouldn't? Can FFI load arbitrary `.so` files?
- [ ] **Audit Review** — Are security-relevant events logged? Can logs be tampered with?
- [ ] **Injection Review**
  - [ ] **Input Validation Review** — Is bytecode input validated before execution? Are FFI arguments sanitized?
  - [ ] **Output Encoding Review** — Are outputs to external systems properly encoded?
- [ ] **Cryptographic Review** — Are cryptographic operations in stdlib correctly implemented? Secure defaults?
- [ ] **Configuration Review** — Are VM startup defaults secure? Are debug features disabled in production?

## Step 5 — Perform Review

Methodically work through the list of review items, examining the application for vulnerabilities, code quality, and adherence to security best practices.

Use **both automated tools and manual inspection**:

| Approach | Tools / Techniques |
|---|---|
| **Automated (SAST)** | `cargo clippy` (security lints), `cargo audit`, `cargo deny`, custom fuzzers in `tst/security/` |
| **Manual** | Line-by-line inspection of `unsafe` blocks, FFI boundary code, bytecode deserialization, scheduler state transitions |

Ensure thoroughness by:
- Tracing data flows from source to sink
- Testing edge cases and boundary conditions
- Reviewing error handling paths (are errors silently swallowed?)
- Checking for TOCTOU races in concurrent code

## Step 6 — Report

The reviewer documents findings in a detailed report. Each finding must provide sufficient information for a developer to identify and fix the issue.

### Finding Template

```
## [FINDING-ID]: [Title]

**Description:**
Clear explanation of the vulnerability, how it was discovered,
and why it poses a risk.

**Location:**
- File: `src/vm/bytecode_loader.rs`
- Function: `load_code_segment()`
- Variables: `segment_length`, `raw_buffer`
- Lines: 142-167

**Risk Severity:** Critical / High / Medium / Low / Informational

**Likelihood of Exploitation:** High / Medium / Low
Justification for the likelihood assessment.

**Ease of Exploitation:** Easy / Moderate / Difficult
What an attacker would need (access, tools, knowledge).

**Remediation Approach:**
Specific steps to fix the issue, with code suggestions if applicable.

**References:**
- CWE-XXX: [Name]
- OWASP ASVS vX.X: [Requirement]
- Relevant documentation or prior findings
```

### Report Severity Definitions

| Severity | Definition | Expected Response |
|---|---|---|
| **Critical** | Exploitable vulnerability that could compromise the VM or host system | Immediate fix, block release |
| **High** | Significant vulnerability with clear exploitation path | Fix before next spiral evaluation |
| **Medium** | Vulnerability requiring specific conditions to exploit | Fix within current spiral |
| **Low** | Minor issue with limited security impact | Track and fix when convenient |
| **Informational** | Observation or improvement suggestion, not a direct vulnerability | Consider for future improvement |
