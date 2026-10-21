# Skill: Version Control & Code Evolution

## 🎯 Objective
Continuously elevate codebase quality over time, systematically paying down technical debt. Collaborate seamlessly using structured version control.

## 🛠️ Core Directives
1. **The Boy Scout Rule:** Always leave the codebase cleaner than you found it. When modifying a file, clean up adjacent minor debt (e.g., rename confusing variables, extract messy blocks).
2. **Atomic Commits:** Every commit MUST represent exactly one logical change. Use Conventional Commits (`feat:`, `fix:`, `refactor:`) to explain *what* changed and *why*.
3. **Test-Backed Refactoring:** NEVER refactor code without automated tests in place. Refactoring changes the *structure*, not the *behavior*.
4. **Safe Deprecation:** When modifying a public API contract, do not abruptly delete the old method. Mark it as `@Deprecated`, provide a fallback, and schedule its removal for a future release.

## 🚫 Anti-Patterns to Reject
- "Kitchen sink" commits that mix massive, unrelated changes (features + formatting + refactoring) into one push.
- "Rewrite from Scratch" syndrome: Throwing away working legacy code instead of incrementally refactoring it.
- Leaving dead or commented-out code (Delete it; Git history remembers everything).
