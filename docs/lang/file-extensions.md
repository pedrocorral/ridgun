# File extensions: `.ridgun` and `.ridgunlib`

Since 1.0.10, Ridgun files use the language's name as their extension (ADR-0010):

| File | Name since 1.0.10 | Name before 1.0.10 |
|---|---|---|
| Source file | `main.ridgun` | `main.rg` |
| Project definition | `build.ridgun` | `build.rg` |
| `stable` plugin | `plugins/deploy.ridgun` | `plugins/deploy.rg` |
| Library bundle | `json.ridgunlib` | `json.rglib` |
| Checked-source copy | removed | `main.rgc` |

**Why:** the Rogue language already uses `.rg`. With `.ridgun`, editors, GitHub and searches recognise Ridgun files as Ridgun.

## The old names still work

`ridgunc` and `stable` read both names. In each place they look, the new name comes first, then the old one. A project that still has `.rg` files builds as before, and you can rename it whenever you want.

- An import with a file name finds the file under either name: `import "io.rglib"` reads `io.ridgunlib`.
- New files always get the new names. This covers `stable new`, `stable init`, and `ridgunc build --lib` without `-o`.
- The editor modes in `editors/` (VS Code, gedit, Emacs) open both names.

## What was removed

- **`ridgunc compile` and `stable compile`.** The `.rgc` file they wrote was the checked source with a header line, and nothing read it. To check a file, use `ridgunc check`. To check a project, use `stable check`.
- **The bytecode VM demo.** `ridgunc` with no arguments used to evaluate a built-in sample on it. Now it prints its help.

## Renaming a project

In a git repository, `git mv` keeps each file's history:

```bash
git ls-files -z '*.rg' | while IFS= read -r -d '' f; do git mv "$f" "${f%.rg}.ridgun"; done
git ls-files -z '*.rglib' | while IFS= read -r -d '' f; do git mv "$f" "${f%.rglib}.ridgunlib"; done
```

Then:

1. **Update the text that names files:**
   - shell scripts and `fn :: task` commands in `build.ridgun` (`… main.rg`, `*.rglib`);
   - `main entry` and other paths in `build.ridgun`;
   - documentation.
2. **Don't rename the copies.** Leave `.stable/deps` and `target/` alone; run `stable deps` and `stable build` to regenerate them.
3. **Build and test:** `stable build` and `stable test`.

`import` lines name modules, not files (`import json`), so they don't change. An import with an explicit file name (`import "io.rglib"`) keeps working; change it to the new name when convenient.
