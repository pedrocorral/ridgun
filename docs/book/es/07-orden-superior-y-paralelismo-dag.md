# Capítulo 07: Funciones de Orden Superior y Paralelismo sin Sudor (Ni `Mutex`, ni `Deadlocks`)

En casi todos los lenguajes de programación hay un momento dramático en la vida de un proyecto: el día en que alguien dice en una reunión:

> *"Esto va lento. Hay que paralelizarlo con hilos."*

Se hace el silencio en la sala. Todo el mundo sabe lo que viene después: semanas cazando *race conditions* fantasma que solo ocurren los martes con luna llena, bloqueos mutuos (*deadlocks*) y errores irreproducibles.

En Ridgun, cuando alguien dice *"hay que paralelizarlo"*, basta con anteponer `||` a tus operaciones de lista (**`||map`** y **`||filter`**) o poner tus cálculos en un bloque paralelo **`||`** con flechas `->` y te vas a tomar un café.

¿Por qué? Porque **cuando tus funciones son puras y tus datos son inmutables por defecto, dos núcleos de CPU trabajando a la vez jamás pueden pisarse la manguera**.

Vamos a verlo paso a paso.

---

## 7.1. Funciones que reciben funciones: `map`, `||map`, `filter`, `||filter` y `fold`

En Ridgun una función es un valor más. Puedes pasarla por parámetro igual que pasas el número `7`.

El lenguaje trae de serie los combinadores de colecciones para transformar listas sin escribir ni una sola recursión manual, tanto en modo secuencial (`map`, `filter`, `fold`) como en modo paralelo multicore con el prefijo `||` (**`||map`**, **`||filter`**):

### 1. `map` (secuencial) y `||map` (paralelo multicore)
Supón que tienes una función `costoso Int => Int` y una lista con números:

```ridgun
costoso Int => Int
costoso x   =  (x * x) + (x * 3)

main => ()
main =
  datos = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Secuencial estricto de izquierda a derecha:
  r1 = map costoso datos
  -- Paralelo multicore con el prefijo `||`:
  r2 = ||map costoso datos
  echo r1
  echo r2
```

- Con **`map`**, Ridgun aplica la función elemento a elemento de izquierda a derecha en el hilo actual (ideal para listas pequeñas o funciones con efectos de entrada/salida ordenados).
- Con **`||map`**, el runtime de Ridgun reparte los elementos de `datos` entre los hilos trabajadores de tu procesador y reconstruye la lista final **exactamente en el mismo orden**, garantizando que `||map f xs == map f xs`.

### 2. `filter` (secuencial) y `||filter` (paralelo): Quedarte solo con los que cumplan una condición
Le pasas una función que devuelva `Bool` (un *predicado*) y una lista:

```ridgun
fn :: es positivo Int => Bool
      es positivo n   =  n > 0

fn :: main => ()
      main =
        limpios = filter es positivo [-5, 10, 0, -2, 42]
        limpios_par = ||filter es positivo [-5, 10, 0, -2, 42]
        echo limpios      -- Imprime [10, 42]
        echo limpios_par  -- Imprime [10, 42]
```

### 3. `fold`: Reducir toda una lista a un solo resultado
Le pasas una función combinadora de dos argumentos `(Acumulado Elemento => Acumulado)`, el valor inicial y la lista:

```ridgun
fn :: acumular producto Int Int => Int
      acumular producto acc x   =  acc * x

fn :: main => ()
      main =
        echo (fold acumular producto 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### ¿Cómo escribo yo mi propia función que reciba otra función?
Muy fácil: en la firma de tipos pones la firma de la función invitada entre paréntesis `(Entrada => Salida)`:

```ridgun
fn :: ejecutar dos veces (A => A) A => A
      ejecutar dos veces f        x =  f (f x)
