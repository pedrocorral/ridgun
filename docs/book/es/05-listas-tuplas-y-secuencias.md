# Capítulo 05: Listas, Tuplas y el truco ninja de las Secuencias

Un programa que solo mueve un número o un texto a la vez sirve de poco. En la vida real manejas listas de archivos, filas de una base de datos, paquetes de red o coordenadas.

Para eso, Ridgun te da tres envases distintos, cada uno pensado para un trabajo muy concreto:
1. **Listas (`[T]`)**: *"Tengo muchos elementos del mismo tipo (o ninguno) y quiero recorrerlos"*.
2. **Tuplas (`(A, B)`)**: *"Quiero devolver un par o un trío de cosas distintas juntas sin crear un tipo nuevo"*.
3. **Secuencias y máscaras (`s(_ + _)`, `(+ _ _ +)`)**: *"Quiero filtrar o reordenar argumentos al vuelo como si tuviera un colador matemático"*.

Vamos una por una.

---

## 5.1. Listas (`[T]`): El pan de cada día

En Ridgun, si pones corchetes alrededor de un tipo, tienes una lista de ese tipo:
- `[Int]` es una lista de enteros: `[10, 20, 30]`.
- `[String]` es una lista de textos: `["manzana", "pera"]`.
- `[]` es la lista vacía (el comodín que encaja con cualquier `[T]`).

> *"Oye, ¿puedo meter un número y un texto juntos en la misma lista tipo `[1, "dos"]`?"*
> Tal cual, **no** (y dale las gracias al compilador por impedírtelo, porque así nunca te explotará una suma en producción al encontrarse un texto sorpresa). En el Capítulo 06 veremos cómo resolver el caso de `[1, "dos"]` con elegancia total usando un Tipo Algebraico (igual que hace Haskell).

### Cómo se trocea una lista sin usar índices `i`, `j`, `k`: `[]` y `(x:xs)`
En los lenguajes imperativos, recorrer una lista suele implicar `for (int i = 0; i < lista.size(); i++)`, con el clásico riesgo de pasarte por uno (*off-by-one*).

En Ridgun no cuentas índices; **desmontas la lista por la cabeza**:
- `[]`: encaja si la lista está vacía.
- `(x:xs)`: encaja si la lista tiene al menos un elemento. Mete el primer elemento en `x` (la **cabeza**) y el resto de la lista en `xs` (la **cola**).

Mira qué gusto da sumar una lista o contar cuántos elementos tiene:

```ridgun
fn :: sumar lista [Int]  => Int
      sumar lista []     =  0
      sumar lista (x:xs) =  x + (sumar lista xs)

fn :: contar elementos [A]    => Int
      contar elementos []     =  0
      contar elementos (_:xs) =  1 + (contar elementos xs)
```

Y un detalle técnico que te alegrará el día: en Ridgun, sacar la cola `xs` en `(x:xs)` **no copia el resto de la lista en memoria**. Internamente es una vista sobre el mismo vector que solo avanza el puntero de inicio en `1` ($O(1)$ instantáneo).

### Puedes destapar varios elementos de golpe
El patrón `:` da muchísimo juego cuando estás parseando comandos o protocolos:

```ridgun
fn :: interpretar comando [String]                  => String
      interpretar comando []                        =  "No has escrito nada"
      interpretar comando ("ayuda":_)               =  "Mostrando la ayuda..."
      interpretar comando ("copiar":origen:dest:[]) =  "Copiando de {origen} a {dest}"
      interpretar comando (cmd:_)                   =  "Comando desconocido: {cmd}"
```

Mira la tercera fila: `("copiar":origen:dest:[])` comprueba de un solo plumazo que la lista tenga **exactamente 3 elementos**, que el primero sea `"copiar"`, y te deja el segundo y el tercero servidos en bandeja en `origen` y `dest`. Intenta escribir eso en C o Java y verás cuántas líneas de `args.length == 3 && args[0].equals("copiar")` te salen.

### Unir listas con doble dos puntos (`::`)
Cuando estás en el lado derecho del `=` (en una expresión) y quieres pegar dos listas, usas **`::`**:

```ridgun
fn :: pegar listas [Int] [Int] => [Int]
      pegar listas a     b     =  a :: b

fn :: anadir detras [Int] Int => [Int]
      anadir detras xs    x   =  xs :: [x]
```

*(Regla mnemotécnica rápida: un solo `:` en los patrones desmonta la lista; dos `::` en las expresiones pegan dos listas).*

¿Y si de verdad quieres sacar el elemento número 5 directamente sin recorrer nada? Usa corchetes pegados al nombre: `mi_lista[5]`.

---

## 5.2. Funciones variádicas (`T...`): "¡Pásame todos los que quieras!"

A veces quieres que quien llame a tu función pueda escribir `sumar varios 4 19 2 88 7` cómodamente, sin obligarle a envolver los números entre corchetes `[4, 19, 2, 88, 7]`.

Pon tres puntos **`...`** detrás del último tipo de tu firma, y dentro de tu función lo recibirás automáticamente empaquetado como una lista:

```ridgun
fn :: sumar varios Int... => Int
      sumar varios nums   =  sumar lista nums

fn :: main => ()
      main =
        echo (sumar varios 10 20 30)       -- Imprime 60
        echo (sumar varios 1 2 3 4 5 6 7)  -- Imprime 28
```

---

## 5.3. Tuplas y la Unificación de Firmas con Espacios (`Int Int [String String] String`)

En muchos lenguajes devolver dos o más cosas desde una función es un dolor: o creas una clase auxiliar tonta `ResultadoConPosicion`, o llenas la firma de paréntesis y comas redundantes.

