-- Ridgun Example Programs
-- Run with: ridgun run <filename> <function_name>

-- ============================================================
-- Basic Examples
-- ============================================================

-- Simple function calling
fn :: main1 => ()
main1 = echo "=== Basic Examples ==="

-- Arithmetic operations
fn :: demo_arithmetic => ()
demo_arithmetic =
  echo "Arithmetic:"
  echo "2 + 3 =" 5
  echo "10 - 4 =" 6
  echo "3 * 7 =" 21
  echo "15 / 3 =" 5

-- Recursion: Factorial
fn :: factorial Int => Int
factorial 0 = 1
factorial n = n * factorial (n - 1)

fn :: demo_factorial => ()
demo_factorial =
  echo "Factorial:" 
  echo "5! =" factorial 5
  echo "10! =" factorial 10

-- Recursion: Fibonacci
fn :: fib Int => Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)

fn :: demo_fib => ()
demo_fib =
  echo "Fibonacci:"
  echo "fib(10) =" fib 10
  echo "fib(15) =" fib 15

-- ============================================================
-- Pattern Matching Examples
-- ============================================================

fn :: main2 => ()
main2 = echo "=== Pattern Matching ==="

-- Multiple pattern cases
fn :: describe Int => String
describe 0 = "zero"
describe 1 = "one"  
describe 2 = "two"
describe n = "other"

fn :: demo_patterns => ()
demo_patterns =
  echo "describe(0) =" describe 0
  echo "describe(1) =" describe 1
  echo "describe(5) =" describe 5

-- Guard clauses
fn :: sign Int => String
sign n
  | n > 0 = "positive"
  | n < 0 = "negative"
  | otherwise = "zero"

fn :: demo_guards => ()
demo_guards =
  echo "sign(5) =" sign 5
  echo "sign(-3) =" sign (-3)
  echo "sign(0) =" sign 0

-- List patterns
fn :: sum_list [Int] => Int
sum_list [] = 0
sum_list (x:xs) = x + sum_list xs

fn :: demo_lists => ()
demo_lists =
  echo "sum([1,2,3,4,5]) =" sum_list [1, 2, 3, 4, 5]
  echo "sum([]) =" sum_list []

-- ============================================================
-- Tuple Examples  
-- ============================================================

fn :: main3 => ()
main3 = echo "=== Tuples ==="

-- Tuple patterns
fn :: swap (Int, String) => (String, Int)
swap (n, s) = (s, n)

fn :: demo_tuples => ()
demo_tuples =
  -- Note: Actual tuple syntax may need adjustment
  echo "Tuple examples shown in source"

-- ============================================================
-- Generic Examples
-- ============================================================

fn :: main4 => ()
main4 = echo "=== Generics ==="

-- Identity function (generic)
fn :: identity a => a
identity x = x

-- Length function (generic lists)
fn :: my_length [a] => Int
my_length [] = 0
my_length (_:xs) = 1 + my_length xs

fn :: demo_generic => ()
demo_generic =
  echo "my_length([1,2,3,4]) =" my_length [1, 2, 3, 4]
  echo "my_length([]) =" my_length []

-- ============================================================
-- Concurrency Examples
-- ============================================================

fn :: main5 => ()
main5 = echo "=== Concurrency ==="

-- Simple parallel computation
fn :: double Int => Int
double n = n * 2

fn :: demo_spawn => ()
demo_spawn =
  echo "Spawn example (simplified):"
  let t1 = spawn "double"
  let t2 = spawn "double"
  -- In a full implementation, would join and get results
  echo "Created threads"

-- ============================================================
-- Main demonstration
-- ============================================================

fn :: demo_all => ()
demo_all =
  demo_arithmetic
  demo_factorial
  demo_fib
  demo_patterns
  demo_guards
  demo_lists
  demo_tuples
  demo_generic
  demo_spawn
