-- ============================================================
-- 01_strings_and_io.rg
-- Interpolated strings, escaped braces, raw strings, echo & out
-- ============================================================

fn :: sum Int Int => Int
sum a b = a + b

fn :: greet String => String
greet name = "Hello, {name}!"

fn :: calc_msg => String
calc_msg = "Sum is {sum 3 4}"

fn :: escaped_msg => String
escaped_msg = "Use {{braces}}"

fn :: raw_msg => String
raw_msg = 'Raw string preserves {braces} without interpolation'

fn :: banner_out => ()
banner_out = "=== Ridgun 01: Strings & I/O ===" out

fn :: main => ()
main =
  _ = banner_out
  echo (greet "Alice")
  echo calc_msg
  echo escaped_msg
  echo raw_msg
