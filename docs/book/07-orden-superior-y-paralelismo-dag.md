# Capítulo 07: Funciones de Orden Superior y Paralelismo sin Sudor (Ni `Mutex`, ni `Deadlocks`)

En casi todos los lenguajes de programación hay un momento dramático en la vida de un proyecto: el día en que alguien dice en una reunión:

> *"Esto va lento. Hay que paralelizarlo con hilos."*

Se hace el silencio en la sala. Todo el mundo sabe lo que viene después: semanas cazando *race conditions* fantasma que solo ocurren los martes con luna llena, bloqueos mutuos (*deadlocks*) y errores irreproducibles.

En Ridgun, cuando alguien dice *"hay que paralelizarlo"*, cambias tres letras (`map` por `pmap`, o pones tus cálculos en un bloque `where`) y te vas a tomar un café.

¿Por qué? Porque **cuando tus funciones son puras y tus datos son inmutables, dos núcleos de CPU trabajando a la vez jamás pueden pisarse la manguera**.

Vamos a verlo paso a paso.

---

## 7.1. Funciones que reciben funciones: `map`, `filter`, `fold` y el turbo `pmap`

En Ridgun una función es un valor más. Puedes pasarla por parámetro igual que pasas el número `7`.

El lenguaje trae de serie el cuarteto fantástico para transformar listas sin escribir ni una sola recursión manual:

### 1. `map` y `pmap`: Transformar cada elemento (en fila india o con todos los núcleos a la vez)
Supón que tienes una función `costoso Int => Int` y una lista con mil números:

```ridgun
costoso Int => Int
costoso x   =  (x * x) + (x * 3)

main => ()
main =
  datos = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Versión normal:
  r1 = map costoso datos
  -- Versión paralela multicore (work-stealing):
  r2 = pmap costoso datos
  echo r1
  echo r2
```

Fíjate en la diferencia entre `r1` y `r2`: **una sola letra (`p`)**.
- Con **`pmap`**, el runtime de Ridgun reparte los elementos de `datos` entre los hilos trabajadores de tu procesador y reconstruye la lista final **exactamente en el mismo orden**, garantizando que `pmap f xs == map f xs`.
- ¿Y si tu función hace efectos de entrada/salida (como imprimir en pantalla o escribir en un archivo) y quieres forzar a que vaya estrictamente de izquierda a derecha de uno en uno? Usas **`seq_map`**.

### 2. `filter` (y `seq_filter`): Quedarte solo con los que cumplan una condición
Le pasas una función que devuelva `Bool` (un *predicado*) y una lista:

```ridgun
es_positivo Int => Bool
es_positivo n   =  n > 0

main => ()
main =
  limpios = filter es_positivo [-5, 10, 0, -2, 42]
  echo limpios  -- Imprime [10, 42]
```

### 3. `fold` (también llamado `foldl` / `foldr`): Reducir toda una lista a un solo resultado
Le pasas una función combinadora de dos argumentos `(Acumulado Elemento => Acumulado)`, el valor inicial y la lista:

```ridgun
acumular_producto Int Int => Int
acumular_producto acc x   =  acc * x

main => ()
main =
  echo (fold acumular_producto 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### ¿Cómo escribo yo mi propia función que reciba otra función?
Muy fácil: en la firma de tipos pones la firma de la función invitada entre paréntesis `(Entrada => Salida)`:

```ridgun
ejecutar_dos_veces (A => A) A => A
ejecutar_dos_veces f        x =  f (f x)
```

---

## 7.2. La joya de la corona: Bloques `where` como Grafos Paralelos (DAGs)

Aquí es donde Ridgun cambia tu forma de pensar.

En un lenguaje imperativo normal, cuando escribes tres líneas seguidas:
1. Primero se ejecuta la línea 1.
2. Luego la línea 2 (aunque no tenga nada que ver con la línea 1).
3. Luego la línea 3.

Eso es obligar al ordenador a trabajar con orejeras. En Ridgun, cuando usas un bloque **`where`**, no estás dando órdenes secuenciales: estás dibujando un **Grafo Acíclico Dirigido (DAG)** con flechas `->` que dicen qué dato alimenta a qué variable:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_calculo => Int
super_calculo =  rama_izquierda + rama_derecha
  where
    fib 10  -> rama_izquierda
    fact 6  -> rama_derecha
```

