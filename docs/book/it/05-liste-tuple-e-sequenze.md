# Capitolo 05: Liste, Tuple e il trucco ninja delle Sequenze

Un programma che sposta solo un numero o un testo alla volta serve a poco. Nella vita reale gestisci liste di file, righe di un database, pacchetti di rete o coordinate.

Per questo, Ridgun ti dà tre contenitori diversi, ciascuno pensato per un lavoro ben preciso:
1. **Liste (`[T]`)**: *"Ho molti elementi dello stesso tipo (o nessuno) e voglio percorrerli"*.
2. **Tuple (`(A, B)`)**: *"Voglio restituire una coppia o un trio di cose diverse insieme senza creare un nuovo tipo"*.
3. **Sequenze e maschere (`s(_ + _)`, `(+ _ _ +)`)**: *"Voglio filtrare o riordinare argomenti al volo come se avessi un colino matematico"*.

Andiamo una per una.

---

## 5.1. Liste (`[T]`): Il pane quotidiano

In Ridgun, se metti le parentesi quadre attorno a un tipo, hai una lista di quel tipo:
- `[Int]` è una lista di interi: `[10, 20, 30]`.
- `[String]` è una lista di testi: `["mela", "pera"]`.
- `[]` è la lista vuota (il jolly che combacia con qualsiasi `[T]`).

> *"Ehi, posso mettere un numero e un testo insieme nella stessa lista tipo `[1, "due"]`?"*
> Così com'è, **no** (e ringrazia il compilatore per impedirtelo, perché così non ti esploderà mai una somma in produzione trovandosi davanti un testo a sorpresa). Nel Capitolo 06 vedremo come risolvere il caso di `[1, "due"]` con totale eleganza usando un Tipo Algebrico (proprio come fa Haskell).

### Come si affetta una lista senza usare indici `i`, `j`, `k`: `[]` e `(x:xs)`
Nei linguaggi imperativi, percorrere una lista di solito implica `for (int i = 0; i < lista.size(); i++)`, con il classico rischio di sforare di uno (*off-by-one*).

In Ridgun non conti gli indici; **smonti la lista dalla testa**:
- `[]`: combacia se la lista è vuota.
- `(x:xs)`: combacia se la lista ha almeno un elemento. Mette il primo elemento in `x` (la **testa**) e il resto della lista in `xs` (la **coda**).

Guarda che piacere sommare una lista o contare quanti elementi ha:

```ridgun
fn :: somma lista [Int]  => Int
      somma lista []     =  0
      somma lista (x:xs) =  x + (somma lista xs)

fn :: conta elementi [A]    => Int
      conta elementi []     =  0
      conta elementi (_:xs) =  1 + (conta elementi xs)
```

E un dettaglio tecnico che ti rallegrerà la giornata: in Ridgun, estrarre la coda `xs` in `(x:xs)` **non copia il resto della lista in memoria**. Internamente è una vista sullo stesso vettore che avanza solo il puntatore di inizio di `1` ($O(1)$ istantaneo).

### Puoi scartare più elementi in un colpo solo
Il pattern `:` dà tantissima soddisfazione quando stai analizzando comandi o protocolli:

```ridgun
fn :: interpreta comando [String]                   => String
      interpreta comando []                         =  "Non hai scritto nulla"
      interpreta comando ("aiuto":_)                =  "Mostrando l'aiuto..."
      interpreta comando ("copia":origine:dest:[])  =  "Copiando da {origine} a {dest}"
      interpreta comando (cmd:_)                    =  "Comando sconosciuto: {cmd}"
```

Guarda la terza riga: `("copia":origine:dest:[])` controlla in un solo colpo che la lista abbia **esattamente 3 elementi**, che il primo sia `"copia"`, e ti lascia il secondo e il terzo serviti su un piatto d'argento in `origine` e `dest`. Prova a scrivere questo in C o Java e vedrai quante righe di `args.length == 3 && args[0].equals("copia")` ti escono.

