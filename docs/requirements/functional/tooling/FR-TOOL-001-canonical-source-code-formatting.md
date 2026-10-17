---
id: FR-TOOL-001
title: Canonical aesthetic source code formatting (stable format)
type: functional
status: implemented
priority: must
domain: TOOL
depends_on: []
related: []
tests: []
---
# FR-TOOL-001 — Canonical aesthetic source code formatting (`stable format`)

## Statement
The `stable` build tool SHALL provide a `format` command (`stable format [path...]` and interactive `stable> format [path...]`) that formats Ridgun (`.rg`) source files according to the canonical signature-aligned layout rules defined in `ridgun-mode.el`, purely as an aesthetic tooling transformation without making column alignment a compiler requirement.

## Rationale
Ridgun's column-aligned signatures (`fn ::` / `op ::`), pattern clauses, and `where` bindings make mathematical and natural-language definitions immediately scannable. Providing a deterministic, self-hosted `stable format` command ensures uniform code aesthetics across editors and CI without coupling the `ridgunc` parser/compiler to whitespace alignment rules.

## Canonical Formatting Specification

> **Non-normative for Compilation**: The `ridgunc` lexer and parser are whitespace-agnostic within a line. Unformatted and formatted `.rg` files are semantically identical and both compile without error or warning.

### 1. Alignment Group Boundaries
- Each `fn :: ...` or `op :: ...` declaration starts an **alignment group** extending through its definition clauses and `where` bindings until the next top-level declaration (`fn`, `op`, `type`, `import`, `global`, `context`, `shared`, `hardware`, or `@`).
- Atomic LHS tokens are scanned left-to-right, treating quoted strings (`"..."`, `'...'`), bracketed lists/types (`[...]`), and parenthesized patterns/types (`(...)`, `Tensor(...)`) as indivisible tokens.

### 2. LHS Column Geometry (Base Column = 6)
- Both `fn :: ` and `op :: ` occupy 6 characters, placing token $0$ of the signature LHS at column $C_0 = 6$.
- Let $N$ be the number of LHS tokens before `=>` / `->` in the signature.
- For each column index $i \in [0, N-1]$, the column width $W_i$ is initialized to $\text{len}(\text{sig\_tok}_i)$ and expanded across matching definition clauses **only for clause pattern tokens with $\text{len}(\text{clause\_tok}_i) \le 18$**:
  $$W_i = \max\left(\text{len}(\text{sig\_tok}_i),\; \max_{\substack{\text{clause} \\ \text{len}(\text{clause\_tok}_i) \le 18}} \text{len}(\text{clause\_tok}_i)\right)$$
- Input patterns wider than `18` characters (such as deep nested ADT deconstructions) are treated as **outliers**: they do not stretch $W_i$ for the signature or the remaining clauses, and simply overflow on their own line with a single space (`" "`) before the next token.
- The starting column $C_i$ for token $i$ is:
  $$C_0 = 6, \qquad C_i = C_{i-1} + W_{i-1} + 1 \quad (i \ge 1)$$
- Matching definition clauses start at column $C_0 = 6$ (aligned directly beneath the first token after `fn :: ` / `op :: `), with each argument pattern $i$ placed at column $C_i$.

### 3. Vertical Alignment of `=>`, `=`, and `->`
- For any `where` binding `<lhs> -> <rhs>` inside the group, its base indentation is $I_{\text{where}} = 6 + 2 \times 2 = 10$ spaces.
- The operator column $C_{\text{arrow}}$ for the group is:
  $$C_{\text{arrow}} = \max\left(C_{N-1} + W_{N-1} + 1,\; \max_{\text{where}}\big(10 + \text{len}(\text{where\_lhs}) + 1\big)\right)$$
- The return/RHS column is:
  $$C_{\text{ret}} = C_{\text{arrow}} + \text{len}(\text{sig\_arrow}) + 1$$
- **Signature line**: `=>` (or `->`) starts at $C_{\text{arrow}}$ and the return type starts at $C_{\text{ret}}$.
- **Single-line clause (`<lhs> = <rhs>`)**: `=` is placed at $C_{\text{arrow}}$ and `<rhs>` starts at $C_{\text{ret}}$ (aligned under the return type).
- **Multi-line block clause (`<lhs> =`)**: When `=` is at the end of the line (followed by an indented block on the next line), `=` is also placed at $C_{\text{arrow}}$ (aligned directly beneath `=>`).
- **`where` binding (`<lhs> -> <rhs>`)**: `<lhs>` starts at column 10, `->` starts at $C_{\text{arrow}}$, and `<rhs>` starts at $C_{\text{ret}}$.
- **Compact Fallback for Wide or High-Arity Signatures (`num_params > 4` or `total_sig_len > 80`)**: When a signature has more than `4` parameter slots or its aligned signature line (`ret_col + len(ret_type)`) would exceed `80` columns, horizontal column padding is disabled for that group: the signature, its clauses (still starting at column `6`), and its `where` bindings (still starting at column `10`) separate tokens with a single space (`" "`).

### 4. Structural Indentation (Offset = 2 Spaces)
- **Column 0**: Top-level declarations (`fn ::`, `op ::`, `type`, `import`, `global`, `context`, `shared`, `hardware`, `@`).
- **Column 6**: Definition clauses belonging to an enclosing `fn ::` or `op ::` signature.
- **Column 8 (`6 + 2`)**: Guard lines (`| cond = expr`), parallel pipe branches (`|| expr`), and the `where` keyword line inside a function/operator group.
- **Block body lines**: When the previous non-blank, non-comment line ends with `=`, `where`, or `do`, the following block body is indented by `+2` spaces relative to the opening line (`8` spaces for a body directly under a column-6 clause; `2` spaces for a body under a column-0 clause). Subsequent statements in the same block preserve that block indentation.
- **Blank lines and comments**: Blank lines are emitted as empty lines (`""` with trailing whitespace stripped); standalone comment lines (`-- ...`) at the top level stay at column 0, and inside a function body follow the surrounding indentation.

## Acceptance Criteria
- AC1: Given an unaligned Ridgun `.rg` file containing `fn ::` and `op ::` declarations with multiple clauses, guards, and `where` bindings, when `stable format <file>` is executed, then the file is rewritten in-place with aligned LHS columns ($C_0 = 6$), aligned `=>`/`=`/`->` columns ($C_{\text{arrow}}$), and 2-space structural indentation.
- AC2: Given a project with `build.rg`, when `stable format` is executed with no path arguments, then all `.rg` files in `source_dir`, `test_dir`, and `build.rg` are formatted in-place.
- AC3: Given any `.rg` file, both the unformatted original and the output of `stable format` SHALL pass `stable check` and compile identically with `ridgunc`.

## Actors & Permissions
- Any developer or CI pipeline invoking `stable format`.

## Constraints & Edge Cases
- Must be implemented 100% in pure Ridgun inside `stable`.
- Must be idempotent: running `stable format` a second time on an already formatted file produces zero changes.
- Must preserve string literal contents (both `"..."` and `'...'`) and inline/standalone `--` comments.

## Out of scope
- Enforcing formatting rules inside `ridgunc` as compiler errors or warnings.
