# Capítulo 06: Tipos de Datos Algebraicos (ADTs), Polimorfismo y por qué aquí no queremos `null` ni `Any`

En 1965, Tony Hoare inventó la referencia nula (`null` / `nil`). Cuarenta años después pidió perdón públicamente y la llamó *"mi error de mil millones de dólares"*.

¿Por qué? Porque en los lenguajes con `null`, una función te promete en su firma que te va a devolver un `Usuario`... y cuando menos te lo esperas te devuelve `null` y te tira abajo el servidor a las tres de la mañana.

Y otro tanto ocurre con la herencia de objetos y el tipo `Any` (u `Object`): metes un número y un texto en una lista `[1, "dos"]`, el lenguaje se encoge de hombros y dice *"vale, pues ahora esto es una `List[Any]`, buena suerte adivinando qué hay dentro cuando la recorras"*.

En Ridgun cortamos esos dos problemas de raíz con **Tipos de Datos Algebraicos (ADTs)** y **Polimorfismo Paramétrico**. Suena a nombre de asignatura dura, pero en cinco minutos vas a ver que es la forma más natural del mundo de modelar datos.

---

## 6.1. Tipos Producto (Registros): Tus `struct` de toda la vida, pero con superpoderes

Cuando quieres agrupar varios datos que pertenecen a una misma entidad (por ejemplo, un servidor con su nombre, su IP y su puerto), defines un **`type`** con sus campos:

```ridgun
type Servidor =
  host: String
  puerto: Int
  tls_activo: Bool
```

*(Si es cortito y prefieres ponerlo en una sola línea, también vale: `type Punto = x: Int, y: Int`).*

Con solo escribir esas cuatro líneas, Ridgun te regala tres cosas automáticamente:

### 1. El constructor `Servidor`
```ridgun
mi_nodo => Servidor
mi_nodo =  Servidor "api.ejemplo.com" 443 True
```

### 2. Una función *getter* pura para cada campo (`host`, `puerto`, `tls_activo`)
No tienes que escribir `s.getHost()` ni nada parecido; cada nombre de campo es directamente una función que extrae ese dato:

```ridgun
url_conexion Servidor => String
url_conexion srv      =  "Conectar a " + (host srv) + " en el puerto {puerto srv}"
```

### 3. *Pattern matching* completo por si quieres abrir el registro en canal
```ridgun
es_puerto_seguro Servidor                 => Bool
es_puerto_seguro (Servidor _ 443 True)    =  True
es_puerto_seguro _                        =  False
```

---

## 6.2. Tipos Suma (Variantes con `|`): Cómo jubilar a `null`, a las excepciones y a la herencia

Ahora viene lo bueno.
Un registro normal tiene `host` **Y** `puerto` **Y** `tls_activo`.
Pero en el mundo real muchas veces necesitas decir: *"Un método de pago es **O BIEN** una tarjeta con su número, **O BIEN** una transferencia con su IBAN, **O BIEN** efectivo (que no lleva ningún dato extra)"*.

En orientación a objetos tendrías que crear una interfaz `MetodoPago`, tres subclases en tres archivos distintos, constructores, `instanceof`... En Ridgun son **4 líneas**:

```ridgun
type MetodoPago =
  | Tarjeta String Int
  | Transferencia String
  | Efectivo
```

Y mira qué pasa cuando procesas un `MetodoPago` en una función:

```ridgun
describir_pago MetodoPago            => String
describir_pago (Tarjeta num _)       =  "Pago con tarjeta terminada en {num}"
describir_pago (Transferencia iban)  =  "Transferencia desde la cuenta {iban}"
describir_pago Efectivo              =  "Pago en metálico en ventanilla"
```

Cada variante (`Tarjeta`, `Transferencia`, `Efectivo`) lleva pegados únicamente los datos que tienen sentido para ella. Es **imposible** construir un pago en `Efectivo` que tenga un `iban` colgado por error.

---

## 6.3. "¿Y cómo meto `[1, "dos"]` en una lista sin usar `Any`?"

Volvamos a la pregunta del millón. Imagina que estás leyendo un archivo CSV o JSON donde una celda puede ser un número entero, un texto o estar vacía.

Si tuvieras un tipo `Any`, meterías `[1, "dos"]` y perderías toda la ayuda del compilador: a partir de ese momento cualquier operación sobre la lista sería caminar con los ojos vendados.

En Ridgun (igual que en Haskell o Rust), creas en dos segundos un tipo suma que explica exactamente qué cosas pueden vivir dentro de esa lista:

```ridgun
type ValorCelda =
  | Entero Int
  | Texto String
  | Vacio

formatear_celda ValorCelda   => String
formatear_celda (Entero n)   =  "Número: {n}"
formatear_celda (Texto s)    =  "Texto: {s}"
formatear_celda Vacio        =  "(vacío)"

mi_fila => [ValorCelda]
mi_fila =  [Entero 1, Texto "dos", Vacio]
```

