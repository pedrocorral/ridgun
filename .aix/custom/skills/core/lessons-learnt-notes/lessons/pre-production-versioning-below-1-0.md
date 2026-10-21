---
rule: "Increment the patch version (+0.0.1, keeping below 1.0.0) in build.rg, ridgunc, and stable whenever ridgunc or stable changes."
author: pedro@obdin.com
scope: project
updated: 2026-10-21
---
**Why:** On 2026-10-17 the agent bumped to `2.0.0` prematurely, and on 2026-10-21 the user reminded to increment `+0.0.1` whenever `ridgunc` or `stable` changes.
**How to apply:** Bump the patch version by `+0.0.1` (staying `< 1.0.0`, e.g. `0.9.3` -> `0.9.4` -> `0.9.5`) in `build.rg`, `ridgunc/main.rg`, `stable/main.rg`, `README.md`, and `harness/` on every compiler/tooling change; only bump to `1.0.0` on explicit production release.
