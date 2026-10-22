# Capítulo 01: Tu primer contacto con Ridgun (Sin cascos, sin llaves y sin puntos y coma)

Vale, ya te he convencido en el Capítulo 00 de que no estamos locos por crear Ridgun. Ahora seguramente estés pensando:

> *"Muy bonito el discurso de las tablas y los 16 núcleos, pero enséñame código de verdad. ¿Cuánto tarda uno en escribir algo que funcione sin pelearse con el compilador?"*

Venga, ¡al turrón!

---

## 1.1. "¡Hola, mundo!", pero con chicha

En la mayoría de los libros de programación te enseñan un `print("Hola mundo")` soso y pasan de página. Nosotros vamos a escribir directamente una función con lógica real para que veas cómo respira Ridgun desde el minuto uno.

Crea un archivo llamado `hola.rg` y escribe esto:

```ridgun
saludo String => String
saludo ""     =  "¡Hola, viajero misterioso! (No me has dicho tu nombre)"
saludo "Root" =  "¡Hombre, Root! Cuidado con lo que borras hoy."
saludo nombre =  "¡Hola, {nombre}! Bienvenido a Ridgun."

main => ()
main =
  echo (saludo "Ada")
  echo (saludo "Root")
  echo (saludo "")
```

Para ejecutarlo ahora mismo:

```bash
ridgunc run hola.rg
```

Y verás en tu terminal:

```text
¡Hola, Ada! Bienvenido a Ridgun.
¡Hombre, Root! Cuidado con lo que borras hoy.
¡Hola, viajero misterioso! (No me has dicho tu nombre)
```

Para un momento y mira el bloque de `saludo` arriba. ¿Notas lo que **NO** hay?
- **No hay `function`, ni `def`, ni `pub fn`** (si quieres poner `fn ::` delante de la firma puedes hacerlo, pero es opcional).
- **No hay paréntesis `(String nombre)` ni llaves `{ ... }`** ensuciando la pantalla.
- **No hay `if (nombre == "") ... else if (nombre == "Root") ... else ...`**.
- **No hay `return`**.

---

## 1.2. Cómo lee tu cerebro un archivo `.rg`

Vamos a destripar esas cuatro líneas de `saludo`, porque aquí ya está el 50% de la filosofía de Ridgun:

```ridgun
saludo String => String
saludo ""     =  "¡Hola, viajero misterioso! (No me has dicho tu nombre)"
saludo "Root" =  "¡Hombre, Root! Cuidado con lo que borras hoy."
saludo nombre =  "¡Hola, {nombre}! Bienvenido a Ridgun."
```

1. **La primera línea es el contrato (`saludo String => String`)**:
   Dice: *"Me llamo `saludo`, recibo un `String` y te devuelvo (`=>`) otro `String`"*. Punto. Si alguien intenta llamarme pasándome el número `42`, el compilador le dará un toque en el hombro antes siquiera de ejecutar el programa.
2. **Las líneas de abajo son los casos (de arriba abajo)**:
   - ¿Me has pasado la cadena vacía `""`? Devuelvo la primera frase.
   - ¿Me has pasado exactamente `"Root"`? Devuelvo la segunda frase.
   - ¿Me has pasado cualquier otra cosa? La guardo en la variable `nombre` y la meto dentro del texto usando `{nombre}`.
3. **¿Y qué es `main => ()`?**:
   Como `main` no recibe argumentos, ponemos `=>` directamente después del nombre. Y devuelve `()` (el tipo vacío o *Unit*, para los amigos), porque su único trabajo es sacar cosas por pantalla con `echo`.

---

## 1.3. "Espera... ¿tengo que alinear esos espacios a mano como un monje copista?"

¡Ni de broma! Si tuvieras que darle a la barra espaciadora contando columnas a ojo, abandonarías Ridgun a los diez minutos (y con razón).

Tú escribes el código deprisa, con un solo espacio entre cada palabra:

```ridgun
saludo String => String
saludo "" = "¡Hola, viajero misterioso!"
saludo nombre = "¡Hola, {nombre}!"
```

