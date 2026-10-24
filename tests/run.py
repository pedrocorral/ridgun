#!/usr/bin/env python3
"""Acceptance tests for ridgunc (see README.md).

Usage: python3 tests/run.py [filter ...]        (default: every case under tests/cases/ and the toolchain checks)
       python3 tests/run.py lists strings        (cases whose path contains "lists" or "strings")
       python3 tests/run.py --no-toolchain ...   (skip the toolchain checks written in this file)

Each case is a Ridgun program under tests/cases/<area>/ whose header says what must happen:
  -- case: what it checks (one line)
  -- source: where the expectation comes from (spec.md §…, FR-COMP-…, Solstice register RG-…, or "consistency: …")
  -- expect-output:            the exact standard output, one "--   line" per line ("--   " alone is an empty line)
  -- expect-build-error: TEXT  the build must fail and its output contain TEXT
  -- expect-exit: N            the program must exit with N (default 0 when there is expected output)
  -- max-ms: N                 the run must take at most N ms of wall time
  -- max-rss-mb: N             the run's peak resident memory must stay under N MB
  -- uses-libs                 copy ridgun-libs bundles next to the case (only when the case imports a library)
Every build is `ridgunc build --strict`: cases are written in the canonical style (spaced names in declarations).
Builds and runs are capped at 4 GB of address space and a time limit. The work folder is
~/.cache/ridgun-compiler-tests/work: never /tmp (a tmpfs) and never inside a repository.
"""
import os, re, resource, shutil, subprocess, sys, threading, time

TESTS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TESTS)
CASES = os.path.join(TESTS, "cases")
RIDGUNC = os.environ.get("RIDGUNC") or os.path.join(REPO, "bin/ridgunc")
LIBS_BUNDLES = os.environ.get("RIDGUN_LIBS_BUNDLES", "/home/boogie/ridgun/libs/target/bundles")
WORK = os.path.join(os.path.expanduser("~"), ".cache", "ridgun-compiler-tests", "work")
BUILD_SECONDS, RUN_SECONDS = 600, 300


def cap():
    resource.setrlimit(resource.RLIMIT_AS, (4_000_000 * 1024, 4_000_000 * 1024))


def sh(cmd, cwd, timeout):
    """Runs cmd; returns (exit code, output, wall ms, peak RSS of that process in KB)."""
    t0 = time.monotonic()
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, preexec_fn=cap)
    timer = threading.Timer(timeout, p.kill)
    timer.start()
    try:
        out = p.stdout.read()
        _, status, usage = os.wait4(p.pid, 0)
    finally:
        timer.cancel()
    p.returncode = os.waitstatus_to_exitcode(status)
    ms = (time.monotonic() - t0) * 1000
    if ms >= timeout * 1000:
        return -1, f"timed out after {timeout} s", ms, usage.ru_maxrss
    return p.returncode, out.decode("utf-8", "replace"), ms, usage.ru_maxrss


def header(path):
    h = {"output": None, "build_error": None, "exit": None, "max_ms": None, "max_rss_mb": None, "libs": False, "case": "", "source": ""}
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines) and lines[i].startswith("--"):
        l = lines[i]
        if l.startswith("-- expect-output:"):
            out = []
            i += 1
            while i < len(lines) and (lines[i].startswith("--   ") or lines[i] == "--"):
                out.append(lines[i][5:] if lines[i].startswith("--   ") else "")
                i += 1
            h["output"] = "\n".join(out)
            continue
        for key, name in [("-- case:", "case"), ("-- source:", "source"), ("-- expect-build-error:", "build_error")]:
            if l.startswith(key):
                h[name] = l[len(key):].strip()
        for key, name in [("-- expect-exit:", "exit"), ("-- max-ms:", "max_ms"), ("-- max-rss-mb:", "max_rss_mb")]:
            if l.startswith(key):
                h[name] = int(l[len(key):].strip())
        if l.strip() == "-- uses-libs":
            h["libs"] = True
        i += 1
    return h


def run_case(path):
    rel = os.path.relpath(path, CASES)
    name = re.sub(r"[^A-Za-z0-9_]", "_", rel[:-3])
    h = header(path)
    if not h["source"]:
        return rel, False, "the case has no '-- source:' line"
    work = os.path.join(WORK, name)
    os.makedirs(os.path.join(work, "target"), exist_ok=True)
    if h["libs"]:
        os.makedirs(os.path.join(work, ".stable/deps"), exist_ok=True)
        for b in os.listdir(LIBS_BUNDLES):
            if b.endswith(".rglib"):
                shutil.copy(os.path.join(LIBS_BUNDLES, b), os.path.join(work, ".stable/deps", b))
    shutil.copy(path, os.path.join(work, "main.rg"))
    exe = os.path.join(work, "target", "case")
    code, out, _, _ = sh([RIDGUNC, "build", "--strict", "main.rg", "-o", exe], work, BUILD_SECONDS)
    built = code == 0 and os.path.exists(exe)
    if h["build_error"] is not None:
        if built:
            return rel, False, f"built, but the build had to fail with: {h['build_error']}"
        if h["build_error"] not in out:
            return rel, False, f"the build failed, but without '{h['build_error']}':\n       " + "\n       ".join(out.strip().splitlines()[-4:])
        return rel, True, ""
    if not built:
        return rel, False, "does not build:\n       " + "\n       ".join(re.findall(r"type error in function [^,\]]*", out)[:6] or out.strip().splitlines()[-4:])
    code, out, ms, rss_kb = sh([exe], work, RUN_SECONDS)
    problems = []
    want_exit = h["exit"] if h["exit"] is not None else 0
    if code != want_exit:
        problems.append(f"exit {code}, expected {want_exit}")
    if h["output"] is not None and out.rstrip("\n") != h["output"].rstrip("\n"):
        problems.append("output differs:\n" + diff(h["output"], out))
    if h["max_ms"] is not None and ms > h["max_ms"]:
        problems.append(f"took {ms:.0f} ms, limit {h['max_ms']} ms")
    if h["max_rss_mb"] is not None and rss_kb > h["max_rss_mb"] * 1024:
        problems.append(f"peak memory {rss_kb / 1024:.1f} MB, limit {h['max_rss_mb']} MB")
    return rel, not problems, "\n       ".join(problems)


