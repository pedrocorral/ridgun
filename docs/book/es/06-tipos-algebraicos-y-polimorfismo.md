# Capítulo 06: Tipos de Datos Algebraicos (ADTs), Polimorfismo y por qué aquí no queremos `null` ni `Any`

En 1965, Tony Hoare inventó la referencia nula (`null` / `nil`). Cuarenta años después pidió perdón públicamente y la llamó *"mi error de mil millones de dólares"*.

¿Por qué? Porque en los lenguajes con `null`, una función te promete en su firma que te va a devolver un `Usuario`... y cuando menos te lo esperas te devuelve `null` y te tira abajo el servidor a las tres de la mañana.

Y otro tanto ocurre con la herencia de objetos y el tipo `Any` (u `Object`): metes un número y un texto en una lista `[1, "dos"]`, el lenguaje se encoge de hombros y dice *"vale, pues ahora esto es una `List[Any]`, buena suerte adivinando qué hay dentro cuando la recorras"*.

En Ridgun cortamos esos dos problemas de raíz con **Tipos de Datos Algebraicos (ADTs)** y **Polimorfismo Paramétrico**. Suena a nombre de asignatura dura, pero en cinco minutos vas a ver que es la forma más natural del mundo de modelar datos.

---

## 6.1. Tipos Producto (Registros): Tus `struct` de toda la vida, pero con superpoderes

Cuando quieres agrupar varios datos que pertenecen a una misma entidad (por ejemplo, un servidor con su nombre, su IP y su puerto), defines un **`type`** con sus campos:

```ridgun
type Servidor = host: String, puerto: Int, tls_activo: Bool
```

Con solo escribir esa línea, Ridgun te regala **cuatro cosas** automáticamente:

### 1. El constructor `Servidor`
```ridgun
fn :: mi nodo => Servidor
      mi nodo =  Servidor "api.ejemplo.com" 443 True
```

### 2. Una función *getter* pura para cada campo (`host`, `puerto`, `tls_activo`)
No tienes que escribir `s.getHost()` ni nada parecido; cada nombre de campo es directamente una función que extrae ese dato:

```ridgun
fn :: url conexion Servidor => String
      url conexion srv      =  "Conectar a " + (host srv) + " en el puerto {puerto srv}"
```

### 3. Actualización funcional de registros (`with campo: valor`)
Imagina un registro de configuración con 12 o 15 campos (como las opciones de un comando `ls` o de un servidor web) y quieres cambiar solo uno o dos campos sin tocar el resto. En vez de reconstruir el registro pasando los 15 campos a mano, usas **`with`** y dos puntos **`:`** (exactamente igual que en la definición del `type`):

```ridgun
fn :: activar modo dev Servidor => Servidor
      activar modo dev srv      =  srv with puerto: 8080, tls_activo: False
```

Lo mejor de los dos mundos:
- En tu código es **100% inmutable y seguro** (el compilador comprueba que `puerto` y `tls_activo` existan en `Servidor` y tengan el tipo correcto).
- Por debajo, si `srv` no está compartido con nadie más, el ejecutable nativo reutiliza su memoria *in-place* (`Arc::try_unwrap`) sin copiar el resto de campos.

### 4. *Pattern matching* completo por si quieres abrir el registro en canal
```ridgun
fn :: es puerto seguro Servidor              => Bool
      es puerto seguro (Servidor _ 443 True) =  True
      es puerto seguro _                     =  False
```

---

## 6.2. Tipos Suma (Variantes con `|`): Cómo jubilar a `null`, a las excepciones y a la herencia

Ahora viene lo bueno.
Un registro normal tiene `host` **Y** `puerto` **Y** `tls_activo`.
Pero en el mundo real muchas veces necesitas decir: *"Un método de pago es **O BIEN** una tarjeta con su número, **O BIEN** una transferencia con su IBAN, **O BIEN** efectivo (que no lleva ningún dato extra)"*.

En orientación a objetos tendrías que crear una interfaz `MetodoPago`, tres subclases en tres archivos distintos, constructores, `instanceof`... En Ridgun es **una línea**:

```ridgun
type MetodoPago = Tarjeta String Int | Transferencia String | Efectivo
```

Y mira qué pasa cuando procesas un `MetodoPago` en una función:

```ridgun
fn :: describir pago MetodoPago           => String
      describir pago (Tarjeta num _)      =  "Pago con tarjeta terminada en {num}"
      describir pago (Transferencia iban) =  "Transferencia desde la cuenta {iban}"
      describir pago Efectivo             =  "Pago en metálico en ventanilla"
```

