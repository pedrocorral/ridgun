---
rule: "Always pass -c user.name='Pedro Corral' and -c user.email='pedro@obdin.com' on every git commit command."
author: pedro@obdin.com
scope: project
updated: 2026-10-17
---
**Why:** On 2026-10-17, running `git commit --author="Pedro Corral <pedro@obdin.com>"` failed with `Committer identity unknown` because git also requires committer `user.name` and `user.email`.
**How to apply:** Whenever running `git commit` in this repository, always include `-c user.name="Pedro Corral" -c user.email="pedro@obdin.com"` so both author and committer match the project owner.
