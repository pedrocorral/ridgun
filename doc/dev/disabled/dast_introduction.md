# Introduction to DAST

> **Status: DISABLED** — This document is archived for future reference. DAST is out of scope for the current development phase. It becomes relevant once Ridgun has networked services, APIs, or web-facing components.

---

## Introduction

Dynamic Application Security Testing (DAST) is a security testing methodology that analyzes a **running application** to identify vulnerabilities by interacting with it in real-time. DAST performs **black-box testing**, simulating an attacker interacting with the application without prior knowledge of its internal structure.

DAST is commonly associated with web applications, APIs, and cloud services, as it evaluates how an application behaves during execution. By focusing on real-world attack scenarios, DAST helps organizations detect vulnerabilities before deployment or in production environments.

---

## How DAST Works

DAST tools work by sending requests to a running application and analyzing its responses for signs of security vulnerabilities. This approach allows detection of runtime security issues such as authentication flaws, insecure configurations, and injection attacks. DAST does not require access to the source code, making it suitable for testing third-party applications, APIs, and microservices.

These tools face challenges with detection accuracy, often leading to:

- **False positives** — Incorrectly flagged vulnerabilities due to misinterpreted responses, inability to recognize external security controls (like Web Application Firewalls), or inconsistent application behavior during testing.
- **False negatives** — Missed vulnerabilities because DAST can only test exposed functionality, cannot see code paths not executed during testing, and has limited visibility into internal components or backend processes.

To improve accuracy, modern tools employ various techniques including authentication handling, session management, and multiple attack vectors to test different aspects of application security.

### Analysis Techniques

| Technique | Description |
|---|---|
| **Fuzzing** | Sends unexpected, malformed, or random inputs to an application |
| **Crawling & Spidering** | Maps out the application's structure by navigating links and forms |
| **Injection Testing** | Detects SQL injection, command injection, and other input-based vulnerabilities by sending malicious payloads |
| **Authentication & Session Testing** | Analyzes how authentication and session management mechanisms handle different login scenarios |
| **Error & Response Analysis** | Examines HTTP responses, headers, and error messages for sensitive information disclosure |
| **Client-Side Security Testing** | Evaluates vulnerabilities like DOM-based XSS and insecure JavaScript functions |
| **API Security Testing** | Scans APIs (REST, SOAP, GraphQL) for authentication flaws, improper rate limiting, and data leakage |

Some DAST tools are starting to leverage AI and machine learning, particularly for smarter testing and anomaly detection, but the technology is still evolving.

---

## Selecting a DAST Tool

### Open-Source Tools

| Tool | Description |
|---|---|
| **ZAP by Checkmarx** | OWASP's widely-used DAST tool, now backed by Checkmarx while remaining open source |
| **w3af** | Modular security scanner with an extendable plugin architecture |
| **Arachni** | High-performance, Ruby-based security scanner for modern web applications |
| **Wapiti** | CLI-based DAST tool that supports SOAP and JSON-based API scanning |
| **Skipfish** | Fast, lightweight web application scanner optimized for high-speed testing |
| **Nuclei** | Fast and customizable vulnerability scanner based on simple YAML-based DSL |
| **Vega** | Open source platform to test the security of web applications |
| **AFL++** | Advanced fuzzing tool that uses genetic algorithms to find crashes and potential vulnerabilities |
| **Valgrind** | Memory debugging framework that detects memory-related errors such as leaks, use-after-free, and buffer overflows through runtime analysis |

### Commercial Tools

| Tool | Description |
|---|---|
| **OpenText Fortify** | Enterprise DAST solution with comprehensive vulnerability detection and CI/CD integration |
| **Burp Suite Professional** | Leading tool for manual and automated security testing with advanced scanning |
| **Acunetix** | Automated scanner with DeepScan technology, ideal for JavaScript-heavy applications |
| **Invicti** (formerly Netsparker) | DAST solution with proof-based scanning to minimize false positives |
| **Rapid7 InsightAppSec** | Cloud-based DAST with attack template customization and dynamic risk scoring |
| **Qualys WAS** | Cloud-based scanner with continuous security monitoring |
| **Tenable Web App Scanning** | Web vulnerability scanner integrating with broader enterprise security |
| **Detectify** | Web vulnerability scanner with crowd-sourced security research |
| **StackHawk** | Developer-focused DAST designed for CI/CD integration |
| **Contrast Security** | DAST capabilities alongside other application security testing options |
| **ImmuniWeb** | AI-based web security testing platform |

