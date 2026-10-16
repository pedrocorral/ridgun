-- ============================================================
-- 05_adts_overload_variadic.rg
-- Sum & Product ADTs, operator overloading by ADT, variadics (T...)
-- ============================================================

type Shape = Circle Int | Rectangle Int Int

fn :: shape_area Shape => Int
shape_area (Circle r) = 3 * r * r
shape_area (Rectangle w h) = w * h

type Complex = real Int, imag Int

op :: Complex + Complex => Complex
a + b = Complex (real a + real b) (imag a + imag b)

fn :: complex_sum_norm => Int
complex_sum_norm =
  c1 = Complex 3 4
  c2 = Complex 10 20
  c3 = c1 + c2
  (real c3) + (imag c3)

fn :: list_len [String] => Int
list_len [] = 0
list_len (_:xs) = 1 + list_len xs

fn :: count_tags String... => Int
count_tags tags = list_len tags

fn :: test_variadic_call => Int
test_variadic_call = count_tags "ridgun" "parallel" "functional" "vm"

fn :: main => ()
main =
  echo "=== Ridgun 05: ADTs, Operator Overloading & Variadics ==="
  echo "shape_area (Rectangle 6 7) =>" (shape_area (Rectangle 6 7))
  echo "complex_sum_norm           =>" complex_sum_norm
  echo "test_variadic_call         =>" test_variadic_call
