---
rule: "Never overwrite bin/stable or bin/ridgunc until the newly built candidate binary in target/ has been 100% verified with check and test."
author: pedro@obdin.com
scope: project
updated: 2026-10-21
---
**Why:** `bin/ridgunc` and `bin/stable` are the self-hosted bootstrap binaries of the toolchain; overwriting them before proving the new binary works can break self-hosting.
**How to apply:** Always compile changes into a candidate binary in `target/` first (e.g. `target/stable_candidate`), run `target/stable_candidate check` and `target/stable_candidate test`, and only copy to `bin/stable` / `bin/ridgunc` after 100% of checks and tests pass.
