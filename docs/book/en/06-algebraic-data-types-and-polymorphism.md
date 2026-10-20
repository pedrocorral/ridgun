# Chapter 06: Algebraic Data Types (ADTs), Polymorphism, and Why We Don't Want `null` or `Any` Here

In 1965, Tony Hoare invented the null reference (`null` / `nil`). Forty years later he publicly apologized for it, calling it *"my billion-dollar mistake"*.

Why? Because in languages with `null`, a function promises in its type signature that it will return a `User`... and when you least expect it, it hands you `null` and crashes your production server at three in the morning.

The exact same problem happens with object inheritance and the `Any` (or `Object`) type: you put a number and a string into a list `[1, "two"]`, the language shrugs and says *"okay, this is now a `List[Any]`, good luck guessing what's inside when you iterate over it"*.

In Ridgun we cut both problems off at the root using **Algebraic Data Types (ADTs)** and **Parametric Polymorphism**. It sounds like a intimidating university course title, but in five minutes you will see that it is the most natural way in the world to model data.

---

## 6.1. Product Types (Records): Your Everyday `struct`, But with Superpowers

When you want to group several pieces of data that belong to the same entity (for example, a server with its hostname, port, and TLS status), you define a **`type`** with named fields:

```ridgun
type Server = host: String, port: Int, tls_enabled: Bool
```

By writing that single line, Ridgun automatically gives you **four things** for free:

### 1. The `Server` constructor
```ridgun
my_node => Server
my_node =  Server "api.example.com" 443 True
```

### 2. A pure *getter* function for every field (`host`, `port`, `tls_enabled`)
You don't write `s.getHost()` or anything like that; each field name is directly a function that extracts that piece of data:

```ridgun
connection_url Server => String
connection_url srv    =  "Connect to " + (host srv) + " on port {port srv}"
```

### 3. Functional record update (`with field: value`)
Imagine a configuration record with 12 or 15 fields (like the flags of an `ls` command or a web server) and you want to change just one or two fields without touching the rest. Instead of rebuilding the entire record by passing all 15 fields by hand, you use **`with`** and colons **`:`** (matching the exact syntax of the `type` definition):

```ridgun
enable_dev_mode Server => Server
enable_dev_mode srv    =  srv with port: 8080, tls_enabled: False
```

The best of both worlds:
- In your code it is **100% immutable and type-safe** (the compiler verifies that `port` and `tls_enabled` exist on `Server` and have the right types).
- Under the hood, if `srv` is not shared with anyone else, the native executable reuses its memory *in-place* (`Arc::try_unwrap`) without copying the remaining fields.

### 4. Full *pattern matching* whenever you want to unpack the record directly
```ridgun
is_secure_port Server              => Bool
is_secure_port (Server _ 443 True) =  True
is_secure_port _                   =  False
```

---

## 6.2. Sum Types (Variants with `|`): How to Retire `null`, Exceptions, and Class Hierarchies

Now for the really good part.
An ordinary record has `host` **AND** `port` **AND** `tls_enabled`.
But in the real world you often need to say: *"A payment method is **EITHER** a credit card with its number, **OR** a bank transfer with its IBAN, **OR** cash (which carries no extra data)"*.

In object-oriented programming you would have to create a `PaymentMethod` interface, three subclasses in three separate files, constructors, `instanceof` checks... In Ridgun it is **one line**:

```ridgun
type PaymentMethod = Card String Int | Transfer String | Cash
```

And look what happens when you process a `PaymentMethod` in a function:

```ridgun
describe_payment PaymentMethod   => String
describe_payment (Card num _)    =  "Card payment ending in {num}"
describe_payment (Transfer iban) =  "Bank transfer from account {iban}"
describe_payment Cash            =  "Cash payment at the counter"
```

Each variant (`Card`, `Transfer`, `Cash`) carries only the data that makes sense for it. It is **impossible** to construct a `Cash` payment with a dangling `iban` attached by mistake.

---

## 6.3. "So How Do I Put `[1, "two"]` in a List Without Using `Any`?"

Let's come back to the million-dollar question. Imagine you are reading a CSV or JSON file where a cell can be an integer, a text string, or empty.

If you had an `Any` type, you would stuff `[1, "two"]` into a list and lose all compiler assistance: from that point onward, every operation on the list would be walking blindfolded.

In Ridgun (just like in Haskell or Rust), it takes two seconds to define a sum type that states the exact kinds of values allowed inside that list:

```ridgun
type CellValue = Integer Int | Text String | Empty

format_cell CellValue   => String
format_cell (Integer n) =  "Number: {n}"
format_cell (Text s)    =  "Text: {s}"
format_cell Empty       =  "(empty)"

my_row => [CellValue]
my_row =  [Integer 1, Text "two", Empty]
```

See the difference?
- With `Any`, the compiler has no idea whether the list holds integers, strings, or a USB-connected coffee maker.
- With `[CellValue]`, you can freely mix numbers and strings in the same list, **while the compiler knows with 100% certainty that only those three cases exist** and forces you to unpack each case (`Integer n`, `Text s`, `Empty`) before using it. Total safety without sacrificing an ounce of flexibility.

---

## 6.4. `Option` and `Result`: When Something Might Be Missing or Might Fail

Because Ridgun has neither `null` nor uncaught exceptions flying through the call stack (`throw new Exception()`), the language ships with two built-in universal sum types:

1. **`Option`**: either you have **`Some value`**, or you have **`None`** (nothing).
2. **`Result`**: either the operation succeeded (**`Ok value`**), or it failed for a specific reason (**`Err error`**).

```ridgun
safe_divide Int Int => Result
safe_divide _   0   =  Err "Hey! Cannot divide by zero"
safe_divide a   b   =  Ok (a / b)

print_result Result    => ()
print_result (Ok n)    =  echo "The result is {n}"
print_result (Err msg) =  echo "Handled failure: {msg}"
```

Nobody can accidentally ignore an error because the `Result` type itself forces you to check whether there is an `Ok` or an `Err` inside.

---

## 6.5. Parametric Polymorphism: Generic Functions with `A`, `B`, `T`...

Suppose you write a function that swaps a pair `(x, y)` or extracts the first element of a list. Does it really matter whether the list holds `Int`, `String`, or `Server`? Not at all! The algorithm is identical.

In Ridgun, **any single uppercase letter (`A` through `Z`)** in a type signature automatically acts as a **polymorphic type wildcard (type variable)**:

```ridgun
safe_head [A]   A       => A
safe_head []    default =  default
safe_head (x:_) _       =  x

swap_pair (A, B) => (B, A)
swap_pair (x, y) =  (y, x)
```

Notice the magic of `safe_head [A] A => A`:
- It is not a lawless `Any`: it states that **the element type of the list `[A]`, the type of the fallback value `default` (`A`), and the return type (`A`) must all be the exact same type**.
- If you call `safe_head [10, 20] 0`, the compiler connects the dots (`A = Int`) and returns an `Int`.
- If you call `safe_head ["a", "b"] "none"`, it connects the dots (`A = String`) and returns a `String`.
- But if you try to cheat and call `safe_head [10, 20] "none"`, boom! The compiler stops you cold because the first argument says `A` is `Int` while the second says `A` is `String`.

---

## 6.6. Create Your Own Operators (`op ::`): From Vectors to Custom Phrases

Why should built-in numbers be the only types allowed to use `+` or `*`? And why settle for standard operators when you can invent the ideal syntax for your domain?

With **`op ::`** (or without a prefix when using operator patterns) you can pull off two neat tricks:

### 1. Teach `+`, `-`, `*`, `/`, `%` how to operate on your own types
```ridgun
type Complex = real: Int, imag: Int

op :: Complex + Complex => Complex
      a       + b       =  Complex ((real a) + (real b)) ((imag a) + (imag b))
```

### 2. Create *Mixfix* operators (which read like natural phrases, including `type` and `with`)
In an operator signature, **capitalized words (`Int`, `String`, `A`..`Z`) or bracketed/parenthesized types (`[Int]`, `(A, B)`) are the argument slots**, and **lowercase words become part of the operator phrase** (including everyday words like `type` or `with`, which are contextual in Ridgun and never get in your way):

```ridgun
op :: when Bool then A else_val A => A
      when True then v else_val _ =  v
      when False then _ else_val f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  message = when (10 > 5) then "Ten wins!" else_val "Impossible"
  echo message
  echo (format "panel" type "bordered" with 80)
```

You just built your own polymorphic ternary operator and a formatting DSL in **3 lines** of Ridgun.

In **Chapter 07** we will put every core of your processor to work at once without breaking a sweat: **higher-order functions (`map`, `||map`, `filter`, `||filter`, `fold`), parallel `||` graphs with `->`, and concurrent channels**.
