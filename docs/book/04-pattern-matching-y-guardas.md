# Capítulo 04: Adiós al `if/else`, adiós al `while` (Pattern Matching, Guardas y TCO)

Cuando le cuentas a alguien que en Ridgun **no existe la palabra clave `if`, ni `else`, ni `switch`, ni `for`, ni `while`**, suele mirarte como si le hubieras dicho que vas a construir una casa sin martillo ni clavos:

> *"¿Que no hay `if` ni `while`? ¿Y cómo narices tomo una decisión o recorro un millón de datos?"*

Pues resulta que `if/else` y `while` son herramientas bastante toscas heredadas de cómo funcionaban los saltos (`GOTO`) en los años 50. En Ridgun los sustituimos por tres piezas que encajan como un guante:
1. ***Pattern Matching*** (cuando decides según la **forma o valor exacto** del dato).
2. **Guardas booleanas `|`** (cuando decides según una **condición o rango**).
3. **Recursión de cola con TCO** (que el compilador convierte por debajo en un bucle `loop` nativo ultrarrápido).

Vamos a verlas en acción.

---

## 4.1. *Pattern Matching*: Cuando el argumento ya te da la respuesta

En el capítulo anterior ya vimos un adelanto. En lugar de recibir una variable genérica `x` y abrir dentro de la función cinco `if (x == ...)`, en Ridgun pones los casos directamente en la puerta de entrada de la función:

```ridgun
codigo_http Int => String
codigo_http 200 =  "OK: Todo fue sobre ruedas"
codigo_http 301 =  "Movido permanentemente"
codigo_http 404 =  "No encontrado (¿has mirado debajo del sofá?)"
codigo_http 500 =  "Fuego en el servidor"
codigo_http n   =  "Código desconocido: {n}"
```

Ridgun prueba las filas **de arriba abajo**:
- Si entra `404`, salta directo a la tercera fila.
- Si entra `418`, ninguna de las cuatro primeras filas coincide, así que cae en la última (`n`), que atrapa cualquier entero y lo nombra `n` para que puedas imprimirlo.
- ¿Y si en el último caso ni siquiera te importa qué número era? Pones un guion bajo `_` (*comodín*) y te olvidas: `codigo_http _ = "Otro código"`.

---

## 4.2. Guardas booleanas (`|`): Tu bisturí para rangos, variables condicionales y árboles de decisión

*"Vale, el pattern matching mola cuando busco el `200` o el `404`. ¿Pero qué hago si quiero comprobar si `nota >= 5` o si `edad > 18 and edad < 65`? ¡No voy a escribir 47 filas con todos los números del 18 al 65!"*

¡Claro que no! Para eso están las **guardas (`|`)**.

Cuando el resultado depende de una desigualdad o de una combinación lógica, después del `=` de la función (o de cualquier variable local) abres una escalera de barras verticales `|`:

```ridgun
calificar Int => String
calificar nota =
  | nota < 0   = "Nota imposible (¿puntos negativos?)"
  | nota < 5   = "Suspenso"
  | nota < 7   = "Aprobado"
  | nota < 9   = "Notable"
  | nota <= 10 = "Sobresaliente"
  | otherwise  = "Te has pasado de la escala"
```

Míralo bien:
- El signo `=` del encabezado (`calificar nota =`) se alinea debajo de `=>` igual que en cualquier otra función.
- Debajo se lee de arriba abajo igual que una tabla de tarifas: cada línea `| condicion = resultado` se comprueba en orden. En cuanto una da `True`, devuelve ese resultado y se acabó.
- Al final pones **`| otherwise = ...`**, que significa literalmente *"en cualquier otro caso"* (tu red de seguridad para que nunca quede un camino sin retorno).

### Lógica booleana en minúsculas claras (`and`, `or`, `xor`, `not`)
¿Te has fijado en que muchos lenguajes usan `|` para bits, `||` para booleanos, `!` para negar... y cuando lees una condición compleja parece que un gato ha caminado sobre el teclado (`if (!a && (b || c))`)?