¿Ves la diferencia?
- Con `Any`, el compilador no sabe si en la lista hay enteros, cadenas o una cafetera conectada por USB.
- Con `[ValorCelda]`, puedes mezclar números y textos en la misma lista, **pero el compilador sabe al 100% que solo existen esas tres posibilidades** y te obliga a desempaquetar cada caso (`Entero n`, `Texto s`, `Vacio`) antes de usarlo. Seguridad total sin perder ni un ápice de flexibilidad.

---

## 6.4. `Option` y `Result`: Cuando algo puede no estar o puede fallar

Como en Ridgun no existe `null` ni existen excepciones que salten por los aires (`throw new Exception()`), el lenguaje trae integrados dos tipos suma universales:

1. **`Option`**: o tienes **`Some valor`**, o tienes **`None`** (nada).
2. **`Result`**: o la operación salió bien (**`Ok valor`**), o falló por un motivo concreto (**`Err error`**).

```ridgun
buscar_division Int Int => Result Int String
buscar_division _   0   =  Err "¡Eh! No se puede dividir por cero"
buscar_division a   b   =  Ok (a / b)

imprimir_res (Result Int String) => ()
imprimir_res (Ok n)              =  echo "El resultado es {n}"
imprimir_res (Err msg)           =  echo "Fallo controlado: {msg}"
```

Nadie puede ignorar un error por descuido porque el propio tipo `Result` te obliga a mirar si dentro hay un `Ok` o un `Err`.

---

## 6.5. Polimorfismo Paramétrico: Funciones genéricas con `A`, `B`, `T`...

Supón que escribes una función que invierte un par `(x, y)` o que saca el primer elemento de una lista. ¿De verdad importa si la lista es de `Int`, de `String` o de `Servidor`? ¡Para nada! El algoritmo es idéntico.

En Ridgun, **cualquier letra mayúscula individual (`A` a `Z`)** en una firma de tipos funciona automáticamente como un **tipo comodín polimórfico (variable de tipo)**:

```ridgun
cabeza_segura [A]    A          => A
cabeza_segura []     por_defecto =  por_defecto
cabeza_segura (x:_)  _          =  x

girar_par (A, B)  => (B, A)
girar_par (x, y)  =  (y, x)
```

Fíjate en la magia de `cabeza_segura [A] A => A`:
- No es un `Any` descontrolado: dice que **el tipo de la lista `[A]`, el tipo del valor `por_defecto` (`A`) y el tipo devuelto (`A`) tienen que ser el mismo**.
- Si llamas a `cabeza_segura [10, 20] 0`, el compilador ata cabos (`A = Int`) y te devuelve un `Int`.
- Si llamas a `cabeza_segura ["a", "b"] "ninguno"`, ata cabos (`A = String`) y te devuelve un `String`.
- Pero si intentas hacer trampa y llamas a `cabeza_segura [10, 20] "ninguno"`, ¡zas! El compilador te frena en seco porque el primer argumento dice que `A` es `Int` y el segundo dice que `A` es `String`.

### "Un momento... ¿y si en mi dominio médico o matemático quiero crear un tipo real llamado `type A` (por ejemplo, grupo sanguíneo A)?"
¡Buena pregunta! En Ridgun, **tus declaraciones `type` mandan siempre**.
- Mientras no hayas definido `type A`, la letra `A` en una firma es un tipo polimórfico genérico.
- En el instante en que escribes en tu código `type A = ...`, el compilador toma nota y, a partir de ahí, `A` significa **tu tipo de datos `A`**, no un genérico. Sin ambigüedades.

---

## 6.6. Crea tus propios operadores (`op ::`): Desde vectores hasta frases a medida

¿Por qué solo los números nativos iban a tener derecho a usar `+` o `*`? ¿Y por qué conformarse con los operadores de siempre cuando puedes inventar la sintaxis perfecta para tu problema?

Con **`op ::`** (o directamente sin prefijo si usas patrones de operador) puedes hacer dos virguerías:

### 1. Enseñarle a `+`, `-`, `*`, `/`, `%` a operar con tus propios tipos
```ridgun
type Complejo = real: Int, imag: Int

op :: (Complejo a) + (Complejo b) => Complejo
      a            + b            =  Complejo ((real a) + (real b)) ((imag a) + (imag b))
```

### 2. Crear operadores *Mixfix* (que se leen como frases naturales)
Puedes intercalar palabras clave con parámetros tipados `(Tipo nombre)` en el orden que quieras:

```ridgun
op :: si (Bool cond) entonces (A verdadero) sino (A falso) => A
      si True        entonces verdadero     sino _         =  verdadero
      si False       entonces _             sino falso     =  falso

main => ()
main =
  mensaje = si (10 > 5) entonces "¡Diez gana!" sino "Imposible"
  echo mensaje
```

Acabas de fabricarte tu propio operador ternario polimórfico en **3 líneas** de Ridgun.

En el **Capítulo 07** vamos a poner todos los núcleos de tu procesador a trabajar a la vez sin derramar una gota de sudor: **funciones de orden superior (`map`, `pmap`, `filter`, `fold`), grafos paralelos `where`-DAG y canales concurrentes**.
