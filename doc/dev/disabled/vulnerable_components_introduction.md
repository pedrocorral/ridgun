# Using Known Vulnerable Components

> **Status: DISABLED** — This document is archived for future reference. Detailed dependency security planning is out of scope for the current development phase.

---

## Introduction

Most applications rely on third-party components to provide functionalities such as logging, templating, database access, and more. These components streamline software development, saving time and effort. However, like any software, they can contain vulnerabilities, whether introduced during their creation or through subsequent updates. This means applications may unknowingly include exploitable vulnerabilities, posing potential security risks.

---

## Description

Vulnerable and outdated components are software or libraries that are no longer supported or contain known security vulnerabilities. These components can expose applications to serious risks, including injection flaws, unauthorized access, buffer overflows, and much more.

Keeping software components like frameworks and libraries up to date is key for minimizing security risks, but the process requires careful management to avoid new issues. Updates can sometimes introduce breaking changes that only surface during production. Applications that fall behind on updates may face significant challenges, especially if multiple versions must be skipped to catch up. This can delay the resolution of urgent vulnerabilities, leaving systems exposed to potential exploits. A thoughtful update process is essential, which includes thoroughly reviewing release notes. These notes often highlight important changes that could impact application functionality.

### Notable Examples

| Vulnerability | Description |
|---|---|
| **Heartbleed** | A critical vulnerability in OpenSSL that allowed attackers to read sensitive data (private keys, passwords) directly from the memory of servers using affected versions. |
| **Struts2** | A remote code execution flaw in Apache Struts2, a popular Java framework. Attackers could execute arbitrary commands by exploiting improperly processed HTTP requests. |
| **Log4Shell** | A severe vulnerability in Log4j, a widely used Java logging library. Enabled remote code execution through a maliciously crafted log entry, impacting countless systems. |

---

## Mitigation Techniques

Effectively managing vulnerable components is essential to ensuring the security, reliability, and compliance of modern software applications. Two key strategies are:

1. **Component tracking and management** — Catalog all software components for visibility and risk identification.
2. **Proactive vulnerability detection** — Automate scanning for known vulnerabilities.

---

## Component Tracking and Management

Track and catalog all software components in your application to gain visibility into dependencies and ensure they are properly managed. This is typically achieved with a **Software Bill of Materials (SBOM)**.

An SBOM is a formal set of machine-readable metadata describing your software application — a listing of all components, their licenses, versions, and origins.

### SBOM Contents

**Core fields:**

- **Author Name** — Creator of the component
- **Vendor Name** — Organization or individual providing the component
- **Component Name** — Name of the dependency
- **Version** — Specific version of the component
- **Component Hash** — Unique hash for integrity verification
- **Unique Identifier** — ID within the SBOM for reference
- **Relationship** — How the component relates to the package or application

**Additional information:**

- **Security Scores** — Risk level indicators
- **Common Vulnerabilities and Exposures (CVEs)** — Known vulnerabilities
- **Severity** — Impact level of identified vulnerabilities

### SBOM Formats

| Format | Maintainer | Focus | File Formats |
|---|---|---|---|
| **SPDX** | Linux Foundation | Software licensing and compliance | JSON, YAML, RDF/XML |
| **CycloneDX** | OWASP | Security and DevSecOps workflows | JSON, XML, Protocol Buffers |
| **SWID** | ISO (ISO/IEC 19770-2) | Software installation, lifecycle, licensing | XML |

