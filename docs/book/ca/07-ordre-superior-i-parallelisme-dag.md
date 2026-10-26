# Capítol 07: Funcions d'Ordre Superior i Paral·lelisme sense Suor (Ni `Mutex`, ni `Deadlocks`)

En gairebé tots els llenguatges de programació hi ha un moment dramàtic en la vida d'un projecte: el dia en què algú diu en una reunió:

> *"Això va lent. Cal paral·lelitzar-ho amb fils."*

Es fa el silenci a la sala. Tothom sap què ve després: setmanes caçant *race conditions* fantasma que només passen els dimarts amb lluna plena, bloquejos mutus (*deadlocks*) i errors irreproduïbles.

En Ridgun, quan algú diu *"cal paral·lelitzar-ho"*, n'hi ha prou d'anteposar `||` a les teves operacions de llista (**`||map`** i **`||filter`**) o posar els teus càlculs en un bloc paral·lel `||` amb fletxes `->` i te'n vas a fer un cafè.

Per què? Perquè **quan les teves funcions són pures i les teves dades són immutables per defecte, dos nuclis de CPU treballant alhora mai no es poden trepitjar la mànega**.

Vegem-ho pas a pas.

---

## 7.1. Funcions que reben funcions: `map`, `||map`, `filter`, `||filter` i `fold`

En Ridgun una funció és un valor més. Pots passar-la per paràmetre igual que passes el número `7`.

El llenguatge porta de sèrie els combinadors de col·leccions per transformar llistes sense escriure ni una sola recursió manual, tant en mode seqüencial (`map`, `filter`, `fold`) com en mode paral·lel multicore amb el prefix `||` (**`||map`**, **`||filter`**):

### 1. `map` (seqüencial) i `||map` (paral·lel multicore)
Suposa que tens una funció `costos Int => Int` i una llista amb números:

```ridgun
costos Int => Int
costos x   =  (x * x) + (x * 3)

main => ()
main =
  dades = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Seqüencial estricte d'esquerra a dreta:
  r1 = map costos dades
  -- Paral·lel multicore amb el prefix `||`:
  r2 = ||map costos dades
  echo r1
  echo r2
```

- Amb **`map`**, Ridgun aplica la funció element a element d'esquerra a dreta en el fil actual (ideal per a llistes petites o funcions amb efectes d'entrada/sortida ordenats).
- Amb **`||map`**, el runtime de Ridgun reparteix els elements de `dades` entre els fils treballadors del teu processador i reconstrueix la llista final **exactament en el mateix ordre**, garantint que `||map f xs == map f xs`.

### 2. `filter` (seqüencial) i `||filter` (paral·lel): Quedar-te només amb els que compleixin una condició
Li passes una funció que retorni `Bool` (un *predicat*) i una llista:

```ridgun
es_positiu Int => Bool
es_positiu n   =  n > 0

main => ()
main =
  nets = filter es_positiu [-5, 10, 0, -2, 42]
  nets_par = ||filter es_positiu [-5, 10, 0, -2, 42]
  echo nets      -- Imprimeix [10, 42]
  echo nets_par  -- Imprimeix [10, 42]
```

### 3. `fold`: Reduir tota una llista a un sol resultat
Li passes una funció combinadora de dos arguments `(Acumulat Element => Acumulat)`, el valor inicial i la llista:

```ridgun
acumular_producte Int Int => Int
acumular_producte acc x   =  acc * x

main => ()
main =
  echo (fold acumular_producte 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### Com escric jo la meva pròpia funció que rebi una altra funció?
Molt fàcil: a la signatura de tipus poses la signatura de la funció convidada entre parèntesis `(Entrada => Sortida)`:

```ridgun
executar_dues_vegades (A => A) A => A
executar_dues_vegades f        x =  f (f x)
```

### 4. Clausures lèxiques i funcions anònimes (`\x -> expr`, `\acc x -> expr`)
Quan vols passar una funció curta al vol o capturar variables locals del teu àmbit actual (com un desplaçament, un prefix o una sessió activa) sense declarar una funció global auxiliar, fas servir una **clausura lèxica** amb **`\`** i **`->`**:

```ridgun
fn :: processar amb sessio => [Int]
      processar amb sessio =
        base      = 10
        bo        = 3
        sumats    = map (\x -> x + base) [1, 2, 3]
        filtrats  = filter (\x -> x >= bo) [1, 2, 3, 4]
        total     = fold (\acc x -> acc + x + bo) 0 [1, 2, 3]
        sumats :: filtrats :: [total]