### Unire liste con i doppi due punti (`::`)
Quando sei sul lato destro dell'`=` (in un'espressione) e vuoi incollare due liste, usi **`::`**:

```ridgun
fn :: incolla liste [Int] [Int] => [Int]
      incolla liste a     b     =  a :: b

fn :: aggiungi dietro [Int] Int => [Int]
      aggiungi dietro xs    x   =  xs :: [x]
```

*(Regola mnemonica veloce: un solo `:` nei pattern smonta la lista; due `::` nelle espressioni incollano due liste).*

E se vuoi davvero prendere l'elemento numero 5 direttamente senza percorrere nulla? Usa le parentesi quadre attaccate al nome: `mia_lista[5]`.

---

## 5.2. Funzioni variadiche (`T...`): "Passamene tutti quelli che vuoi!"

A volte vuoi che chi chiama la tua funzione possa scrivere comodamente `somma vari 4 19 2 88 7`, senza obbligarlo a racchiudere i numeri tra parentesi quadre `[4, 19, 2, 88, 7]`.

Metti tre punti **`...`** dietro l'ultimo tipo della tua firma, e dentro la tua funzione lo riceverai automaticamente impacchettato come una lista:

```ridgun
fn :: somma vari Int... => Int
      somma vari nums   =  somma lista nums

fn :: main => ()
      main =
        echo (somma vari 10 20 30)       -- Stampa 60
        echo (somma vari 1 2 3 4 5 6 7)  -- Stampa 28
```

---

## 5.3. Tuple e l'Unificazione delle Firme con Spazi (`Int Int [String String] String`)

In molti linguaggi restituire due o più cose da una funzione è una sofferenza: o crei una sciocca classe ausiliaria `RisultatoConPosizione`, o riempi la firma di parentesi e virgole ridondanti.

In Ridgun, **una lista di argomenti `Int String Int` e una tupla `(Int, String, Int)` sono concettualmente la stessa cosa: una sequenza tipizzata (`seq`)**. Per questo, nelle firme dei tipi puoi separare gli elementi di una tupla semplicemente con **spazi**, sia dopo `=>`, sia dentro le liste `[...]` e dentro le parentesi `(...)`:

```ridgun
-- Due interi di ritorno separati da spazio:
fn :: dividi e resto Int Int => Int Int
      dividi e resto a   b   =  (a / b, a % b)

-- Firma complessa senza rumore di virgole né parentesi esterne:
fn :: analizza intestazione String => Int Int [String String] String
      analizza intestazione tag    =  (200, 2, [("Host", "ridgun.org"), ("X-Tag", tag)], "OK")

-- Lista di tuple [String String] come parametro di ingresso:
fn :: cerca intestazione [String String] String => String
      cerca intestazione []              _      =  "non trovata"
      cerca intestazione ((k, v):resto)  chiave
        | k == chiave = v
        | otherwise   = cerca intestazione resto chiave
```

Nota l'eleganza di `=> Int Int [String String] String`:
- Dopo `=>`, `Int Int [String String] String` significa esattamente la stessa cosa di `(Int, Int, [(String, String)], String)`.
- Dentro le parentesi quadre, `[String String]` significa una lista di coppie di testi `[(String, String)]`.
- Dentro le parentesi tonde (quando passi una tupla come un unico parametro di ingresso), `(Int String)` significa esattamente la stessa cosa di `(Int, String)`:
  ```ridgun
  fn :: spiega divisione (Int Int)          => String
        spiega divisione (quoziente, resto) =  "Ci sta {quoziente} volte e avanzano {resto}"
  ```
- **Perché questo non crea alcuna ambiguità in Ridgun?** Perché a differenza di Haskell (dove `Maybe Int` applica un costruttore di tipi per giustapposizione), in Ridgun i tipi parametrizzati usano parentesi esplicite come `Tensor(Float, 3, 3)` e le liste usano `[T]`. Così, due tipi separati da spazio (`T1 T2`) significano sempre e senza eccezioni una sequenza/tupla di tipi, mantenendo la compatibilità al 100% con la sintassi con le virgole.

