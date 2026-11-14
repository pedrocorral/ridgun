---
id: ADR-0012
title: The browser compiler reads libraries from a virtual file system, fetched file by file from ridgun.com/wasm
status: accepted
date: 2026-11-14
supersedes: []
affects: [ADR-0011, FR-COMP-026, src/main/ridgun/lib/parser.ridgun, src/main/ridgun/ridgunc/main.ridgun]
---
# ADR-0012 — The browser compiler reads libraries from a virtual file system

## Context
In the playground (ADR-0011), `ridgunc.wasm` compiles a visitor's program in the browser. A program may import libraries (`import json`). `ridgunc` reads them as files, from the places it searches (`.stable/deps`, `$HOME/.local/lib/ridgun`, …). The browser has no file system, and the server only serves static files.

The libraries of ridgun-libs are 37 bundles (`.ridgunlib`), 976 KB of text, about 175 KB compressed. Most programs import none or one or two of them. The compiler's own modules need no files: they are compiled into `ridgunc.wasm`.

## Options considered
1. **Compile on a server**, where the files are. Rejected in ADR-0011 (cost per visitor, a sandbox for unknown code).
2. **Embed the libraries in `ridgunc.wasm`.** No requests; but every visitor downloads every library, and a library change means a new compiler build.
3. **One archive of all the libraries**, downloaded with the page and mounted in memory (what Pyodide and clang in the browser do). Simple; every visitor downloads 175 KB they mostly do not use.
4. **A virtual file system with a manifest, and each file fetched when the compiler opens it.** The page downloads a small list of the files. A library is fetched the first time the compiler reads it; the HTTP cache keeps it.
5. **Scan the program's imports in JavaScript and fetch them before compiling.** A second import resolver that drifts from the compiler's.

## Decision
Option 4.

- **Static files.** `ridgun.com/wasm/<version>/` holds `ridgunc.wasm`, the JavaScript host, and `lib/` with one `.ridgunlib` per library and `lib/manifest.txt` (one name per line). `<version>` is the `ridgunc` version, so every file is immutable and served with a long cache life; the server compresses them (brotli or gzip). These files are not part of one page: the playground (`ridgun.com/play`), the book or any page with runnable examples loads them from there.
- **The file system.** The compiler runs in a Web Worker. The host keeps a file system in memory with two folders, and nothing else:
  - `/lib/` is read-only. A path listed in the manifest is fetched from `lib/` on its first read (a synchronous request, allowed in a worker), then kept. Any other path is "not found" at once, with no request: the compiler probes several paths, and none of those probes may reach the network.
  - `/work/` is read-write and lives only in memory: the visitor's `main.ridgun`, and the `.wasm` the compiler writes.
- **`--libs <dir>`.** `ridgunc` gains an option that names the folder of the library bundles. The host runs `ridgunc build --libs /lib /work/main.ridgun -o /work/main.wasm`. With `--libs`, that folder is searched first; the other places stay for Linux. No Linux conventions (`HOME`, `.local`) are imitated in the browser, and the option is also useful on Linux to build against one folder of libraries.
- **The program's own files.** When the page runs the compiled program, its file imports use the same host, with a fresh `/work/` per run. Nothing is written on the server.
- **Publishing.** The www-ridgun build copies the bundles of the ridgun-libs release that matches the `ridgunc` version into `lib/` and writes `manifest.txt` from the same list.

If a browser ever drops synchronous requests in workers, the worker can wait on a `SharedArrayBuffer` with `Atomics.wait` while the page fetches; that needs the COOP and COEP headers, so it is the fallback, not the default.

## Consequences
- The visitor downloads only the libraries their program imports, once per version.
- Adding or changing a library is a new file in `lib/` and a line in the manifest; `ridgunc.wasm` does not change.
- TASK-0089 adds `--libs` and implements the file imports in the browser host over this file system. The library search in `parser.ridgun` also lists a fixed path of the development machine (`/home/boogie/ridgun/ridgun/.stable/deps`); TASK-0089 removes it, since `--libs` covers that use.
- TASK-0091 publishes `ridgun.com/wasm/<version>/` (with `lib/` and the manifest) and the playground page that loads it.
- A library fetched for one program stays in the worker's memory for the next compile in the same page.
