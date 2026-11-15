/* ============================================================
 * tests/wasm/wasi-host.c
 * Test host for wasm32 programs built by ridgunc (FR-COMP-026, ADR-0013).
 * The program is translated to C by wasm2c (module name "ridgun") and
 * linked with this file. It gives the program the WASI preview1 functions
 * the runtime's PAL imports, on top of the Linux calls:
 *   fd_write, fd_read, fd_close, proc_exit, clock_time_get, poll_oneoff
 *   (clock, fd_read and fd_write subscriptions), args_*, environ_*, fd_prestat_get,
 *   fd_prestat_dir_name, path_open, path_filestat_get, path_readlink,
 *   fd_readdir, path_create_directory, path_remove_directory,
 *   path_unlink_file, path_rename.
 * WASI file descriptors are the host's. Two directories are preopened:
 * fd 3 is "/" and fd 4 is "." (the directory the host runs in).
 * Test tool only: the playground's host is JavaScript (TASK-0089).
 * ============================================================ */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "wasm-rt.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"
#include "prog.h"

struct w2c_wasi__snapshot__preview1 {
  wasm_rt_memory_t* mem;
};
typedef struct w2c_wasi__snapshot__preview1 W;

static int g_argc;
static char** g_argv;
extern char** environ;

/* ── Memory ──────────────────────────────────────────────────── */
static int in_mem(W* w, uint64_t a, uint64_t n) { return a + n <= w->mem->size; }
static uint8_t* at(W* w, uint32_t a) { return w->mem->data + a; }
static uint32_t ld32(W* w, uint32_t a) { uint32_t v; memcpy(&v, at(w, a), 4); return v; }
static void st32(W* w, uint32_t a, uint32_t v) { memcpy(at(w, a), &v, 4); }
static void st64(W* w, uint32_t a, uint64_t v) { memcpy(at(w, a), &v, 8); }
static uint64_t ld64(W* w, uint32_t a) { uint64_t v; memcpy(&v, at(w, a), 8); return v; }

/* A NUL-terminated copy of the path at (p, n); NULL when out of memory. */
static char* path_of(W* w, uint32_t p, uint32_t n) {
  if (!in_mem(w, p, n)) return NULL;
  char* s = malloc((size_t)n + 1);
  memcpy(s, at(w, p), n);
  s[n] = 0;
  return s;
}

/* ── Errors: Linux errno -> WASI errno ───────────────────────── */
static uint32_t werr(int e) {
  switch (e) {
    case 0: return 0;
    case E2BIG: return 1;
    case EACCES: return 2;
    case EAGAIN: return 6;
    case EBADF: return 8;
    case EBUSY: return 10;
    case EEXIST: return 20;
    case EFAULT: return 21;
    case EINTR: return 27;
    case EINVAL: return 28;
    case EIO: return 29;
    case EISDIR: return 31;
    case ELOOP: return 32;
    case EMFILE: return 33;
    case ENAMETOOLONG: return 37;
    case ENOENT: return 44;
    case ENOMEM: return 48;
    case ENOSPC: return 51;
    case ENOSYS: return 52;
    case ENOTDIR: return 54;
    case ENOTEMPTY: return 55;
    case ENOTSUP: return 58;
    case EPERM: return 63;
    case EPIPE: return 64;
    case EXDEV: return 75;
    default: return 29;
  }
}

/* ── Streams ─────────────────────────────────────────────────── */
static uint32_t io(W* w, uint32_t fd, uint32_t iovs, uint32_t n, uint32_t out, int writing) {
  uint32_t total = 0;
  if (!in_mem(w, iovs, 8ull * n) || !in_mem(w, out, 4)) return 21;
  for (uint32_t i = 0; i < n; i++) {
    uint32_t base = ld32(w, iovs + 8 * i);
    uint32_t len = ld32(w, iovs + 8 * i + 4);
    if (!in_mem(w, base, len)) return 21;
    ssize_t r = writing ? write((int)fd, at(w, base), len) : read((int)fd, at(w, base), len);
    if (r < 0) {
      if (total > 0) break;
      return werr(errno);
    }
    total += (uint32_t)r;
    if ((uint32_t)r < len) break;
  }
  st32(w, out, total);
  return 0;
}

u32 w2c_wasi__snapshot__preview1_fd_write(W* w, u32 fd, u32 iovs, u32 n, u32 out) {
  return io(w, fd, iovs, n, out, 1);
}

u32 w2c_wasi__snapshot__preview1_fd_read(W* w, u32 fd, u32 iovs, u32 n, u32 out) {
  return io(w, fd, iovs, n, out, 0);
}

u32 w2c_wasi__snapshot__preview1_fd_close(W* w, u32 fd) {
  (void)w;
  if (fd <= 4) return 8; /* the standard streams and the preopens stay */
  return close((int)fd) == 0 ? 0 : werr(errno);
}

