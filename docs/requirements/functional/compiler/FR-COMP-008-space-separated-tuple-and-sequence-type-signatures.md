---
id: FR-COMP-008
title: Unified Space-Separated Tuple and Sequence Type Signatures
status: implemented
priority: must
created: 2026-10-22
updated: 2026-10-22
depends_on:
  - FR-COMP-003
  - FR-COMP-005
verified_by: []
---
# FR-COMP-008 — Unified Space-Separated Tuple and Sequence Type Signatures

## Statement
The Ridgun language and `ridgunc` / `stable` toolchain SHALL unify the type syntax of argument sequences and tuples so that space-separated types (`T1 T2 ... Tn`) can be written without redundant commas or outer parentheses in return types, list brackets, and parenthesized tuple types:

1. **Space-Separated Return Types After `=>` / `->`**:
   - After `=>` or `->` in a `fn ::`, `op ::`, or prefixless signature, two or more space-separated type expressions `T1 T2 ... Tn` ($N \ge 2$) SHALL denote an $N$-element tuple/sequence return type equivalent to `(T1, T2, ..., Tn)`:
     ```ridgun
     fn :: parse header String => Int Int [String String] String
     -- Canonical equivalent:
     fn :: parse header String => (Int, Int, [(String, String)], String)
     ```
   - Each component `Ti` MAY be any valid type expression: a concrete or user-defined type (`Int`, `String`, `RExpr`), a polymorphic type variable (`A`..`Z`), a list type (`[...]`), or a parenthesized type (`(...)`).

2. **Space-Separated Tuple Elements Inside List Types (`[T1 T2 ... Tn]`)**:
   - Inside list brackets `[...]`, two or more space-separated (or comma-separated) type expressions `[T1 T2 ... Tn]` ($N \ge 2$) SHALL denote a list of $N$-tuples equivalent to `[(T1, T2, ..., Tn)]`:
     ```ridgun
     [String String]        -- equivalent to [(String, String)]
     [Int String Bool]      -- equivalent to [(Int, String, Bool)]
     [[Int Int] String]     -- equivalent to [([(Int, Int)], String)]
     ```

3. **Space-Separated Tuple Elements Inside Parentheses (`(T1 T2 ... Tn)`)**:
   - Inside parenthesized type expressions `(...)`, two or more space-separated (or comma-separated) type expressions `(T1 T2 ... Tn)` ($N \ge 2$) SHALL denote an $N$-tuple equivalent to `(T1, T2, ..., Tn)`, except when the parentheses contain a function arrow `=>` / `->` (which denotes a first-class function type `(T1 T2 => Ret)`):
     ```ridgun
     fn :: fst (A B) => A
           fst (a, _) =  a

     fn :: transform (Int [String String]) => Bool
     ```

4. **Top-Level Input Sequence vs. Nested Tuple Parameter**:
   - Before `=>` in a signature, space-separated types `fn :: compute Int String Int => Bool` define the top-level input sequence (3 positional arguments), whereas parenthesizing a subsequence `fn :: compute (Int String) Int => Bool` groups that subsequence into a single nested tuple parameter slot (2 positional arguments, where the first is a 2-tuple).

5. **100% Backward Compatibility & Canonical Normalization**:
   - Both the space-separated syntax (`Int Int [String String] String`) and the traditional parenthesized/comma-separated syntax (`(Int, Int, [(String, String)], String)`) SHALL normalize in `parser.rg` to the same canonical type string representation `"(Int, Int, [(String, String)], String)"`.
   - All existing Ridgun code using `(T1, T2)` and `[(T1, T2)]` SHALL remain 100% valid and interchangeable with the space-separated notation.

## Rationale
- **Conceptual Unity**: In Ridgun, a parameter list `Int String Int` and a tuple `(Int, String, Int)` are both typed sequences (`seq`). Requiring `Int String Int` on the left of `=>` while forcing `(Int, Int, [(String, String)], String)` on the right of `=>` introduced unnecessary punctuation noise.
- **Zero Syntactic Ambiguity**: Unlike languages of the ML/Haskell family—where juxtaposition in types (`Maybe Int`) denotes type constructor application—Ridgun uses explicit parentheses for parameterized types (`Tensor(Float, 3, 3)`) and brackets for lists (`[T]`). Furthermore, every type token starts with an uppercase letter (`A`..`Z`, `Int`, `String`), `[`, or `(`, while function and operator words are lowercase. Consequently, space-separated types `T1 T2` never collide with type constructors or operator keywords.

## Acceptance Criteria
1. **AC-1 (Space-Separated Return Types)**: A signature returning multiple space-separated types (including mixed identifiers, `[...]` lists, and `(...)` tuples, such as `=> Int Int [String String] String`) parses, typechecks, compiles, and runs identically to `=> (Int, Int, [(String, String)], String)`.
2. **AC-2 (List of Tuples `[T1 T2 ...]`)**: A list type with space-separated element types (`[String String]`, `[Int String Bool]`) parses and typechecks identically to `[(String, String)]` and `[(Int, String, Bool)]`.
3. **AC-3 (Parenthesized Space-Separated Tuples `(T1 T2 ...)`)**: Parenthesized tuple types `(A B)` and `(Int [String String] String)` work in parameter positions, return types, and nested type positions.
4. **AC-4 (Backward Compatibility)**: Existing signatures using explicit commas and parentheses (`(Int, Int, [(String, String)], String)`) continue to pass `stable check` and `stable test` without modification.
