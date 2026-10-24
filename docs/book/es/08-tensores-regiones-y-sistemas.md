# Capítulo 08: Tensores, Memoria Compilada RMM (`RMM1`/`RMM2`), Regiones y Sistemas

Hasta aquí hemos visto el lado más amable, elegante y matemático de Ridgun: funciones puras, tipos algebraicos, *pattern matching*, árboles de decisión con `|` / `|.` y grafos paralelos `||` con `->` que aprovechan todos los núcleos de tu procesador sin pedirte ni un triste `Mutex`.

Llegados a este punto, el programador veterano de sistemas suele levantar la mano al fondo del aula con media sonrisa y preguntar:

> *"Todo esto es precioso para calcular facturas o compilar ASTs, pero ¿qué pasa cuando necesito multiplicar matrices de millones de flotantes a velocidad de vértigo? ¿Qué pasa con la memoria? ¿Hay un recolector de basura (Garbage Collector) escondido debajo de la alfombra esperando el peor momento para congelar mi programa durante 200 milisegundos? ¿Y cómo hablo con el sistema operativo Unix de verdad?"*

Excelentes preguntas. Vamos a levantar el capó de Ridgun para ver cómo se las gasta cuando toca bajar al barro de los sistemas, el cálculo numérico y la memoria determinista.

---

## 8.1. El dilema de la memoria: ni Garbage Collector ni peleas con el Borrow Checker (`RMM1` y `RMM2`)

En el mundo de los lenguajes modernos suele haber dos bandos irreconciliables:

1. **El bando del Garbage Collector (Java, Go, Python, JS, Haskell, OCaml):** tú pides memoria alegremente y, de vez en cuando, un camión de la basura invisible detiene el tráfico de tu programa para rastrear qué objetos siguen vivos y cuáles no. Es comodísimo... hasta que estás haciendo una herramienta de sistema ultrarrápida o un servidor con latencias estrictas y el camión decide aparcar en doble fila.
2. **El bando del control manual / Borrow Checker (C, C++, Rust):** no hay recolector de basura, pero a cambio tienes que gestionar punteros a mano (jugándote un `Segmentation fault` o un *use-after-free*) o pasarte media tarde negociando con el *borrow checker* por qué `'a` no vive tanto como `'b`.

Ridgun resuelve este dilema de raíz con **Ridgun Memory Management (`RMM`)**, un sistema determinista de dos políticas complementarias (**`RMM1`** y **`RMM2`**) combinado con **regiones léxicas (`with region`)**:

### Política `RMM1` — Gestión de Memoria Compilada (CMM Lineal y Condicional)
Cuando el compilador conoce estáticamente el flujo de las variables locales dentro de una función:
- **CMM Lineal**: `ridgunc` calcula en tiempo de compilación cuál es la **última línea** en la que se lee cada variable local (`a`, `b`, ...) e inserta justo después su liberación determinista (`rg_cmm_drop`), o transfiere su propiedad sin copias (`rg_cmm_move`) cuando la variable se devuelve como resultado.
- **CMM Condicional (`ptr(a) != ptr(c)`)**: ¿y si una función como `elegir cond a b` devuelve `a` o `b` según una condición en tiempo de ejecución? `ridgunc` construye la tabla de ancestros y emite una guarda de identidad de punteros de **1 ciclo de CPU**: si `b` deja de usarse mientras `c` sigue viva, comprueba `if ptr(b) != ptr(c) { free(b) }`. La rama no elegida se libera al instante y la elegida sobrevive intacta.

### Política `RMM2` — Conteo por Asignación y Cascada Estructural
¿Y qué ocurre cuando metes estructuras dentro de otras estructuras (`xs = [a, b]`), reasignas variables mutables (`mut x = ...`) o encadenas llamadas complejas? Ahí entra **`RMM2`**, que gobierna todo el ciclo de vida con cuatro reglas matemáticas sin fisuras:

