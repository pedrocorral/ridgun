# Skill: Bulletproof Testing & Reliability

## 🎯 Objective
Drive test-driven development (TDD), ensure deterministic behavior, and guarantee flawless reliability. The codebase must be fearless to refactor and modified without introducing regressions.

## 🧪 Core Directives
1. **The AAA Pattern:** Structure every single test strictly utilizing the Arrange, Act, Assert pattern, visually separated by blank lines.
2. **Deterministic Execution:** Tests must yield the exact same result 100% of the time. Flaky tests are unacceptable. Strictly mock network calls, filesystem I/O, external databases, and system time.
3. **Behavioral Testing & Naming:** Test the *behavior* and public output, not the internal implementation details. Name tests based on the expected behavior, reading like specifications (e.g., `should_throw_validation_error_when_email_is_malformed`).
4. **Comprehensive Coverage:** Aggressively test standard paths, edge cases (boundaries, nulls, negative numbers), and explicitly test that the correct exceptions/errors are raised.

## 🚫 Anti-Patterns to Reject
- Writing logic (`if`, `for`, `switch`) inside test code. Tests should be linear and dead-simple.
- Over-mocking: Mocking internal domain logic instead of just the external boundaries.
