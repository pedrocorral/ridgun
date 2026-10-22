# Ridgun (`v0.9.8`)

**A tabular, pure-by-default functional & systems programming language built for massive parallelism, symbolic tensor algebra, and deterministic zero-GC memory management.**

Ridgun combines the declarative clarity of tabular functional programming with native systems performance. Its self-hosted compiler (**`ridgunc`**) and project manager/formatter (**`stable`**) are written **100% in pure Ridgun** (`src/main/ridgun/`, zero Rust/C code or external compiler dependencies) and emit standalone, statically linked Linux ELF64 executables (`x86_64` and `ARM64` / Raspberry Pi) directly to disk with zero Garbage Collector pauses.

---

## 📖 The Ridgun Book — Complete Guide in 7 Languages

Learn Ridgun from scratch—from your first tabular function to parallel DAGs, symbolic tensors, and `RMM1`/`RMM2` deterministic memory management—in your preferred language:

| Language | Online Interactive Book (`HTML`) | Markdown Chapters (`00`–`08`) |
|---|---|---|
| 🇪🇸 **Español** | [**El Libro de Ridgun (`es/index.html`)**](docs/book/es/index.html) | [`docs/book/es/INDEX.md`](docs/book/es/INDEX.md) — [Cap. 00](docs/book/es/00-por-que-necesito-ridgun.md) · [01](docs/book/es/01-bienvenido-a-ridgun.md) · [02](docs/book/es/02-primeros-pasos-y-herramientas.md) · [03](docs/book/es/03-funciones-tipos-y-alineacion.md) · [04](docs/book/es/04-pattern-matching-y-guardas.md) · [05](docs/book/es/05-listas-tuplas-y-secuencias.md) · [06](docs/book/es/06-tipos-algebraicos-y-polimorfismo.md) · [07](docs/book/es/07-orden-superior-y-paralelismo-dag.md) · [08](docs/book/es/08-tensores-regiones-y-sistemas.md) |
| 🇬🇧 **English** | [**The Ridgun Book (`en/index.html`)**](docs/book/en/index.html) | [`docs/book/en/INDEX.md`](docs/book/en/INDEX.md) — [Ch. 00](docs/book/en/00-why-do-i-need-ridgun.md) · [01](docs/book/en/01-welcome-to-ridgun.md) · [02](docs/book/en/02-getting-started-and-tooling.md) · [03](docs/book/en/03-functions-types-and-alignment.md) · [04](docs/book/en/04-pattern-matching-and-guards.md) · [05](docs/book/en/05-lists-tuples-and-sequences.md) · [06](docs/book/en/06-algebraic-data-types-and-polymorphism.md) · [07](docs/book/en/07-higher-order-functions-and-dag-parallelism.md) · [08](docs/book/en/08-tensors-rmm-regions-and-systems.md) |
| 🇵🇹 **Português** | [**O Livro do Ridgun (`pt/index.html`)**](docs/book/pt/index.html) | [`docs/book/pt/INDEX.md`](docs/book/pt/INDEX.md) — [Cap. 00](docs/book/pt/00-por-que-preciso-do-ridgun.md) · [01](docs/book/pt/01-bem-vindo-ao-ridgun.md) · [02](docs/book/pt/02-primeiros-passos-e-ferramentas.md) · [03](docs/book/pt/03-funcoes-tipos-e-alinhamento.md) · [04](docs/book/pt/04-pattern-matching-e-guardas.md) · [05](docs/book/pt/05-listas-tuplas-e-sequencias.md) · [06](docs/book/pt/06-tipos-algebricos-e-polimorfismo.md) · [07](docs/book/pt/07-ordem-superior-e-paralelismo-dag.md) · [08](docs/book/pt/08-tensores-rmm-regioes-e-sistemas.md) |
| 🇸🇪 **Svenska** | [**Boken om Ridgun (`sv/index.html`)**](docs/book/sv/index.html) | [`docs/book/sv/INDEX.md`](docs/book/sv/INDEX.md) — [Kap. 00](docs/book/sv/00-varfor-behover-jag-ridgun.md) · [01](docs/book/sv/01-valkommen-till-ridgun.md) · [02](docs/book/sv/02-forsta-stegen-och-verktyg.md) · [03](docs/book/sv/03-funktioner-typer-och-justering.md) · [04](docs/book/sv/04-monstermatchning-och-vakter.md) · [05](docs/book/sv/05-listor-tupler-och-sekvenser.md) · [06](docs/book/sv/06-algebraiska-datatyper-och-polymorfism.md) · [07](docs/book/sv/07-hogre-ordningen-och-dag-parallellism.md) · [08](docs/book/sv/08-tensorer-rmm-regioner-och-system.md) |
| 🏴 **Català** | [**El Llibre de Ridgun (`ca/index.html`)**](docs/book/ca/index.html) | [`docs/book/ca/INDEX.md`](docs/book/ca/INDEX.md) — [Cap. 00](docs/book/ca/00-per-que-necessito-ridgun.md) · [01](docs/book/ca/01-benvingut-a-ridgun.md) · [02](docs/book/ca/02-primers-passos-i-eines.md) · [03](docs/book/ca/03-funcions-tipus-i-alineacio.md) · [04](docs/book/ca/04-pattern-matching-i-guardes.md) · [05](docs/book/ca/05-llistes-tuples-i-sequencies.md) · [06](docs/book/ca/06-tipus-algebraics-i-polimorfisme.md) · [07](docs/book/ca/07-ordre-superior-i-parallelisme-dag.md) · [08](docs/book/ca/08-tensors-rmm-regions-i-sistemes.md) |
| 🏴 **Galego** | [**O Libro de Ridgun (`gl/index.html`)**](docs/book/gl/index.html) | [`docs/book/gl/INDEX.md`](docs/book/gl/INDEX.md) — [Cap. 00](docs/book/gl/00-por-que-preciso-ridgun.md) · [01](docs/book/gl/01-benvido-a-ridgun.md) · [02](docs/book/gl/02-primeiros-pasos-e-ferramentas.md) · [03](docs/book/gl/03-funcions-tipos-e-alinamento.md) · [04](docs/book/gl/04-pattern-matching-e-gardas.md) · [05](docs/book/gl/05-listas-tuplas-e-secuencias.md) · [06](docs/book/gl/06-tipos-alxebricos-e-polimorfismo.md) · [07](docs/book/gl/07-orde-superior-e-paralelismo-dag.md) · [08](docs/book/gl/08-tensores-rmm-rexions-e-sistemas.md) |
| 🏴 **Euskara** | [**Ridgun Liburua (`eu/index.html`)**](docs/book/eu/index.html) | [`docs/book/eu/INDEX.md`](docs/book/eu/INDEX.md) — [00. kap.](docs/book/eu/00-zergatik-behar-dut-ridgun.md) · [01](docs/book/eu/01-ongi-etorri-ridgunera.md) · [02](docs/book/eu/02-lehen-urratsak-eta-tresnak.md) · [03](docs/book/eu/03-funtzioak-motak-eta-lerrokatzea.md) · [04](docs/book/eu/04-eredu-bat-etortzea-eta-zainak.md) · [05](docs/book/eu/05-zerrendak-tuplak-eta-sekuentziak.md) · [06](docs/book/eu/06-datu-mota-aljebraikoak-eta-polimorfismoa.md) · [07](docs/book/eu/07-goi-mailako-funtzioak-eta-dag-paralelismoa.md) · [08](docs/book/eu/08-tentsoreak-rmm-eskualdeak-eta-sistemak.md) |

