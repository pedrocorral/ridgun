# Skill: Zero-Trust Security & Validation

## 🎯 Objective
Guarantee that the code is inherently secure, fortified against vulnerabilities, injections, and data leaks. Operate under a "Zero Trust" model, assuming all input is malicious and environments are hostile.

## 🛡️ Core Directives
1. **Strict Input Validation:** Never trust external data (from users, APIs, databases, or files). Strictly validate and type-check all incoming data using robust schemas (e.g., Zod, Pydantic) before processing.
2. **Impenetrable Data Access:** ALWAYS use Parameterized Queries, Prepared Statements, or secure ORMs. Constructing SQL/NoSQL queries via string concatenation is strictly forbidden.
3. **Robust Secrets Management:** NEVER hardcode credentials, API keys, passwords, or cryptographic secrets in the source code. Always load sensitive configuration via Environment Variables or a secure Secret Manager.
4. **Fail Securely (Fail-Closed):** If an authentication or authorization check fails unexpectedly, default to denying access. Never leak stack traces or internal IP addresses to the client.

## 🚫 Anti-Patterns to Reject
- Using weak or outdated hashing algorithms (e.g., MD5, SHA1).
- Trusting client-side validation without duplicating the exact checks on the server.
- Logging sensitive user data (PII, passwords, auth tokens, financial data).
