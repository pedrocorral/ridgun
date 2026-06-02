# Ridgun

**A programming language built for massive parallelism.**

Ridgun is a new programming language designed from the ground up to execute tasks in parallel. It compiles to bytecode and runs on a custom virtual machine with a built-in parallel scheduler, lightweight green threads, and a work-stealing execution model.

## Quick Start

```bash
# Build
cargo build --release

# Run a program
./target/release/ridgun run my_program.rg <function> [args...]

# Examples
./target/release/ridgun run my_program.rg sum 3 4          # → 7
./target/release/ridgun run my_program.rg factorial 5      # → 120
./target/release/ridgun run my_program.rg fib 10           # → 55

# Install system-wide (optional)
cargo install --path .
ridgun run my_program.rg factorial 10
```

## Key Design Principles

- **Parallelism is the default.** Concurrency isn't bolted on — it's the foundation. Ridgun's VM manages thousands of lightweight processes out of the box.
- **Safe by design.** Message passing and channels replace shared mutable state. Data races are impossible at the language level.
- **Interop without compromise.** Call C/C++ libraries directly via FFI (LibTorch, OpenBLAS, etc.) with full parallelism. Use the Python bridge to access any `pip install`-able library when convenience matters more than GIL avoidance.
- **Compile once, schedule smart.** Ridgun source compiles to bytecode. The VM's work-stealing scheduler distributes green threads across OS threads automatically.

## Architecture

```
Ridgun Source (.rg)
        │
        ▼
  ┌──────────┐
  │  Lexer   │
  │  Parser  │   Source → AST
  └────┬─────┘
       │
       ▼
  ┌──────────┐
  │ Compiler │   AST → Bytecode
  └────┬─────┘
       │
       ▼
  ┌──────────┐
  │ Ridgun   │   Custom VM
  │   VM     │   • Green threads
  │          │   • Work-stealing scheduler
  │          │   • FFI + Python bridge
  └──────────┘
```

## A Taste of Ridgun

```ridgun
-- Functions are defined with fn ::
fn :: sum int int => int
sum a b = a + b

-- Operators read like natural language
op :: add int to int => int
add a to b = a + b

-- Parallelism is a first-class syntactic primitive
op :: run conf and conf in parallel => res, res
run a and b in parallel = res_a, res_b
  where
    run my own process a -> res_a
    run my own process b -> res_b
```

## Project Structure

The `src/` layout is inspired by **Scala's sbt** — mirrored `main`/`test` trees with language-specific subdirectories.

```
ridgun/
├── docs/
│   ├── lang/              # Language specification and samples
│   ├── dev/               # Development policies and coding standards
│   │   └── disabled/      # Future reference (out of scope)
│   └── etc/               # Architecture, VM, interop, roadmap
├── src/
│   ├── main/
│   │   ├── ridgun/        # Ridgun source (.rg) — standard library
│   │   └── rust/          # Rust source — VM, compiler, scheduler
│   └── test/
│       ├── ridgun/        # Ridgun test programs (.rg)
│       └── rust/          # Rust unit and integration tests
├── tsk/                   # Task definitions (security workflows, SCA, SAST)
├── tst/                   # High-level test suites (V-Model)
├── LICENSE                # Apache 2.0
└── README.md
```

## Implementation Language

The VM and compiler are implemented in **Rust** — chosen for its memory safety guarantees, zero-cost abstractions, and excellent concurrency primitives. Rust dogfoods the "safe parallelism" philosophy that Ridgun embodies.

## Documentation

| Document | Description |
|---|---|
| [Language Spec](docs/lang/spec.md) | Syntax, functions, operators, parallelism primitives |
| [Architecture](docs/etc/architecture.md) | VM internals, bytecode format, compilation pipeline |
| [Parallelism](docs/etc/parallelism.md) | Green threads, scheduler, channels, message passing |
| [Interop](docs/etc/interop.md) | FFI for C/C++ libraries, Python bridge via PyO3 |
| [Process](docs/etc/process.md) | Development methodology: Spiral + V-Model + OWASP SAMM |
| [Roadmap](docs/etc/roadmap.md) | Development phases and milestones |
| [SAST Policy](docs/dev/sast_policy.md) | Static analysis policy and security gates |

## License

Apache 2.0 — see [LICENSE](LICENSE).