### Il dettaglio di punta: Spacchettamento automatico tra funzioni
Supponiamo che tu abbia `dividi e resto` (che restituisce `Int Int`) e un'altra funzione `somma coppia Int Int => Int` (che si aspetta 2 interi). In Ridgun puoi collegare una funzione dentro l'altra direttamente:

```ridgun
fn :: somma coppia Int Int => Int
      somma coppia x   y   =  x + y

fn :: main => ()
      main =
        -- dividi e resto 17 5 restituisce (3, 2), e somma coppia riceve 3 e 2 direttamente:
        echo (somma coppia (dividi e resto 17 5))  -- Stampa 5
```

---

## 5.4. Il trucco ninja: Sequenze e Maschere Posizionali (`s(_ + _)`, `(+ _ _ +)`)

Ecco uno dei gioielli più originali di Ridgun, ereditato direttamente dai linguaggi vettoriali come J e APL.

Immagina di ricevere una sfilza di argomenti con il pattern di sequenza **`(s)`** e di volerne tenere solo alcuni e scartare gli altri senza dichiarare cinque variabili con nomi inventati (`_a`, `b`, `_c`, `d`...).

Applichi a `s` una **maschera di tupla con `+` (tienilo) e `_` (scartalo)**:

- **`s(_ + _)`**: su 3 elementi, scarta il primo (`_`), tieni il secondo (`+`) e scarta il terzo (`_`).
- **`s(+ _ +)`**: tieni il primo e il terzo; restituisce la sequenza con quei due.
- **`s(_ _ +...)`**: scarta i primi due (`_ _`) e applica `+...` **a tutti gli altri che vengono dietro**, quanti che siano.

Guardalo in funzione:

```ridgun
fn :: quello in mezzo Int Int Int => Int
      quello in mezzo (s)         =  s(_ + _)

fn :: scarta primi due Int... => [Int]
      scarta primi due (s)    =  s(_ _ +...)

fn :: main => ()
      main =
        echo (quello in mezzo 100 42 999)         -- Stampa 42
        echo (scarta primi due 1 2 10 20 30)      -- Stampa [10, 20, 30]
```

Ancora meglio: puoi posizionare una maschera **`(+ _ _ +)`** come una tappa intermedia all'interno di una pipeline **`->`** (`FR-COMP-014`). Quando una funzione o un operatore restituisce una tupla di più valori, la maschera filtra quali posizioni conservi (`+`) e quali scarti (`_`), e gli elementi selezionati vengono spacchettati automaticamente come argomenti della funzione successiva della pipeline:

```ridgun
fn :: analizza pacchetto String => Int Int String String
      analizza pacchetto ver    =  (200, 4, ver, "OK")

fn :: combina codice Int  String => String
      combina codice code msg    =  "{code}:{msg}"

fn :: main => ()
      main =
        -- Da (200, 4, "v0.9.9", "OK"), (+ _ _ +) seleziona il 1.º (200) e il 4.º ("OK")
        -- e li passa come i 2 argomenti di `combina codice`:
        analizza pacchetto "v0.9.9" -> (+ _ _ +) -> combina codice -> riepilogo
        echo riepilogo  -- Stampa 200:OK
```

Inoltre, se usi l'operatore virgola `,` fuori dalle parentesi (`lista1 , lista2`), Ridgun appiattisce entrambe le collezioni in un'unica sequenza continua.

Nel **Capitolo 06** faremo il passo che trasforma un programmatore funzionale in un architetto di prim'ordine: **creare i tuoi Tipi di Dati Algebrici (ADT), scrivere funzioni polimorfiche con `A`..`Z` e fabbricare i tuoi operatori su misura**.
