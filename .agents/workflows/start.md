---
description: Initialize context by reading project guidelines and key files
---

1. Read the project guidelines:
// turbo
```
cat /home/uzul/boogie/ridgun/doc/agents.md
```

2. Read the language spec for current syntax reference:
// turbo
```
cat /home/uzul/boogie/ridgun/doc/lang/spec.md
```

3. Read the samples for current code style:
// turbo
```
cat /home/uzul/boogie/ridgun/doc/lang/samples.rg
```

4. **🔴 ABSOLUTE RULE — All `.rg` files must be 100% functional.** Every `.rg` file in the project — tests, samples, examples — MUST compile and run successfully via `ridgun <file.rg>`. No aspirational syntax. No spec-only documentation disguised as code. If the compiler cannot handle a feature, the `.rg` files MUST NOT use it. When adding new language features, implement them in the compiler FIRST, then add `.rg` files that use them.

5. **Cross-reference rule:** Whenever a language change is introduced — whether in samples, spec, or requested in a prompt — you MUST update ALL affected files to maintain consistency:
   - `doc/lang/spec.md` — language specification
   - `doc/lang/samples.rg` — code samples
   - `editors/vscode/syntaxes/ridgun.tmLanguage.json` — syntax highlighting
   - `src/test/ridgun/` — test files
   - `README.md` — if it documents syntax
   - `src/main/rust/` — lexer, parser, compiler (if implemented)
   Never leave a language feature inconsistent across these files.

5. **Terminal execution rule:** Always use short synchronous waits (`WaitMsBeforeAsync` ≤ 5000ms). When checking background command status, use `WaitDurationSeconds: 0` — never block with long async polling. If a command completes within the sync window, read output immediately.

6. **After every code change**, always rebuild and install the binary:
// turbo
```
touch src/main/rust/main.rs && cargo build --release 2>&1 | tail -3 && cp target/release/ridgun ~/.cargo/bin/ridgun
```

7. Confirm you are ready and summarize the current state of the project.
