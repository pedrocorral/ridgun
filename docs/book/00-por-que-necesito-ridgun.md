# Capítulo 00: ¿Por qué necesito Ridgun? ¿Ah, sí? No lo sabía... ¡Cuéntame más!

Seamos sinceros: cuando alguien te dice *"hemos creado un nuevo lenguaje de programación"*, tu primera reacción natural —y muy sana— es arquear una ceja y pensar:

> *"¿Otro más? Pero si ya tengo Python para ir rápido, Rust o C para cuando necesito velocidad, y Bash para pegar cosas en la terminal. ¿Para qué demonios necesito yo aprender Ridgun?"*

Es una pregunta excelente. Y la respuesta corta es: **porque te has acostumbrado a sufrir tres dolores diarios pensando que eran inevitables**.

Vamos a ponerles nombre.

---

## Dolor n.º 1: "El síndrome de los dos mundos" (Prototipar en uno, reescribir en otro)

Seguro que has vivido esta película:

1. Empiezas una herramienta o un motor de cálculo en **Python**, **JavaScript** o **Ruby** porque quieres pensar en el problema, no en punteros ni en el compilador.
2. El código queda corto y bonito... pero cuando le pasas un archivo de 500 MB o intentas usar los 16 núcleos de tu máquina, se arrastra. Y si quieres distribuir tu programa a un servidor limpio, tienes que empaquetar medio gigabyte de entorno virtual, intérprete y librerías dinámicas.
3. Resignado, decides reescribirlo en **C**, **C++** o **Rust**. Ahora vuela y ocupa unos pocos cientos de kilobytes, pero tu código de 40 líneas se ha convertido en 300 líneas llenas de `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, llaves `{}` y puntos y coma `;`.

**¿Qué cambia con Ridgun?**
En Ridgun escribes código **más corto y limpio que en Python**, pero cuando ejecutas `ridgunc build`, obtienes **un único binario nativo ELF de ~350 KB** sin intérprete, sin máquina virtual externa y sin recolector de basura. No hay fase de *"luego lo reescribimos en el lenguaje rápido"*: el código limpio donde piensas el problema **ya es** el binario nativo de producción.

---

## Dolor n.º 2: "Leer código ajeno (o el tuyo de hace 6 meses) es jugar a ser detective"

Mira cómo escribimos lógica condicional en casi todos los lenguajes mainstream:

```text
if (estado == ACTIVO && (rol == ADMIN || (rol == EDITOR && tienePermiso))) {
    if (cuota > 0) {
        return procesar(usuario);
    } else {
        return denegar("Sin cuota");
    }
} else {
    return denegar("No autorizado");
}
```

Nuestros ojos no evolucionaron para emparejar llaves anidadas ni para desentrañar árboles de `if / else` escalonados. Cuando los ingenieros, matemáticos o físicos quieren entender reglas complejas sin equivocarse, no escriben párrafos de `if / else`: **dibujan una tabla**.

En Ridgun, **el código es esa tabla**:

```ridgun
autorizar String   String   Bool  Int   => String
autorizar "activo" "admin"  _     cuota =
  | cuota > 0 = "Procesando petición"
  | otherwise = "Denegado: sin cuota"
autorizar "activo" "editor" True  cuota =
  | cuota > 0 = "Procesando petición"
  | otherwise = "Denegado: sin cuota"
