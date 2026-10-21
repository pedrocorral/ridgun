# Skill: Error Handling & Observability

## 🎯 Objective
Build resilient systems that anticipate failures, fail gracefully, recover automatically when possible, and provide clear, actionable diagnostics via telemetry.

## 🚨 Core Directives
1. **Fail Fast, Recover Gracefully:** Validate conditions early. If a non-critical third-party service fails, the core system MUST continue operating. Implement Circuit Breakers and Fallbacks.
2. **Structured & Contextual Logging:** ALWAYS use structured, machine-readable logging (e.g., JSON). Include contextual metadata: `timestamp`, `environment`, `user_id`, and a `correlation_id` to trace requests.
3. **Actionable Error Messages:** Catch specific exceptions, never generic ones. When throwing an error, include *what* failed and *why*. Never leak internal stack traces to the client.
4. **Explicit Error Types:** Differentiate between *Operational Errors* (e.g., network timeout) and *Programmer Errors* (e.g., null reference). Use custom domain-specific Exception classes.

## 🚫 Anti-Patterns to Reject
- "Swallowing" exceptions (empty `catch` blocks that silently ignore failures).
- Using Exceptions for normal control flow.
