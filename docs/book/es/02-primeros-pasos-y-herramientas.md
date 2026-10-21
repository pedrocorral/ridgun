# Capítulo 02: Tus dos mejores amigos: `ridgunc` y `stable` (Cero archivos YAML, prometido)

Hay lenguajes cuyo compilador es maravilloso, pero cuyo sistema de proyectos parece diseñado por tu peor enemigo: que si un `Makefile` de 400 líneas con tabuladores invisibles, que si un `pom.xml` infinito, que si un `webpack.config.js` que deja de funcionar si lo miras fijo...

En Ridgun nos hicimos una promesa muy simple desde el primer día:

> *"Sólo habrá dos ejecutables en todo el ecosistema (`ridgunc` y `stable`), ambos estarán escritos en el propio Ridgun, y el archivo de configuración del proyecto (`build.rg`) será código Ridgun normal y corriente. Ni JSON, ni YAML, ni TOML, ni inventos raros."*

Vamos a ver cómo se usan.

---

## 2.1. `ridgunc`: El francotirador para archivos sueltos

Cuando tienes un único archivo `.rg` entre manos y quieres probar una idea rápida, analizar sus tipos o compilar un ejecutable, hablas directamente con **`ridgunc`**.

Sólo tiene 4 comandos que de verdad necesitas recordar:

```bash
# 1. "¿Compila esto o he metido la pata con algún tipo?"
ridgunc check experimento.rg

# 2. "¡Ejecútalo ya!" (Compila y corre de un tirón)
ridgunc run experimento.rg

# 3. "Hazme un binario nativo ELF listo para llevar"
ridgunc build experimento.rg -o mi_programa

# 4. "Sácame el artefacto intermedio de bytecode (.rgc)"
ridgunc compile experimento.rg -o experimento.rgc
```

### El superpoder oculto de `ridgunc check`
Cuando lanzas `ridgunc check`, no solo te dice *"0 errores"*. También te chiva qué estrategia ha elegido el analizador estático para cada una de tus funciones:
- **`InlineSequential`**: *"Esta función es pequeñita y directa; la voy a ejecutar en línea sin meter sobrecoste de planificación"*.
- **`LazyStealableTask`**: *"Aquí hay recursión o un grafo paralelo `||`; la preparo para que otros núcleos de CPU puedan robar trabajo si hace falta"*.

### El bisturí de `ridgunc build` (Por qué tus binarios no pesan 20 MB)
Cuando ejecutas `ridgunc build`, el compilador no se limita a escupir todo el código de las librerías que hayas importado:
1. Empieza en tu función `main` y recorre el grafo de llamadas para ver **qué funciones usas de verdad**. Si importaste una librería enorme de 80 funciones pero solo llamas a 2, las otras 78 se descartan antes siquiera de tocar el ensamblador (*Tree-Shaking*).
2. Busca todas las funciones recursivas de cola y las convierte en bucles `loop` nativos que consumen **0 bytes de pila**.
3. Pasa el enlace final con optimización global (*fat LTO*) y limpia la basura de depuración DWARF para dejarte un binario compacto y afilado (~350 KB).

---

## 2.2. `stable`: Cuando tu proyecto crece y quieres orden

Un archivo suelto está genial para un script, pero en cuanto tienes varios módulos, librerías compartidas y tests, necesitas un director de orquesta. Ese es **`stable`**.

La estructura de carpetas de un proyecto Ridgun no tiene misterio:

```text
mi-super-herramienta/
├── build.rg                  # El manifiesto del proyecto (¡es código Ridgun!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Tus módulos reutilizables (`import utilidades`)
│   │       └── app/
│   │           └── main.rg   # Punto de entrada (`main => ()`)
│   └── test/
│       └── ridgun/           # Tus baterías de tests (`test *.rg`)
│           └── test todo.rg
└── target/                   # Donde aparecen los binarios compilados
```

---

## 2.3. `build.rg`: Un archivo de configuración que nunca te mentirá

¿Por qué nos negamos a usar YAML o TOML para configurar un proyecto Ridgun?
Porque en YAML te equivocas en dos espacios de indentación y no te enteras hasta que falla el despliegue. En cambio, como **`build.rg` es un archivo Ridgun**, tiene tipos estáticos, pasa por `stable check` y se alinea solo con `stable format`:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "mi-super-herramienta" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"
```

Si te equivocas al escribir un campo, el propio compilador te avisa. Sin sorpresas.

---

## 2.4. Tu rutina diaria con `stable` (Los 4 fantásticos)

Cuando estás trabajando dentro de tu proyecto, tu día a día se reduce a cuatro comandos:

### 1. `stable format` — El fin de las discusiones de estilo en el equipo
```bash
stable format
```
¿Que tu compañero pone tres espacios antes del `=>` y tú pones uno? Da igual. Ejecutas `stable format` y en menos de un segundo deja **todos** los archivos `.rg` del repositorio alineados como una tabla suiza.

### 2. `stable check` — El radar instantáneo
```bash
stable check
```
Recorre todos los módulos de `src/main/ridgun/`, verifica tipos, constructores, aridades y dimensiones de tensores, y te da el veredicto módulo por módulo.

### 3. `stable test` — Dormir tranquilo por las noches
```bash
stable test
```
Busca todas las suites `src/test/ridgun/test *.rg`, las ejecuta y comprueba cada `assert equals` y `assert true`.

```ridgun
-- Ejemplo de src/test/ridgun/test mates.rg
import test

doble Int => Int
doble x   =  x * 2

main => ()
main =
  assert equals (doble 21) 42
  assert true ((doble 5) > 0)
```

### 4. `stable built` (y `stable clean`) — A producción
```bash
stable built
```
Compila todos los objetivos nativos en `target/`. Y si algún día quieres borrar `target/` y empezar limpio: `stable clean`.

---

## 2.5. ¿Cómo importo un archivo desde otro? (`import`)

Sin rutas relativas infernales tipo `../../../lib/cosas.rg`. Si tienes un archivo `src/main/ridgun/lib/cadenas.rg`, en cualquier otro archivo escribes arriba del todo:

```ridgun
import cadenas
```

Y listo: todas las funciones y tipos de `cadenas.rg` están disponibles como si estuvieran en tu propio archivo. ¿Y qué pasa si el módulo `A` hace `import cadenas`, el módulo `B` también hace `import cadenas`, y tu `main.rg` importa `A` y `B`? Tranquilo: el cargador de Ridgun recuerda qué archivos canónicos ha leído ya y **solo lo incluye una vez**.

Ahora que tienes la caja de herramientas controlada, pasemos al **Capítulo 03** para dominar las funciones, los tipos, los bloques y los trucos con cadenas de texto.
