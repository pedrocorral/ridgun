# Capítulo 02: Os teus dous mellores amigos: `ridgunc` e `stable` (Cero ficheiros YAML, prometido)

Hai linguaxes cuxo compilador é marabilloso, pero cuxo sistema de proxectos parece deseñado polo teu peor inimigo: que se un `Makefile` de 400 liñas con tabuladores invisibles, que se un `pom.xml` infinito, que se un `webpack.config.js` que deixa de funcionar se o miras fixo...

En Ridgun fixémonos unha promesa moi simple desde o primeiro día:

> *"Só haberá dous executables en todo o ecosistema (`ridgunc` e `stable`), ambos estarán escritos no propio Ridgun, e o ficheiro de configuración do proxecto (`build.rg`) será código Ridgun normal e corrente. Nin JSON, nin YAML, nin TOML, nin inventos raros."*

Imos ver como se usan.

---

## 2.1. `ridgunc`: O francotirador para ficheiros soltos

Cando tes un único ficheiro `.rg` entre mans e queres probar unha idea rápida, analizar os seus tipos ou compilar un executable, falas directamente con **`ridgunc`**.

Só ten 4 comandos que de verdade precisas lembrar:

```bash
# 1. "Compila isto ou metín a pata con algún tipo?"
ridgunc check experimento.rg

# 2. "Execútao xa!" (Compila e corre dun tirón)
ridgunc run experimento.rg

# 3. "Faime un binario nativo ELF listo para levar"
ridgunc build experimento.rg -o meu_programa

# 4. "Sácame o artefacto intermedio de bytecode (.rgc)"
ridgunc compile experimento.rg -o experimento.rgc
```

### O superpoder oculto de `ridgunc check`
Cando lanzas `ridgunc check`, non só che di *"0 erros"*. Tamén che sopra que estratexia escolleu o analizador estático para cada unha das túas funcións:
- **`InlineSequential`**: *"Esta función é pequeniña e directa; vouna executar en liña sen meter sobrecusto de planificación"*.
- **`LazyStealableTask`**: *"Aquí hai recursión ou un grafo paralelo `||`; prepároa para que outros núcleos de CPU poidan roubar traballo se fai falta"*.

### O bisturí de `ridgunc build` (Por que os teus binarios non pesan 20 MB)
Cando executas `ridgunc build`, o compilador non se limita a cuspir todo o código das bibliotecas que importaras:
1. Comeza na túa función `main` e percorre o grafo de chamadas para ver **que funcións usas de verdade**. Se importaches unha biblioteca enorme de 80 funcións pero só chamas a 2, as outras 78 descártanse antes sequera de tocar o ensamblador (*Tree-Shaking*).
2. Busca todas as funcións recursivas de cola e convérteas en bucles `loop` nativos que consumen **0 bytes de pila**.
3. Pasa a ligazón final con optimización global (*fat LTO*) e limpa o lixo de depuración DWARF para deixarche un binario compacto e afiado (~350 KB).

---

## 2.2. `stable`: Cando o teu proxecto medra e queres orde

Un ficheiro solto está xenial para un script, pero en canto tes varios módulos, bibliotecas compartidas e probas, precisas un director de orquestra. Ese é **`stable`**.

A estrutura de cartafoles dun proxecto Ridgun non ten misterio:

```text
a-mina-super-ferramenta/
├── build.rg                  # O manifesto do proxecto (é código Ridgun!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Os teus módulos reutilizables (`import utilidades`)
│   │       └── app/
│   │           └── main.rg   # Punto de entrada (`main => ()`)
│   └── test/
│       └── ridgun/           # As túas baterías de probas (`test *.rg`)
│           └── test todo.rg
└── target/                   # Onde aparecen os binarios compilados
```

---

## 2.3. `build.rg`: Un ficheiro de configuración que nunca che mentirá

Por que nos negamos a usar YAML ou TOML para configurar un proxecto Ridgun?
Porque en YAML trabúcaste en dous espazos de sangrado e non te decatas ata que falla o despregamento. En cambio, como **`build.rg` é un ficheiro Ridgun**, ten tipos estáticos, pasa por `stable check` e alíñase só con `stable format`:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "a-mina-super-ferramenta" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"

-- Opcional: activa o modo estrito de sinaturas e nomes (desactivado por defecto)
strict mode => Bool
strict mode =  True
```

Se te trabucas ao escribir un campo, o propio compilador avísate. Sen sorpresas.

### O modo estrito (`--strict` / `strict mode = True`)
Por defecto, tanto `ridgunc` como os novos proxectos creados con `stable new` ou `stable init` teñen o modo estrito **desactivado** para que poidas prototipar con total liberdade. Cando queiras blindar o estilo canónico dun proxecto (como facemos no propio compilador de Ridgun), podes pasar `--strict` a `ridgunc` ou engadir `strict mode = True` ao teu `build.rg`. O modo estrito esixe dúas regras de elegancia:
1. **Nomes de `fn ::` e `op ::` con espazos naturais, sen `_`**: as declaracións deben usar espazos (`fn :: calcular imposto`, nunca `fn :: calcular_imposto`).
2. **Retornos múltiples separados por espazos tras `=>`**: cando unha función ou operador devolve varios valores, a súa sinatura de saída escríbese `=> Int Int` ou `=> Estado Int` (nunca `=> (Int, Int)` con parénteses nin comas).

---

## 2.4. A túa rutina diaria con `stable` (Os 4 fantásticos)

Cando estás traballando dentro do teu proxecto, o teu día a día redúcese a catro comandos:

### 1. `stable format` — A fin das discusións de estilo no equipo
```bash
stable format
```
Que o teu compañeiro pon tres espazos antes do `=>` e ti pos un? Dá igual. Executas `stable format` e en menos dun segundo deixa **todos** os ficheiros `.rg` do repositorio aliñados coma unha táboa suíza.

### 2. `stable check` — O radar instantáneo
```bash
stable check
```
Percorre todos os módulos de `src/main/ridgun/`, verifica tipos, construtores, aridades e dimensións de tensores, e dáche o veredicto módulo por módulo.

### 3. `stable test` — Durmir tranquilo polas noites
```bash
stable test
```
Busca todas as suites `src/test/ridgun/test *.rg`, execútaas e comproba cada `assert equals` e `assert true`.

```ridgun
-- Exemplo de src/test/ridgun/test mates.rg
import test

dobro Int => Int
dobro x   =  x * 2

main => ()
main =
  assert equals (dobro 21) 42
  assert true ((dobro 5) > 0)
```

### 4. `stable built` (e `stable clean`) — A produción
```bash
stable built
```
Compila todos os obxectivos nativos en `target/`. E se algún día queres borrar `target/` e comezar limpo: `stable clean`.

---

## 2.5. Como importo un ficheiro desde outro? (`import`)

Sen rutas relativas infernais tipo `../../../lib/cousas.rg`. Se tes un ficheiro `src/main/ridgun/lib/cadeas.rg`, en calquera outro ficheiro escribes arriba de todo:

```ridgun
import cadeas
```

E listo: todas as funcións e tipos de `cadeas.rg` están dispoñibles coma se estivesen no teu propio ficheiro. E que pasa se o módulo `A` fai `import cadeas`, o módulo `B` tamén fai `import cadeas`, e o teu `main.rg` importa `A` e `B`? Tranquilo: o cargador de Ridgun lembra que ficheiros canónicos leu xa e **só o inclúe unha vez**.

Agora que tes a caixa de ferramentas controlada, pasemos ao **Capítulo 03** para dominar as funcións, os tipos, os bloques e os trucos con cadeas de texto.
