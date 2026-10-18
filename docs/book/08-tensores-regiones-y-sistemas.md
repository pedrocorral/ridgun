---
id: DOC-BOOK-08
title: "Capítulo 8 — Tensores, Regiones de Memoria y Programación de Sistemas"
status: active
last_updated: 2026-10-18
---

# Capítulo 8 — Tensores, Regiones de Memoria y Programación de Sistemas

Hasta aquí hemos visto el lado más amable, elegante y matemático de Ridgun: funciones puras, tipos algebraicos, *pattern matching* con guardas y grafos `where` que paralelizan tus cálculos sin pedirte ni un triste `Mutex`.

Llegados a este punto, el programador veterano de sistemas suele levantar la mano al fondo del aula con media sonrisa y preguntar:

> *"Todo esto es precioso para calcular facturas o compilar ASTs, pero ¿qué pasa cuando necesito multiplicar matrices de millones de flotantes a velocidad de vértigo? ¿Qué pasa con la memoria? ¿Hay un recolector de basura (Garbage Collector) escondido debajo de la alfombra esperando el peor momento para congelar mi programa durante 200 milisegundos? ¿Y cómo hablo con el sistema operativo Unix de verdad?"*

Excelentes preguntas. Vamos a levantar el capó de Ridgun para ver cómo se las gasta cuando toca bajar al barro de los sistemas, el cálculo numérico y la memoria determinista.

---

## 8.1 El dilema de la memoria: ni Garbage Collector ni peleas con el Borrow Checker

En el mundo de los lenguajes modernos suele haber dos bandos irreconciliables:

1. **El bando del Garbage Collector (Java, Go, Python, JS, Haskell, OCaml):** tú pides memoria alegremente y, de vez en cuando, un camión de la basura invisible detiene el tráfico de tu programa para rastrear qué objetos siguen vivos y cuáles no. Es comodísimo... hasta que estás haciendo un motor de audio en tiempo real, una herramienta de sistema ultrarrápida o un servidor con latencias estrictas y el camión decide aparcar en doble fila.
2. **El bando del control manual / Borrow Checker (C, C++, Rust):** no hay recolector de basura, pero a cambio tienes que gestionar punteros a mano (jugándote un `Segmentation fault` o un *use-after-free*) o pasarte media tarde negociando con el *borrow checker* de Rust por qué `'a` no vive tanto como `'b` dentro de un *closure* anidado.

Ridgun toma una tercera vía clásica de la literatura de compiladores (inspirada en el cálculo de regiones de Tofte y Talpin, MLKit y las arenas de sistemas): **gestión determinista de memoria basada en regiones léxicas (`region`)**.

### ¿Qué es exactamente un bloque `region`?

Piensa en una `region` como una **pizarra en blanco** (una *arena* de memoria contigua ultrarrápida) que pides prestada al entrar en un bloque de código:

```ridgun
fn :: procesar_lote_masivo [Str] => Int
procesar_lote_masivo lineas =
  region r
    limpias = map limpiar_linea lineas
    tokens  = map tokenizar limpias
    contar_validos tokens
```

Mira lo que ocurre aquí dentro:

1. **Al entrar en `region r`**: el runtime reserva una arena temporal asociada al identificador léxico `r`.
2. **Durante el bloque**: todas las estructuras intermedias (`limpias`, `tokens`, listas auxiliares, cadenas temporales...) se alojan en esa pizarra a velocidad de vértigo (un simple avance de puntero, *bump allocation*).
3. **Al salir de `region r`**: el compilador sabe estáticamente que el cálculo ha terminado. Conserva el valor de retorno (`Int`) y **destruye toda la región `r` de golpe en tiempo constante $O(1)$**, en el instante exacto en que termina la última línea del bloque.

Sin pausas aleatorias de un recolector de basura. Sin tener que escribir `free()` a mano en 14 sitios distintos. Y sin anotar lifetimes `'a` en cada firma de función.

---

## 8.2 Reglas de escape: nada roto sale de la habitación

*"Espera"*, dirás. *"¿Y qué pasa si dentro de `region r` construyo un puntero o un recurso atado a `r` e intento devolverlo hacia fuera cuando la región ya se ha destruido?"*