autorizar _        _        _     _     =  "Denegado: no autorizado"
```

Mira las columnas:
- Columna 1: el estado (`"activo"` o `_`).
- Columna 2: el rol (`"admin"`, `"editor"` o `_`).
- Columna 3: si tiene permiso (`True` o `_`).
- Columna 4: la `cuota`.

No tienes que ejecutar mentalmente el programa línea por línea para saber qué pasa cuando entra un `"editor"` con permiso `False`: tus ojos bajan verticalmente por la tabla y lo ven en medio segundo.

---

## Dolor n.º 3: "Mi ordenador tiene 16 núcleos, pero mi programa solo usa 1 (porque me da pánico tocar hilos)"

Hoy hasta el teléfono más modesto tiene 8 núcleos, y cualquier servidor o portátil de trabajo tiene entre 12 y 32. Sin embargo, el 95% de los programas cotidianos siguen ejecutándose en un solo hilo secuencial.

¿Por qué? Porque en los lenguajes imperativos, paralelizar significa abrir la caja de Pandora:
- ¿Y si dos hilos modifican el mismo diccionario a la vez? (*Data race*).
- ¿Y si bloqueo el `Mutex` A y luego el B en un hilo, y el B y luego el A en otro? (*Deadlock*).
- ¿Y si contamino toda mi base de código con `async` y `await` de arriba abajo?

En Ridgun, **toda función es pura y todo dato es inmutable por defecto**. Eso tiene una consecuencia mágica: **dos expresiones que no dependen una de la otra jamás pueden interferir entre sí**.

Por eso, en Ridgun no tienes que gestionar hilos para aprovechar tu CPU. Solo declaras **qué depende de qué** con barras paralelas `||` y flechas `->`:

```ridgun
informe_mensual Datos => Informe
informe_mensual d     =  combinar metricas_red metricas_disco metricas_cpu
  || analizar_red d   -> metricas_red
  || analizar_disco d -> metricas_disco
  || analizar_cpu d   -> metricas_cpu
```

Tú solo has escrito tres líneas limpias indicando de dónde sale cada dato. El compilador ve que las tres ramas son independientes y sabe que puede lanzarlas en paralelo sin que exista ni la más mínima posibilidad de un *data race* o un *deadlock*.

---

## Dolor n.º 4: "El recolector de basura decide pausar el mundo justo en el peor momento"

Los lenguajes funcionales clásicos (Haskell, OCaml, Erlang, Clojure) son maravillosos para razonar sobre el código, pero casi todos dependen de un **Recolector de Basura (*Garbage Collector*)** en tiempo de ejecución. Eso los descarta cuando necesitas:
- Latencias predecibles al microsegundo.
- Controlar exactamente cuánta memoria RAM puede consumir una operación antes de abortarla limpiamente.
- Escribir utilidades del sistema operativo (`ls`, `find`, `sh`, `doas`, `make`) o tocar registros de hardware (`MMIO`).

Ridgun te da **toda la elegancia del mundo funcional puro, pero con Gestión de Memoria de Ridgun (`RMM`: `RMM1` estática y `RMM2` por conteo de asignaciones en cascada) más regiones léxicas con cuota exacta (`with region`)**:

```ridgun
parsear_paquete String => Result
parsear_paquete crudo  =
  with region 16_KB do
    decodificar_trama crudo
```

Cada estructura temporal es liberada de forma determinista por el compilador (`RMM1` / `RMM2`) en el instante en que deja de usarse, y si un atacante te envía un paquete malicioso diseñado para explotar la memoria, al superar el byte 16.384 la región se corta al instante, libera su arena en $O(1)$ y te devuelve `Err OutOfMemory`. Sin caídas del proceso, sin pausas de GC y sin fugas de memoria.

---

## En resumen: ¿Cuándo brilla Ridgun?

Ridgun está hecho para ti si alguna vez has querido:

1. **Escribir herramientas de sistemas, compiladores, analizadores o utilidades CLI** que arranquen en microsegundos, pesen unos pocos cientos de KB y no puedan romperse por punteros nulos ni efectos colaterales ocultos.
2. **Programar algoritmos, pipelines de datos o álgebra de tensores** donde el compilador verifique por ti hasta las dimensiones de las matrices (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) antes de ejecutar nada.
3. **Disfrutar leyendo tu propio código**: que cada archivo `.rg` parezca una página de un libro bien maquetado gracias al formateador tabular automático (`stable format`).

¿Te pica la curiosidad? Pasa al **Capítulo 01** y escribamos nuestro primer programa en menos de dos minutos.