```

---

## 7.2. La joya de la corona: Bloques `||` con `->` como Grafos Paralelos (DAGs)

Aquí es donde Ridgun cambia tu forma de pensar.

En un lenguaje imperativo normal, cuando escribes tres líneas seguidas:
1. Primero se ejecuta la línea 1.
2. Luego la línea 2 (aunque no tenga nada que ver con la línea 1).
3. Luego la línea 3.

Eso es obligar al ordenador a trabajar con orejeras. En Ridgun, cuando usas barras paralelas **`||`** con flechas **`->`** (sin necesidad de escribir ninguna palabra clave como `where`), no estás dando órdenes secuenciales: estás dibujando un **Grafo Acíclico Dirigido (DAG)** que dice qué cálculo alimenta a qué variable:

```ridgun
fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  (fib (n - 1)) + (fib (n - 2))

fn :: fact Int => Int
      fact 0   =  1
      fact n   =  n * (fact (n - 1))

fn :: super calculo => Int
      super calculo =  rama_izquierda + rama_derecha
        || fib 10 -> rama_izquierda
        || fact 6 -> rama_derecha
```

Léelo en voz alta:
- *"Quiero calcular `rama_izquierda + rama_derecha`, mientras en paralelo (`||`) `fib 10` va a `rama_izquierda` (`->`) y `fact 6` va a `rama_derecha` (`->`)."*

### Lo que hace `ridgunc` entre bambalinas con tus líneas `||`:
1. Mira las flechas `->` y arma el árbol de dependencias (DAG).
2. **Caza ciclos estáticamente**: si por error escribes `|| a + 1 -> b` y `|| b + 1 -> a`, el compilador te dice en el acto *"¡Quietos! Hay una dependencia circular"* y no te deja compilar un cuelgue infinito.
3. Ve que `fib 10` y `fact 6` no dependen el uno del otro, así que tienen luz verde para correr en paralelo antes de sumarse en `rama_izquierda + rama_derecha`.

Incluso puedes montar un pipeline de varias plantas dentro del mismo bloque `||` —ya sea al pie de la expresión o justo después del `=`— y el compilador deducirá solito qué plantas pueden ir a la vez y cuáles tienen que esperar:

```ridgun
fn :: balance trimestral Int  => Int
      balance trimestral base =
        || base * 100                  -> ventas_brutas
        || base * 40                   -> costes_fijos
        || ventas_brutas - costes_fijos -> beneficio_bruto ||.
        beneficio_bruto * 80 / 100
```

Fíjate en el detalle **`||.`** al final de la última línea `||`: igual que `|.` cierra un árbol de guardas anidado, **`||.`** cierra el bloque paralelo `||` cuando debajo siguen sentencias secuenciales normales. Aquí `ventas_brutas` y `costes_fijos` arrancan en paralelo; cuando ambos están listos se calcula `beneficio_bruto`, y finalmente se devuelve `beneficio_bruto * 80 / 100`. Todo sin un solo `async`, `Future`, `Promise` ni `Mutex`.

---

## 7.3. El atajo `||` sin nombres: Tuberías paralelas que devuelven una tupla

¿Y si solo quieres lanzar dos o tres cálculos en paralelo y recogerlos juntos en una tupla sin siquiera inventar nombres de variables con `->`?

Usas `||` directamente:

```ridgun
fn :: par paralelo Int => Int Int
      par paralelo n   =
        || fib n
        || fact n