En C o C++, eso se llama *dangling pointer* (puntero colgante) y es la receta clásica para que tu programa explote tres horas después en producción.

En Ridgun, el verificador estático aplica la **regla de no-escape de regiones**:

* El tipo del valor final que devuelve un bloque `region r` **no puede contener referencias atadas a la región `r`**.
* Los valores puros o copiados al ámbito exterior (`Int`, `Float`, `Bool`, `Str`, `List`, ADTs ordinarios) pueden salir libremente del bloque `region r`.
* Pero cualquier recurso anclado explícitamente a la vida de `r` tiene prohibido cruzar la puerta de salida. Si lo intentas, `ridgunc` detiene la compilación en el acto y te señala la línea exacta.

Además, puedes anidar regiones si tienes un bucle o una fase interna que genera gigabytes de datos efímeros y quieres reciclar esa memoria en cada paso:

```ridgun
fn :: analizar_documento Str => (Int, Int)
analizar_documento texto =
  region r_externa
    parrafos = dividir_parrafos texto
    total_p  = length parrafos
    palabras =
      region r_interna
        listas_palabras = map extraer_palabras parrafos
        sumar_longitudes listas_palabras
    (total_p, palabras)
```

En cuanto `palabras` termina de calcularse, toda la memoria de `listas_palabras` dentro de `r_interna` desaparece inmediatamente, antes incluso de construir la tupla final `(total_p, palabras)`.

---

## 8.3 Tensores Tipados (`Tensor<DType, [Dims]>`): álgebra lineal sin sorpresas

Si alguna vez has programado en Python con NumPy, PyTorch o TensorFlow, seguro que has vivido esta escena de terror:

Lanzas un entrenamiento o un pipeline numérico pesado, se tira 40 minutos calculando con la GPU al 100%, y en el minuto 41 salta en tiempo de ejecución:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

O peor aún: las dimensiones *casi* coinciden gracias a una regla mágica e implícita de *broadcasting*, el programa no falla, y te pasas dos semanas publicando resultados numéricos silenciosamente erróneos.

En Ridgun, **las dimensiones y el tipo numérico de un tensor forman parte de su tipo estático**:

```ridgun
Tensor<DType, [D1, D2, ...]>
```

Donde:
* **`DType`** es el tipo escalar de los elementos (por ejemplo, `Float32`, `Float64`, `Int32`, `Int64`).
* **`[D1, D2, ...]`** son las dimensiones (ejes) del tensor: ya sean constantes enteras conocidas (`3`, `128`, `1024`) o variables simbólicas de dimensión (`N`, `M`, `K`, `Batch`).

### Ejemplos de firmas con tensores

Mira qué expresiva se vuelve una firma cuando el propio tipo te documenta la geometría de los datos:

```ridgun
-- Un vector de 3 componentes en precisión simple
fn :: normalizar Tensor<Float32, [3]> => Tensor<Float32, [3]>

-- Una imagen RGB en alta definición (Alto × Ancho × Canales)
fn :: convertir_a_gris Tensor<Float32, [1080, 1920, 3]> => Tensor<Float32, [1080, 1920]>

-- Multiplicación de matrices polimórfica en sus dimensiones:
-- Si entra (N × K) y (K × M), ¡por narices sale (N × M)!
fn :: multiplicar_matrices Tensor<Float32, [N, K]> Tensor<Float32, [K, M]> => Tensor<Float32, [N, M]>
```

Fíjate en la última firma: la dimensión interior `K` de la primera matriz `[N, K]` **tiene que ser la misma `K`** que la primera dimensión de la segunda matriz `[K, M]`. Si intentas multiplicar una matriz `[128, 64]` por una `[32, 128]`, **no tienes que esperar 40 minutos a que falle en ejecución**: el compilador subraya la llamada en menos de un segundo antes de generar el binario.

### El operador `@` (multiplicación matricial) y operaciones elemento a elemento

Ridgun incorpora el operador infijo `@` como ciudadano de primera clase para el producto matricial (o producto escalar de vectores), además de los operadores aritméticos habituales (`+`, `-`, `*`, `/`) para operaciones elemento a elemento entre tensores de idéntica forma:

```ridgun
-- Capa lineal clásica de una red neuronal: Y = (X @ W) + B
fn :: capa_lineal Tensor<Float32, [B, In]> Tensor<Float32, [In, Out]> Tensor<Float32, [B, Out]> => Tensor<Float32, [B, Out]>
capa_lineal x pesos sesgo = (x @ pesos) + sesgo
```

Al conocer estáticamente los tipos y las dimensiones `[B, In]` e `[In, Out]`, el compilador AOT puede emitir bucles nativos contiguos en memoria (listos para vectorización SIMD / AVX / NEON) sin comprobaciones dinámicas de rango en cada celda.

---

## 8.4 Programación de Sistemas y Primitivas POSIX / Sistema Operativo

Ridgun no nació para vivir encerrado en una torre de marfil académica: su propio compilador (`ridgunc`), su gestor de proyectos (`stable`) y utilidades clásicas de sistemas Unix (`ls`, `find`, `mtree`, `jot`, `rs`, `lam`, `vis`, `unvis`, `apply`, `make`, `sh`, `doas`) están escritos íntegramente en Ridgun.

Para lograrlo, el runtime nativo expone un conjunto directo y sin intermediarios de **primitivas de sistema**, organizadas por dominios:

### 1. Argumentos, Consola y Salida del Proceso

| Primitiva | Firma conceptual | Qué hace |
|---|---|---|
| `cli_args` | `() => [Str]` | Devuelve la lista de argumentos pasados por línea de comandos (`argv`). |
| `print` | `a => ()` | Imprime un valor en `stdout` seguido de salto de línea. |
| `eprint` | `a => ()` | Imprime un mensaje de error en `stderr`. |
| `sys_exit` | `Int => a` | Termina el proceso inmediatamente con el código de salida indicado (`0` éxito, `!= 0` error). |

### 2. Sistema de Archivos y Metadatos (POSIX `stat`, `lstat`, directorios)

| Primitiva | Firma conceptual | Qué hace |
|---|---|---|
| `fs_exists` | `Str => Bool` | Comprueba si existe una ruta en el sistema de archivos. |
| `fs_is_dir` | `Str => Bool` | Devuelve `True` si la ruta es un directorio. |
| `fs_read` | `Str => Str` | Lee el contenido completo de un archivo de texto. |
| `fs_write` | `Str Str => ()` | Escribe una cadena en un archivo (creando los directorios padre si hace falta). |
| `fs_mkdir` | `Str => ()` | Crea un directorio (`mkdir -p`). |
| `fs_rm` | `Str => ()` | Elimina un archivo o directorio recursivamente. |
| `fs_list_dir` | `Str => [Str]` | Lista los nombres de las entradas dentro de un directorio. |
| `fs_walk` | `Str => [Str]` | Recorre recursivamente un directorio devolviendo todos los archivos `.rg`. |
| `fs_stat_View` / `fs_lstat_View` | `Str => StatInfo` | Inspecciona permisos octales, UID/GID, tamaño, inodo, enlaces y marcas de tiempo (`mtime`). |
| `fs_chmod` / `fs_chown` | `... => Int` | Modifica permisos o propietario de archivos en disco. |

### 3. Procesos, Señales, Reloj y Entorno Unix

| Primitiva | Firma conceptual | Qué hace |
|---|---|---|
| `sys_run` | `Str => (Int, Str)` | Ejecuta un comando del sistema y devuelve `(exit_code, salida_combinada)`. |
| `env_get` / `env_set` | `Str => Str` / `Str Str => ()` | Lee o modifica variables de entorno del proceso. |
| `sys_getcwd` / `sys_chdir` | `() => Str` / `Str => Int` | Obtiene o cambia el directorio de trabajo actual. |
| `sys_getuid` / `sys_geteuid` | `() => Int` | Consulta el UID real o efectivo del usuario (esencial en herramientas como `doas`). |
| `clock_ms` | `() => Int` | Devuelve un reloj monotónico en milisegundos para medir tiempos con precisión. |
| `sha256_file` | `Str => Str` | Calcula el hash criptográfico SHA-256 de un archivo directamente en nativo. |

---

## 8.5 ¿Cómo produce Ridgun binarios nativos de ~350 KB?

