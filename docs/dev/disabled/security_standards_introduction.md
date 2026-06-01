# Introduction to Security Standards

> **Status: DISABLED** — This document is archived for future reference. Detailed compliance planning is out of scope for the current development phase.

---

## Introduction

In today's digital age, the importance of security cannot be overstated. From protecting personal data to ensuring the integrity of financial transactions, security policies, laws, and regulations play an important role in securing information by setting the framework for how organizations should protect their data. To translate these regulatory controls into actionable measures, standards are developed that provide detailed guidelines and best practices for achieving and maintaining compliance.

---

## Overview

| Aspect | Standards | Frameworks | Policy | Law | Regulation |
|---|---|---|---|---|---|
| **Purpose** | Risk mitigation, quality assurance, interoperability | Guidance | Internal rules | Compliance | Industry standards, consumer protection |
| **Mandatory** | Voluntary (sometimes required) | Voluntary | Usually mandatory | Mandatory | Mandatory |
| **Scope** | Wide range | Specific domains | Organization-wide | Varies by jurisdiction | Varies by sector |
| **Flexibility** | Flexible | Customizable | Moderately flexible | Rigid | Rigid |
| **Development** | Recognized bodies | Industry groups, agencies | Internal committees | Government bodies | Government bodies |
| **Enforcement** | Contracts, certifications | Performance benchmark | Internal reviews | Legal enforcement | Regulatory bodies |

Each component plays a role in making sure that security measures are well-defined, implemented, and maintained.

### How They Work Together

```
Policy, Law, or Regulation
│   "Why do we need to do this?"
│   High-level commitment to security; answers why security measures are necessary.
│
▼
Standard
│   "What is required to achieve it?"
│   Detailed requirements derived from policies/laws; specifies what must be met.
│   Ensures consistent and effective security controls.
│
▼
Framework or Procedure
│   "How do we do what is required?"
│   Step-by-step instructions on how to implement standards.
│   Detailed guidance on performing specific tasks.
│
▼
Technical Controls
    "How do we regulate necessary operations?"
    Specific technologies and configurations: firewalls, encryption, access controls,
    monitoring systems. Automates and regulates security operations.
```

### Analogy

Imagine hosting a dinner party:

- **Policy** — "Everyone should have a great time and enjoy a delicious meal."
- **Standard** — "The meal must include a main course, a dessert, and be prepared with fresh ingredients."
- **Framework** — "Prepare the main course following a recipe for roast chicken, and the dessert using a chocolate cake recipe."
- **Controls** — "Preheat the oven to 190°C (375°F), use a meat thermometer to ensure the chicken reaches 75°C (165°F), and marinate for 2 hours."

---

## Key Security Laws

### HIPAA (Health Insurance Portability and Accountability Act)

U.S. law designed to protect sensitive patient health information. Sets national standards for the security and privacy of health data, ensuring healthcare providers, insurers, and other entities handle patient information securely. Contains resources on data handling and breach response.

---

## Key Regulations

### GDPR (General Data Protection Regulation)

EU data protection regulation mandating strict guidelines for handling and protection of personal data of EU citizens. Gives individuals significant control over their personal information and imposes severe penalties for non-compliance.

---

## Key Standards

### PCI DSS (Payment Card Industry Data Security Standard)

Security standard ensuring all companies that process, store, or transmit credit card information maintain a secure environment. Vital for preventing credit card fraud and ensuring payment card transaction safety.

### ISO/IEC 27000 Series (Information Security Management System)

International standard for managing information security. Provides a systematic approach to managing sensitive company information, ensuring confidentiality, integrity, and availability (CIA triad). The ISO 27000 series has 60 standards covering a broad spectrum of information security issues.

---

## Key Frameworks

### OWASP (Open Web Application Security Project)

Globally recognized organization focused on improving software security. Provides free resources including:

**Standards (Top 10):**
- Web
- API
- Mobile
- LLM
- Embedded

**Checklists and verification frameworks:**
- ASVS (Application Security Verification Standard)
- MASVS (Mobile Application Security Verification Standard)
- Cheatsheets

### NIST Cybersecurity Framework

Policy framework of computer security guidance for how organizations can assess and improve their ability to prevent, detect, and respond to cyber-attacks. Widely used across industries.

### CIS Controls (Center for Internet Security)

A set of 18 key actions that organizations should implement to block or mitigate known attacks. Initially developed by the SANS Institute as the "SANS Top 20," later transferred to the Council on Cyber Security (CCS).

---

## Practical Example

A healthcare company must comply with **HIPAA** law, focusing on data protection at rest:

| Layer | Component | Application |
|---|---|---|
| **Law** | HIPAA | Mandates protection of electronic protected health information (ePHI) at rest |
| **Standard** | ISO/IEC 27001 | Establishes ISMS: risk assessment for data at rest, cryptographic controls (AES-256) |
| **Framework** | OWASP ASVS | V6 Stored Cryptography, V8 Data Protection |
| **Framework** | OWASP Top Ten | A02:2021 – Cryptographic Failures |

---

## Summary Table

| Framework | Purpose | Industry | Type |
|---|---|---|---|
| COBIT | IT management and governance | General | Framework |
| CIS Controls | Best practices for cybersecurity | General | Framework |
| CMMI Cybermaturity Platform | Assess and improve cybersecurity maturity | General | Framework |
| CSA CCM | Security controls for cloud services | Cloud Services | Framework |
| Cyber Essentials | Basic measures to protect against cyber threats | General | Standard |
| FISMA | Security standards for federal information systems | Government | Law |
| GDPR | Data protection and privacy for EU citizens | General | Regulation |
| HIPAA | Protects patient health information | Healthcare | Law |
| HITRUST CSF | Comprehensive security and privacy framework | Healthcare | Framework |
| IAB CCPA | Privacy guidelines for California residents | General | Regulation |
| ISO 27001 | Information security management system | General | Standard |
| ISO/IEC 27017 | Information security controls for cloud services | Cloud Services | Standard |
| ISO/IEC 27018 | Protection of PII in public clouds | Cloud Services | Standard |
| ISO/IEC 27019 | Information security for process control in energy | Energy | Standard |
| ISO/IEC 27040 | Information on storage security | General | Standard |
| ISO/IEC 27799 | Information security management in healthcare | Healthcare | Standard |
| NERC-CIP | Protecting critical infrastructure in energy sector | Energy | Standard |
| NIST Cybersecurity Framework | Cybersecurity risk management and control | General | Framework |
| NIST SP 800-53 | Security controls for federal information systems | Government | Framework |
| NIST SP 800-171 | Protecting controlled unclassified information | Government/Defense | Framework |
| OWASP | Improving software security | Software | Framework |
| PCI DSS | Secure handling of credit card information | Finance | Standard |
| SOC 1 | Internal controls over financial reporting | Finance | Standard |
| SOC 2 | Data security, availability, and privacy controls | General | Standard |

---

## References & Resources

- [OWASP](https://owasp.org/)
- [ISO](https://www.iso.org/)
- [NIST](https://www.nist.gov/)
- [PCI Security Standards Council](https://www.pcisecuritystandards.org/)
- [HHS (U.S. Department of Health & Human Services)](https://www.hhs.gov/)
- [Wikipedia: Information Security Standards](https://en.wikipedia.org/wiki/Information_security_standards)
- [Standard vs Framework vs Laws vs Regulations](https://www.complianceforge.com/)
