# Software Composition Analysis (SCA)

Software Composition Analysis identifies open source software used in a codebase to evaluate **security**, **license compliance**, and **code quality**. SCA can be used before even deploying an application, pinpointing the source of known vulnerabilities in dependencies.

---

## Purpose

The Ridgun toolchain depends on third-party components at multiple layers:

| Layer | Dependencies |
|---|---|
| **VM & Compiler** (Rust) | Crates: PyO3, crossbeam, libffi, serde, etc. |
| **Python Bridge** | Python packages imported by Ridgun programs at runtime |
| **FFI Libraries** | System shared libraries: libtorch, libcurl, libsqlite3, etc. |

Each dependency is a potential vector for:
- **Known vulnerabilities** (CVEs) — exploitable bugs in upstream code
- **License violations** — incompatible licenses contaminating Ridgun's Apache 2.0
- **Supply chain attacks** — malicious code injected into dependencies

SCA provides continuous visibility into all of these risks.

---

## Tool: OWASP Dependency-Track

[OWASP Dependency-Track](https://dependencytrack.org/) is an intelligent Component Analysis platform that allows organizations to identify and reduce risk in the software supply chain.

Dependency-Track takes a unique approach by leveraging **Software Bill of Materials (SBOM)**, providing capabilities that traditional SCA solutions cannot achieve.

### Why Dependency-Track for Ridgun

| Capability | Benefit |
|---|---|
| **SBOM ingestion** | Consumes CycloneDX / SPDX BOMs generated from `Cargo.lock`, `pip`, and system packages |
| **Continuous monitoring** | Tracks vulnerabilities as new CVEs are published — not just at build time |
| **Policy engine** | Define license policies (e.g., reject GPL, flag LGPL) and enforce automatically |
| **Multi-source vulnerability intelligence** | Aggregates from NVD, GitHub Advisories, OSV, and more |
| **Component inventory** | Centralized view of every dependency across all Ridgun layers |
| **Risk scoring** | CVSS-based severity with exploitability context |

### Integration with Ridgun Build Pipeline

```
  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐
  │  cargo build │     │  pip freeze  │     │  ldd / pkg-config    │
  │              │     │              │     │  (system libs)       │
  └──────┬───────┘     └──────┬───────┘     └──────────┬───────────┘
         │                    │                        │
         ▼                    ▼                        ▼
  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐
  │ cargo-cyclone│     │ cyclonedx-   │     │  Manual / scripted   │
  │ dx (SBOM)    │     │ python (SBOM)│     │  SBOM generation     │
  └──────┬───────┘     └──────┬───────┘     └──────────┬───────────┘
         │                    │                        │
         └────────────────────┼────────────────────────┘
                              │
                              ▼
                ┌─────────────────────────┐
                │   OWASP Dependency-     │
                │   Track Server          │
                │                         │
                │  • Vulnerability alerts  │
                │  • License policy check  │
                │  • Component inventory   │
                │  • Risk dashboard        │
                └─────────────────────────┘
```

### SBOM Generation Commands

```bash
# Rust crates (Cargo)
cargo install cargo-cyclonedx
cargo cyclonedx --format json --output-file ridgun-rust-sbom.json

# Python dependencies
pip install cyclonedx-bom
cyclonedx-py environment --output-format json -o ridgun-python-sbom.json
```

### License Policy for Ridgun

Ridgun is licensed under **Apache 2.0**. Dependencies must be compatible:

| License | Policy |
|---|---|
| MIT, BSD-2, BSD-3 | ✅ Allowed |
| Apache 2.0 | ✅ Allowed |
| ISC, Zlib, Unlicense | ✅ Allowed |
| MPL-2.0 | ⚠️ Review required (file-level copyleft) |
| LGPL-2.1, LGPL-3.0 | ⚠️ Review required (dynamic linking may be acceptable) |
| GPL-2.0, GPL-3.0 | ❌ Rejected (incompatible with Apache 2.0 distribution) |
| AGPL-3.0 | ❌ Rejected |
| No license / Unknown | ❌ Rejected until clarified |

### When to Run SCA

| Trigger | Action |
|---|---|
| **Every CI build** | Generate SBOM, upload to Dependency-Track |
| **Dependency update** | Re-generate SBOM, verify no new vulnerabilities or license violations |
| **New spiral starts** | Full dependency audit as part of SAMM Dependency Management |
| **CVE alert from Dependency-Track** | Triage, assess impact on Ridgun, patch or mitigate |

---

## Relationship to Other Process Documents

- **[process.md](../doc/process.md)** — OWASP SAMM "Dependency Management" practice references SCA
- **[secure_code_review_workflow.md](secure_code_review_workflow.md)** — SCA complements manual secure code review (automated supply chain analysis vs. manual code inspection)