Una de las sorpresas más gratas cuando compilas una herramienta en Ridgun con `ridgunc build` o `stable build` es mirar el tamaño y la velocidad del ejecutable resultante.

Mientras muchos lenguajes modernos de alto nivel generan binarios de 15 a 50 MB porque arrastran consigo medio recolector de basura, un motor de reflexión y toda su librería estándar aunque solo imprimas `"Hola"`, el compilador AOT de Ridgun aplica tres optimizaciones de ingeniería de compiladores que mantienen los binarios en torno a **300–400 KB**:

1. **Poda de Grafo de Llamadas (*Call-Graph Tree-Shaking* / DCE):**
   Cuando importas diez módulos llenos de utilidades, `ridgunc` construye el grafo de dependencias exacto partiendo de tu función `main`. Si tu programa usa ` dividir_lineas` de una librería pero no toca las otras 80 funciones de ese módulo, **esas 80 funciones ni siquiera se emiten al código nativo**. Solo viaja en el binario lo que es estrictamente alcanzable desde `main`.
2. **Optimización de Llamadas de Cola (*Tail-Call Optimization* / TCO a bucle nativo):**
   Como en Ridgun iteramos mediante recursión, un compilador ingenuo consumiría un marco de pila por cada elemento de una lista de un millón de líneas. `ridgunc` detecta automáticamente cuándo una función se llama a sí misma en posición de cola (al final de una rama o guarda) y **la transforma en un bucle `loop { ... continue; }` de máquina**, mutando los registros en el sitio con **consumo de pila $O(1)$ (cero bytes extra por iteración)**.
3. **Optimización AOT con LTO completo (`lto=fat`, `panic=abort`, `strip=symbols`):**
   El backend nativo enlaza con optimización global de tiempo de enlace (*Link-Time Optimization*), elimina tablas de *unwinding* innecesarias y limpia los símbolos DWARF de depuración, dejando únicamente código máquina puro y compacto.

---

## 8.6 Caso de Estudio Real: Construyendo `rg-wc`, una utilidad Unix paralela

Vamos a unir todo lo que has aprendido desde el Capítulo 1 hasta aquí en un programa real de sistemas: una versión moderna de la herramienta Unix `wc` (contador de líneas, palabras y bytes para múltiples archivos) que:

1. Usa **ADTs** para modelar el resultado de cada archivo.
2. Usa **guardas y *pattern matching*** para validar los argumentos de CLI.
3. Usa un **bloque `region`** para limpiar la memoria temporal al analizar cada archivo.
4. Usa un **bloque `where`** para procesar los resúmenes de forma declarativa y limpia.

```ridgun
module main

-- 1. Modelamos las métricas de un archivo con un ADT (Capítulo 6)
type Metricas = Metricas
  archivo :: Str
  lineas  :: Int
  bytes   :: Int

-- 2. Función pura para contar saltos de línea con recursión de cola (Capítulos 4 y 8.5)
fn :: contar_saltos Str Int Int Int => Int
contar_saltos texto pos limite acum
  | pos >= limite                      = acum
  | str_char_at texto pos == "\n"      = contar_saltos texto (pos + 1) limite (acum + 1)
  | otherwise                          = contar_saltos texto (pos + 1) limite acum

fn :: numero_de_lineas Str => Int
numero_de_lineas texto = contar_saltos texto 0 (str_len texto) 0

-- 3. Analizamos un archivo dentro de una región léxica temporal (Capítulo 8.1)
fn :: analizar_archivo Str => Metricas
analizar_archivo ruta
  | not (fs_exists ruta) = Metricas ruta 0 0
  | otherwise =
    region r_archivo
      contenido = fs_read ruta
      n_lineas  = numero_de_lineas contenido
      n_bytes   = str_len contenido
      Metricas ruta n_lineas n_bytes

-- 4. Formateamos una fila del informe con interpolación (Capítulo 5)
fn :: formatear_metrica Metricas => Str
formatear_metrica (Metricas ruta lin byt) =
  "{lin}\t{byt}\t{ruta}"

-- 5. Sumamos totales usando fold (Capítulo 7)
fn :: sumar_lineas Int Metricas => Int
sumar_lineas acc (Metricas _ lin _) = acc + lin

fn :: sumar_bytes Int Metricas => Int
sumar_bytes acc (Metricas _ _ byt) = acc + byt

-- 6. Procesamos la lista de archivos usando un grafo where (Capítulo 7)
fn :: generar_informe [Str] => Str
generar_informe rutas = "{cuerpo}\n{totales_lineas}\t{totales_bytes}\ttotal"
  where
    metricas       = map analizar_archivo rutas
    filas          = map formatear_metrica metricas
    cuerpo         = str_join filas "\n"
    totales_lineas = fold sumar_lineas 0 metricas
    totales_bytes  = fold sumar_bytes 0 metricas

-- 7. Punto de entrada del sistema
fn :: main => ()
main =
  args = cli_args ()
  if length args <= 1
    eprint "Uso: rg-wc <archivo1> [archivo2 ...]"
    sys_exit 1
  else
    rutas = drop 1 args
    print (generar_informe rutas)
```

