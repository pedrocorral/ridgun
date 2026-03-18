# Ridgun Interop — FFI & Python Bridge

## Overview

Ridgun provides two complementary mechanisms for calling external code:

1. **FFI (Foreign Function Interface)** — Call C/C++ libraries directly. No Python, no GIL. Full parallelism.
2. **Python Bridge** — Call any Python library via an embedded CPython interpreter. Convenient but GIL-bound.

The two mechanisms coexist. Programmers choose based on their needs:

| Need | Use |
|---|---|
| Maximum performance, full parallelism | FFI |
| Access to Python-only libraries (sklearn, etc.) | Python Bridge |
| Libraries with C++ APIs (LibTorch, OpenCV) | FFI |
| Quick prototyping with Python packages | Python Bridge |

## FFI (Foreign Function Interface)

### How It Works

The FFI layer allows Ridgun code to call functions in shared libraries (`.so`, `.dylib`, `.dll`) written in C or any language with a C-compatible ABI.

```
Ridgun green thread
        │
        │ FFI_CALL
        ▼
┌──────────────────┐
│ libffi dispatch  │   Marshals Ridgun values → C types
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Native library  │   libtorch.so, libopencv.so, etc.
│  (C/C++ code)    │   Executes natively, fully parallel
└──────────────────┘
```

### Type Marshalling

Ridgun values are automatically converted to/from C types:

| Ridgun Type | C Type | Notes |
|---|---|---|
| `i32`, `i64` | `int32_t`, `int64_t` | Direct mapping |
| `f32`, `f64` | `float`, `double` | Direct mapping |
| `bool` | `_Bool` / `int` | 0/1 |
| `string` | `const char*` | Null-terminated, UTF-8 |
| `bytes` | `const uint8_t*` + `size_t` | Buffer + length |
| `ptr` | `void*` | Opaque pointer (unsafe) |

### Thread Safety

- FFI calls that are **non-blocking** execute directly on the worker thread. The green thread continues after the call returns.
- FFI calls marked as **blocking** (e.g., synchronous I/O) are dispatched to a **dedicated I/O thread pool** so they don't block the scheduler's worker threads.
- The programmer annotates blocking FFI calls. The VM handles the rest.

### Key Libraries Accessible via FFI

| Library | C/C++ API | Use Case |
|---|---|---|
| **LibTorch** | `libtorch` C++ API | Neural networks, GPU compute, inference |
| **OpenCV** | `opencv_core`, etc. | Computer vision, image processing |
| **OpenBLAS/LAPACK** | C API | Linear algebra, matrix operations |
| **SQLite** | `sqlite3.h` | Embedded database |
| **libcurl** | `curl.h` | HTTP requests |
| **ONNX Runtime** | C API | ML model inference |
| **TensorFlow** | C API | ML training and inference |

#### LibTorch Example (Conceptual)

LibTorch is PyTorch's official C++ API. It provides the same tensor operations, autograd, and neural network modules without any Python dependency.

What's available via LibTorch FFI:
- Tensor creation and manipulation
- Neural network layers (`nn::Linear`, `nn::Conv2d`, etc.)
- Autograd (automatic differentiation)
- GPU/CUDA operations
- Loading TorchScript models exported from Python
- Distributed training

What's **not** directly available:
- `torchvision` model zoo (Python-only, but models can be exported via TorchScript)
- Python-based data transforms (rewrite in Ridgun or use FFI to image processing libs)

The workflow for ML in Ridgun:
1. **Train** in Python with PyTorch (use the full ecosystem).
2. **Export** via `torch.jit.script()` or `torch.export()` to TorchScript.
3. **Load and run inference** in Ridgun via LibTorch FFI — fully parallel, no GIL.

## Python Bridge

### How It Works

The Python bridge embeds a **CPython interpreter** inside the Ridgun VM using [PyO3](https://pyo3.rs/) (Rust-Python bindings). This gives Ridgun access to **any** Python library installable via `pip`.

```
Ridgun green thread
        │
        │ PY_CALL (thread yields)
        ▼
┌──────────────────┐
│  PyO3 Bridge     │   Acquires GIL, marshals values
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  CPython         │   Executes Python code
│  interpreter     │   import pandas, sklearn, etc.
│  (GIL-bound)     │
└──────────────────┘
         │
         │ Returns result
         ▼
┌──────────────────┐
│  PyO3 Bridge     │   Releases GIL, marshals result back
└────────┬─────────┘
         │
         ▼
Ridgun green thread resumes
```

### GIL Isolation Strategy

The GIL (Global Interpreter Lock) is CPython's mutex that prevents true parallel execution of Python code. Ridgun handles this by treating Python calls as **async I/O**:

1. When a green thread calls `PY_CALL`, it **yields** to the scheduler.
2. The Python call is dispatched to a **dedicated Python worker thread**.
3. Other Ridgun green threads continue executing on the remaining worker threads.
4. When the Python call completes, the green thread is marked READY and re-enters the scheduler.

**The GIL only blocks other Python calls — not Ridgun green threads.**

```
Timeline:

Worker 0:  [T1: Ridgun] [T3: Ridgun] [T5: Ridgun] ...
Worker 1:  [T2: Ridgun] [T4: Ridgun] [T6: Ridgun] ...
Python W:  [T7: PY_CALL ████████████] [T8: PY_CALL ███] ...
                         GIL held here     GIL held here
```

Multiple concurrent `PY_CALL` requests are **serialized** by the GIL. If high Python throughput is needed, consider:
- Using FFI to the underlying C library instead.
- Batching work into fewer, larger Python calls.
- Using Python libraries that release the GIL internally (NumPy, pandas operations on large arrays).

### Type Marshalling (Python Bridge)

| Ridgun Type | Python Type | Notes |
|---|---|---|
| `i64` | `int` | Arbitrary precision on Python side |
| `f64` | `float` | IEEE 754 |
| `string` | `str` | UTF-8 |
| `bool` | `bool` | |
| `list<T>` | `list` | Deep conversion |
| `map<K,V>` | `dict` | Deep conversion |
| `bytes` | `bytes` | Zero-copy when possible |
| `None` | `None` | |

Complex Python objects (DataFrames, models, etc.) are returned as **opaque handles** — Ridgun holds a reference to the Python object without converting it to a native type. These handles can be passed back to subsequent Python calls.

## Choosing Between FFI and Python Bridge

```
                     Need a Python-only library?
                     (sklearn, transformers, etc.)
                           │
                     ┌─────┴─────┐
                     │           │
                    YES         NO
                     │           │
                     ▼           ▼
              Python Bridge   Does a C/C++ API exist?
                               │
                         ┌─────┴─────┐
                         │           │
                        YES         NO
                         │           │
                         ▼           ▼
                       FFI     Python Bridge
                   (parallel)  (GIL-bound)
```

## Python Environment

The Python bridge uses the system's Python installation (or a virtual environment if `VIRTUAL_ENV` is set). Dependencies are managed through standard `pip`:

```bash
# Install Python dependencies for use in Ridgun
pip install pandas scikit-learn transformers
```

The Ridgun VM discovers the Python installation at startup and initializes the embedded interpreter. Virtual environment support is automatic — if the VM is launched from within an activated venv, it uses that venv's packages.
