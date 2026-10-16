-- ============================================================
-- 09_scoped_state_and_atomics.rg
-- global ::, context :: (with ... do inherited by spawn),
-- and shared :: (atomic updates)
-- ============================================================

global :: base_multiplier Int
base_multiplier = 10

context :: tenant_offset Int
tenant_offset = 1

shared :: total_requests Int
total_requests = 0

fn :: worker_with_context Int => Int
worker_with_context x = (x * base_multiplier) + tenant_offset

fn :: run_scoped_context => Int
run_scoped_context =
  with tenant_offset = 500 do
    t = spawn "worker_with_context" 7
    join t

fn :: run_atomic_counter => Int
run_atomic_counter =
  atomic total_requests = total_requests + 15
  atomic total_requests = total_requests + 27
  total_requests

fn :: main => ()
main =
  echo "=== Ridgun 09: Global, Context & Shared Atomic State ==="
  echo "run_scoped_context (with tenant_offset=500) =>" run_scoped_context
  echo "worker_with_context 7 (default offset=1)    =>" (worker_with_context 7)
  echo "run_atomic_counter                          =>" run_atomic_counter