Y cuando ejecutas **`stable format`** (o pulsas `TAB` / guardas el archivo en Emacs con `ridgun-mode`), el formateador canónico coloca cada parámetro debajo de su tipo y alinea todos los `=` con precisión milimétrica. Tú escribes rápido; la máquina maqueta la tabla.

---

## 1.4. De script rápido a binario de combate en un comando

Cuando haces `ridgunc run hola.rg`, estás compilando y lanzando el programa al vuelo. Pero imagina que ya has terminado tu herramienta y quieres llevártela a un servidor de producción o compartirla con un compañero que no tiene instalado Ridgun.

Ejecutas:

```bash
ridgunc build hola.rg -o hola
```

Y ya tienes `./hola`: un **ejecutable nativo ELF de Linux x86_64**, limpio, sin código muerto (*Tree-Shaking*), con optimización de enlace completo (*LTO*) y sin depender de ningún intérprete externo.

---

## 1.5. La chuleta honesta: ¿De dónde viene cada idea de Ridgun?

Ridgun no pretende reinventar la rueda cuadrada; toma prestado sin complejos lo mejor de cuatro tradiciones:

| De quién | Qué toma Ridgun | Qué deja fuera (por tu salud mental) |
|---|---|---|
| **Haskell / ML** | Funciones puras, *pattern matching* por casos, tipos algebraicos (`Option`, `Result`) y polimorfismo (`A`..`Z`). | Las mónadas abstractas, los 40 `LANGUAGE pragmas` y el recolector de basura. |
| **J / APL** | La obsesión por la forma tabular del código, tensores nativos y máscaras de secuencias (`s["-+-"]`). | Los símbolos jeroglíficos imposibles de escribir en un teclado normal. |
| **Rust / C** | Binarios ELF nativos pequeños, cero GC, control de memoria (`with region`) y llamadas al sistema POSIX. | La pelea constante con el *borrow checker*, los *lifetimes* `'a` y la verbosidad sintáctica. |
| **Erlang / Go** | Agentes aislados (`agent`, `send ... to`, `receive from`) y concurrencia por canales (`new bounded channel`). | Los punteros `nil` y las mutaciones compartidas por descuido. |

---

## 1.6. Y lo más importante: ¿Qué hace Ridgun que NO tiene nadie más?

Reconocer a los clásicos es de buena educación, pero si Ridgun fuera solo un "recopilatorio de grandes éxitos" de otros lenguajes, no estarías leyendo este libro.

Hay **siete cosas** que hemos diseñado e integrado en Ridgun que no vas a encontrar juntas —y muchas de ellas, ni siquiera por separado— en ningún otro lenguaje actual:

### 1. Bloques paralelos `||` con `->` que son grafos paralelos reales, no simple azúcar sintáctico
En otros lenguajes funcionales un bloque de variables locales solo ordena expresiones que luego se evalúan en un único hilo.
En Ridgun, **un bloque `||` con flechas `->` es un Grafo Acíclico Dirigido (DAG) de ejecución paralela** sin siquiera necesitar escribir palabras clave extra como `where`:
```ridgun
informe_anual Int => Int
informe_anual id  =  ingresos - gastos
  || calcular_ventas id -> ingresos
  || calcular_costes id -> gastos
```
Tú dibujas las flechas de flujo (`->`). El compilador analiza quién depende de quién, **verifica estáticamente que no hayas creado ningún ciclo infinito**, y lanza las ramas independientes en paralelo sin que escribas ni un solo `async`, `await`, `Future` ni `Mutex`.

### 2. El código como tabla bidimensional donde la firma es la cabecera de las columnas
En cualquier otro lenguaje, la firma de tipos va por libre en una línea y el cuerpo de la función va debajo como un párrafo de texto normal.
En Ridgun, **la firma de tipos es literalmente la cabecera de una tabla**, y cada caso debajo alinea cada patrón justo en la vertical de su tipo y cada `=` bajo el `=>`:
```ridgun
dividir Int Int => Option
dividir _   0   =  None
dividir a   b   =  Some (a / b)
```
Nadie más trata la firma y las ecuaciones como una única matriz visual verificada por el compilador y maquetada automáticamente por `stable format`.

