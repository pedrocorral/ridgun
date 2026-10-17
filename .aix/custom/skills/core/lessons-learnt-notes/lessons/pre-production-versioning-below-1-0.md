---
rule: "Keep project and tool versions below 1.0.0 (currently 0.9.0) until explicitly ready for production; never bump major versions speculatively."
author: pedro@obdin.com
scope: project
updated: 2026-10-17
---
**Why:** On 2026-10-17, the agent labeled `ridgunc` and `stable` as version `2.0.0` before the project had reached production readiness (`1.0.0`).
**How to apply:** Use `0.9.0` (or the current pre-1.0 version in `build.rg` and `Cargo.toml`) for all tools, banners, and manifests, and only advance to `1.0.0` when the user explicitly declares a production release.
