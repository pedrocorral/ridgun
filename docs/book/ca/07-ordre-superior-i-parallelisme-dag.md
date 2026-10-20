# Capítol 07: Funcions d'Ordre Superior i Paral·lelisme sense Suor (Ni `Mutex`, ni `Deadlocks`)

En gairebé tots els llenguatges de programació hi ha un moment dramàtic en la vida d'un projecte: el dia en què algú diu en una reunió:

> *"Això va lent. Cal paral·lelitzar-ho amb fils."*

Es fa el silenci a la sala. Tothom sap què ve després: setmanes caçant *race conditions* fantasma que només passen els dimarts amb lluna plena, bloquejos mutus (*deadlocks*) i errors irreproduïbles.

En Ridgun, quan algú diu *"cal paral·lelitzar-ho"*, `map` i `filter` ja són paral·lels per defecte, o poses els teus càlculs en un bloc paral·lel `||` amb fletxes `->` i te'n vas a fer un cafè.

Per què? Perquè **quan les teves funcions són pures i les teves dades són immutables per defecte, dos nuclis de CPU treballant alhora mai no es poden trepitjar la mànega**.

Vegem-ho pas a pas.

---

## 7.1. Funcions que reben funcions: `map`, `seq_map`, `filter`, `seq_filter` i `fold`

En Ridgun una funció és un valor més. Pots passar-la per paràmetre igual que passes el número `7`.

El llenguatge porta de sèrie els combinadors de col·leccions per transformar llistes sense escriure ni una sola recursió manual:

### 1. `map` (paral·lel per defecte) i `seq_map` (seqüencial)
Suposa que tens una funció `costos Int => Int` i una llista amb números:

```ridgun
costos Int => Int
costos x   =  (x * x) + (x * 3)

main => ()
main =
  dades = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Paral·lel multicore per defecte:
  r1 = map costos dades
  -- Seqüencial estricte d'esquerra a dreta:
  r2 = seq_map costos dades
  echo r1
  echo r2
```

- Amb **`map`**, el runtime de Ridgun reparteix els elements de `dades` entre els fils treballadors del teu processador i reconstrueix la llista final **exactament en el mateix ordre**, garantint que `map f xs == seq_map f xs`.
- I si la teva funció fa efectes d'entrada/sortida (com imprimir per pantalla o escriure en un fitxer) i vols forçar que vagi estrictament d'esquerra a dreta d'un en un? Fas servir **`seq_map`**.

### 2. `filter` (paral·lel) i `seq_filter` (seqüencial): Quedar-te només amb els que compleixin una condició
Li passes una funció que retorni `Bool` (un *predicat*) i una llista:

```ridgun
es_positiu Int => Bool
es_positiu n   =  n > 0

main => ()
main =
  nets = filter es_positiu [-5, 10, 0, -2, 42]
  echo nets  -- Imprimeix [10, 42]
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

## 7.4. Quan vols el volant manual: `spawn`, `join` i Canals CSP

El paral·lelisme automàtic de `||` i `map` cobreix el 90% dels casos. Però de vegades estàs programant un sistema d'actors, una cua de treballs o una canonada productor-consumidor i vols controlar tu mateix les tasques i els missatges.

Per a això tens dues eines netes:

### 1. Llançar tasques amb `spawn` i recollir el resultat amb `join`
```ridgun
processar_lot Int => Int
processar_lot id  =  id * 100

main => ()
main =
  tasca1 = spawn processar_lot 1
  tasca2 = spawn processar_lot 2
  -- Mentrestant podries fer altres coses aquí...
  res1 = join tasca1
  res2 = join tasca2
  echo "Han acabat amb:" res1 "i" res2
```

### 2. Passar missatges per canals afitats (`new_bounded_channel`)
Igual que en Go o Erlang, en lloc de compartir memòria entre fils, envies valors immutables a través d'un tub segur:

- `new_bounded_channel capacitat`: crea un canal amb espai per a `capacitat` missatges.
- `chan_send valor canal` (o `send_through valor canal`): fica un missatge al tub.
- `chan_recv canal` (o `receive_from canal`): treu el següent missatge del tub.
- `chan_try_recv canal`: mira si hi ha missatge sense quedar-se esperant; retorna `Some valor` o `None`.
- `receive_from_timeout canal ticks`: espera un límit de temps i retorna `Ok valor` o `Err Timeout`.

```ridgun
main => ()
main =
  tub = new_bounded_channel 4
  _ = chan_send "Tasca A completada" tub
  _ = chan_send "Tasca B completada" tub
  primer = chan_recv tub
  segon = chan_recv tub
  echo primer "|" segon
```

I ara, corda't el cinturó per al **Capítol 08**, el gran final: **tensors amb dimensions verificades en compilació, variables d'àmbit (`context`/`shared`), regions de memòria deterministes, accés directe a maquinari MMIO i programació de sistemes UNIX/POSIX**.