void w2c_wasi__snapshot__preview1_proc_exit(W* w, u32 code) {
  (void)w;
  fflush(stdout);
  _exit((int)code);
}

/* ── Clocks ──────────────────────────────────────────────────── */
u32 w2c_wasi__snapshot__preview1_clock_time_get(W* w, u32 id, u64 precision, u32 out) {
  (void)precision;
  struct timespec ts;
  if (!in_mem(w, out, 8)) return 21;
  if (clock_gettime(id == 0 ? CLOCK_REALTIME : CLOCK_MONOTONIC, &ts) != 0) return werr(errno);
  st64(w, out, (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec);
  return 0;
}

/* Clock subscriptions (relative timeouts) and fd_read / fd_write
   subscriptions, through poll(2): the events of the ready descriptors, or
   of the clock when the shortest timeout passed first. */
u32 w2c_wasi__snapshot__preview1_poll_oneoff(W* w, u32 in, u32 out, u32 n, u32 nout) {
  struct pollfd fds[16];
  uint32_t fsub[16];
  int nf = 0, timed = 0;
  uint64_t wait = 0;
  if (!in_mem(w, in, 48ull * n) || !in_mem(w, out, 32ull * n) || !in_mem(w, nout, 4)) return 21;
  for (uint32_t i = 0; i < n; i++) {
    uint32_t s = in + 48 * i;
    uint8_t tag = at(w, s + 8)[0];
    if (tag == 0) {
      uint64_t t = ld64(w, s + 24);
      if (!timed || t < wait) wait = t;
      timed = 1;
    } else if (nf < 16) {
      fds[nf].fd = (int)ld32(w, s + 16);
      fds[nf].events = tag == 1 ? POLLIN : POLLOUT;
      fds[nf].revents = 0;
      fsub[nf++] = s;
    }
  }
  int ready = 0;
  if (nf > 0) {
    int ms = timed ? (int)((wait + 999999ull) / 1000000ull) : -1;
    ready = poll(fds, (nfds_t)nf, ms);
    if (ready < 0) return werr(errno);
  } else if (timed && wait > 0) {
    struct timespec ts = {(time_t)(wait / 1000000000ull), (long)(wait % 1000000000ull)};
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) {}
  }
  uint32_t k = 0;
  for (int i = 0; i < nf && ready > 0; i++) {
    if (fds[i].revents == 0) continue;
    uint32_t e = out + 32 * k++;
    memset(at(w, e), 0, 32);
    st64(w, e, ld64(w, fsub[i]));
    at(w, e + 10)[0] = at(w, fsub[i] + 8)[0];
    if (fds[i].revents & POLLNVAL) at(w, e + 8)[0] = 8;
  }
  if (k == 0) {
    for (uint32_t i = 0; i < n; i++) {
      uint32_t s = in + 48 * i, e = out + 32 * k;
      if (at(w, s + 8)[0] != 0) continue;
      memset(at(w, e), 0, 32);
      st64(w, e, ld64(w, s));
      k++;
      break;
    }
  }
  st32(w, nout, k);
  return 0;
}

/* ── Arguments and environment ───────────────────────────────── */
static uint32_t sizes(W* w, char** v, int count, u32 cout, u32 sout) {
  uint32_t total = 0;
  if (!in_mem(w, cout, 4) || !in_mem(w, sout, 4)) return 21;
  for (int i = 0; i < count; i++) total += (uint32_t)strlen(v[i]) + 1;
  st32(w, cout, (uint32_t)count);
  st32(w, sout, total);
  return 0;
}

static uint32_t fill(W* w, char** v, int count, u32 ptrs, u32 buf) {
  for (int i = 0; i < count; i++) {
    uint32_t len = (uint32_t)strlen(v[i]) + 1;
    if (!in_mem(w, ptrs + 4ull * i, 4) || !in_mem(w, buf, len)) return 21;
    st32(w, ptrs + 4 * i, buf);
    memcpy(at(w, buf), v[i], len);
    buf += len;
  }
  return 0;
}

static int env_count(void) {
  int n = 0;
  while (environ[n]) n++;
  return n;
}

u32 w2c_wasi__snapshot__preview1_args_sizes_get(W* w, u32 c, u32 s) { return sizes(w, g_argv, g_argc, c, s); }
u32 w2c_wasi__snapshot__preview1_args_get(W* w, u32 p, u32 b) { return fill(w, g_argv, g_argc, p, b); }
u32 w2c_wasi__snapshot__preview1_environ_sizes_get(W* w, u32 c, u32 s) { return sizes(w, environ, env_count(), c, s); }
u32 w2c_wasi__snapshot__preview1_environ_get(W* w, u32 p, u32 b) { return fill(w, environ, env_count(), p, b); }

