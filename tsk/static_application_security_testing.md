# Static Application Security Testing (SAST)

SAST is a **white-box testing** approach that analyzes source code without executing it. It is particularly effective at finding code-level security flaws such as injection vulnerabilities, hardcoded secrets, and weak cryptography.

---

## Detection Accuracy

SAST tools face challenges with detection accuracy:

- **False positives** — Incorrectly flagged vulnerabilities due to overly generic rules, lack of context, or existing security controls that the tool cannot see.
- **False negatives** — Missed vulnerabilities caused by tool limitations, particularly with runtime-related issues like authentication flaws, business logic errors, and misconfigurations.

To improve accuracy, SAST combines multiple techniques, allowing different approaches to compensate for each other's weaknesses.

---

## Analysis Techniques

| Technique | Description |
|---|---|
| **Rule-based pattern matching** | Finds vulnerabilities using predefined code patterns |
| **Lexical analysis** | Breaks code into tokens to spot suspicious patterns |
| **AST analysis** | Structures code as a tree to analyze relationships |
| **Data flow analysis** | Tracks data movement throughout the application |
| **Control flow analysis** | Examines execution paths for logical flaws |
| **Taint analysis** | Follows untrusted input to sensitive functions |
| **Context-sensitive analysis** | Considers function context to reduce false positives |

Some SAST tools incorporate **AI and Machine Learning** to further improve accuracy. These algorithms analyze large amounts of data and learn from past security issues, helping detect problems more effectively over time — including identification of previously unknown vulnerabilities (zero-days). NLP capabilities can understand variable names, comments, and documentation, recognizing when flagged code is actually safe and reducing false alarms.

---

## Application to Ridgun

Ridgun is built in **Rust** with **FFI to C/C++** and an **embedded CPython bridge**. SAST must cover all three language boundaries:

| Codebase Layer | Language | Key Vulnerability Classes |
|---|---|---|
| VM, compiler, scheduler | Rust | `unsafe` block misuse, memory safety violations, concurrency bugs |
| FFI boundary | Rust + C | Buffer overflows, null pointer dereference, use-after-free, type confusion |
| Python bridge | Rust + Python | Injection via string interpolation, GIL state corruption |
| Standard library | Rust | Cryptographic misuse, insecure defaults, path traversal |
| Build scripts | Bash / Python | Command injection, environment variable leaks |

### Technique Mapping for Ridgun

| Technique | Ridgun Application |
|---|---|
| **Taint analysis** | Track untrusted bytecode input from `.rgc` files through the loader to execution |
| **Data flow analysis** | Follow FFI arguments from Ridgun values through marshalling to native calls |
| **Control flow analysis** | Verify scheduler state machine transitions have no unreachable-but-exploitable paths |
| **AST analysis** | Analyze Ridgun source (`.rg`) for patterns that could cause runtime security issues |
| **Pattern matching** | Detect `unsafe` blocks, raw pointer usage, `transmute`, `.unwrap()` in error paths |

---

## Selecting a SAST Tool

### Open-Source Tools Relevant to Ridgun

| Tool | Target | Use in Ridgun |
|---|---|---|
| **`cargo clippy`** | Rust | Built-in linter with security-relevant lints; run on every build |
| **`cargo audit`** | Rust (Cargo.lock) | Checks dependencies for known vulnerabilities (RustSec advisory DB) |
| **`cargo deny`** | Rust | License + vulnerability + duplicate dependency checking |
| **`cargo geiger`** | Rust | Counts and reports usage of `unsafe` code in the dependency tree |
| **Semgrep** | Multi-language | Lightweight, customizable rules; write Ridgun-specific patterns |
| **Flawfinder** | C/C++ | Scan any C/C++ code exposed to Ridgun via FFI |
| **Cppcheck** | C/C++ | Low false-positive C/C++ analysis, useful for FFI target libraries |
| **Bandit** | Python | Scan Python code used in build scripts or Python bridge test harnesses |

### Tool Selection Criteria

| Criterion | Consideration |
|---|---|
| **Language support** | Must cover Rust (primary), C/C++ (FFI), Python (bridge/scripts) |
| **CI integration** | Must run in automated pipelines with machine-readable output |
| **Custom rules** | Ability to write Ridgun-specific patterns (e.g., Semgrep rules for `unsafe` FFI patterns) |
| **False-positive rate** | Prioritize precision — high false-positive rates erode developer trust |
| **Maintenance** | Active community, regular updates, responsive to new vulnerability classes |

### Recommended Stack for Ridgun

```
Rust Code                  C/C++ (FFI targets)        Python (scripts/tests)
    │                           │                          │
    ▼                           ▼                          ▼
cargo clippy               Flawfinder                 Bandit
cargo audit                Cppcheck                       │
cargo deny                     │                          │
cargo geiger                   │                          │
    │                          │                          │
    └──────────────────────────┼──────────────────────────┘
                               │
                               ▼
                           Semgrep
                    (cross-language custom rules)
```

### When to Run SAST

| Trigger | Tools | Scope |
|---|---|---|
| **Every commit** (pre-commit) | `cargo clippy` | Changed Rust files |
| **Every CI build** | All tools | Full codebase |
| **Dependency update** | `cargo audit`, `cargo deny` | Dependency tree |
| **New spiral starts** | Full suite + `cargo geiger` | Deep `unsafe` audit |
| **Before release** | All tools + manual review of findings | Full codebase + triage |

---

## Relationship to Other Process Documents

- **[process.md](../doc/process.md)** — OWASP SAMM "Security Testing" practice; SAST is the primary automated verification tool
- **[secure_code_review_workflow.md](secure_code_review_workflow.md)** — SAST complements manual secure code review; automated findings feed into the review item list (Step 4)
- **[software_composition_analysis.md](software_composition_analysis.md)** — SCA covers dependency vulnerabilities; SAST covers first-party code vulnerabilities
- **[secrets_scanning.md](secrets_scanning.md)** — Some SAST tools detect hardcoded secrets, but TruffleHog provides deeper Git-history scanning