Cada variante (`Tarjeta`, `Transferencia`, `Efectivo`) lleva pegados únicamente los datos que tienen sentido para ella. Es **imposible** construir un pago en `Efectivo` que tenga un `iban` colgado por error.

---

## 6.3. "¿Y cómo meto `[1, "dos"]` en una lista sin usar `Any`?"

Volvamos a la pregunta del millón. Imagina que estás leyendo un archivo CSV o JSON donde una celda puede ser un número entero, un texto o estar vacía.

Si tuvieras un tipo `Any`, meterías `[1, "dos"]` y perderías toda la ayuda del compilador: a partir de ese momento cualquier operación sobre la lista sería caminar con los ojos vendados.

En Ridgun (igual que en Haskell o Rust), creas en dos segundos un tipo suma que explica exactamente qué cosas pueden vivir dentro de esa lista:

```ridgun
type ValorCelda = Entero Int | Texto String | Vacio

fn :: formatear celda ValorCelda => String
      formatear celda (Entero n) =  "Número: {n}"
      formatear celda (Texto s)  =  "Texto: {s}"
      formatear celda Vacio      =  "(vacío)"

fn :: mi fila => [ValorCelda]
      mi fila =  [Entero 1, Texto "dos", Vacio]
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
fn :: buscar division Int Int => Result
      buscar division _   0   =  Err "¡Eh! No se puede dividir por cero"
      buscar division a   b   =  Ok (a / b)

fn :: imprimir res Result    => ()
      imprimir res (Ok n)    =  echo "El resultado es {n}"
      imprimir res (Err msg) =  echo "Fallo controlado: {msg}"
```

Nadie puede ignorar un error por descuido porque el propio tipo `Result` te obliga a mirar si dentro hay un `Ok` o un `Err`.

---

## 6.5. Polimorfismo Paramétrico: Funciones genéricas con `A`, `B`, `T`...

Supón que escribes una función que invierte un par `(x, y)` o que saca el primer elemento de una lista. ¿De verdad importa si la lista es de `Int`, de `String` o de `Servidor`? ¡Para nada! El algoritmo es idéntico.

En Ridgun, **cualquier letra mayúscula individual (`A` a `Z`)** en una firma de tipos funciona automáticamente como un **tipo comodín polimórfico (variable de tipo)**:

```ridgun
fn :: cabeza segura [A]   A       => A
      cabeza segura []    defecto =  defecto
      cabeza segura (x:_) _       =  x

fn :: girar par (A B)  => B A
      girar par (x, y) =  (y, x)
```

Fíjate en la magia de `cabeza segura [A] A => A` y `girar par (A B) => B A`:
- No es un `Any` descontrolado: dice que **el tipo de la lista `[A]`, el tipo del valor `defecto` (`A`) y el tipo devuelto (`A`) tienen que ser el mismo**.
- Si llamas a `cabeza segura [10, 20] 0`, el compilador ata cabos (`A = Int`) y te devuelve un `Int`.
- Si llamas a `cabeza segura ["a", "b"] "ninguno"`, ata cabos (`A = String`) y te devuelve un `String`.
- Pero si intentas hacer trampa y llamas a `cabeza segura [10, 20] "ninguno"`, ¡zas! El compilador te frena en seco porque el primer argumento dice que `A` es `Int` y el segundo dice que `A` es `String`.

---

## 6.6. Crea tus propios operadores (`op ::`): Desde vectores hasta frases a medida

¿Por qué solo los números nativos iban a tener derecho a usar `+` o `*`? ¿Y por qué conformarse con los operadores de siempre cuando puedes inventar la sintaxis perfecta para tu problema?

Con **`op ::`** (o directamente sin prefijo si usas patrones de operador) puedes hacer dos virguerías:

### 1. Enseñarle a `+`, `-`, `*`, `/`, `%` a operar con tus propios tipos
```ridgun
type Complejo = real: Int, imag: Int

op :: Complejo + Complejo => Complejo
      a        + b        =  Complejo ((real a) + (real b)) ((imag a) + (imag b))
```

### 2. Crear operadores *Mixfix* (que se leen como frases naturales, incluidos `type` y `with`)
En una firma de operador, **las palabras con mayúscula inicial (`Int`, `String`, `A`..`Z`) o entre corchetes/paréntesis (`[Int]`, `(A, B)`) son los huecos para los argumentos**, y **las palabras en minúscula son parte de la frase del operador** (incluso palabras tan habituales como `type` o `with`, que en Ridgun son contextuales y nunca te bloquean):

