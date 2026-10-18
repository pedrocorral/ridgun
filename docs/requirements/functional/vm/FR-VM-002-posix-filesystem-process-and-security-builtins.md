---
id: FR-VM-002
title: Native POSIX Filesystem, Process, and Security Built-ins
status: implemented
priority: must
created: 2026-10-17
updated: 2026-10-17
depends_on: [FR-VM-001]
verified_by: []
---
# FR-VM-002 — Native POSIX Filesystem, Process, and Security Built-ins

## Statement
The `ridgunc` runtime SHALL provide direct OS/POSIX built-in functions for filesystem inspection (`list_dir`, `file_lstat`, `sha256_file`, `sys_mkdir`, `sys_chmod`), process and environment management (`sys_exec`, `sys_chdir`, `sys_getcwd`, `sys_getenv`, `sys_setenv`, `sys_exit`), and privilege separation (`sys_getuid`, `sys_getgid`, `sys_username`, `sys_user_groups`, `sys_lookup_uid_gid`, `sys_setresgid`, `sys_setgroups`, `sys_setresuid`, `sys_execve`, `sys_read_pass`) without invoking `/bin/sh`.

## Functional Specification

### 1. Filesystem & Hierarchy Built-ins (for `ls`, `find`, `mtree`)
- **`list_dir : String => [String]`**: Returns sorted entry names in directory `path` (excluding `.` and `..`, or raw entries via `std::fs::read_dir`).
- **`file_lstat : String => (Bool, String, Int, Int, Int, String, String, Int, String)`**:
  - Inspects `path` via `lstat(2)` (not following symlinks) and returns `(exists, kind, mode, nlink, size, owner, group, mtime, symlink_target)` where `kind` is `"file"`, `"dir"`, `"link"`, `"fifo"`, `"sock"`, `"block"`, or `"char"`, and `mode` is the octal permission bits (`0o7777`).
- **`sha256_file : String => String`**: Computes the 64-character lowercase hex SHA-256 digest of `path`.
- **`sys_mkdir : String Int => Int`**: Creates directory `path` with mode `mode`, returning `0` on success.
- **`sys_chmod : String Int => Int`**: Sets permissions on `path` to `mode`, returning `0` on success.

### 2. Process & Environment Built-ins (for `apply`, `make`, `sh`)
- **`sys_exec : String [String] [String] => Int`**: Spawns executable `prog` directly (`Command::new(prog).args(args)`) without `/bin/sh` and returns its exit status code.
- **`sys_chdir : String => Int`**: Changes the current working directory of the running process (`std::env::set_current_dir`).
- **`sys_getcwd : => String`**: Returns the current working directory path.
- **`sys_getenv : String => String`**: Returns the value of environment variable `key` (or `""` if unset).
- **`sys_setenv : String String => Int`**: Sets environment variable `key = val` in the current process.
- **`sys_exit : Int => ()`**: Terminates the current process immediately with exit code `code` (`std::process::exit(code)`).

### 3. Security & Privilege Built-ins (for OpenBSD `doas`)
- **`sys_getuid : => Int`** and **`sys_getgid : => Int`**: Return real UID and GID of the calling process.
- **`sys_username : Int => String`**: Resolves a numeric UID to its username from `/etc/passwd`.
- **`sys_user_groups : String => [String]`**: Returns all group names to which `username` belongs (`/etc/passwd` primary GID + `/etc/group` supplementary memberships).
- **`sys_lookup_uid_gid : String => (Int, Int)`**: Resolves `username` to `(uid, gid)` (or `(-1, -1)` if not found).
- **`sys_setresgid : Int => Int`**, **`sys_setgroups : [Int] => Int`**, **`sys_setresuid : Int => Int`**: Drop or switch group and user credentials directly via libc/Linux syscalls.
- **`sys_execve : String [String] [String] => Int`**: Replaces the current process image (`execve`) with `prog`, `argv`, and explicit sanitized `envp` (`KEY=VAL` list), **never** invoking `/bin/sh`.
- **`sys_read_pass : String => String`**: Prints `prompt` to `/dev/tty` with terminal echo disabled (`termios`), reads one line, restores terminal state, and returns the password string.

## Acceptance Criteria
- AC1: `list_dir` and `file_lstat` inspect directories, permissions, sizes, timestamps, and symlinks without spawning a shell.
- AC2: `sys_exit 1` terminates the Ridgun binary with OS exit code `1`.
- AC3: `sys_exec` and `sys_execve` execute target binaries directly with argument vectors containing spaces or shell metacharacters without shell interpretation.