def diff(want, got):
    w, g = want.rstrip("\n").split("\n"), got.rstrip("\n").split("\n")
    lines = []
    for i in range(max(len(w), len(g))):
        a = w[i] if i < len(w) else "(nothing)"
        b = g[i] if i < len(g) else "(nothing)"
        if a != b:
            lines.append(f"       line {i + 1}: expected {a!r}\n                got      {b!r}")
        if len(lines) >= 6:
            lines.append("       …")
            break
    return "\n".join(lines)


# ── Toolchain checks (no single program can express them) ────

def toolchain():
    rows = []
    d = os.path.join(WORK, "toolchain")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    open(os.path.join(d, "hello.rg"), "w").write('fn :: main => ()\n      main =  echo "hello"\n')
    code, out, _, _ = sh([RIDGUNC, "build", "--strict", "hello.rg", "-o", "no/such/folder/hello"], d, BUILD_SECONDS)
    exists = os.path.exists(os.path.join(d, "no/such/folder/hello"))
    rows.append(("toolchain: -o into a folder that doesn't exist either creates it or fails (exit != 0); never reports success without the file (Solstice register RG-081)",
                 exists or code != 0, f"exit {code}, file written: {exists}; output: {out.strip()[-160:]}"))
    open(os.path.join(d, "bad.rg"), "w").write('fn :: main => ()\n      main =  echo (1 + "a")\n')
    code, out, _, _ = sh([RIDGUNC, "build", "--strict", "bad.rg", "-o", "bad"], d, BUILD_SECONDS)
    rows.append(("toolchain: a type error exits with a non-zero status and writes no binary", code != 0 and not os.path.exists(os.path.join(d, "bad")), f"exit {code}; output: {out.strip()[-160:]}"))
    # Compile time grows with the program, not with its square (RG-075: 26 s for any program importing Solstice).
    times = []
    for n in [200, 800]:
        def nm(i):  # letters only: a digit word would read as an argument
            w = ""
            while True:
                w = chr(97 + i % 26) + w
                i = i // 26
                if i == 0:
                    return "step " + w
        src = "".join(f"fn :: {nm(i)} Int => Int\n      {nm(i)} x =  x + {i}\n\n" for i in range(n))
        src += "fn :: main => ()\n      main =  echo (int_to_str (" + " + ".join(f"({nm(i).replace(' ', '_')} 1)" for i in range(0, n, 50)) + "))\n"
        open(os.path.join(d, f"many{n}.rg"), "w").write(src)
        code, out, ms, _ = sh([RIDGUNC, "build", f"many{n}.rg", "-o", f"many{n}"], d, BUILD_SECONDS)
        times.append((n, ms, code))
    (n1, t1, c1), (n2, t2, c2) = times
    rows.append((f"toolchain: build time is near-linear in the number of functions ({n1} → {n2} functions: at most 8× the time; quadratic is 16×)",
                 c1 == 0 and c2 == 0 and t2 <= max(t1, 300) * 8, f"{n1} functions {t1:.0f} ms (exit {c1}), {n2} functions {t2:.0f} ms (exit {c2})"))
    return rows


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    head = subprocess.run(["git", "-c", f"safe.directory={REPO}", "log", "-1", "--format=%h %cd", "--date=format:%Y-%m-%d %H:%M"], cwd=REPO, capture_output=True, text=True).stdout.strip()
    ver = subprocess.run([RIDGUNC, "--version"], capture_output=True, text=True).stdout.strip().splitlines()[:1]
    print(f"ridgun {head}; {RIDGUNC} {' '.join(ver)}\n", flush=True)
    cases = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(CASES) for f in fs if f.endswith(".rg"))
    if args:
        cases = [c for c in cases if any(a in os.path.relpath(c, CASES) for a in args)]
    rows = []
    for c in cases:
        r = run_case(c)
        rows.append(r)
        print(("ok   " if r[1] else "FAIL ") + r[0] + ("" if r[1] else "\n       " + r[2]), flush=True)
    if "--no-toolchain" not in sys.argv and not args:
        for r in toolchain():
            rows.append(r)
            print(("ok   " if r[1] else "FAIL ") + r[0] + ("" if r[1] else "\n       " + r[2]), flush=True)
    failed = [r[0] for r in rows if not r[1]]
    print(f"\n{len(rows) - len(failed)} of {len(rows)} passed" + (":\n  " + "\n  ".join(failed) if failed else ""))
    sys.exit(1 if failed else 0)


main()