```ridgun
op :: si Bool entonces A sino A => A
      si True entonces v sino _ =  v
      si False entonces _ sino f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  mensaje = si (10 > 5) entonces "¡Diez gana!" sino "Imposible"
  echo mensaje
  echo (format "panel" type "bordered" with 80)
```

Acabas de fabricarte tu propio operador ternario polimórfico y un DSL de formateo en **3 líneas** de Ridgun.

---

## 6.7. Constructores compartidos, variantes de tipo directo, `expand type` y espacios naturales en `fn ::`

Ridgun lleva los tipos algebraicos y las funciones un paso más allá en expresividad y extensibilidad:

1. **Constructores compartidos entre distintos `type`**: Varios tipos suma pueden reutilizar el mismo nombre de constructor (`Error`, `Var`, `Lit`) con igual o distinta aridad; el verificador de tipos los distingue por la columna de la firma.
2. **Variantes con nombre de tipo directo (`type Something = String | Int | MyStruct Float Int`)**: Cuando una variante es un tipo primitivo (`String`, `Int`, `Float`/`Real`, `Bool`, `Char`), no necesitas repetir `Int Int` ni `String String`. Puedes pasar valores directos (`"hola"`, `42`) o constructores explícitos (`String "hola"`, `Int 42`), y hacer pattern matching tanto con literales (`"admin"`, `0`) como con patrones tipados (`(String s)`, `(Int n)`).
3. **Extensión abierta de tipos (`expand type`) y fusión automática de cláusulas `fn ::`**: Con `expand type` puedes añadir nuevas variantes a un tipo suma o nuevos campos a un registro. Al volver a declarar `fn ::` para la misma función, las nuevas cláusulas se fusionan automáticamente **antes** de cualquier cláusula comodín `_` (sin necesidad de escribir `expand fn`).
4. **Espacios naturales `" "` en lugar de `_` en `fn ::`, funciones nativas y nombres de archivo**: Igual que en `op ::`, los nombres de función en `fn ::`, las llamadas a funciones nativas (`assert equals`, `str len`, `read file`) y los archivos `.rg` (`test core language.rg`) pueden escribirse con espacios naturales:

```ridgun
type Something = String | Int | MyStruct Float Int

fn :: describir algo Something            => String
      describir algo "admin"              =  "admin_especial"
      describir algo 0                    =  "cero"
      describir algo (String   s)         =  "texto:{s}"
      describir algo (Int      n)         =  "entero:{n}"
      describir algo (MyStruct ratio cnt) =  "estructura:{ratio}:{cnt}"
      describir algo _                    =  "otro"

expand type Something = Bool

fn :: describir algo Something => String
      describir algo (Bool b)  =  "booleano:{b}"
```

### 5. Tipos genéricos propios (`type Result T E`, `type Page T`) y espacios de nombres de módulo (`import ... as`, `mod.Tipo`)
Además de funciones polimórficas, puedes declarar **tus propios tipos suma y registros genéricos** con parámetros de tipo (`A`..`Z`), así como organizar tipos, constructores, campos y funciones con el mismo nombre en distintos módulos sin colisión (`module ::`, `import db as d`, `http.Config`, `d.Config`). Cada módulo tiene **visibilidad estricta por importación en 3 niveles**: resuelve los nombres sin prefijo buscando primero en **(1) sus propias declaraciones** (incluyendo varios archivos que compartan `module :: nombre`), después en **(2) sus `import` directos** y solo en último lugar en **(3) sus `import` transitivos**, de modo que otros módulos hermanos o la aplicación principal nunca contaminan una librería importada:

```ridgun
type Resultado T E = Exito T | Fallo E
type Pagina T      = elementos: [T], total: Int

fn :: desempaquetar exito (Resultado A String) A => A
      desempaquetar exito (Exito v)            _ =  v
      desempaquetar exito (Fallo _)            d =  d
```

En el **Capítulo 07** vamos a poner todos los núcleos de tu procesador a trabajar a la vez sin derramar una gota de sudor: **funciones de orden superior (`map`, `||map`, `filter`, `||filter`, `fold`), clausuras léxicas (`(x => expr)`), grafos paralelos `||` con `->` y canales concurrentes**.