1. **Los argumentos de entrada de una función no se tocan (`+0` al entrar, `-0` al salir)**: pasar una lista o un registro a una función jamás incrementa ni decrementa contadores en vano.
2. **Toda asignación a una variable local interna o celda de contenedor suma `+1`**:
   - `a = [10, 20]` $\rightarrow$ el bloque `M1` nace con contador `1`.
   - `xs = [a, b]` $\rightarrow$ la lista `xs` nace con `1`, y como guarda referencias a `a` y `b`, ambos suben a `2`.
   - Si reasignas una variable mutable (`mut x = ...` y luego `x = nuevo`), `RMM2` aplica primero **`+1`** al valor nuevo antes de aplicar **`-1`** al antiguo.
3. **Al salir de la función, las variables locales que NO se devuelven reciben `-1`**: si el contador de una estructura llega a `0`, se libera su memoria en el acto y **propaga `-1` en cascada, uno por uno, a cada uno de sus hijos directos**.
4. **El valor devuelto por la función se exime en tránsito**: recibe su `-1` de variable local pero no se destruye al cruzar el `return`, de modo que cuando quien llamó hace `c = mi_funcion ()`, ese `+1` de la asignación lo deja exactamente en `1`.

```ridgun
elegir Bool [Int] [Int] => [Int]
elegir cond a     b     =
  | cond      = a
  | otherwise = b

ejemplo_rmm2 Bool => Int
ejemplo_rmm2 cond =
  a = [10, 20, 30]         -- M1 (rc = 1)
  b = [40, 50, 60]         -- M2 (rc = 1)
  c = elegir cond a b      -- `c` recibe +1; el no elegido muere aquí mismo (rc -> 0)
  (contar a) + (contar c)  -- Al terminar, `a` y `c` reciben -1 y todo queda en 0 bloques vivos
```

---

## 8.2. Regiones Léxicas con Cuota (`with region`): Cortafuegos de memoria en $O(1)$

Además de `RMM1` y `RMM2`, cuando estás procesando un paquete de red externo, un archivo gigante o un lote de datos no confiables y quieres poner un **techo estricto de memoria RAM**, envuelves el cálculo en un bloque **`with region`**:

```ridgun
procesar_trama String => Result
procesar_trama crudo  =
  with region 64_KB do
    limpias = map limpiar_linea (dividir_lineas crudo)
    contar_validos limpias
```

1. **Cuota garantizada en hardware/runtime**: si dentro del bloque se intenta reservar ni un solo byte por encima de `64_KB` (`65.536` bytes), el runtime aborta limpiamente el bloque, libera toda la arena temporal en tiempo constante $O(1)$ y devuelve `Err OutOfMemory` sin tumbar el proceso.
2. **Liberación instantánea al salir**: en cuanto termina el bloque `with region`, toda la memoria temporal de la arena desaparece de golpe sin dejar fragmentación.

---

## 8.3. Tensores Nativos, Contracción de Einstein (`@`) yDimensiones Simbólicas

Si alguna vez has programado en Python con NumPy o PyTorch, seguro que has sufrido el clásico error en el minuto 41 de ejecución:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

En Ridgun, los **`Tensor`** son ciudadanos nativos de primera clase y sus dimensiones forman parte de la firma de tipos:

```ridgun
-- Si entra (N × K) y (K × M), ¡por narices sale (N × M)!
multiplicar_matrices Tensor[N, K] Tensor[K, M] => Tensor[N, M]
multiplicar_matrices a            b            =  a_ik @ b_kj
```

Fíjate en dos detalles espectaculares:
1. **Verificación estática de dimensiones (`Tensor[N, K]`)**: el eje interno `K` de la primera matriz tiene que coincidir con el primer eje `K` de la segunda. Si intentas pasar dimensiones incompatibles, `ridgunc check` te detiene antes de ejecutar nada.
2. **Notación de subíndices de Einstein (`a_ik @ b_kj`) y Hadamard (`a_ij * b_j`)**:
   - Con **`@`**, los subíndices repetidos en todos los operandos (`k`) se contraen (se suman) y los únicos (`i`, `j`) sobreviven en el tensor resultado.
   - Con **`+`, `-`, `*`, `/`**, los subíndices alinean dimensiones y hacen *broadcasting* automático (`a_ij * b_j` multiplica cada fila `i` de `a` por el vector `b_j` sin necesidad de escribir `unsqueeze` ni `reshape`).