Léelo en voz alta:
- *"Quiero calcular `rama_izquierda + rama_derecha`, **donde** (`where`) `fib 10` va a `rama_izquierda` (`->`) y `fact 6` va a `rama_derecha` (`->`)."*

### Lo que hace `ridgunc` entre bambalinas con tu `where`:
1. Mira las flechas `->` y arma el árbol de dependencias.
2. **Caza ciclos estáticamente**: si por error escribes `a + 1 -> b` y `b + 1 -> a`, el compilador te dice en el acto *"¡Quietos! Hay una dependencia circular en tu `where`"* y no te deja compilar un cuelgue infinito.
3. Ve que `fib 10` y `fact 6` no dependen el uno del otro, así que tienen luz verde para correr en paralelo antes de sumarse en `rama_izquierda + rama_derecha`.

Incluso puedes montar un pipeline de varias plantas dentro del mismo `where` y el compilador deducirá solito qué plantas pueden ir a la vez y cuáles tienen que esperar:

```ridgun
balance_trimestral Int => Int
balance_trimestral base =  beneficio_neto
  where
    base * 100              -> ventas_brutas
    base * 40               -> costes_fijos
    ventas_brutas - costes_fijos -> beneficio_bruto
    beneficio_bruto * 80 / 100   -> beneficio_neto
```

Aquí `ventas_brutas` y `costes_fijos` arrancan en paralelo; cuando ambos están listos se calcula `beneficio_bruto`, y de ahí sale `beneficio_neto`. Todo sin un solo `async`, `Future`, `Promise` ni `Mutex`.

---

## 7.3. El atajo `||`: Tuberías paralelas al vuelo

¿Y si solo quieres lanzar dos o tres cálculos en paralelo y recogerlos juntos en una tupla sin siquiera inventar nombres de variables en un `where`?

Usas la doble barra vertical **`||`**:

```ridgun
par_paralelo Int => (Int, Int)
par_paralelo n   =  (fib n) || (fact n)
```

Directo, visual y devuelve `(fib n, fact n)`.

---

## 7.4. Cuando quieres el volante manual: `spawn`, `join` y Canales CSP

El paralelismo automático de `where` y `pmap` cubre el 90% de los casos. Pero a veces estás programando un sistema de actores, una cola de trabajos o un pipeline productor-consumidor y quieres controlar tú mismo las tareas y los mensajes.

Para eso tienes dos herramientas limpias:

### 1. Lanzar tareas con `spawn` y recoger el resultado con `join`
```ridgun
procesar_lote Int => Int
procesar_lote id  =  id * 100

main => ()
main =
  tarea1 = spawn procesar_lote 1
  tarea2 = spawn procesar_lote 2
  -- Mientras tanto podrías hacer otras cosas aquí...
  res1 = join tarea1
  res2 = join tarea2
  echo "Terminaron con:" res1 "y" res2
```

### 2. Pasar mensajes por canales acotados (`new_bounded_channel`)
Igual que en Go o Erlang, en lugar de compartir memoria entre hilos, envías valores inmutables a través de un tubo seguro:

- `new_bounded_channel capacidad`: crea un canal con espacio para `capacidad` mensajes.
- `chan_send valor canal` (o `send_through valor canal`): mete un mensaje en el tubo.
- `chan_recv canal` (o `receive_from canal`): saca el siguiente mensaje del tubo.
- `chan_try_recv canal`: mira si hay mensaje sin quedarse esperando; devuelve `Some valor` o `None`.
- `receive_from_timeout canal ticks`: espera un límite de tiempo y devuelve `Ok valor` o `Err Timeout`.

```ridgun
main => ()
main =
  tubo = new_bounded_channel 4
  _ = chan_send "Tarea A completada" tubo
  _ = chan_send "Tarea B completada" tubo
  primero = chan_recv tubo
  segundo = chan_recv tubo
  echo primero "|" segundo
```

Y ahora, abróchate el cinturón para el **Capítulo 08**, el gran final: **tensores con dimensiones verificadas en compilación, variables de ámbito (`context`/`shared`), regiones de memoria deterministas, acceso directo a hardware MMIO y programación de sistemas UNIX/POSIX**.
