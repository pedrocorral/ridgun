# Capítulo 05: Listas, Tuplas y el truco ninja de las Secuencias

Un programa que solo mueve un número o un texto a la vez sirve de poco. En la vida real manejas listas de archivos, filas de una base de datos, paquetes de red o coordenadas.

Para eso, Ridgun te da tres envases distintos, cada uno pensado para un trabajo muy concreto:
1. **Listas (`[T]`)**: *"Tengo muchos elementos del mismo tipo (o ninguno) y quiero recorrerlos"*.
2. **Tuplas (`(A, B)`)**: *"Quiero devolver un par o un trío de cosas distintas juntas sin crear un tipo nuevo"*.
3. **Secuencias y máscaras (`s["-+-"]`)**: *"Quiero filtrar o reordenar argumentos al vuelo como si tuviera un colador matemático"*.

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
sumar_lista [Int]  => Int
sumar_lista []     =  0
sumar_lista (x:xs) =  x + (sumar_lista xs)

contar_elementos [A]    => Int
contar_elementos []     =  0
contar_elementos (_:xs) =  1 + (contar_elementos xs)
```

Y un detalle técnico que te alegrará el día: en Ridgun, sacar la cola `xs` en `(x:xs)` **no copia el resto de la lista en memoria**. Internamente es una vista sobre el mismo vector que solo avanza el puntero de inicio en `1` ($O(1)$ instantáneo).

### Puedes destapar varios elementos de golpe
El patrón `:` da muchísimo juego cuando estás parseando comandos o protocolos:

```ridgun
interpretar_comando [String]                => String
interpretar_comando []                      =  "No has escrito nada"
interpretar_comando ("ayuda":_)             =  "Mostrando la ayuda..."
interpretar_comando ("copiar":origen:dest:[]) = "Copiando de {origen} a {dest}"
interpretar_comando (cmd:_)                 =  "Comando desconocido: {cmd}"
```

Mira la tercera fila: `("copiar":origen:dest:[])` comprueba de un solo plumazo que la lista tenga **exactamente 3 elementos**, que el primero sea `"copiar"`, y te deja el segundo y el tercero servidos en bandeja en `origen` y `dest`. Intenta escribir eso en C o Java y verás cuántas líneas de `args.length == 3 && args[0].equals("copiar")` te salen.

### Unir listas con doble dos puntos (`::`)
Cuando estás en el lado derecho del `=` (en una expresión) y quieres pegar dos listas, usas **`::`**:

```ridgun
pegar_listas [Int] [Int] => [Int]
pegar_listas a     b     =  a :: b

anadir_detras [Int] Int => [Int]
anadir_detras xs    x   =  xs :: [x]
```

*(Regla mnemotécnica rápida: un solo `:` en los patrones desmonta la lista; dos `::` en las expresiones pegan dos listas).*

¿Y si de verdad quieres sacar el elemento número 5 directamente sin recorrer nada? Usa corchetes pegados al nombre: `mi_lista[5]`.

---

## 5.2. Funciones variádicas (`T...`): "¡Pásame todos los que quieras!"

A veces quieres que quien llame a tu función pueda escribir `maximo_de 4 19 2 88 7` cómodamente, sin obligarle a envolver los números entre corchetes `[4, 19, 2, 88, 7]`.

Pon tres puntos **`...`** detrás del último tipo de tu firma, y dentro de tu función lo recibirás automáticamente empaquetado como una lista:

```ridgun
sumar_varios Int... => Int
sumar_varios nums   =  sumar_lista nums

main => ()
main =
  echo (sumar_varios 10 20 30)       -- Imprime 60
  echo (sumar_varios 1 2 3 4 5 6 7)  -- Imprime 28
```

---

## 5.3. Tuplas: Cuando una función quiere devolver más de una cosa

En muchos lenguajes devolver dos cosas desde una función es un dolor: o creas una clase auxiliar tonta `ResultadoConPosicion`, o pasas punteros de salida por referencia.

En Ridgun devuelves una **tupla** `(A, B)`:

```ridgun
dividir_y_resto Int Int => (Int, Int)
dividir_y_resto a   b   =  (a / b, a % b)
```

Incluso puedes ahorrarte los paréntesis en la línea de la firma si te resulta más limpio:
`dividir_y_resto Int Int => Int Int`.

### Cómo abrir una tupla
Igual que la creas con `(a, b)`, la abres en los argumentos de cualquier función con `(cociente, resto)`:

```ridgun
explicar_division (Int, Int)        => String
explicar_division (cociente, resto) =  "Cabe a {cociente} y sobran {resto}"
```

### El detalle estrella: Desempaquetado automático entre funciones
Supón que tienes `dividir_y_resto` (que devuelve una tupla de 2 enteros) y otra función `sumar_par Int Int => Int` (que espera 2 enteros sueltos). En Ridgun no tienes que abrir la tupla a mano en una variable intermedia; puedes enchufar una función dentro de la otra directamente:

```ridgun
sumar_par Int Int => Int
sumar_par x   y   =  x + y

main => ()
main =
  -- dividir_y_resto 17 5 devuelve (3, 2), y sumar_par recibe 3 y 2 directamente:
  echo (sumar_par (dividir_y_resto 17 5))  -- Imprime 5
```

---

## 5.4. El truco ninja: Secuencias y Máscaras Posicionales (`s["-+-"]`)

Aquí viene una de las joyas más originales de Ridgun, heredada directamente de los lenguajes vectoriales como J y APL.

Imagina que recibes una ristra de argumentos con el patrón de secuencia **`(s)`** y quieres quedarte solo con algunos y tirar otros sin declarar cinco variables con nombres inventados (`_a`, `b`, `_c`, `d`...).

Le aplicas a `s` una **máscara de signos `+` (quédatelo) y `-` (tíralo)**:

- **`s["-+-"]`**: de 3 elementos, tira el primero (`-`), quédate con el segundo (`+`) y tira el tercero (`-`).
- **`s["+-+"]`**: quédate con el primero y el tercero; devuelve la secuencia con esos dos.
- **`s["-- +"]`** (ojo al espacio antes del último `+`): tira los dos primeros (`--`) y aplica `+` **a todos los demás que vengan detrás**, sean cuantos sean.

Míralo funcionando:

```ridgun
el_del_medio Int Int Int => Int
el_del_medio (s)         =  s["-+-"]

descartar_dos_primeros Int... => [Int]
descartar_dos_primeros (s)    =  s["-- +"]

main => ()
main =
  echo (el_del_medio 100 42 999)              -- Imprime 42
  echo (descartar_dos_primeros 1 2 10 20 30)  -- Imprime [10, 20, 30]
```

Además, si usas el operador coma `,` fuera de paréntesis (`lista1 , lista2`), Ridgun aplana ambas colecciones en una única secuencia continua.

En el **Capítulo 06** vamos a dar el paso que convierte a un programador funcional en un arquitecto de primera: **crear tus propios Tipos de Datos Algebraicos (ADTs), escribir funciones polimórficas con `A`..`Z` y fabricar tus propios operadores a medida**.