3. **Tensores tipados (`Tensor[T * d1 * d2]`), subíndices matemáticos `t_(i, j)`, vistas `t_(i,)` y mapeo *in-place* (`in`)**:
   Puedes declarar tensores multidimensionales con tipo escalar explícito (`U64`, `Int`, `Float`, `Byte`) inicializados a cero en una sola línea, indexarlos con subíndices matemáticos `t_(i, j)`, extraer vistas de fila `t_(i,)` o columna `t_(,j)` sin copiar memoria, desestructurar retornos múltiples directamente sobre celdas del tensor sin alojar tuplas en el heap, y aplicar funciones *in-place* sobre un eje con `map ... in` o `||map ... in`:
   ```ridgun
   fn :: blamka p16 Tensor[U64 * 16] => ()
         blamka p16 v                =
           v_(0), v_(4), v_(8), v_(12) = blamka g v_(0) v_(4) v_(8) v_(12)

   fn :: comprimir bloque Tensor[U64 * 8 * 16] Tensor[U64 * 8 * 16] => Tensor[U64 * 8 * 16]
         comprimir bloque x                    y                    =
           r_ij = x_ij xor y_ij
           z_ij = r_ij
           ||map blamka p16 in z_(i,)
           ||map blamka p16 in z_(,j)
           z_ij xor r_ij
   ```

---

## 8.4. Acceso a Hardware (`hardware ::`) y Primitivas POSIX de Sistemas

El propio compilador `ridgunc`, el gestor `stable` y utilidades de sistemas Unix están escritos en Ridgun. Para ello, el lenguaje incluye bloques de registros mapeados en memoria (`hardware ::`) y primitivas POSIX directas:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

Y para trabajar con el sistema operativo:

| Primitiva | Firma | Qué hace |
|---|---|---|
| `cli args` | `=> [String]` | Argumentos de línea de comandos (`argv`). |
| `read file` / `write file` | `String => String` / `String String => ()` | Lectura y escritura íntegra de archivos en disco. |
| `read bytes` / `write bytes` | `String => [Int]` / `String [Int] => ()` | Lectura y escritura binaria exacta byte a byte (`0..255`). |
| `list dir` / `file lstat` | `String => [String]` / `String => ...` | Listado de directorios e inspección de metadatos POSIX (`lstat`). |
| `sha256 file` / `sha256 str` | `String => String` | Hash criptográfico SHA-256 nativo en hexadecimal (64 caracteres). |
| `sha256 raw` / `sha256 bytes` | `String => String` | Digest SHA-256 binario crudo de 32 bytes (con soporte completo para bytes `0x00` intermedios y cero conversiones hex). |
| `sys exec` / `shell exec` | `... => Int` | Ejecución de procesos del sistema operativo. |
| `sys getcwd` / `sys chdir` | `=> String` / `String => Int` | Consultar o cambiar el directorio de trabajo. |
| `sys getenv` / `sys setenv` | `String => String` / `String String => Int` | Variables de entorno del proceso. |
| `sys getuid` / `sys getgid` | `=> Int` | UID y GID reales del proceso (`doas`, herramientas de seguridad). |
| `sys open mode` / `sys close` / `sys poll` | `String String => Int` / `Int => Int` / `Int Int Int => Int` | Descriptores PAL multiplataforma y `poll` acotado por `with timeout`. |
| `sys exit` | `Int => ()` | Terminar el proceso con código de salida. |

---

## 8.5. Caso de Estudio Real: Construyendo `rg-wc`, una utilidad Unix paralela

Vamos a unir todo lo aprendido desde el Capítulo 01 hasta aquí en un programa real de sistemas: una versión paralela de la herramienta Unix `wc` (contador de líneas y bytes para múltiples archivos) escrita en Ridgun puro:

```ridgun
-- 1. Modelamos las métricas de un archivo con un registro ADT (Capítulo 06)
type Metricas = archivo: String, lineas: Int, bytes: Int

-- 2. Contamos saltos de línea (código ASCII 10) con recursión de cola TCO (Capítulo 04)
fn :: contar saltos String Int Int Int => Int
      contar saltos texto  pos fin acum =
        | pos >= fin                    = acum
        | (str char at texto pos) == 10 = contar saltos texto (pos + 1) fin (acum + 1)
        | otherwise                     = contar saltos texto (pos + 1) fin acum

fn :: numero de lineas String => Int
      numero de lineas texto  =  contar saltos texto 0 (str len texto) 0

-- 3. Analizamos un archivo y devolvemos su estructura Metricas
fn :: analizar archivo String => Metricas
      analizar archivo ruta   =
        contenido = read file ruta
        || numero de lineas contenido -> n_lineas
        || str len contenido          -> n_bytes ||.
        Metricas ruta n_lineas n_bytes

-- 4. Formateamos cada fila y sumamos totales con `fold` y `||` (Capítulo 07)
fn :: formatear metrica Metricas => String
      formatear metrica m        =  "{lineas m}\t{bytes m}\t{archivo m}"

fn :: sumar lineas Int Metricas => Int
      sumar lineas acc m        =  acc + (lineas m)

fn :: sumar bytes Int Metricas => Int
      sumar bytes acc m        =  acc + (bytes m)

fn :: generar informe [String] => String
      generar informe rutas    =
        metricas = ||map analizar archivo rutas
        || map formatear metrica metricas -> filas
        || fold sumar lineas 0 metricas   -> total_l
        || fold sumar bytes 0 metricas    -> total_b ||.
        "{filas}\nTotal: {total_l} líneas, {total_b} bytes"

fn :: main => ()
      main =
        echo (generar informe ["README.md", "AGENTS.md"])
```

Párate un segundo a mirar esas ~40 líneas de código:
- No hay ni un solo `null`, ni una excepción descontrolada, ni un `Mutex`.
- `contar saltos` se compila a un `loop` nativo con 0 bytes de pila gracias al TCO automático.
- `||map analizar archivo rutas` procesa los archivos en paralelo en todos los núcleos de tu CPU, y el bloque `||` calcula simultáneamente las filas formateadas, el total de líneas y el total de bytes.
- La memoria temporal se libera determinísticamente mediante **`RMM1`/`RMM2`**.
- Y cuando ejecutas `ridgunc build rg_wc.rg -o rg-wc`, obtienes un binario nativo autónomo de ~350 KB listo para copiar a `/usr/local/bin`.

---

## 8.6. Hoja de Ruta Final: Las 10 Reglas de Oro del Programador Ridgun

1. **Escribe siempre primero el contrato (`=>`) y después las ecuaciones (`=`):** pensar en los tipos primero hace que el compilador trabaje para ti.
2. **Deja que `stable format` maquete tus tablas:** escribe con un espacio y deja que la herramienta alinee columnas, `=>`, `=` y `->`.
3. **Recuerda la regla universal del `=`:** detrás de cualquier `=` puedes abrir un bloque secuencial, un árbol de guardas `|` o un grafo paralelo `||`.
4. **Usa `|.` y `||.` solo cuando cierres un bloque anidado para volver a un nivel superior:** mantén los árboles de decisión profundos compactos y sin ambigüedad.
5. **Inmutable por defecto (`x = ...`), mutable explícito (`mut x = ...`):** usa `mut` únicamente cuando un acumulador local lo pida de verdad.
6. **Usa operadores booleanos claros en minúsculas (`and`, `or`, `xor`, `not`) y cierra siempre tus guardas con `| otherwise =`.**
7. **Modela tu dominio con ADTs (`type`):** usa registros con `with campo: valor` y tipos suma (`Option`, `Result`) en lugar de `null`.
8. **Paraleliza declarando dependencias con `|| expr -> var` y `||map` / `||filter`:** deja que el compilador verifique que no hay ciclos y reparta el trabajo entre los núcleos.
9. **Ponle dimensiones simbólicas a tus Tensores (`Tensor[N, K]`) y subíndices a tus contracciones (`a_ik @ b_kj`).**
10. **Confía en `RMM` (`RMM1`/`RMM2`), acota entradas externas con `with region` y verifica siempre con `stable check` y `stable test`.**

¡Feliz viaje programando en Ridgun!
