---
rule: "Always use natural spaces instead of underscores in Ridgun function names, built-in calls, and tuple/sequence type signatures."
author: pedro@obdin.com
scope: project
updated: 2026-10-22
---
**Why:** On 2026-10-22, the user noted that code examples and tests still used `_`-joined function names (`aplicar_descuento`, `str_len`) instead of natural spaces.
**How to apply:** Whenever writing Ridgun code, tests, documentation, or book examples, write multi-word `fn ::` declarations and calls with natural spaces (`fn :: format app err AppErr => String`, `assert equals`, `str len`, `read file`) and space-separated tuple/sequence type signatures (`=> Int Int [String String] String`, `[String String]`, `(A B)`).