---

## Quick Start

 Ridgun ships with two self-hosted tools—**`ridgunc`** (the single-file compiler & runner) and **`stable`** (the project manager, typechecker, test runner, and canonical tabular formatter)—configured via a pure Ridgun [`build.rg`](build.rg) file (no YAML, JSON, or TOML):

```bash
# Type-check all project modules in src/main/ridgun/
./target/stable check

# Compile & run all test suites in src/test/ridgun/
./target/stable test

# Format all .rg source files into canonical tabular alignment
./target/stable format

# Build all project targets into target/ (or install into ~/.local/bin/)
./target/stable built
./target/stable built lib
./target/stable install

# Scaffold a new app or library project, list tasks/plugins, or sync dependencies
./target/stable new my_app
./target/stable new --lib my_lib
./target/stable tasks
./target/stable plugins
./target/stable deps

# Compile or run a single .rg file or library directly with ridgunc (x86_64 or ARM64 Raspberry Pi)
./target/ridgunc check my_program.rg
./target/ridgunc run my_program.rg
./target/ridgunc build my_program.rg -o my_program
./target/ridgunc build --lib my_lib.rg -o my_lib.rglib
./target/ridgunc build --so my_lib.rg -o libmy_lib.so
./target/ridgunc build --target arm64-linux my_program.rg -o my_program_arm64
```