### 3. Operadores frase (*Mixfix* N-arios) tipados y alineados (`op ::`)
En la mayoría de los lenguajes, o te aguantas con `+`, `-`, `*` o como mucho defines un operador binario críptico como `<|>` que nadie sabe qué significa.
En Ridgun puedes crear **operadores que son frases legibles con tantos huecos tipados como quieras** (incluyendo palabras contextuales como `type` o `with`):
```ridgun
op :: Int limitado_entre Int y Int => Int
      x   limitado_entre min y max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
Y luego en tu código escribes `velocidad limitado_entre 0 y 120`. Se lee como castellano (o inglés), pero está 100% tipado y compilado a código nativo.

### 4. Máscaras visuales sobre secuencias (`s(+ _)` y `s["-+-"]`)
¿Alguna vez has tenido que escribir una ensalada de índices `filter(\(i, x) -> i % 2 == 0)` solo para quedarte con los elementos pares o extraer un patrón rítmico de una lista?
En Ridgun le pasas directamente una **máscara visual**:
- `datos["-+-"]`: descarta el primero (`-`), se queda el segundo (`+`), descarta el tercero (`-`).
- `datos["+-~"]`: el símbolo `~` repite el patrón `+-` en bucle hasta el final de la lista (todos los índices pares de un plumazo).
Cero aritmética de índices, cero errores *off-by-one*.

### 5. Polimorfismo de "cero ruido" (`A`..`Z`) gobernado por tu dominio
En Rust, TypeScript o Java, cuando una función es genérica tienes que llenar la línea de paréntesis angulares: `fn intercambiar<A, B>(par: (A, B)) -> (B, A)`.
En Ridgun simplemente usas una letra mayúscula suelta:
```ridgun
intercambiar (A, B) => (B, A)
intercambiar (x, y) =  (y, x)
```
*"¿Y si en mi programa quiero tener un tipo real que se llame `type A`?"* — Ningún problema: en Ridgun **tus declaraciones `type` mandan**. Si no existe `type A`, `A` es genérico; en el instante en que defines `type A = ...`, pasa a ser tu tipo concreto en todo el módulo.

### 6. Cero archivos de configuración extraños: `build.rg` es Ridgun puro
Olvídate de aprender TOML para Cargo, JSON para npm, XML para Maven o la sintaxis arcana de `Makefile` con tabuladores invisibles. En Ridgun, la receta que construye tu proyecto (`build.rg`) **es un archivo `.rg` más**, con las mismas funciones puras y el mismo *pattern matching* que el resto de tu código.

### 7. La "Santísima Trinidad" que parecía imposible: Nivel Haskell + Memoria RMM sin GC ni Lifetimes + Binarios de ~350 KB
Hasta hoy tenías que elegir:
- Si querías expresividad funcional pura (Haskell, OCaml, Elixir), pagabas con un recolector de basura y un runtime pesado.
- Si querías binarios diminutos de sistema sin recolector de basura (C, Rust, Zig), pagabas gestionando punteros o peleándote con el *borrow checker* y escribiendo código imperativo lleno de `let mut`.

Ridgun rompe ese dilema combinando **Ridgun Memory Management (`RMM`: `RMM1` estática y `RMM2` por conteo de asignaciones en cascada)**, **regiones léxicas (`with region`)** que liberan arenas enteras en $O(1)$, **recursión de cola transformada en bucles nativos (`loop`)**, y **poda de grafo de llamadas (*Tree-Shaking*)** desde `main`. El resultado: escribes código declarativo de altísimo nivel y obtienes un ejecutable ELF autónomo de **~350 KB** capaz de competir de tú a tú con herramientas escritas en C.

Ahora sí: con las cartas sobre la mesa, vamos al **Capítulo 02** para poner a trabajar a **`ridgunc`** y **`stable`**.