```

Directo, visual y devuelve la tupla `(fib n, fact n)`.

---

## 7.4. Cuando quieres el volante manual: el Modelo Nativo de Agentes (`agent`, `send ... to`, `receive from`) y Canales CSP

El paralelismo automático de `||` y `||map` cubre el 90% de los casos. Pero cuando programas un servidor persistente, sesiones de usuario con estado aislado, colas de trabajo o un pipeline productor-consumidor, quieres **agentes concurrentes con memoria aislada y paso de mensajes tipado**.

En Ridgun no hace falta inventar una sintaxis extraña como `actor ::`: **cualquier función normal (`fn ::` u `op ::`) se convierte en un agente concurrente en una línea con `agent`**:

### 1. Agentes sin estado y con estado aislado (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (mi funcion)`: convierte una función `M => R` en un agente sin estado de tipo `Agent M R`.
- `ag = agent (mi funcion con estado) estado_inicial`: convierte una función `S M => S` (o `S M => S R`) en un agente con estado aislado que recuerda su estado mensaje tras mensaje sin un solo `Mutex`.
- `send msg to ag` (o con varios argumentos: `send a b to ag`): envía un mensaje tipado al buzón del agente.
- `res = receive from ag` (o `try receive from ag` sin bloquear): recoge la siguiente respuesta del buzón de salida del agente.
- `stop ag`: detiene el agente y libera su estado automáticamente mediante `RMM1`/`RMM2`.

```ridgun
fn :: sumar visita Int Int => Int
      sumar visita acum n  =  acum + n

fn :: procesar lote Int Int => Int
      procesar lote id  t   =  (id * 100) + t

fn :: main => ()
      main =
        contador = agent (sumar visita) 10
        send 5 to contador
        send 7 to contador
        v1 = receive from contador
        v2 = receive from contador
        stop contador

        trabajador = agent (procesar lote)
        send 3 25 to trabajador
        lote = receive from trabajador
        stop trabajador
        echo "Visitas:" v1 "->" v2 "| Lote:" lote
```

### 2. Elección inteligente en tiempo de compilación (*Green Threads* vs. Hilos Reales del Kernel)
Una pregunta habitual es: *"¿Los bloques `||`, `||map` y los agentes `agent` crean siempre hilos del sistema operativo o corren como tareas ligeras?"*

En Ridgun, **el compilador toma esa decisión por ti analizando estáticamente cada función**:
- **Funciones ligeras (`TierTrivial` / `StratInlineSequential`)**: Si la función que pasas a `||`, `||map`, `||filter` o `agent` tiene poca profundidad (aritmética, formateo de cadenas, transición de estado rápida de una sesión HTTP), calentar hilos del sistema operativo costaría más que el propio cálculo. El compilador la ejecuta como un paso *green-thread* ultraligero sin sobrecarga de `SYS_clone`.
- **Cálculos pesados o recursivos profundos (`TierDynamicRecursive` / `TierHeavyCPU`)**: Si la función tiene recursión profunda (como `fib` o `fact`) o álgebra de tensores (`einsum`, `hadamard`, `@`), el compilador genera automáticamente el despacho multinúcleo sobre **hilos reales del kernel (`SYS_clone`)**, procesando las ramas `||` o la cola de mensajes del `agent` en paralelo real sobre todos tus núcleos de CPU.

### 3. Pasar mensajes por canales acotados (`new bounded channel`)
Igual que en Go o Erlang, además de agentes también puedes crear tubos explícitos para comunicar etapas:

- `new bounded channel capacidad`: crea un canal con espacio para `capacidad` mensajes.
- `send through valor canal` (o `chan send valor canal`): mete un mensaje en el tubo.
- `receive from canal` (o `chan recv canal`): saca el siguiente mensaje del tubo.
- `try receive from canal`: mira si hay mensaje sin quedarse esperando; devuelve `Some valor` o `None`.
- `receive from timeout canal ticks`: espera un límite de tiempo y devuelve `Ok valor` o `Err Timeout`.

```ridgun
fn :: main => ()
      main =
        tubo = new bounded channel 4
        _ = send through "Tarea A completada" tubo
        _ = send through "Tarea B completada" tubo
        primero = receive from tubo
        segundo = receive from tubo
        echo primero "|" segundo
```

Y ahora, abróchate el cinturón para el **Capítulo 08**, el gran final: **tensores con dimensiones verificadas en compilación, variables de ámbito (`context`/`shared`), regiones de memoria deterministas, acceso directo a hardware MMIO y programación de sistemas UNIX/POSIX**.