---

## What Makes Ridgun Different?

1. **Code as a 2D Table (`=>`, `=`, `->`)**: Type signatures act as column headers. Pattern-matching clauses align each argument beneath its type and align `=` beneath `=>`. `stable format` (and GNU Emacs `ridgun-mode`) formats your code automatically.
2. **Unified `=` Block Grammar (`(none)`, `|`, `||`) & Compact Nested Closers (`|.` / `||.`)**:
   - Every `=` (in functions, operators, local bindings `x =`, or guard branches) accepts sequential lines, conditional guard blocks (`|`), or parallel DAG blocks (`||`).
   - Guard branches can nest 3–4+ levels deep to form rich decision trees, using the compact inline **`|.`** closer (`| otherwise = val |.`) only when returning to an outer branch level below.
3. **Parallel DAG Blocks (`|| expr -> var`) & Multicore Combinators (`||map`, `||filter`)**:
   - Parallel dataflow dependencies are declared directly with `|| expr -> var` (no `where` keyword required). The static analyzer verifies cycle freedom at compile time and schedules independent branches in parallel.
   - `map`, `filter`, and `fold` execute sequentially left-to-right, while **`||map`** and **`||filter`** distribute list elements across multicore worker threads using Ridgun's `||` parallel prefix.
4. **Immutable by Default (`x = ...`) with Explicit `mut` (`mut x = ...`)**:
   - Local bindings are immutable constants unless declared with `mut x = expr`, preventing accidental rebinding in the same scope.
5. **Deterministic Memory Without a Garbage Collector (`RMM1`, `RMM2` & `with region`)**:
   - **Policy `RMM1` (Compiled Memory Management)**: Static last-use deallocation (`rg_cmm_drop`), zero-copy return moves (`rg_cmm_move`), and 1-cycle pointer-identity guards (`ptr(a) != ptr(c)`) for branching functions.
   - **Policy `RMM2` (Assignment & Cascaded Structure Counting)**: Incoming function arguments are untouched (`+0`/`-0`), local/container assignments add `+1`, returned locals are spared in transit, and non-returned locals cascade `-1` through child structures on scope exit.
   - **Lexical Regions (`with region 64_KB do`)**: Enforce hard byte quotas on untrusted workloads and free entire arenas in $O(1)$.
6. **Natural-Language Spaces in `fn ::` & `op ::`, Open `expand type`, Polymorphism (`A`..`Z`), and Symbolic Tensors (`@`)**:
   - Define multi-word functions and N-ary operators with natural spaces instead of underscores (`fn :: format err AppErr => String`, `op :: clamp Int between Int and Int => Int`).
   - Share ADT constructor names across types (`Error`, `Var`), use bare type names as variants (`type Something = String | Int | MyStruct Float Int`), extend types via `expand type`, and merge new `fn ::` clauses automatically before `_` catch-alls.
   - Single uppercase letters (`A`..`Z`) act as zero-noise polymorphic type variables.
   - Native `Tensor[N, K]` types check symbolic dimensions at compile time and support Einstein summation (`A_ik @ B_kj`) and Hadamard broadcasting (`A_ij * B_j`).

