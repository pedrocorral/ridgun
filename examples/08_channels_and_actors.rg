-- ============================================================
-- 08_channels_and_actors.rg
-- Green threads (spawn/join), typed channels & receive timeout
-- ============================================================

fn :: compute_worker Int => Int
compute_worker x = x * x + 10

fn :: channel_and_spawn_demo => Int
channel_and_spawn_demo =
  ch = channel
  _ = send_through 42 ch
  msg = receive_from ch
  t1 = spawn "compute_worker" 5
  t2 = spawn "compute_worker" 6
  msg + (join t1) + (join t2)

fn :: timeout_demo => Int
timeout_demo =
  empty_ch = channel
  _ = receive from empty_ch timeout 25
  100

fn :: main => ()
main =
  echo "=== Ridgun 08: Channels, Actors & Green Threads ==="
  echo "channel_and_spawn_demo =>" channel_and_spawn_demo
  echo "timeout_demo           =>" timeout_demo