### CycloneDX SBOM Example

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "timestamp": "2023-12-06T12:00:00Z",
    "tools": [
      {
        "vendor": "CycloneDX",
        "name": "CycloneDX CLI",
        "version": "1.4.0"
      }
    ],
    "component": {
      "type": "application",
      "name": "Sample Project",
      "version": "1.0.0",
      "description": "A sample project to demonstrate a CycloneDX SBOM."
    }
  },
  "components": [
    {
      "type": "library",
      "name": "lodash",
      "version": "4.17.21",
      "purl": "pkg:npm/lodash@4.17.21",
      "hashes": [
        {
          "alg": "SHA-256",
          "content": "ef6c12f4ebf9e4f8e78bd4a3a7ea6bf94f37d6e907aa48e4bbd2b5c4b99f89bc"
        }
      ]
    },
    {
      "type": "library",
      "name": "express",
      "version": "4.18.2",
      "purl": "pkg:npm/express@4.18.2",
      "hashes": [
        {
          "alg": "SHA-256",
          "content": "b50f0df343b6b8d5f2a5dc9477082b4b567d8b0b514c1a9f0b8bfb4a8ebc6c9d"
        }
      ]
    }
  ],
  "dependencies": [
    {
      "ref": "pkg:npm/lodash@4.17.21",
      "dependsOn": []
    },
    {
      "ref": "pkg:npm/express@4.18.2",
      "dependsOn": []
    }
  ]
}
```

---

## Proactive Vulnerability Detection

Implement automated tools, such as **Software Composition Analysis (SCA)**, to continuously scan dependencies for known vulnerabilities. SCA tools can both generate and consume SBOMs, scanning codebases and dependency manifests (e.g., `package.json`, `pom.xml`) to catalog all direct and transitive dependencies.

### Open Source Tools

- **OWASP Dependency-Check** — Identifies known vulnerabilities in project dependencies using the National Vulnerability Database (NVD).

### Commercial Tools

Commercial tools offer features such as real-time vulnerability scanning, license compliance management, SBOM generation, CI/CD pipeline integration, and continuous monitoring of artifacts, containers, and packages.

---

## Integration with the SDLC

Integrating SBOMs and proactive vulnerability detection into the Software Development Lifecycle ensures comprehensive coverage and continuous improvement.

| Phase | Main Task | SBOM | SCA |
|---|---|---|---|
| **Planning** | Establish security policies and dependency management guidelines | Create preliminary SBOM templates for compliance tracking | Set up SCA tools and configure policies for license compliance and vulnerability thresholds |
| **Development** | Integrate security tools directly into the development environment | Generate/update SBOMs as dependencies are added or modified | Real-time feedback via IDE plugins and pre-commit hooks |
| **Build** | Automate dependency scanning during CI/CD | Generate comprehensive SBOMs capturing all direct and transitive dependencies | Run automated vulnerability scans and enforce security gates |
| **Testing** | Validate integrity and compliance of dependencies | Cross-reference SBOMs with vulnerability databases | Test for outdated components and risky transitive dependencies |
| **Deployment** | Ensure secure and compliant deployments | Include SBOMs with deployment artifacts and validate against updated databases | Run final SCA scans on production-ready artifacts |
| **Maintenance** | Monitor for emerging vulnerabilities and keep dependencies up-to-date | Regularly refresh SBOMs and cross-reference with new vulnerabilities | Continuous scanning and proactive alerts |

### Phase Details

**Planning:**
- Draft dependency management and vulnerability handling guidelines
- Configure SBOM formats to align with project requirements (e.g., CycloneDX for security workflows)
- Onboard SCA tools into the project's pipeline

**Development:**
- Integrate IDE plugins (e.g., OWASP Dependency-Check)
- Apply pre-commit hooks for dependency validation
- Generate/update SBOMs as dependencies are added
- Enforce coding standards that prevent dependency misuse

**Build:**
- Automate SBOM generation (e.g., CycloneDX or SPDX plugins in Maven or Gradle)
- Configure CI/CD pipelines to halt builds with critical vulnerabilities
- Ensure transitive dependencies are accurately cataloged

**Testing:**
- Validate SBOM completeness and check for outdated or high-risk dependencies
- Conduct vulnerability scans against known databases like NVD or OSV

**Deployment:**
- Include SBOMs with deployment packages for transparency and audits
- Validate runtime dependencies against updated vulnerability databases

**Maintenance:**
- Regularly refresh SBOMs to reflect updates
- Schedule regular audits to ensure compliance and security
- Monitor environments for new vulnerabilities using tools:
  - **Open Source:** OWASP Dependency-Track, CycloneDX CLI, Dependabot
  - **Commercial:** Sonatype Lifecycle, Black Duck, Veracode, Aikido Security

---

## Python-Specific Guidance

### Versioning

Python typically uses a version string in the format `major.minor.patch`:

- **Major** — Significant release with new features
- **Minor** — Minor updates without significant changes
- **Patch** — Bug fixes or security updates (note: some security updates may be released as a major version if they include breaking changes)

Version constraints are specified in `requirements.txt` and managed using `pip`.

Consider using **pipenv**, which uses `Pipfile` (package versions) and `Pipfile.lock` (actual installed versions with dependencies). The lock file includes package archive hashes, offering additional protection against OSS supply chain injection attacks.

### Dependency Scanning

- **pip-audit** — Sends dependency information to the Python Packaging Advisory database and reports known vulnerabilities. Use `pip-audit --fix` to automatically update vulnerable packages.
- **OWASP Dependency Check** — Scans dependencies in Python, .NET, Java, and other languages for known vulnerabilities.

---

## References & Resources

- **OWASP:**
  - [OWASP Top 10 A06:2021 – Vulnerable and Outdated Components](https://owasp.org/Top10/A06_2021-Vulnerable_and_Outdated_Components/)
  - [OWASP Cheat Sheet Series - Vulnerable Dependency Management](https://cheatsheetseries.owasp.org/cheatsheets/Vulnerable_Dependency_Management_Cheat_Sheet.html)
- **CWE:**
  - [CWE-937](https://cwe.mitre.org/data/definitions/937.html)
  - [CWE-1035](https://cwe.mitre.org/data/definitions/1035.html)
  - [CWE-1395](https://cwe.mitre.org/data/definitions/1395.html)
- [Aquasec SBOM](https://www.aquasec.com/cloud-native-academy/supply-chain-security/sbom/)
