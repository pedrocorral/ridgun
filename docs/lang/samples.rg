-- ============================================================
-- Ridgun Language Samples
-- ============================================================

-- This is a comment
-- Functions are defined with fn ::
fn :: sum Int Int => Int
      sum a b     =  a + b

-- Operators
-- Operators are defined with op ::
op :: add Int to Int => Int
      add a   to b   =  a + b

-- Conf and Res are user-defined struct types (like Rust structs),
-- defined elsewhere by the programmer.
op :: run Conf and Conf in parallel => Res   Res
      run a and b in parallel       =  res_a res_b
        where
          run my own process a      -> res_a
          run my own process b      -> res_b

-- Non-finished code
op :: run my own process Conf => Result
      run my own process my_conf -- blah blah blah, more code here

-- Another syntax to run processes in parallel
op :: another way to run two processes Conf Conf in parallel => Res Res
      another way to run two processes a    b in parallel =
        | run my own process a
        | run my own process b

-- Overloading operators
-- Symbolic operators (+, *, etc.) have highest precedence - math first!
op :: Complex + Complex => Complex
      a + b = (real a) + (real b) + complex_i * ((imaginary a) + (imaginary b))

-- Pattern matching (Haskell-style)
fn :: factorial Int => Int
      factorial 0   = 1
      factorial n   = n * factorial (n - 1)

fn :: fib Int => Int
      fib 0   = 0
      fib 1   = 1
      fib n   = fib (n - 1) + fib (n - 2)

-- Algebraic Data Types
-- Product type (record)
type Conf = host String, port Int

-- Sum type (variants)
type Result = Ok Int | Err String
type Option = Some Int | None

-- Recursive type (tree still uses ADT since only lists are native)
type Tree = Leaf Int | Node Tree Tree

-- Constructor pattern matching
fn :: unwrap Result    => Int
      unwrap (Ok n)    = n
      unwrap (Err msg) = 0

fn :: sum_tree Tree              => Int
      sum_tree (Leaf n)          =  n
      sum_tree (Node left right) =  sum_tree left + sum_tree right

-- Native list types
-- Lists use [type] syntax and (x:xs) for cons-pattern matching
fn :: length [Int]  => Int
      length []     =  0
      length (_:xs) =  1 + length xs

fn :: sum_list [Int]  => Int
      sum_list []     =  0
      sum_list (x:xs) =  x + sum_list xs

fn :: reverse [Int] =>  [Int]
      reverse []     =  []
      reverse (x:xs) =  reverse xs :: [x]

-- Tensors
-- Mutable N-dimensional numeric type (Real by default, CPU)
-- Generalizes vectors, matrices, and higher-dimensional arrays

-- Creation
v = Tensor [1, 2, 3]                    -- 1D vector, shape: (3)
m = Tensor [[1, 2], [5, 3]]             -- 2D matrix, shape: (2, 2)
t = Tensor [[[1, 2], [3, 4]],           -- 3D tensor, shape: (2, 2, 2)
             [[5, 6], [7, 8]]]

-- Indexing (chained or comma-separated)
val = m[0][1]                            -- 2.0
val = m[0, 1]                            -- equivalent
row = m[0]                               -- Tensor [1, 2]

-- Mutation (in-place, PyTorch/NumPy style)
m[0, 1] = 5.0
m[0] = Tensor [10, 20]

-- Einstein notation: subscript indices for automatic contraction
-- Shared indices are summed, unique indices survive in the result
T = A_sdf * B_ndf                        -- T has shape (s, n)

-- Multi-tensor contraction in a single expression
R = A_abc * B_abc * C_abcd               -- R has shape (d)

-- GPU-resident tensors
g = Tensor_GPU [[1, 2], [3, 4]]
result = g_ij * g_jk                     -- GPU-accelerated matmul

-- Sequences (seq)
-- A seq is the implicit type of parameter and return lists
-- Flat join (:) concatenates two seqs
-- Nesting (,) creates a seq of seqs
-- Positional selector (<@_>) extracts elements by mask

fn :: first_of_seq Int Int => Int
      first_of_seq (s)     =  s(+ _)

fn :: first_of Int Int => Int
      first_of s   _   => s

fn :: swap_seq Int Int => Int Int
      swap_seq (s)     =  s(_ +) s(_ +)

fn :: swap_pair Int Int => Int Int
      swap pair a   b   =  b a

fn :: endpoints Int Int Int Int => Int Int
      endpoints (s)             =  s(+ _ _ _) s(_ _ _ +)

-- Additional way to extract elements from a seq
-- using their direct positions in the sequence.
fn :: extreme_points Int Int Int Int => Int Int
      extreme_points (s)             =  s(0 3)

op :: Int Int switch -> Int Int
      a   b   switch =  b   a

-- Output sequences may be used to input of other operators.
op :: Int Int invariant -> Int Int
      a   b   invariant =  a b switch switch