```
Les variables capturades (`base`, `bo`) s'empaqueten automàticament amb gestió determinista de memòria (`RMM1`/`RMM2`), sense fuites i sense pauses de recol·lector de brossa.

---

## 7.2. La joia de la corona: Blocs `||` amb `->` com a Grafs Paral·lels (DAGs)

Aquí és on Ridgun canvia la teva manera de pensar.

En un llenguatge imperatiu normal, quan escrius tres línies seguides:
1. Primer s'executa la línia 1.
2. Després la línia 2 (encara que no tingui res a veure amb la línia 1).
3. Després la línia 3.

Això és obligar l'ordinador a treballar amb clucales. En Ridgun, quan fas servir barres paral·leles **`||`** amb fletxes **`->`** (sense necessitat d'escriure cap paraula clau com `where`), no estàs donant ordres seqüencials: estàs dibuixant un **Graf Acíclic Dirigit (DAG)** que diu quin càlcul alimenta quina variable:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_calcul => Int
super_calcul =  branca_esquerra + branca_dreta
  || fib 10 -> branca_esquerra
  || fact 6 -> branca_dreta
```

Llegeix-ho en veu alta:
- *"Vull calcular `branca_esquerra + branca_dreta`, mentre en paral·lel (`||`) `fib 10` va a `branca_esquerra` (`->`) i `fact 6` va a `branca_dreta` (`->`)."*

### Què fa `ridgunc` entre bastidors amb les teves línies `||`:
1. Mira les fletxes `->` i munta l'arbre de dependències (DAG).
2. **Caça cicles estàticament**: si per error escrius `|| a + 1 -> b` i `|| b + 1 -> a`, el compilador et diu a l'instant *"Quiets! Hi ha una dependència circular"* i no et deixa compilar un bloqueig infinit.
3. Veu que `fib 10` i `fact 6` no depenen l'un de l'altre, així que tenen llum verda per córrer en paral·lel abans de sumar-se a `branca_esquerra + branca_dreta`.

Fins i tot pots muntar una canonada de diverses plantes dins del mateix bloc `||` —ja sigui al peu de l'expressió o just després de l'`=`— i el compilador deduirà tot sol quines plantes poden anar alhora i quines s'han d'esperar:

```ridgun
balanc_trimestral Int  => Int
balanc_trimestral base =
  || base * 100                  -> vendes_brutes
  || base * 40                   -> costos_fixos
  || vendes_brutes - costos_fixos -> benefici_brut ||.
  benefici_brut * 80 / 100
```

Fixa't en el detall **`||.`** al final de l'última línia `||`: igual que `|.` tanca un arbre de guardes imbricat, **`||.`** tanca el bloc paral·lel `||` quan a sota continuen sentències seqüencials normals. Aquí `vendes_brutes` i `costos_fixos` arrenquen en paral·lel; quan tots dos estan a punt es calcula `benefici_brut`, i finalment es retorna `benefici_brut * 80 / 100`. Tot sense un sol `async`, `Future`, `Promise` ni `Mutex`.

---

## 7.3. La drecera `||` sense noms: Canonades paral·leles que retornen una tupla

I si només vols llançar dos o tres càlculs en paral·lel i recollir-los junts en una tupla sense ni tan sols inventar noms de variables amb `->`?

Fas servir `||` directament:

```ridgun
parell_parallel Int => (Int, Int)
parell_parallel n   =
  || fib n
  || fact n
```

Directe, visual i retorna la tupla `(fib n, fact n)`.

---

## 7.4. Quan vols el volant manual: el Model Natiu d'Agents (`agent`, `send ... to`, `receive from`) i Canals CSP

El paral·lelisme automàtic de `||` i `||map` cobreix el 90% dels casos. Però quan programes un servidor persistent, sessions d'usuari amb estat aïllat, cues de treballs o una canonada productor-consumidor, vols **agents concurrents amb memòria aïllada i pas de missatges tipat**.

