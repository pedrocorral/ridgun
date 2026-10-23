---
rule: "Never touch ~/.local/bin/ symlinks or overwrite bin/ridgunc and bin/stable until the candidate binary in target/ is 100% verified and fast."
author: pedro@obdin.com
scope: project
updated: 2026-10-23
---
**Why:** `~/.local/bin/ridgunc` and `~/.local/bin/stable` are symlinks to `bin/`, and on 2026-10-23 overwriting `bin/ridgunc` before verifying external `.stable/deps/` imports broke downstream projects.
**How to apply:** Never modify `~/.local/bin/` directly. Build candidates in `target/` (`target/ridgunc_candidate`, `target/stable_candidate`), verify speed and tests in `target/`, and only copy to `bin/` (`cp -f --remove-destination`) once 100% verified.
