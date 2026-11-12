---
id: FR-COMP-025
title: Opaque Types
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-12
updated: 2026-11-12
depends_on: [FR-COMP-005, FR-COMP-012]
related: [ADR-0006]
verified_by: [TS-COMP-025]
---
# FR-COMP-025 — Opaque Types

## Statement
A module SHALL be able to export a type while keeping to itself the right to create values of it and to look
inside them. The keyword `opaque` before `type` declares such a type.

```ridgun
module :: store

opaque type TenantScope = UnsafeTenantScope String
opaque type Session     = ss_user: String, ss_scope: TenantScope

fn :: sign in String => TenantScope          -- the only way other modules get a TenantScope
      sign in t =  UnsafeTenantScope t
```

## Terms
- **Defining module:** the module named by the `module ::` line above the `opaque type` declaration. A file with
  no `module ::` line belongs to the main module. Every file that declares the same module name is inside it.
- **Other module:** any module with another name, including the main module and library modules.

## Requirements
1. **Allowed everywhere.** Any module SHALL be able to name an opaque type in signatures, and to hold, pass,
   return and store its values, put them in lists, tuples, records and agent messages, and compare them with
   `==` and `!=`.
2. **Constructors are private.** A function of another module SHALL NOT compile when it:
   1. calls a constructor of the type, or names it as a value (`UnsafeTenantScope "x"`, `map UnsafeTenantScope xs`);
   2. builds an opaque record by position (`Session "u" scope`);
   3. matches a constructor of the type in a pattern, at any depth;
   4. reads a field of an opaque record with its accessor (`ss_user s`), or names the accessor as a value;
   5. updates an opaque record with `with`.
3. **No expansion.** An `expand type` of an opaque type SHALL NOT compile outside its defining module.
4. **Wildcards.** `_` and a plain variable SHALL still match an opaque value in other modules.
5. **Inside.** Every function of the defining module SHALL be able to do all of the above.
6. **Error message.** The error SHALL name the constructor or field, the type, its defining module and the
   function that broke the rule, for example:
   `constructor 'UnsafeTenantScope' of opaque type 'TenantScope' is private to module 'store' (used in function 'peek')`.
7. **Opt-in.** A type without `opaque` keeps its present behaviour. `opaque` changes nothing inside the defining
   module and nothing at run time.
8. **Libraries.** A `.ridgunlib` keeps its source, so the rules hold when a program that imports it is compiled. A
   native `.so` called from another language does not check them.

## Known limit
`echo` and string interpolation show an opaque value like any other value, with its constructor and fields. The
runtime printer is shared machine code in every backend; hiding the content there is a separate change. Do not
use an opaque type to keep a secret out of logs.

## Rationale
- A value can be a proof that a check was done: a validated address, an authenticated session, a tenant scope.
  The proof holds only when no other module can forge or open the value.
- Without this, each such rule is a naming convention and a source-scanning test that can be skipped.

## Acceptance criteria
- **AC1.** A module declares an opaque type and a function that returns one. The main module calls the function,
  stores the value, passes it to another function and compares two values with `==`. It compiles and runs.
- **AC2.** The main module calls the constructor: rejected with the type and module named.
- **AC3.** The main module matches on the constructor in a function clause: rejected.
- **AC4.** The main module reads a field of an opaque record with its accessor: rejected.
- **AC5.** The main module uses `with` on an opaque record, or `expand type` on the opaque type: rejected.
- **AC6.** Inside the defining module all of the above compile.
