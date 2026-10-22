-- ============================================================
-- src/test/ridgun/test parallel and tensors.rg
-- Ridgun Test Suite: Parallel where-DAG, Tensors & Regions
-- ============================================================

import test

context :: active_tag => String
      active_tag =  "default-tag"

shared :: visit_count => Int
      visit_count =  10

fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  (fib (n - 1)) + (fib (n - 2))

fn :: fact Int => Int
      fact 0   =  1
      fact n   =  n * (fact (n - 1))

fn :: parallel dag calc => Int
      parallel dag calc =  a + b
        || fib 10       -> a
        || fact 6       -> b

fn :: tensor slice calc => Int
      tensor slice calc =
        m = Tensor [[1, 2], [3, 4]]
        m[0, 1] = 50
        m[0][1] + m[1][0]

fn :: tensor einsum hadamard Tensor Tensor => Int Int
      tensor einsum hadamard A      B      =
        c = A_ik @ B_kj
        h = A_ij + B_ij
        (c[0, 0] + c[1, 1], h[0, 0] + h[1, 1])

fn :: middle seq mask Int Int Int => Int
      middle seq mask (s)         =  s(_ + _)

type Result = Ok Int | QuotaExceeded

fn :: unwrap arena Result        => Int
      unwrap arena (Ok n)        =  n
      unwrap arena QuotaExceeded =  0 - 1

fn :: compute in arena => Result
      compute in arena =
        with region 64_KB do
          xs = [10, 20, 30]
          xs[1] + xs[2]

fn :: read active tag => String
      read active tag =  active_tag

fn :: compute in ctx => String
      compute in ctx =
        with active_tag = "phase3-region" do
          read active tag

fn :: scoped arena calc => Int String
      scoped arena calc =
        reg_val = unwrap arena (compute in arena)
        ctx_val = compute in ctx
        atomic visit_count = visit_count + 5
        (reg_val + visit_count, ctx_val)

fn :: main => ()
      main =
        echo "=== Parallel || DAG, Tensors, Einsum, Masks, Region, Context & Shared (Slots 38..52) ==="
        assert equals (parallel dag calc) 775
        assert equals (tensor slice calc) 53
        ta = Tensor [[1, 2], [3, 4]]
        tb = Tensor [[2, 0], [1, 2]]
        assert equals (tensor einsum hadamard ta tb) (12, 9)
        assert equals (middle seq mask 10 42 99) 42
        assert equals (read active tag) "default-tag"
        assert equals (scoped arena calc) (65, "phase3-region")
        assert equals (read active tag) "default-tag"
        echo "=== All parallel & tensor tests passed ==="