Párate un segundo a mirar esas ~55 líneas de código.

* No hay ni un solo `null`, ni una excepción no controlada, ni una variable mutable global.
* El bucle `contar_saltos` se compila a un `loop` nativo con 0 bytes de gasto de pila gracias al TCO automático.
* En `generar_informe`, el bloque `where` descubre solo que `cuerpo`, `totales_lineas` y `totales_bytes` dependen de `metricas`, pero son independientes entre sí.
* Cada archivo se lee y procesa dentro de su propia `region r_archivo`.
* Y cuando ejecutas `ridgunc build main.rg -o rg-wc`, obtienes un binario nativo autónomo de unos ~370 KB listo para copiar a `/usr/local/bin`.

---

## 8.7 Hoja de Ruta Final: Las 10 Reglas de Oro del Programador Ridgun

Has llegado al final del libro. Si quieres tener una chuleta mental (o impresa junto al monitor) con la esencia de todo lo que hemos recorrido desde el Capítulo 00, aquí tienes los **10 mandamientos del buen código Ridgun**:

1. **Toda función lleva su pasaporte (`fn ::`):** escribe siempre primero el contrato de tipos y después las ecuaciones. Te ayudará a pensar antes de picar código y el compilador será tu mejor copiloto.
2. **Alinea tus `=` y tus `|`:** deja que `stable format` (o `ridgun-mode` en Emacs) mantenga tus ecuaciones y guardas como una tabla limpia que se lee de un vistazo.
3. **Usa *Pattern Matching* para la forma y Guardas (`|`) para las condiciones:** no anides escaleras infinitas de `if / else`. Desestructura el dato a la izquierda y filtra con guardas en cascada a la derecha.
4. **Cierra siempre con `| otherwise =`:** nunca dejes una función a merced de la casualidad; haz que tus guardas y patrones sean exhaustivos.
5. **Modela tu dominio con ADTs (`type`):** haz que los estados ilegales sean irrepresentables. Si una función puede fallar de forma esperada, devuelve un `Option<a>` o un `Result<a, e>` en lugar de valores mágicos como `-1` o `""`.
6. **Piensa en transformaciones (`map`, `filter`, `fold`):** evita escribir recursión manual cuando una combinación de funciones de orden superior expresa tu intención en una sola línea.
7. **Declara el *qué* con `where` y deja el *cómo* (y el paralelismo) al compilador:** agrupa los subcálculos independientes en un bloque `where` puro para que Ridgun construya el DAG y aproveche todos los núcleos de tu CPU sin *data races*.
8. **Ponle dimensiones a tus Tensores (`Tensor<DType, [Dims]>`):** deja que el compilador cace los errores de formas matriciales antes de ejecutar ni un solo cálculo.
9. **Acota la memoria temporal con `region`:** cuando proceses lotes grandes de datos intermedios, envuélvelos en una región léxica para liberar la memoria de forma determinista y en tiempo $O(1)$.
10. **Confía en `stable check` y `stable test`:** si pasa el verificador de tipos de Ridgun y tus tests en `src/test/ridgun/` están en verde, puedes desplegar tranquilo un viernes a las 18:00.

¡Feliz viaje programando en Ridgun!
