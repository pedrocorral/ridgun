# Capítulo 03: Funciones, firmas de tipos y el arte de escribir código como una tabla

Hay una pregunta que todo programador se hace la primera vez que ve código funcional:

> *"Si aquí no hay clases, ni objetos, ni variables que cambian de valor... ¿entonces dónde meto mi lógica?"*

En **funciones**. Pero no en esas funciones de 200 líneas llenas de banderas booleanas que todos hemos sufrido alguna vez, sino en funciones pequeñas, directas y tan fáciles de leer que parecen una tabla en una pizarra.

Vamos a ver cómo se construyen.

---

## 3.1. Dos formas de presentar una función (Tú eliges el traje)

En Ridgun toda función empieza con su **firma de tipos** (qué entra y qué sale tras `=>`) y debajo van sus **cláusulas de implementación** (con `=`).

Puedes escribir el encabezado de dos maneras:

### Opción A: Directa al grano (sin prefijo)
```ridgun
aplicar_descuento Int    Int        => Int
aplicar_descuento precio porcentaje =  precio - (precio * porcentaje / 100)
```

### Opción B: Con etiqueta explícita (`fn ::`)
```ridgun
fn :: aplicar_descuento Int    Int        => Int
      aplicar_descuento precio porcentaje =  precio - (precio * porcentaje / 100)
```

*"Oye, ¿y por qué existen las dos?"*
Porque para gustos, los colores:
- Hay quien prefiere que las funciones empiecen pegadas al margen izquierdo sin escribir `fn ::` cada vez (al fin y al cabo, la flecha `=>` ya grita a los cuatro vientos que esa línea es una firma de tipos).
- Y hay quien prefiere tener una columna izquierda dedicada a las etiquetas (`fn ::`, `op ::`, `type`, `import`) para escanear el archivo visualmente.

El compilador y `stable format` entienden ambas a la perfección.

---

## 3.2. La magia de las columnas: por qué tus ojos descansan

Mira esta función que calcula el coste de un envío según el país y si es urgente:

```ridgun
coste_envio String    Bool  Int  => Int
coste_envio "ES"      False _    =  5
coste_envio "ES"      True  _    =  12
coste_envio _         False peso =  10 + (peso * 2)
coste_envio _         True  peso =  25 + (peso * 4)
```

Haz la prueba: tapa la mitad derecha de la pantalla y mira solo las tres columnas de entrada:
- Primera columna (`String`): `"ES"`, `"ES"`, `_`, `_`.
- Segunda columna (`Bool`): `False`, `True`, `False`, `True`.
- Tercera columna (`Int`): `_`, `_`, `peso`, `peso`.

¿Ves algún agujero lógico? Ninguno: están las 4 combinaciones posibles delante de tus narices, alineadas verticalmente debajo de `String`, `Bool` e `Int`. En un bloque de `if / else` tradicional tendrías que leer 18 líneas para estar seguro de que no te has dejado ningún caso suelto.

---

## 3.3. Los tipos básicos y un regalo para no contar ceros (`_KB`, `_MB`, `_GB`)

Los tipos escalares de Ridgun son directos y sin sorpresas:

| Tipo | Qué es en realidad | Ejemplos |
|---|---|---|
| `Int` | Entero de 64 bits con signo (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `Real` | Decimal de doble precisión (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Cadena de texto inmutable | `"Hola"`, `'ruta\cruda'` |
| `Char` | Código de carácter | Devuelto por `str_char_at` |
| `Bool` | Booleano de toda la vida | `True`, `False` |
| `()` | Vacío (*Unit*, cuando solo imprimes o haces I/O) | `()` |

### ¿Cansado de escribir `65536` o `1048576` y rezar para no haberte comido un dígito?
En Ridgun los literales numéricos aceptan directamente los sufijos **`_KB`**, **`_MB`** y **`_GB`**, además de guiones bajos `_` para separar grupos de cifras:

```ridgun
tamano_buffer => Int
tamano_buffer =  64_KB      -- El compilador lo traduce a 65536

limite_archivo => Int
limite_archivo =  16_MB     -- El compilador lo traduce a 16777216

mascara_octeto => Int
mascara_octeto =  0xFF_00   -- Hexadecimal limpio y legible
```

---

## 3.4. Comillas dobles (`"..."`) vs. Comillas simples (`'...'`)

En muchos lenguajes las comillas simples y dobles hacen exactamente lo mismo (un desperdicio). En Ridgun cada una tiene una misión clarísima:

### 1. Comillas dobles (`"..."`): Inteligentes e interpoladas
Interpretan escapes (`\n`, `\t`, `\"`, `\\`) y **evalúan cualquier variable o expresión que metas entre llaves `{...}`**:

```ridgun
resumen_pedido String Int Int => String
resumen_pedido item   uds precio =
  "Has pedido {uds}x {item}. Total a pagar: {uds * precio} euros."
```

*(Truco: si necesitas escribir una llave literal dentro de comillas dobles, ponla doble: `{{` o `}}`).*

### 2. Comillas simples (`'...'`): Crudas y literales (*Raw Strings*)
Lo que escribes entre comillas simples sale **tal cual**, sin tocar ni una barra invertida `\`, ni una llave `{}`. Perfecto para cuando generas código en otro lenguaje, escribes comandos de shell o trabajas con rutas llenas de barras:

```ridgun
comando_sed => String
comando_sed =  's/\([0-9]+\)/[\1]/g'
```

### Tu caja de herramientas para cadenas (`String`)
Unir cadenas es tan simple como sumarlas con `+`: `"Hola, " + nombre`. Y cuando necesitas hacer cirugía fina sobre un texto, tienes estas funciones nativas listas sin importar nada:

- `str_len s` $\rightarrow$ longitud de `s`.
- `str_char_at s i` $\rightarrow$ código numérico (`Int`) del carácter en la posición `i` (`-1` si te sales).
- `str_slice s inicio fin` $\rightarrow$ recorta desde `inicio` hasta `fin` (sin incluir `fin`).
- `char_from_code c` $\rightarrow$ convierte un código numérico (`Int`, p. ej. `10` para `\n` o `34` para `"`) en un `String` de 1 carácter.
- `str_contains s aguja` y `str_starts_with s prefijo` $\rightarrow$ devuelven `True` o `False`.
- `int_to_str n` y `str_to_int s` $\rightarrow$ convierten de número a texto y viceversa (¡`str_to_int` entiende incluso `"0xFF"`!).

---

## 3.5. Bloques de varias líneas: "¿Dónde está el `return`?"

Cuando una función no cabe en una sola línea, haces un salto de línea después del `=` e indentas el bloque.

Mira cómo se lee un bloque paso a paso:

```ridgun
calcular_factura Int Int => Int
calcular_factura base iva_pct =
  impuestos = base * iva_pct / 100
  gastos_gestion = 5
  echo "Desglose -> Base:" base "Impuestos:" impuestos
  base + impuestos + gastos_gestion
```

Tres reglas de oro que hacen que los bloques en Ridgun sean limpios:
1. **No hace falta poner `let` ni `const`**: escribes `impuestos = ...` y ya tienes tu constante local.
2. **La última línea es siempre el resultado**: `base + impuestos + gastos_gestion` es lo que devuelve `calcular_factura`. Sin `return`.
3. **¿Y cómo llamo a una función dentro de otra?**: separando los argumentos con espacios (`calcular_factura 100 21`). Solo pones paréntesis cuando un argumento es a su vez otra operación compuesta: `calcular_factura (80 + 20) (iva_actual + 1)`.

En el **Capítulo 04** vamos a ver cómo tomar decisiones complejas sin escribir jamás un `if/else` ni un bucle `while`: bienvenido al mundo de las **guardas booleanas** y la **recursión de cola de coste cero**.