En Ridgun, como `|` ya es el símbolo sagrado de las guardas y de los tipos algebraicos, y `||` es el operador de paralelismo, **los operadores booleanos se escriben con palabras claras en minúsculas**:

- **`and`**: se cumplen las dos cosas (`edad >= 18 and tiene_carnet`).
- **`or`**: se cumple al menos una (`dia == "sabado" or dia == "domingo"`).
- **`xor`**: se cumple una u otra, pero no las dos a la vez.
- **`not`**: invierte el booleano (`not (esta_vacio texto)`).

Mira qué limpio queda el clásico problema de los años bisiestos:

```ridgun
es_bisiesto Int => Bool
es_bisiesto a =
  | (a % 400) == 0                = True
  | (a % 4) == 0 and (a % 100) != 0 = True
  | otherwise                     = False
```

Cero símbolos crípticos. Lo lee alguien que no sabe Ridgun y lo entiende a la primera.

### Variables locales condicionales (`x =` + `|`)
Como en Ridgun todo `=` sigue la misma regla, **también puedes usar `|` para asignar una variable local** sin tener que crear una función auxiliar aparte:

```ridgun
precio_billete Int Bool => Int
precio_billete base es_familia_numerosa =
  descuento =
    | es_familia_numerosa = 20
    | base > 100          = 10
    | otherwise           = 0
  base - (base * descuento / 100)
```

### Árboles de decisión anidados y el limitador compacto `|.`
*"¿Y si dentro de una rama `| cond =` o `| otherwise =` quiero abrir otro sub-árbol de guardas `|` de 3 o 4 niveles de profundidad y luego volver a un nivel superior?"*

Puedes anidar `|` dentro de `|` tantos niveles como quieras. Y cuando un bloque `|` anidado termina pero debajo siguen más ramas de un nivel padre (o más sentencias del bloque), colocas **`|.`** al final de su última línea (`| otherwise = valor |.`) para indicar sin ninguna ambigüedad que ese sub-árbol se cierra y vuelves al nivel anterior:

```ridgun
enrutar_peticion Int    Int Bool      Bool     Int        Int       => Int
enrutar_peticion metodo rol firmada   es_admin tamano_kb  limitado  =
  | metodo == 0 =
    | tamano_kb == 0 = 204
    | otherwise      = 200 |.
  | metodo == 1 =
    | not firmada = 401
    | otherwise =
      -- Nivel 2: petición POST firmada
      | limitado > 0 =
        -- Nivel 3: control de rate-limit
        | es_admin =
          -- Nivel 4: excepción para administradores
          | tamano_kb > 10000 = 413
          | otherwise         = 202 |.
        | otherwise = 429 |.
      | tamano_kb > 1000 =
        -- Nivel 3: hemos vuelto desde el Nivel 4 gracias a `|.`
        | rol >= 2 and es_admin = 201
        | otherwise             = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Fíjate en lo limpio que es:
- En un árbol simple de 1 nivel (o al final de toda la función) **nunca hace falta poner `|.`** (sería ruido innecesario).
- Solo escribes `|.` al cerrar una rama anidada cuando debajo continúa una rama de un nivel superior.

### Bloques de varias líneas dentro de una guarda (`| cond =` + bloque indentado)
Igual que después del `=` de una función normal puedes abrir un bloque indentado de varias líneas, **después del `=` de cualquier guarda `| cond =` o `| otherwise =` también puedes hacer un salto de línea y abrir un bloque secuencial**:

```ridgun
ajustar_ventana Int Int => Int
ajustar_ventana idx limite =
  | idx >= limite =
      tope = limite - 1
      escalado = tope * 2
      escalado + 10
  | otherwise =
      siguiente = idx + 1
      siguiente * 2