/* ── Preopened directories ───────────────────────────────────── */
static const char* preopen_name(u32 fd) { return fd == 3 ? "/" : fd == 4 ? "." : NULL; }

u32 w2c_wasi__snapshot__preview1_fd_prestat_get(W* w, u32 fd, u32 out) {
  const char* name = preopen_name(fd);
  if (!name) return 8;
  if (!in_mem(w, out, 8)) return 21;
  memset(at(w, out), 0, 8);
  st32(w, out + 4, (uint32_t)strlen(name));
  return 0;
}

u32 w2c_wasi__snapshot__preview1_fd_prestat_dir_name(W* w, u32 fd, u32 p, u32 n) {
  const char* name = preopen_name(fd);
  if (!name) return 8;
  if (n < strlen(name) || !in_mem(w, p, n)) return 28;
  memcpy(at(w, p), name, strlen(name));
  return 0;
}

/* ── Paths ───────────────────────────────────────────────────── */
#define RIGHT_READ (1ull << 1)
#define RIGHT_WRITE (1ull << 6)

u32 w2c_wasi__snapshot__preview1_path_open(W* w, u32 dirfd, u32 lookup, u32 p, u32 n, u32 oflags,
                                           u64 rights, u64 inherit, u32 fdflags, u32 out) {
  (void)inherit;
  char* path = path_of(w, p, n);
  if (!path || !in_mem(w, out, 4)) { free(path); return 21; }
  int flags = O_CLOEXEC;
  int rd = (rights & RIGHT_READ) != 0, wr = (rights & RIGHT_WRITE) != 0;
  if (oflags & 2) flags |= O_DIRECTORY | O_RDONLY;
  else if (rd && wr) flags |= O_RDWR;
  else if (wr) flags |= O_WRONLY;
  else flags |= O_RDONLY;
  if (oflags & 1) flags |= O_CREAT;
  if (oflags & 4) flags |= O_EXCL;
  if (oflags & 8) flags |= O_TRUNC;
  if (fdflags & 1) flags |= O_APPEND;
  if (fdflags & 4) flags |= O_NONBLOCK;
  if (!(lookup & 1)) flags |= O_NOFOLLOW;
  int fd = openat((int)dirfd, path, flags, 0666);
  int e = errno;
  free(path);
  if (fd < 0) return werr(e);
  st32(w, out, (uint32_t)fd);
  return 0;
}

static uint8_t filetype(mode_t m) {
  if (S_ISBLK(m)) return 1;
  if (S_ISCHR(m)) return 2;
  if (S_ISDIR(m)) return 3;
  if (S_ISREG(m)) return 4;
  if (S_ISSOCK(m)) return 6;
  if (S_ISLNK(m)) return 7;
  return 0;
}

static uint64_t ns_of(struct timespec t) { return (uint64_t)t.tv_sec * 1000000000ull + (uint64_t)t.tv_nsec; }

u32 w2c_wasi__snapshot__preview1_path_filestat_get(W* w, u32 dirfd, u32 lookup, u32 p, u32 n, u32 out) {
  char* path = path_of(w, p, n);
  struct stat st;
  if (!path || !in_mem(w, out, 64)) { free(path); return 21; }
  int r = fstatat((int)dirfd, path, &st, (lookup & 1) ? 0 : AT_SYMLINK_NOFOLLOW);
  int e = errno;
  free(path);
  if (r != 0) return werr(e);
  memset(at(w, out), 0, 64);
  st64(w, out, (uint64_t)st.st_dev);
  st64(w, out + 8, (uint64_t)st.st_ino);
  at(w, out + 16)[0] = filetype(st.st_mode);
  st64(w, out + 24, (uint64_t)st.st_nlink);
  st64(w, out + 32, (uint64_t)st.st_size);
  st64(w, out + 40, ns_of(st.st_atim));
  st64(w, out + 48, ns_of(st.st_mtim));
  st64(w, out + 56, ns_of(st.st_ctim));
  return 0;
}

u32 w2c_wasi__snapshot__preview1_path_readlink(W* w, u32 dirfd, u32 p, u32 n, u32 buf, u32 cap, u32 used) {
  char* path = path_of(w, p, n);
  if (!path || !in_mem(w, buf, cap) || !in_mem(w, used, 4)) { free(path); return 21; }
  ssize_t r = readlinkat((int)dirfd, path, (char*)at(w, buf), cap);
  int e = errno;
  free(path);
  if (r < 0) return werr(e);
  st32(w, used, (uint32_t)r);
  return 0;
}

/* Entries from index `cookie` on, as WASI dirents (24-byte header, then the
   name); a full buffer may end with a cut entry, as WASI allows. */
