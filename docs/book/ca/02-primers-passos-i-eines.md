# Capítol 02: Els teus dos millors amics: `ridgunc` i `stable` (Zero fitxers YAML, promès)

Hi ha llenguatges el compilador dels quals és meravellós, però amb un sistema de projectes que sembla dissenyat pel teu pitjor enemic: que si un `Makefile` de 400 línies amb tabuladors invisibles, que si un `pom.xml` infinit, que si un `webpack.config.js` que deixa de funcionar si te'l mires fixament...

A Ridgun ens vam fer una promesa molt simple des del primer dia:

> *"Només hi haurà dos executables en tot l'ecosistema (`ridgunc` i `stable`), tots dos estaran escrits en el mateix Ridgun, i el fitxer de configuració del projecte (`build.rg`) serà codi Ridgun normal i corrent. Ni JSON, ni YAML, ni TOML, ni invents estranys."*

Vegem com es fan servir.

---

## 2.1. `ridgunc`: El franctirador per a fitxers solts

Quan tens un únic fitxer `.rg` entre mans i vols provar una idea ràpida, analitzar els seus tipus o compilar un executable, parles directament amb **`ridgunc`**.

Només té 4 ordres que de debò necessites recordar:

```bash
# 1. "Compila això o he ficat la pota amb algun tipus?"
ridgunc check experiment.rg

# 2. "Executa-ho ja!" (Compila i corre d'una tirada)
ridgunc run experiment.rg

# 3. "Fes-me un binari natiu ELF a punt per emportar"
ridgunc build experiment.rg -o el_meu_programa

# 4. "Treu-me l'artefacte intermedi de bytecode (.rgc)"
ridgunc compile experiment.rg -o experiment.rgc
```

### El superpoder ocult de `ridgunc check`
Quan llances `ridgunc check`, no només et diu *"0 errors"*. També et xiva quina estratègia ha triat l'analitzador estàtic per a cadascuna de les teves funcions:
- **`InlineSequential`**: *"Aquesta funció és petitona i directa; l'executaré en línia sense afegir sobrecost de planificació"*.
- **`LazyStealableTask`**: *"Aquí hi ha recursió o un graf paral·lel `||`; la preparo perquè altres nuclis de CPU puguin robar feina si cal"*.

### El bisturí de `ridgunc build` (Per què els teus binaris no pesen 20 MB)
Quan executes `ridgunc build`, el compilador no es limita a escopir tot el codi de les llibreries que hagis importat:
1. Comença a la teva funció `main` i recorre el graf de crides per veure **quines funcions fas servir de debò**. Si has importat una llibreria enorme de 80 funcions però només en crides 2, les altres 78 es descarten abans fins i tot de tocar l'assemblador (*Tree-Shaking*).
2. Busca totes les funcions recursives de cua i les converteix en bucles `loop` natius que consumeixen **0 bytes de pila**.
3. Passa l'enllaç final amb optimització global (*fat LTO*) i neteja la brossa de depuració DWARF per deixar-te un binari compacte i esmolat (~350 KB).

---

## 2.2. `stable`: Quan el teu projecte creix i vols ordre

Un fitxer solt està genial per a un script, però tan bon punt tens diversos mòduls, llibreries compartides i tests, necessites un director d'orquestra. Aquest és **`stable`**.

L'estructura de carpetes d'un projecte Ridgun no té misteri:

```text
la-meva-super-eina/
├── build.rg                  # El manifest del projecte (és codi Ridgun!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Els teus mòduls reutilitzables (`import utilitats`)
│   │       └── app/
│   │           └── main.rg   # Punt d'entrada (`main => ()`)
│   └── test/
│       └── ridgun/           # Les teves bateries de tests (`test *.rg`)
│           └── test tot.rg
└── target/                   # On apareixen els binaris compilats
```

---

## 2.3. `build.rg`: Un fitxer de configuració que mai no et mentirà

Per què ens neguem a fer servir YAML o TOML per configurar un projecte Ridgun?
Perquè en YAML t'equivoques en dos espais de sagnat i no te n'assabentes fins que falla el desplegament. En canvi, com que **`build.rg` és un fitxer Ridgun**, té tipus estàtics, passa per `stable check` i s'alinea sol amb `stable format`:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "la-meva-super-eina" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"
```

Si t'equivoques en escriure un camp, el mateix compilador t'avisa. Sense sorpreses.

---

## 2.4. La teva rutina diària amb `stable` (Els 4 fantàstics)

Quan estàs treballant dins del teu projecte, el teu dia a dia es redueix a quatre ordres:

### 1. `stable format` — La fi de les discussions d'estil a l'equip
```bash
stable format
```
Que el teu company posa tres espais abans del `=>` i tu en poses un? Tant se val. Executes `stable format` i en menys d'un segon deixa **tots** els fitxers `.rg` del repositori alineats com una taula suïssa.

### 2. `stable check` — El radar instantani
```bash
stable check
```
Recorre tots els mòduls de `src/main/ridgun/`, verifica tipus, constructors, aritats i dimensions de tensors, i et dóna el veredicte mòdul per mòdul.

### 3. `stable test` — Dormir tranquil a les nits
```bash
stable test
```
Busca totes les suites `src/test/ridgun/test *.rg`, les executa i comprova cada `assert equals` i `assert true`.

```ridgun
-- Exemple de src/test/ridgun/test mates.rg
import test

doble Int => Int
doble x   =  x * 2

main => ()
main =
  assert equals (doble 21) 42
  assert true ((doble 5) > 0)
```

### 4. `stable built` (i `stable clean`) — A producció
```bash
stable built
```
Compila tots els objectius natius a `target/`. I si algun dia vols esborrar `target/` i començar de nou: `stable clean`.

---

## 2.5. Com importo un fitxer des d'un altre? (`import`)

Sense rutes relatives infernals tipus `../../../lib/coses.rg`. Si tens un fitxer `src/main/ridgun/lib/cadenes.rg`, en qualsevol altre fitxer escrius a dalt de tot:

```ridgun
import cadenes
```

I llestos: totes les funcions i tipus de `cadenes.rg` estan disponibles com si fossin al teu propi fitxer. I què passa si el mòdul `A` fa `import cadenes`, el mòdul `B` també fa `import cadenes`, i el teu `main.rg` importa `A` i `B`? Tranquil: el carregador de Ridgun recorda quins fitxers canònics ja ha llegit i **només l'inclou una vegada**.

Ara que tens la caixa d'eines controlada, passem al **Capítol 03** per dominar les funcions, els tipus, els blocs i els trucs amb cadenes de text.