### Selection Criteria

| Criterion | Consideration |
|---|---|
| **Application compatibility** | Support for modern frameworks, SPAs, and APIs (REST, SOAP, GraphQL) |
| **Authentication & session management** | Ability to test authenticated areas (OAuth, JWT, MFA) |
| **Accuracy & false positive reduction** | AI/ML-based validation of exploitable vulnerabilities |
| **DevSecOps integration** | CI/CD integration for automated testing in build pipelines |
| **Compliance & reporting** | Required for PCI-DSS, GDPR, HIPAA |

---

## Interpreting DAST Results

### Severity Levels

| Severity | Definition |
|---|---|
| **Critical** | Directly exploitable issues (e.g., remote code execution, authentication bypass) |
| **High** | Injection flaws, misconfigurations, or data leaks |
| **Medium** | Security weaknesses requiring specific conditions to exploit |
| **Low** | Minor misconfigurations or best-practice violations |

### Report Components

A well-structured DAST report includes:

- **URL/Endpoint** — The specific application endpoint where the vulnerability was detected
- **HTTP Request/Response** — The exact request that triggered the vulnerability and the application's response
- **Vulnerability type** — Category of risk (e.g., XSS, SQL Injection, CSRF)
- **Exploitability details** — Description of how the flaw could be abused
- **Proof of concept** — Evidence demonstrating the vulnerability, including the specific payload used
- **Remediation guidance** — Suggested fixes and security best practices
- **CWE/OWASP reference** — Common Weakness Enumeration ID or OWASP Top 10 category
- **Confidence level** — High (real vulnerability), Medium (requires verification), Low (potentially misleading)
- **Session details** — Information about the authenticated session used during testing

### Output Formats

| Format | Use Case |
|---|---|
| **HTML/PDF** | Human-readable reports for stakeholder review and documentation |
| **JSON** | Automation and API integrations; structured parsing by security tools and CI/CD pipelines |
| **CSV** | Manual review and spreadsheet-based analysis |
| **XML** | Structured data exchange and compliance reporting |

### Sample ZAP JSON Output

```json
{
   "@version": "Dev Build",
   "@generated": "Fri, 4 Feb 2022 13:04:51",
   "site": [
       {
           "@name": "http://localhost:8080",
           "@host": "localhost",
           "@port": "8080",
           "@ssl": "false",
           "alerts": [
               {
                   "pluginid": "40012",
                   "alertRef": "40012",
                   "alert": "Cross Site Scripting (Reflected)",
                   "name": "Cross Site Scripting (Reflected)",
                   "riskcode": "3",
                   "confidence": "2",
                   "riskdesc": "High (Medium)",
                   "desc": "<p>Cross-site Scripting (XSS) is an attack technique...</p>",
                   "instances": [
                       {
                           "uri": "http://localhost:8080/bodgeit/search.jsp?q=...",
                           "method": "GET",
                           "param": "q",
                           "attack": "</font><scrIpt>alert(1);</scRipt><font>",
                           "evidence": "</font><scrIpt>alert(1);</scRipt><font>"
                       },
                       {
                           "uri": "http://localhost:8080/bodgeit/contact.jsp",
                           "method": "POST",
                           "param": "comments",
                           "attack": "</td><scrIpt>alert(1);</scRipt><td>",
                           "evidence": "</td><scrIpt>alert(1);</scRipt><td>"
                       }
                   ],
                   "count": "2",
                   "solution": "<p>Use a vetted library or framework...</p>",
                   "cweid": "79",
                   "wascid": "8",
                   "sourceid": "36977"
               }
           ]
       }
   ]
}
```

The security scan detected a **Reflected Cross-Site Scripting (XSS)** vulnerability in two endpoints:

1. `search.jsp` (GET, parameter: `q`) — Improperly handles user input, allowing `<script>` tag injection
2. `contact.jsp` (POST, parameter: `comments`) — Accepts and reflects malicious payloads

---

## Prioritizing Vulnerabilities

### Key Factors

1. **Assess exploitability and attack complexity**
   - Is the vulnerability actively exploitable with existing proof of concept?
   - What authentication level and prerequisites are required?
   - Are existing security controls (WAF) mitigating the risk?
   - Are specialized tools or public exploits available?