En Ridgun, **una lista de argumentos `Int String Int` y una tupla `(Int, String, Int)` son conceptualmente lo mismo: una secuencia tipada (`seq`)**. Por eso, en las firmas de tipos puedes separar los elementos de una tupla simplemente con **espacios**, tanto después de `=>`, como dentro de listas `[...]` y dentro de paréntesis `(...)`:

```ridgun
-- Dos enteros de retorno separados por espacio:
fn :: dividir y resto Int Int => Int Int
      dividir y resto a   b   =  (a / b, a % b)

-- Firma compleja sin ruido de comas ni paréntesis exteriores:
fn :: parsear cabecera String => Int Int [String String] String
      parsear cabecera tag    =  (200, 2, [("Host", "ridgun.org"), ("X-Tag", tag)], "OK")

-- Lista de tuplas [String String] como parámetro de entrada:
fn :: buscar cabecera [String String] String => String
      buscar cabecera []              _      =  "no encontrada"
      buscar cabecera ((k, v):resto)  clave
        | k == clave = v
        | otherwise  = buscar cabecera resto clave
```

Fíjate en la elegancia de `=> Int Int [String String] String`:
- Después de `=>`, `Int Int [String String] String` significa exactamente lo mismo que `(Int, Int, [(String, String)], String)`.
- Dentro de corchetes, `[String String]` significa una lista de pares de textos `[(String, String)]`.
- Dentro de paréntesis (cuando pasas una tupla como un único parámetro de entrada), `(Int String)` significa exactamente lo mismo que `(Int, String)`:
  ```ridgun
  fn :: explicar division (Int Int)         => String
        explicar division (cociente, resto) =  "Cabe a {cociente} y sobran {resto}"
  ```
- **¿Por qué esto no crea ninguna ambigüedad en Ridgun?** Porque a diferencia de Haskell (donde `Maybe Int` aplica un constructor de tipos por yuxtaposición), en Ridgun los tipos parametrizados usan paréntesis explícitos como `Tensor(Float, 3, 3)` y las listas usan `[T]`. Así, dos tipos separados por espacio (`T1 T2`) significan siempre y sin excepción una secuencia/tupla de tipos, manteniendo compatibilidad al 100% con la sintaxis con comas.

### El detalle estrella: Desempaquetado automático entre funciones
Supón que tienes `dividir y resto` (que devuelve `Int Int`) y otra función `sumar par Int Int => Int` (que espera 2 enteros). En Ridgun puedes enchufar una función dentro de la otra directamente:

```ridgun
fn :: sumar par Int Int => Int
      sumar par x   y   =  x + y

fn :: main => ()
      main =
        -- dividir y resto 17 5 devuelve (3, 2), y sumar par recibe 3 y 2 directamente:
        echo (sumar par (dividir y resto 17 5))  -- Imprime 5
```

---

## 5.4. El truco ninja: Secuencias y Máscaras Posicionales (`s(_ + _)`, `(+ _ _ +)`)

Aquí viene una de las joyas más originales de Ridgun, heredada directamente de los lenguajes vectoriales como J y APL.

Imagina que recibes una ristra de argumentos con el patrón de secuencia **`(s)`** y quieres quedarte solo con algunos y descartar otros sin declarar cinco variables con nombres inventados (`_a`, `b`, `_c`, `d`...).

Le aplicas a `s` una **máscara de tupla con `+` (quédatelo) y `_` (descártalo)**:

- **`s(_ + _)`**: de 3 elementos, descarta el primero (`_`), quédate con el segundo (`+`) y descarta el tercero (`_`).
- **`s(+ _ +)`**: quédate con el primero y el tercero; devuelve la secuencia con esos dos.
- **`s(_ _ +...)`**: descarta los dos primeros (`_ _`) y aplica `+...` **a todos los demás que vengan detrás**, sean cuantos sean.

Míralo funcionando:

```ridgun
fn :: el del medio Int Int Int => Int
      el del medio (s)         =  s(_ + _)

fn :: descartar dos primeros Int... => [Int]
      descartar dos primeros (s)    =  s(_ _ +...)

fn :: main => ()
      main =
        echo (el del medio 100 42 999)              -- Imprime 42
        echo (descartar dos primeros 1 2 10 20 30)  -- Imprime [10, 20, 30]
```

Mejor aún: puedes colocar una máscara **`(+ _ _ +)`** como una etapa intermedia dentro de una tubería **`->`** (`FR-COMP-014`). Cuando una función u operador devuelve una tupla de varios valores, la máscara filtra qué posiciones conservas (`+`) y cuáles descartas (`_`), y los elementos seleccionados se desempaquetan automáticamente como argumentos de la siguiente función de la tubería:

```ridgun
fn :: parsear paquete String => Int Int String String
      parsear paquete ver    =  (200, 4, ver, "OK")

fn :: combinar codigo Int  String => String
      combinar codigo code msg    =  "{code}:{msg}"

fn :: main => ()
      main =
        -- De (200, 4, "v0.9.9", "OK"), (+ _ _ +) selecciona el 1.º (200) y el 4.º ("OK")
        -- y los pasa como los 2 argumentos de `combinar codigo`:
        parsear paquete "v0.9.9" -> (+ _ _ +) -> combinar codigo -> resumen
        echo resumen  -- Imprime 200:OK
```

Además, si usas el operador coma `,` fuera de paréntesis (`lista1 , lista2`), Ridgun aplana ambas colecciones en una única secuencia continua.

En el **Capítulo 06** vamos a dar el paso que convierte a un programador funcional en un arquitecto de primera: **crear tus propios Tipos de Datos Algebraicos (ADTs), escribir funciones polimórficas con `A`..`Z` y fabricar tus propios operadores a medida**.