```

Cada rama de la guarda tiene su propio bloque local limpio y su última línea es el valor que devuelve esa rama.

---

## 4.3. "¿Sin `while`? ¿Y no va a reventar la pila si recorro un archivo grande?"

Hablemos del elefante en la habitación.

Si vienes de Python, Java o JavaScript, te han enseñado desde pequeñito que *"la recursión es elegante en la pizarra de la universidad, pero en el mundo real desborda la pila (`StackOverflowError`) a las 1.000 vueltas; usa un bucle `while`"*.

Eso es verdad en lenguajes que **no** optimizan las llamadas de cola. Pero en un lenguaje funcional de sistemas como Ridgun, **una recursión de cola ES un bucle `while` disfrazado de función pura**.

### ¿Qué diferencia hay entre una recursión normal y una recursión de cola?
Fíjate en estas dos funciones que cuentan hacia atrás desde `n` hasta `0` sumando los números:

```ridgun
-- Versión A: Recursión NORMAL (deja trabajo pendiente para la vuelta)
sumar_lento Int => Int
sumar_lento 0   =  0
sumar_lento n   =  n + (sumar_lento (n - 1))

-- Versión B: Recursión DE COLA (lleva la cuenta al día en `acumulado`)
sumar_rapido_loop Int Int       => Int
sumar_rapido_loop 0   acumulado =  acumulado
sumar_rapido_loop n   acumulado =  sumar_rapido_loop (n - 1) (acumulado + n)
```

- En la **Versión A**, antes de poder sumar `n + ...`, la función tiene que esperar a que termine `sumar_lento (n - 1)`. Eso obliga al ordenador a guardar `n` en la pila en cada paso.
- En la **Versión B**, la llamada a `sumar_rapido_loop` **es lo último que ocurre en la línea**. No queda nada pendiente detrás de ella. Ya le pasas la suma actualizada en `acumulado + n`.

### El truco de magia de `ridgunc` (TCO: *Tail-Call Optimization*)
Cuando `ridgunc` compila `sumar_rapido_loop`, ve que la función se llama a sí misma al final de la cláusula y dice:

> *"¿Para qué voy a crear un marco de pila nuevo si el actual ya no sirve para nada? Voy a sobrescribir `n` con `n - 1`, sobrescribir `acumulado` con `acumulado + n` y saltar al principio con un `loop { ... continue; }` nativo."*

Resultado:
1. Puedes llamar a `sumar_rapido_loop 100_000_000 0` (cien millones de vueltas) y **gastará exactamente 0 bytes extra de pila**.
2. Va igual de rápido que un bucle `while` escrito a mano en Rust o C, pero sin haber tenido que declarar ni una sola variable mutable en tu código Ridgun.

---

## 4.4. El patrón maestro que usarás en todo programa Ridgun

Cada vez que en otro lenguaje pensarías *"voy a hacer un bucle `while` con un índice `i` y un acumulador"*, en Ridgun escribes una pareja de funciones como esta (la función principal limpia y su ayudante `_loop` de cola):

```ridgun
buscar_caracter_loop String Int Int Int     => Int
buscar_caracter_loop texto  pos fin buscado =
  | pos >= fin                        = -1
  | (str_char_at texto pos) == buscado = pos
  | otherwise                         = buscar_caracter_loop texto (pos + 1) fin buscado

buscar_caracter String Int     => Int
buscar_caracter texto  buscado =  buscar_caracter_loop texto 0 (str_len texto) buscado
```

Mira las tres guardas de `buscar_caracter_loop`:
1. ¿Llegué al final (`pos >= fin`)? Devuelvo `-1` (fin del bucle).
2. ¿Encontré el carácter en `pos`? Devuelvo `pos` (fin del bucle).
3. ¿No es este? Paso al siguiente (`pos + 1`) con una llamada de cola (que el compilador convierte en `continue;`).

Limpio, imposible de tener *bugs* de variables globales pisadas y rápido como un rayo.

En el **Capítulo 05** vamos a meterle mano a las colecciones de datos: **listas, tuplas, funciones que aceptan infinitos argumentos (`...`) y las máscaras de secuencias estilo J/APL**.