2. **Evaluate business impact**
   - Does it affect critical functionality or expose sensitive data?
   - Could exploitation lead to data breaches, privilege escalation, or financial loss?
   - Is it isolated to one environment or present across multiple systems?

3. **Factor in environment context**
   - Production vs testing environment?
   - Can the issue be mitigated at multiple layers (app code, config, infrastructure)?
   - Is emergency mitigation (WAF rules) needed while permanent fixes are developed?

4. **Compliance requirements**
   - GDPR, PCI-DSS, HIPAA may mandate fixing certain vulnerabilities
   - OWASP Top 10 helps prioritize common web vulnerabilities

5. **Remediation deadlines**
   - Critical: 7 days
   - High: 30 days
   - Medium: 60 days
   - Low: Addressed as needed
   - Track and escalate overdue vulnerabilities

---

## Integrating DAST into the SDLC

DAST typically fits in the later stages of the SDLC, particularly during Test and Release phases.

### Plan

**Pitfalls:**
- DAST requirements (environments, authentication workflows) not defined during planning
- Security standards for runtime testing overlooked
- Tool selection delayed until testing phases

**Recommendations:**
- Select DAST tools aligned with the application's tech stack
- Define scanning scope (staging vs. production) and compliance needs
- Plan for authentication workflows (OAuth, JWT)
- Allocate time for scan configuration and false-positive triage

### Code

**Pitfalls:**
- No DAST involvement, but failure to design testable authentication/API endpoints creates roadblocks later

**Recommendations:**
- Use Swagger/OpenAPI documentation to guide DAST scan configurations later

### Build

**Pitfalls:**
- DAST scans delayed until post-deployment
- Pre-production environments not provisioned for DAST testing
- No CI/CD pipeline integration

**Recommendations:**
- Deploy builds to a staging environment that mirrors production
- Integrate lightweight DAST scans into CI/CD

### Test

**Pitfalls:**
- Scans limited to surface-level vulnerabilities, ignoring business logic flaws
- Lack of coverage for modern APIs (GraphQL, WebSockets) or SPAs
- False positives overwhelm teams

**Recommendations:**
- Run full DAST scans in staging, covering authenticated and unauthenticated paths
- Combine DAST with manual penetration testing
- Tune DAST rules to reduce noise

### Release

**Pitfalls:**
- DAST results not reviewed before deployment
- No security gates blocking releases with unpatched flaws
- Compliance reports lack DAST data

**Recommendations:**
- Enforce security gates blocking releases with critical findings
- Generate compliance-ready reports (PDF/SARIF)

### Deploy, Operate, and Monitor

**Pitfalls:**
- DAST scans stop post-deployment
- Third-party APIs and microservices excluded from scans
- No process to retest fixed vulnerabilities

**Recommendations:**
- Schedule regular DAST scans in production (weekly/monthly)
- Integrate DAST with SIEM tools for real-time alerts
- Retest fixed issues to confirm remediation

---

## Conclusion

DAST is an important component of application security testing, offering an external perspective on vulnerabilities, but its value depends on strategic implementation, proper timing, and continuous refinement.

### Key Takeaways

1. **Real-world perspective matters.** DAST identifies vulnerabilities as they exist in the running application, catching issues that static analysis might miss.
2. **Configuration is crucial.** Proper scan coverage, authentication handling, and environment setup determine DAST effectiveness.
3. **DAST alone is not enough.** Combine with SAST, IAST, and SCA for comprehensive coverage.

### Strategies for Improvement

- **Shift left where possible** — Lightweight DAST scans in CI/CD alongside comprehensive scans in staging
- **Enhance discovery and coverage** — Use API documentation to improve scan coverage
- **Track meaningful metrics** — Vulnerability detection rates, time-to-remediation, attack surface coverage
- **Automate** — Balance scan depth with speed at different pipeline stages
- **Continuous improvement** — Regularly update scan profiles, authentication methods, and tool configurations

---

## References & Resources

- [OWASP: Vulnerability Scanning Tools](https://owasp.org/www-community/Vulnerability_Scanning_Tools)
- [GitHub: Dynamic Application Security Testing (DAST)](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning)
- [GitLab: Dynamic Application Security Testing (DAST)](https://docs.gitlab.com/ee/user/application_security/dast/)
