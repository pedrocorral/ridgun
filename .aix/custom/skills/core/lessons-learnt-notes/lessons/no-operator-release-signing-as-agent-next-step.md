---
rule: "Never list operator-only release signing or deployment actions as agent next steps; report Next step: None when agent work is complete."
author: pedro@obdin.com
scope: project
updated: 2026-11-06
---
**Why:** On 2026-11-06, the task report listed release signing (`sign sums`) and deployment to `public/downloads/` under `Next step`, which are strictly operator-owned actions performed by the user with offline keys.
**How to apply:** When all coding, testing, packaging, and documentation tasks assigned to the agent are complete, report `Next step: None` in the task report and never propose or queue operator signing, key handling, or production publishing as an agent next step.