---

## A Taste of Ridgun

```ridgun
-- 1. Tabular pattern matching, natural spaces & zero-noise polymorphism (A..Z)
head or [A]   A => A
head or []    d =  d
head or (x:_) _ =  x

-- 2. Bare type-name variants, `expand type` & automatic `fn ::` clause merging
type Something = String | Int | MyStruct Float Int

fn :: describe something Something          => String
      describe something (String   s)       =  "str:{s}"
      describe something (Int      n)       =  "int:{n}"
      describe something (MyStruct f count) =  "struct:{f}:{count}"
      describe something _                  =  "other"

expand type Something = Bool

fn :: describe something Something => String
      describe something (Bool b)  =  "bool:{b}"

-- 3. Natural-language mixfix operator with `=` + `|` guards
op :: clamp Int between Int and Int => Int
      clamp x   between lo  and hi  =
        | x < lo    = lo
        | x > hi    = hi
        | otherwise = x

-- 4. Multi-level decision tree with compact inline `|.` closers
fn :: route request Int    Int  Bool      Bool     Int        Int          => Int
      route request method role is_signed is_admin payload_kb rate_limited =
        | method == 0 =
          | payload_kb == 0 = 204
          | otherwise       = 200 |.
        | method == 1 =
          | not is_signed = 401
          | otherwise =
            | rate_limited > 0 =
              | is_admin =
                | payload_kb > 10000 = 413
                | otherwise          = 202 |.
              | otherwise = 429 |.
            | payload_kb > 1000 =
              | role >= 2 and is_admin = 201
              | otherwise              = 413 |.
            | otherwise = 201 |.
        | otherwise = 405

-- 5. Parallel DAG block (`|| expr -> var`) without `where` + `||.` closer
fn :: quarterly balance Int  => Int
      quarterly balance base =
        || base * 100                 -> gross_sales
        || base * 40                  -> fixed_costs
        || gross_sales - fixed_costs  -> gross_profit ||.
        gross_profit * 80 / 100

-- 6. Conditional local variable (`x = | ...`) and explicit `mut` accumulator
fn :: compute total Bool   Int => Int
      compute total is_vip raw =
        discount =
          | is_vip and raw > 50 = 20
          | otherwise           = 0
        mut total = raw - discount
        total = total + 5
        total

-- 7. Symbolic-dimension Tensor contraction (Einstein summation `@`)
fn :: linear layer Tensor[B, In] Tensor[In, Out] Tensor[B, Out] => Tensor[B, Out]
      linear layer x             weights         bias           =  (x_bi @ weights_io) + bias
```

---

## Self-Hosted Architecture (`src/main/ridgun/`)

```text
Ridgun Source (.rg) + build.rg
              │
              ▼
  ┌────────────────────────┐
  │  lexer.rg & parser.rg  │  Tokenization, Mixfix Resolution, Unified `=` (`|`, `||`, `|.`, `||.`)
  └───────────┬────────────┘
              │
              ▼
  ┌────────────────────────┐
  │      typecheck.rg      │  Polymorphic `A..Z`, `mut` Immutability Check, Symbolic Tensor Dims
  └───────────┬────────────┘
              │
              ▼
  ┌────────────────────────┐
  │       analyzer.rg      │  Static `||` DAG Cycle Detection & Work-Stealing Strategy Inference
  └───────────┬────────────┘
              │
              ▼
  ┌────────────────────────┐
  │       compiler.rg      │  Call-Graph Tree-Shaking, TCO (`loop`), `RMM1` & `RMM2` Lowering
  └─────┬────────────┬─────┘
        │            │
        ▼            ▼
  ┌───────────┐    Bytecode (`.rgc`)
  │ x86_64.rg │   (`vm.rg` Stack VM)
  │ arm64.rg  │
  │ elf64.rg  │
  └─────┬─────┘
        ▼
  Native ELF64 (`x86_64` / `ARM64`)
```