En Ridgun no cal inventar cap sintaxi estranya com `actor ::`: **qualsevol funció normal (`fn ::` o `op ::`) es converteix en un agent concurrent en una sola línia amb `agent`**:

### 1. Agents sense estat i amb estat aïllat (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (la meva funcio)`: converteix una funció `M => R` en un agent sense estat de tipus `Agent M R`.
- `ag = agent (funcio amb estat) estat_inicial`: converteix una funció `S M => S` (o `S M => S R`) en un agent amb estat aïllat que recorda el seu estat missatge rere missatge sense cap `Mutex`.
- `send msg to ag` (o amb diversos arguments: `send a b to ag`): envia un missatge tipat a la bústia de l'agent.
- `res = receive from ag` (o `try receive from ag` sense bloquejar): recull la següent resposta de la bústia de sortida de l'agent.
- `stop ag`: atura l'agent i allibera el seu estat automàticament mitjançant `RMM1`/`RMM2`.

```ridgun
fn :: sumar visita Int Int => Int
      sumar visita acum n  =  acum + n

fn :: processar lot Int Int => Int
      processar lot id  t   =  (id * 100) + t

fn :: main => ()
      main =
        comptador = agent (sumar visita) 10
        send 5 to comptador
        send 7 to comptador
        v1 = receive from comptador
        v2 = receive from comptador
        stop comptador

        treballador = agent (processar lot)
        send 3 25 to treballador
        lot = receive from treballador
        stop treballador
        echo "Visites:" v1 "->" v2 "| Lot:" lot
```

### 2. Elecció intel·ligent en temps de compilació (*Green Threads* vs. Fils Reals del Nucli)
Una pregunta habitual és: *"Els blocs `||`, `||map` i els agents `agent` creen sempre fils del sistema operatiu o corren com a tasques lleugeres?"*

En Ridgun, **el compilador pren aquesta decisió per tu analitzant estàticament cada funció**:
- **Funcions lleugeres (`TierTrivial` / `StratInlineSequential`)**: Si la funció que passes a `||`, `||map`, `||filter` o `agent` té poca profunditat (aritmètica, formatat de cadenes, transició d'estat ràpida d'una sessió HTTP), escalfar fils del sistema operatiu costaria més que el propi càlcul. El compilador l'executa com un pas *green-thread* ultralleuger sense sobrecàrrega de `SYS_clone`.
- **Càlculs pesats o recursius profunds (`TierDynamicRecursive` / `TierHeavyCPU`)**: Si la funció té recursió profunda (com `fib` o `fact`) o àlgebra de tensors (`einsum`, `hadamard`, `@`), el compilador genera automàticament el despatx multinucli sobre **fils reals del nucli (`SYS_clone`)**, processant les branques `||` o la cua de missatges de l'`agent` en paral·lel real sobre tots els teus nuclis de CPU.

### 3. Passar missatges per canals afitats (`new bounded channel`)
Igual que en Go o Erlang, a més d'agents també pots crear tubs explícits per comunicar etapes:

- `new bounded channel capacitat`: crea un canal amb espai per a `capacitat` missatges.
- `send through valor canal` (o `chan send valor canal`): fica un missatge al tub.
- `receive from canal` (o `chan recv canal`): treu el següent missatge del tub.
- `try receive from canal`: mira si hi ha missatge sense quedar-se esperant; retorna `Some valor` o `None`.
- `receive from timeout canal ticks`: espera un límit de temps i retorna `Ok valor` o `Err Timeout`.

```ridgun
fn :: main => ()
      main =
        tub = new bounded channel 4
        _ = send through "Tasca A completada" tub
        _ = send through "Tasca B completada" tub
        primer = receive from tub
        segon = receive from tub
        echo primer "|" segon
```

I ara, corda't el cinturó per al **Capítol 08**, el gran final: **tensors amb dimensions verificades en compilació, variables d'àmbit (`context`/`shared`), regions de memòria deterministes, accés directe a maquinari MMIO i programació de sistemes UNIX/POSIX**.
