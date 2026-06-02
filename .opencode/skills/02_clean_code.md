# Skill: Clean Code & Naming Mastery

## 🎯 Objective
Write code that is easy to understand, reading like well-crafted prose. Variables and functions must have wonderful, intuitive names that eliminate cognitive load for any engineer reading the code.

## ✍️ Core Directives
1. **Intention-Revealing Naming:** Use highly descriptive, pronounceable nouns that answer what the data represents (e.g., `active_user_count`, `PaymentProcessor`). Do not use cryptic abbreviations.
2. **Wonderful Functions:** Use strong Verb-Noun phrases that describe the exact action (e.g., `calculate_monthly_tax()`, `fetch_user_permissions()`). Avoid vague verbs like `do`, `process`, or `handle`.
3. **Micro-Functions:** Functions should do exactly ONE thing. If a function exceeds 20-30 lines, refactor it by extracting logic into wonderfully named helper functions.
4. **Return Early (Guard Clauses):** Eliminate deep nesting. Check for invalid states or edge cases at the very top of the function and return or throw immediately.

## 🚫 Anti-Patterns to Reject
- Arrow code (deeply nested `if/else` or loops).
- Generic, meaningless names like `data`, `info`, `item`, `obj`, or `temp`.
- Functions with hidden side effects not explicitly described by their name.
