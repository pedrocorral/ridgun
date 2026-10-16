-- ============================================================
-- 02_logic_and_math.rg
-- Int & Real (f64) math, % modulo, != inequality, AND/OR/XOR/NOT
-- ============================================================

fn :: is_odd Int => Bool
is_odd n = (n % 2) != 0

fn :: in_valid_window Int => Bool
in_valid_window x = x > 0 AND x < 100 AND NOT (x == 50)

fn :: xor_gate Bool Bool => Bool
xor_gate a b = a XOR b

fn :: or_gate Bool Bool => Bool
or_gate a b = a OR b

fn :: circle_area Real => Real
circle_area r = 3.14159 * r * r

fn :: celsius_to_fahrenheit Real => Real
celsius_to_fahrenheit c = c * 1.8 + 32.0

fn :: classify_number Int => String
classify_number n
  | n < 0 = "negative"
  | n == 0 = "zero"
  | (n % 2) == 0 = "positive-even"
  | otherwise = "positive-odd"

fn :: main => ()
main =
  echo "=== Ridgun 02: Logic & Math ==="
  echo "is_odd 7                 =>" (is_odd 7)
  echo "in_valid_window 42       =>" (in_valid_window 42)
  echo "in_valid_window 50       =>" (in_valid_window 50)
  echo "xor_gate True True       =>" (xor_gate True True)
  echo "celsius_to_fahrenheit 100=>" (celsius_to_fahrenheit 100.0)
  echo "classify_number 13       =>" (classify_number 13)
