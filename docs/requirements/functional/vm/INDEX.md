# docs/requirements/functional/vm/ — Runtime I/O & POSIX Built-in Requirements (`VM`)

| Path | What | Read when |
|---|---|---|
| `FR-VM-001-verbatim-file-and-byte-stream-io.md` | Verbatim `read_file` (no import rewriting on data files, exact CRLF and EOF newline preservation) and binary `read_bytes`/`write_bytes` | Fixing `read_file` data fidelity and binary byte stream support |
| `FR-VM-002-posix-filesystem-process-and-security-builtins.md` | Native POSIX built-ins for directory/stat inspection (`list_dir`, `file_lstat`, `sha256_file`), process control (`sys_exec`, `sys_exit`), and privilege separation (`sys_getuid`, `sys_setresuid`, `sys_execve`) | Implementing OS primitives for BSD/Unix userland tools |
