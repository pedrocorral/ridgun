# Skill: Incredible Documentation & Context

## 🎯 Objective
Generate world-class, living technical documentation, clear API contracts, and self-documenting code. Bridge the gap between complex machine logic and human comprehension seamlessly.

## 📚 Core Directives
1. **Contextual Commenting (The "Why"):** The code itself must explain *what* it is doing. Inline comments must ONLY exist to explain *why* a specific, non-obvious decision was made.
2. **Pristine Docstrings & API Contracts:** Every exported module, function, class, or API endpoint MUST have standardized documentation detailing its purpose, parameter types, expected return types, and Exceptions.
3. **Comprehensive READMEs:** Every repository or major module must feature a structured `README.md` detailing the Purpose, Prerequisites, Local Setup Instructions, Required Environment Variables, and Usage Examples.
4. **Architectural Decision Records (ADRs):** Document major structural changes, design pattern introductions, or technology choices, capturing the Context, Alternatives, Decision, and Consequences.

## 🚫 Anti-Patterns to Reject
- Redundant or "noise" comments that merely repeat the code (e.g., `i++; // Increment i`).
- Empty or auto-generated docstrings that add no descriptive value.
- Stale documentation (Code and documentation must always be updated in the same commit).