---

## Project Layout

```text
ridgun/
├── build.rg                   # Pure-Ridgun project manifest for `stable`
├── editors/
│   └── emacs/ridgun-mode.el   # GNU Emacs major mode with tabular alignment
├── src/
│   ├── main/ridgun/
│   │   ├── lib/
│   │   │   ├── ast.rg         # Compiler & VM Algebraic Data Types
│   │   │   ├── lexer.rg       # Lexical scanner & byte-unit literals (_KB, _MB, _GB)
│   │   │   ├── parser.rg      # Recursive-descent parser & mixfix normalizer
│   │   │   ├── typecheck.rg   # Typechecker, A..Z unification & tensor shape checker
│   │   │   ├── analyzer.rg    # Static parallel DAG & strategy analyzer
│   │   │   ├── compiler.rg    # RMM1/RMM2 analyzer, native IR lowerer & .rgc compiler
│   │   │   ├── elf64.rg       # Direct Linux ELF64 executable binary emitter
│   │   │   ├── x86_64.rg      # Pure-Ridgun 2-pass x86_64 machine-code assembler & kernel
│   │   │   ├── arm64.rg       # Pure-Ridgun 2-pass ARM64 (AArch64 / Raspberry Pi) assembler
│   │   │   ├── formatter.rg   # Canonical tabular code formatter (`stable format`)
│   │   │   └── vm.rg          # Meta-circular stack virtual machine
│   │   ├── ridgunc/main.rg    # Self-hosted `ridgunc` CLI entry point
│   │   └── stable/main.rg     # Self-hosted `stable` project manager CLI entry point
│   └── test/ridgun/           # Self-hosted Ridgun test suites (`test_*.rg`)
├── docs/
│   ├── book/                  # The Ridgun Book in 7 languages (es, ca, gl, eu, en, pt, sv)
│   ├── lang/spec.md           # Formal language specification
│   ├── etc/cmm_architecture.md# RMM1 & RMM2 memory management architecture
│   └── requirements/          # Functional requirements (FR-COMP-*, FR-TOOL-*, FR-VM-*)
└── target/                    # Compiled self-hosted ELF64 binaries (`ridgunc`, `stable`)
```

---

## Technical Documentation

| Document | Description |
|---|---|
| [**Language Specification (`docs/lang/spec.md`)**](docs/lang/spec.md) | Complete syntax, type system, unified `=` blocks, `|` / `|.` decision trees, `||` DAGs, `mut`, ADTs, tensors, and canonical formatting rules |
| [**RMM Memory Architecture (`docs/etc/cmm_architecture.md`)**](docs/etc/cmm_architecture.md) | Detailed design of `RMM1` (Linear & Conditional CMM) and `RMM2` (Assignment & Cascaded Structure Counting) |
| [**FR-COMP-004 (`docs/requirements/functional/compiler/`)**](docs/requirements/functional/compiler/FR-COMP-004-native-elf64-codegen-x86-64-and-arm64.md) | Requirement specification for 100% pure-Ridgun native ELF64 machine-code generation (`x86_64` and `ARM64` Raspberry Pi) without Rust or `rustc` |
| [**FR-COMP-003 (`docs/requirements/functional/compiler/`)**](docs/requirements/functional/compiler/FR-COMP-003-unified-equals-grammar-guards-parallel-pipes-and-mut.md) | Requirement specification for unified `=` grammar, `|.` / `||.` closers, `mut`, and lowercase logical operators |
| [**FR-COMP-002 (`docs/requirements/functional/compiler/`)**](docs/requirements/functional/compiler/FR-COMP-002-compiled-memory-management-cmm.md) | Requirement specification for `RMM1` and `RMM2` deterministic memory management |
| [**Roadmap & Active Tasks (`docs/road-map/INDEX.md`)**](docs/road-map/INDEX.md) | Current session state, completed milestones, and backlog |

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
