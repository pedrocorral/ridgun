# SAST Policy

Guidelines for integrating Static Application Security Testing into the Ridgun development lifecycle.

---

## Tool Selection

- Select SAST tools aligned with the technology stack (Rust, C/C++, Python) and compliance needs.
- Define security policies, severity thresholds, and enforcement gates.
- Identify coding standards to be verified through SAST.

See [static_application_security_testing.md](../../tsk/static_application_security_testing.md) for the recommended tool stack.

---

## Security Gates

- Establish security gates that **block critical vulnerabilities** from being merged.
- Implement incremental scanning and parallel processing to improve CI performance.
- Create baselines to focus on **new vulnerabilities** — avoid alert fatigue from pre-existing findings.

| Severity | Gate Policy |
|---|---|
| **Critical** | ❌ Block merge. Immediate fix required. |
| **High** | ❌ Block merge. Fix before next evaluation. |
| **Medium** | ⚠️ Warn. Track. Fix within current spiral. |
| **Low** | ℹ️ Inform. Fix when convenient. |

---

## Release Approval

- Include SAST results in **release approval criteria**.
- Require **security sign-off** based on SAST findings before deployment.
- Generate automated security dashboards showing vulnerability status per release.

---

## Strategies for Improving SAST

| Strategy | Action |
|---|---|
| **Keep rules updated** | Regularly refine detection rules to cover new threats and Ridgun-specific patterns |
| **Fine-tune scanning** | Exclude non-relevant code, use context-aware analysis to reduce noise |
| **Track key metrics** | Monitor false-positive rate, time-to-fix, high-risk findings per release |
| **Promote secure coding culture** | Provide security training, hands-on exercises, and learning opportunities based on SAST findings |
| **Continuous improvement** | Security testing must be regularly refined and updated to stay effective |

---

## Key Principles

1. **Early detection matters.** Catching vulnerabilities early prevents security flaws from reaching production.

2. **Accuracy is key.** Reducing false positives, customizing rules, and prioritizing findings improve efficiency and developer adoption.

3. **SAST alone is not enough.** Combine with:

| Method | Purpose |
|---|---|
| **DAST** (Dynamic Application Security Testing) | Runtime vulnerability detection |
| **IAST** (Interactive Application Security Testing) | Combines SAST + DAST with runtime instrumentation |
| **SCA** (Software Composition Analysis) | Dependency vulnerability and license compliance |
| **Secrets Scanning** | Detect leaked credentials across Git history and filesystems |

Together these provide defense-in-depth coverage that no single tool can achieve alone.

---

## Related Documents

- [process.md](../etc/process.md) — OWASP SAMM verification practices
- [SAST task](../../tsk/static_application_security_testing.md) — Tool stack and CI integration
- [SCA task](../../tsk/software_composition_analysis.md) — Dependency analysis
- [Secrets scanning task](../../tsk/secrets_scanning.md) — Credential leak detection
- [Secure code review workflow](../../tsk/secure_code_review_workflow.md) — Manual review process
