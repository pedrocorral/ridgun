# SEI CERT Coding Standards

## Introduction

The SEI CERT Coding Standards, developed by Carnegie Mellon University's Software Engineering Institute (SEI), provide best practices and coding guidelines designed to improve software security and reliability. These standards focus on preventing vulnerabilities and ensuring that software is developed in a secure and maintainable manner.

Guidelines are cross-referenced with several other standards including **Common Weakness Enumeration (CWE)** entries and **Motor Industry Software Reliability Association (MISRA)** guidelines.

---

## Structure

The standards are divided into two components:

- **Rules** — Mandatory guidelines to prevent critical vulnerabilities or failures. Each includes a risk assessment evaluating potential consequences (security, reliability, maintainability).
- **Recommendations** — Optional best practices that improve overall code quality and address less critical concerns.

Each rule or recommendation follows a consistent structure:

| Element | Description |
|---|---|
| **Title** | Concise name summarizing the rule or recommendation |
| **Description** | Detailed explanation of the issue and why it matters |
| **Risk Assessment** (rules only) | Impact evaluation categorized by severity and likelihood |
| **Noncompliant Code Example** | Demonstrates a violation |
| **Compliant Solution** | Corrected example adhering to the guideline |
| **Mapping to Standards** | Links to relevant standards (CWE, MISRA, etc.) |

---

## Languages Covered

| Language | Notes |
|---|---|
| **C** | Extensive rule set; most mature |
| **C++** | Covers modern C++ practices |
| **Java** | Enterprise and Android development |
| **Perl** | Scripting security |
| **Android** | Mobile-specific security guidelines |

Each language has its own set of specific rules and recommendations on the [SEI CERT website](https://wiki.sei.cmu.edu/confluence/display/seccode).

---

## Relevance to Ridgun

Although Ridgun itself is a new language, the SEI CERT standards are directly relevant to its **implementation** stack:

| Ridgun Component | Applicable CERT Standard |
|---|---|
| VM and compiler (Rust) | CERT C/C++ rules apply to any `unsafe` blocks and FFI boundary code |
| FFI layer (C/C++ interop) | CERT C and CERT C++ rules for memory safety, pointer handling, integer overflow |
| Python bridge | CERT Java rules offer analogous security patterns for managed-language interop |
| Linked native libraries | CERT C/C++ rules for any third-party C/C++ code called via FFI |

---

## Benefits

- **Improved Security** — Reduces common vulnerabilities: buffer overflows, injection attacks, XSS
- **Consistent Code Quality** — Ensures consistency in coding practices; reduces technical debt
- **Compliance** — Meets regulatory requirements (e.g., ISO 26262 for functional safety integrates with MISRA, which aligns with CERT)

---

## How to Apply

1. **Education and Training** — Train developers on CERT rules relevant to the languages they work in
2. **Use of Tools** — Static analysis tools that support CERT rules:
   - **Cppcheck** — C/C++ analysis with CERT rule checking
   - **SCALe** (Source Code Analysis Laboratory) — CMU's own CERT-aligned analysis tool
   - **Cargo Clippy** — While Rust-specific, many lints align with CERT memory safety principles
3. **Regular Code Reviews** — Review code with CERT rules as a checklist, especially for `unsafe` blocks and FFI boundary code

---

## References & Resources

- [SEI CERT Coding Standards](https://wiki.sei.cmu.edu/confluence/display/seccode)
- [CERT C Coding Standard](https://wiki.sei.cmu.edu/confluence/display/c)
- [CERT C++ Coding Standard](https://wiki.sei.cmu.edu/confluence/display/cplusplus)

---

## Related Documents

- [SAST Policy](sast_policy.md) — SAST tools can automate CERT rule checking
- [Secure Code Review Workflow](../../tsk/secure_code_review_workflow.md) — CERT rules feed into the review item list (Step 4)
