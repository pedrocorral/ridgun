# Chapter 02: Your Two Best Friends: `ridgunc` and `stable` (Zero YAML Files, Promised)

Some languages have a wonderful compiler, but a project tooling ecosystem that feels like it was designed by your worst enemy: a 400-line `Makefile` with invisible tabs, an endless `pom.xml`, or a `webpack.config.js` that stops working if you look at it funny...

In Ridgun we made ourselves a very simple promise on day one:

> *"There will be only two executables in the entire ecosystem (`ridgunc` and `stable`), both will be written in Ridgun itself, and the project configuration file (`build.rg`) will be ordinary Ridgun code. No JSON, no YAML, no TOML, no weird inventions."*

Let's see how to use them.

---

## 2.1. `ridgunc`: The Sniper for Standalone Files

When you have a single `.rg` file in front of you and want to test a quick idea, check its types, or compile an executable, you talk directly to **`ridgunc`**.

It only has 4 commands you actually need to remember:

```bash
# 1. "Does this compile, or did I mess up a type?"
ridgunc check experiment.rg

# 2. "Run it now!" (Compiles and runs in one go)
ridgunc run experiment.rg

# 3. "Build me a standalone native ELF binary to go"
ridgunc build experiment.rg -o my_program

# 4. "Emit the intermediate bytecode artifact (.rgc)"
ridgunc compile experiment.rg -o experiment.rgc
```

### The Hidden Superpower of `ridgunc check`
When you run `ridgunc check`, it doesn't just tell you *"0 errors"*. It also reveals which execution strategy the static analyzer chose for each of your functions:
- **`InlineSequential`**: *"This function is small and direct; I'll run it inline with zero scheduling overhead"*.
- **`LazyStealableTask`**: *"There is recursion or a parallel `||` graph here; I'll set it up so other CPU cores can steal work if needed"*.

### The Scalpel Inside `ridgunc build` (Why Your Binaries Don't Weigh 20 MB)
When you run `ridgunc build`, the compiler doesn't just dump all the code from every library you imported:
1. It starts at your `main` function and walks the call graph to see **which functions you actually use**. If you imported a massive 80-function library but only call 2 of them, the other 78 are discarded before ever touching the assembler (*Tree-Shaking*).
2. It finds every tail-recursive function and turns it into a native `loop` that consumes **0 bytes of stack**.
3. It runs the final link pass with full link-time optimization (*fat LTO*) and strips DWARF debug bloat to leave you with a compact, razor-sharp binary (~350 KB).

---

## 2.2. `stable`: When Your Project Grows and You Want Order

A standalone file is great for a script, but the moment you have multiple modules, shared libraries, and test suites, you need an orchestra conductor. That conductor is **`stable`**.

The directory layout of a Ridgun project is completely straightforward:

```text
my-super-tool/
├── build.rg                  # The project manifest (it's Ridgun code!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Your reusable modules (`import utils`)
│   │       └── app/
│   │           └── main.rg   # Entry point (`main => ()`)
│   └── test/
│       └── ridgun/           # Your test suites (`test *.rg`)
│           └── test all.rg
└── target/                   # Where compiled binaries appear
```

---

## 2.3. `build.rg`: A Configuration File That Will Never Lie to You

Why did we refuse to use YAML or TOML to configure a Ridgun project?
Because in YAML you misalign two spaces of indentation and don't find out until deployment fails. By contrast, since **`build.rg` is a Ridgun file**, it has static types, gets verified by `stable check`, and formats itself with `stable format`:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "my-super-tool" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"
```

If you mistype a field, the compiler tells you immediately. No surprises.

---

## 2.4. Your Daily Routine with `stable` (The Fantastic Four)

When working inside your project, your day-to-day workflow boils down to four commands:

### 1. `stable format` — The End of Team Style Wars
```bash
stable format
```
Your teammate puts three spaces before `=>` and you put one? Doesn't matter. Run `stable format` and in under a second it leaves **every** `.rg` file in the repository aligned like a Swiss watch.

### 2. `stable check` — Instant Radar
```bash
stable check
```
Walks every module in `src/main/ridgun/`, verifies types, constructors, arities, and tensor dimensions, and gives you a module-by-module verdict.

### 3. `stable test` — Sleep Soundly at Night
```bash
stable test
```
Finds all `src/test/ridgun/test *.rg` suites, executes them, and verifies every `assert equals` and `assert true`.

```ridgun
-- Example of src/test/ridgun/test math.rg
import test

double Int => Int
double x   =  x * 2

main => ()
main =
  assert equals (double 21) 42
  assert true ((double 5) > 0)
```

### 4. `stable built` (and `stable clean`) — Ready for Production
```bash
stable built
```
Compiles all native targets into `target/`. And if you ever want to wipe `target/` and start fresh: `stable clean`.

---

## 2.5. How Do I Import One File from Another? (`import`)

Without horrific relative paths like `../../../lib/stuff.rg`. If you have a file at `src/main/ridgun/lib/strings.rg`, in any other file you simply write at the top:

```ridgun
import strings
```

And you're done: all functions and types from `strings.rg` are available as if they were in your own file. What if module `A` does `import strings`, module `B` also does `import strings`, and your `main.rg` imports both `A` and `B`? Don't worry: Ridgun's loader remembers which canonical files it has already read and **includes each file only once**.

Now that you have the toolbox under control, let's move on to **Chapter 03** to master functions, types, blocks, and string tricks.