u32 w2c_wasi__snapshot__preview1_fd_readdir(W* w, u32 fd, u32 buf, u32 len, u64 cookie, u32 used) {
  if (!in_mem(w, buf, len) || !in_mem(w, used, 4)) return 21;
  int dfd = dup((int)fd);
  if (dfd < 0) return werr(errno);
  DIR* d = fdopendir(dfd);
  if (!d) { int e = errno; close(dfd); return werr(e); }
  rewinddir(d);
  uint64_t index = 0;
  uint32_t pos = 0;
  struct dirent* de;
  while (pos < len && (de = readdir(d)) != NULL) {
    if (index++ < cookie) continue;
    uint8_t head[24];
    uint32_t nl = (uint32_t)strlen(de->d_name);
    uint8_t t = de->d_type == DT_DIR ? 3 : de->d_type == DT_REG ? 4 : de->d_type == DT_LNK ? 7 : 0;
    uint64_t next = index, ino = (uint64_t)de->d_ino;
    memset(head, 0, sizeof head);
    memcpy(head, &next, 8);
    memcpy(head + 8, &ino, 8);
    memcpy(head + 16, &nl, 4);
    head[20] = t;
    uint32_t k = len - pos < 24 ? len - pos : 24;
    memcpy(at(w, buf + pos), head, k);
    pos += k;
    k = len - pos < nl ? len - pos : nl;
    memcpy(at(w, buf + pos), de->d_name, k);
    pos += k;
  }
  closedir(d);
  st32(w, used, pos);
  return 0;
}

static u32 path_call(W* w, u32 p, u32 n, int (*op)(char*, void*), void* arg) {
  char* path = path_of(w, p, n);
  if (!path) return 21;
  int r = op(path, arg);
  int e = errno;
  free(path);
  return r == 0 ? 0 : werr(e);
}

static int do_mkdir(char* p, void* fd) { return mkdirat(*(int*)fd, p, 0777); }
static int do_rmdir(char* p, void* fd) { return unlinkat(*(int*)fd, p, AT_REMOVEDIR); }
static int do_unlink(char* p, void* fd) { return unlinkat(*(int*)fd, p, 0); }

u32 w2c_wasi__snapshot__preview1_path_create_directory(W* w, u32 fd, u32 p, u32 n) {
  int d = (int)fd;
  return path_call(w, p, n, do_mkdir, &d);
}

u32 w2c_wasi__snapshot__preview1_path_remove_directory(W* w, u32 fd, u32 p, u32 n) {
  int d = (int)fd;
  return path_call(w, p, n, do_rmdir, &d);
}

u32 w2c_wasi__snapshot__preview1_path_unlink_file(W* w, u32 fd, u32 p, u32 n) {
  int d = (int)fd;
  return path_call(w, p, n, do_unlink, &d);
}

u32 w2c_wasi__snapshot__preview1_path_rename(W* w, u32 fd, u32 p, u32 n, u32 fd2, u32 p2, u32 n2) {
  char* a = path_of(w, p, n);
  char* b = path_of(w, p2, n2);
  int r = (a && b) ? renameat((int)fd, a, (int)fd2, b) : -1;
  int e = (a && b) ? errno : EFAULT;
  free(a);
  free(b);
  return r == 0 ? 0 : werr(e);
}

/* ── Start ───────────────────────────────────────────────────── */
/* The program runs on a thread with a large stack: each wasm call is a C
   call, and Ridgun programs recurse deeply. */
static void* run(void* arg) {
  (void)arg;
  static w2c_ridgun prog;
  static W wasi;
  wasm_rt_init();
  wasm2c_ridgun_instantiate(&prog, &wasi);
  wasi.mem = w2c_ridgun_memory(&prog);
  wasm_rt_trap_t trap = wasm_rt_impl_try();
  if (trap != WASM_RT_TRAP_NONE) {
    fflush(stdout);
    fprintf(stderr, "wasm trap: %s\n", wasm_rt_strerror(trap));
    _exit(134);
  }
  w2c_ridgun_ridgun_main(&prog);
  fflush(stdout);
  _exit(0);
  return NULL;
}

/* Put the directory at path on file descriptor fd. */
static void preopen(const char* path, int fd) {
  int d = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (d < 0) { perror(path); exit(1); }
  if (d != fd) {
    if (dup2(d, fd) < 0) { perror("dup2"); exit(1); }
    close(d);
  }
}

int main(int argc, char** argv) {
  pthread_attr_t attr;
  pthread_t t;
  g_argc = argc;
  g_argv = argv;
  preopen("/", 3);
  preopen(".", 4);
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, (size_t)1 << 30);
  if (pthread_create(&t, &attr, run, NULL) != 0) {
    perror("pthread_create");
    return 1;
  }
  pthread_join(t, NULL);
  return 0;
}
