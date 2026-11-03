# Capitolo 07: Funzioni di Ordine Superiore e Parallelismo senza Sudore (Né `Mutex`, né `Deadlock`)

In quasi tutti i linguaggi di programmazione c'è un momento drammatico nella vita di un progetto: il giorno in cui qualcuno dice durante una riunione:

> *"Questo va lento. Bisogna parallelizzarlo con i thread."*

Cala il silenzio nella sala. Tutti sanno cosa viene dopo: settimane a dare la caccia a *race condition* fantasma che accadono solo il martedì di luna piena, blocchi reciproci (*deadlock*) ed errori irriproducibili.

In Ridgun, quando qualcuno dice *"bisogna parallelizzarlo"*, basta anteporre `||` alle tue operazioni sulle liste (**`||map`** e **`||filter`**) o mettere i tuoi calcoli in un blocco parallelo **`||`** con frecce `->` e vai a prenderti un caffè.

Perché? Perché **quando le tue funzioni sono pure e i tuoi dati sono immutabili per impostazione predefinita, due core della CPU che lavorano contemporaneamente non possono mai pestarsi i piedi**.

Vediamolo passo dopo passo.

---

## 7.1. Funzioni che ricevono funzioni: `map`, `||map`, `filter`, `||filter` e `fold`

In Ridgun una funzione è un valore come gli altri. Puoi passarla come parametro proprio come passi il numero `7`.

Il linguaggio offre di serie i combinatori di collezioni per trasformare liste senza scrivere nemmeno una singola ricorsione manuale, sia in modalità sequenziale (`map`, `filter`, `fold`) sia in modalità parallela multicore con il prefisso `||` (**`||map`**, **`||filter`**):

### 1. `map` (sequenziale) e `||map` (parallelo multicore)
Supponi di avere una funzione `costoso Int => Int` e una lista di numeri:

```ridgun
costoso Int => Int
costoso x   =  (x * x) + (x * 3)

main => ()
main =
  dati = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Sequenziale stretto da sinistra a destra:
  r1 = map costoso dati
  -- Parallelo multicore con il prefisso `||`:
  r2 = ||map costoso dati
  echo r1
  echo r2
```

- Con **`map`**, Ridgun applica la funzione elemento per elemento da sinistra a destra nel thread attuale (ideale per liste piccole o funzioni con effetti di input/output ordinati).
- Con **`||map`**, il runtime di Ridgun distribuisce gli elementi di `dati` tra i thread worker del tuo processore e ricostruisce la lista finale **esattamente nello stesso ordine**, garantendo che `||map f xs == map f xs`.

### 2. `filter` (sequenziale) e `||filter` (parallelo): Tenere solo quelli che soddisfano una condizione
Le passi una funzione che restituisca `Bool` (un *predicato*) e una lista:

```ridgun
fn :: e positivo Int => Bool
      e positivo n   =  n > 0

fn :: main => ()
      main =
        puliti = filter e positivo [-5, 10, 0, -2, 42]
        puliti_par = ||filter e positivo [-5, 10, 0, -2, 42]
        echo puliti      -- Stampa [10, 42]
        echo puliti_par  -- Stampa [10, 42]
```

### 3. `fold`: Ridurre un'intera lista a un solo risultato
Le passi una funzione combinatrice a due argomenti `(Accumulato Elemento => Accumulato)`, il valore iniziale e la lista:

```ridgun
fn :: accumula prodotto Int Int => Int
      accumula prodotto acc x   =  acc * x

fn :: main => ()
      main =
        echo (fold accumula prodotto 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### Come scrivo io la mia funzione che riceve un'altra funzione?
Facilissimo: nella firma dei tipi metti la firma della funzione ospite tra parentesi `(Ingresso => Uscita)`:

```ridgun
fn :: esegui due volte (A => A) A => A
      esegui due volte f        x =  f (f x)
```

### 4. Chiusure lessicali e funzioni anonime (`(x => expr)`, `(acc x => expr)`)
Quando vuoi passare una funzione breve al volo o catturare variabili locali del tuo ambito attuale (come uno scostamento, un prefisso o una sessione attiva) senza dichiarare una funzione globale ausiliaria, usi una **chiusura lessicale** tra parentesi con **`=>`**:

```ridgun
fn :: elabora con sessione => [Int]
      elabora con sessione =
        base     = 10
        bonus    = 3
        sommati  = map (x => x + base) [1, 2, 3]
        filtrati = filter (x => x >= bonus) [1, 2, 3, 4]
        totale   = fold (acc x => acc + x + bonus) 0 [1, 2, 3]
        coppie   = map ((a b) => a + b + base) [(1, 2), (3, 4)]
        sommati :: filtrati :: [totale] :: coppie
```

Cinque regole mantengono le lambda pulite e prive di ambiguità:
- **Parentesi obbligatorie**: ogni lambda va sempre tra parentesi `(... => ...)`.
- **Lambda senza parametri (`(=> expr)`)**: proprio come `fn :: main => ()` non porta `()` prima di `=>`, una lambda senza parametri si scrive `(=> expr)` (e il suo tipo è `(=> Tipo)`), mai `(() => expr)`.
- **Più parametri rispetto a una tupla (`(a b => ...)` vs. `((a b) => ...)`)**: `(acc x => ...)` riceve due parametri separati; `((a b) => ...)` riceve un'unica tupla e la destruttura.
- **Corpo su più righe**: se vai a capo dopo `=>`, puoi scrivere un blocco indentato di più passi prima della `)` di chiusura:
  ```ridgun
  doppi = map (x =>
    passo = x * 2
    passo + base
  ) [1, 2, 3]
  ```
- **Maiuscole rispetto a minuscole**: `(Conn => Conn)` è un tipo di funzione (iniziale maiuscola) e `(conn => conn)` è un valore lambda (iniziale minuscola).

Le variabili catturate (`base`, `bonus`) vengono impacchettate automaticamente con gestione deterministica della memoria (`RMM1`/`RMM2`), senza perdite e senza pause del garbage collector.

### 5. Lo stile più idiomatico di Ridgun (consigliato): Pipeline fluide con `->`, invocazione da sinistra e blocchi senza `_ =` (`FR-COMP-014`)
Scrivere `map f xs` o assegnare ogni passo intermedio a una variabile (`r1 = ...`, `r2 = ...`) va benissimo, ma dove Ridgun si gode al 100% è concatenando trasformazioni da sinistra a destra con **`->`** e legando il risultato finale direttamente con **`-> variabile`**:

```ridgun
op :: [Int] compact limit Int => [Int]
      []     compact limit _   =  []
      (x:xs) compact limit lim
        | x <= lim  = [x] :: (xs compact limit lim)
        | otherwise = xs compact limit lim

fn :: main => ()
      main =
        xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

        -- Stile consigliato (2b): avvio infisso naturale + `->` tra le tappe + `-> results`
        xs map (x => x * 2) -> filter (x => x > 6) -> compact limit 14 -> results
        echo results  -- Stampa [8, 10, 12, 14]
```

Ridgun unifica i quattro modi di scrivere la catena nello stesso albero sintattico (AST), così puoi scegliere quello che si legge meglio in ogni caso:
1. **Stile `2b` (consigliato)**: `xs map f -> filter g -> compact limit 14 -> results` (avvio infisso naturale con il soggetto a sinistra, `->` a separare ogni tappa e `-> results` alla fine).
2. **Stile `2` (`->` dal valore iniziale)**: `xs -> map f -> filter g -> compact limit 14 -> results`.
3. **Stile `1` (infisso continuo senza `->` intermedi)**: `xs map f filter g compact limit 14 -> results`.
4. **Stile `3` (avvio prefisso classico + `->`)**: `map f xs -> filter g -> compact limit 14 -> results`.

E se la pipeline è lunga, puoi spezzarla su più righe indentate che iniziano con `->`:

```ridgun
        xs map (x => x * 3)
          -> filter (x => x >= 12)
          -> fold 0 (acc x => acc + x)
          -> totale
```

La regola universale di `->` è semplice e coerente in tutto il linguaggio:
- **Il valore che arriva da sinistra entra come PRIMO argomento** della funzione o dell'operatore di destra (`x -> f a b` $\equiv$ `x f a b` $\equiv$ `f x a b`), tranne in `map`/`filter`/`fold` (dove entra come la collezione su cui iterare) o se posizioni un jolly esplicito **`_`** (`payload -> write file percorso_uscita _`).
- **Invio diretto agli agenti**: `[5, 10, 15] -> somma lista -> send to ag` e `[1, 2, 3] -> somma lista -> ask to ag -> totale`.
- **Maschere di sequenza in transito (`-> (+ _ _ +) ->`)**: `analizza pacchetto "v0.9.9" -> (+ _ _ +) -> combina codice -> riepilogo`.
- **Blocchi sequenziali puliti senza `_ =` e scarto esplicito `-> ()`**: le chiamate con effetti collaterali (`echo`, `write file`, `shell exec`, `log`, ecc.) si scrivono direttamente senza `_ =`. Se l'ultima riga di una funzione `=> ()` chiama una funzione che restituisce un valore (come `Int`), basta terminare quella riga con **`-> ()`** per scartare esplicitamente il risultato e restituire `()`.

---

## 7.2. Il fiore all'occhiello: Blocchi `||` con `->` come Grafi Paralleli (DAG)

Qui è dove Ridgun cambia il tuo modo di pensare.

In un normale linguaggio imperativo, quando scrivi tre righe di fila:
1. Prima viene eseguita la riga 1.
2. Poi la riga 2 (anche se non ha nulla a che vedere con la riga 1).
3. Poi la riga 3.

Questo significa costringere il computer a lavorare con i paraocchi. In Ridgun, quando usi le barre parallele **`||`** con le frecce **`->`** (senza bisogno di scrivere alcuna parola chiave come `where`), non stai dando ordini sequenziali: stai disegnando un **Grafo Aciclico Diretto (DAG)** che dice quale calcolo alimenta quale variabile:

```ridgun
fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  (fib (n - 1)) + (fib (n - 2))

fn :: fact Int => Int
      fact 0   =  1
      fact n   =  n * (fact (n - 1))

fn :: super calcolo => Int
      super calcolo =  ramo_sinistro + ramo_destro
        || fib 10 -> ramo_sinistro
        || fact 6 -> ramo_destro
```

Leggilo ad alta voce:
- *"Voglio calcolare `ramo_sinistro + ramo_destro`, mentre in parallelo (`||`) `fib 10` va in `ramo_sinistro` (`->`) e `fact 6` va in `ramo_destro` (`->`)."*

### Cosa fa `ridgunc` dietro le quinte con le tue righe `||`:
1. Guarda le frecce `->` e costruisce l'albero delle dipendenze (DAG).
2. **Cattura i cicli staticamente**: se per errore scrivi `|| a + 1 -> b` e `|| b + 1 -> a`, il compilatore ti dice all'istante *"Fermi tutti! C'è una dipendenza circolare"* e non ti lascia compilare un blocco infinito.
3. Vede che `fib 10` e `fact 6` non dipendono l'uno dall'altro, quindi hanno via libera per correre in parallelo prima di sommarsi in `ramo_sinistro + ramo_destro`.

Puoi persino montare una pipeline a più piani dentro lo stesso blocco `||` — sia in fondo all'espressione sia subito dopo l'`=` — e il compilatore dedurrà da solo quali piani possono andare contemporaneamente e quali devono aspettare:

```ridgun
fn :: bilancio trimestrale Int  => Int
      bilancio trimestrale base =
        || base * 100                  -> vendite_lorde
        || base * 40                   -> costi_fissi
        || vendite_lorde - costi_fissi -> utile_lordo ||.
        utile_lordo * 80 / 100
```

Nota il dettaglio **`||.`** alla fine dell'ultima riga `||`: proprio come `|.` chiude un albero di guardie annidato, **`||.`** chiude il blocco parallelo `||` quando sotto seguono normali istruzioni sequenziali. Qui `vendite_lorde` e `costi_fissi` partono in parallelo; quando entrambi sono pronti si calcola `utile_lordo`, e infine si restituisce `utile_lordo * 80 / 100`. Tutto senza un singolo `async`, `Future`, `Promise` o `Mutex`.

---

## 7.3. La scorciatoia `||` senza nomi: Pipeline parallele che restituiscono una tupla

E se vuoi solo lanciare due o tre calcoli in parallelo e raccoglierli insieme in una tupla senza nemmeno inventare nomi di variabili con `->`?

Usi `||` direttamente:

```ridgun
fn :: coppia parallela Int => Int Int
      coppia parallela n   =
        || fib n
        || fact n
```

Diretto, visivo e restituisce la tupla `(fib n, fact n)`.

---

## 7.4. Quando vuoi il volante manuale: il Modello Nativo di Agenti (`agent`, `send ... to`, `receive from`) e Canali CSP

Il parallelismo automatico di `||` e `||map` copre il 90% dei casi. Ma quando programmi un server persistente, sessioni utente con stato isolato, code di lavoro o una pipeline produttore-consumatore, vuoi **agenti concorrenti con memoria isolata e passaggio di messaggi tipizzato**.

In Ridgun non serve inventare una sintassi strana come `actor ::`: **qualsiasi funzione normale (`fn ::` o `op ::`) si trasforma in un agente concorrente in una riga con `agent`**:

### 1. Agenti senza stato e con stato isolato (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (mia funzione)`: converte una funzione `M => R` in un agente senza stato di tipo `Agent M R`.
- `ag = agent (mia funzione con stato) stato_iniziale`: converte una funzione `S M => S` (o `S M => S R`) in un agente con stato isolato che ricorda il suo stato messaggio dopo messaggio senza un singolo `Mutex`.
- `send msg to ag` (o con più argomenti: `send a b to ag`): invia un messaggio tipizzato alla casella di posta dell'agente.
- `res = receive from ag` (o `try receive from ag` senza bloccare): raccoglie la risposta successiva dalla casella di uscita dell'agente.
- `stop ag`: ferma l'agente e libera automaticamente il suo stato mediante `RMM1`/`RMM2`.

```ridgun
fn :: somma visita Int  Int => Int
      somma visita acum n   =  acum + n

fn :: elabora lotto Int Int => Int
      elabora lotto id  t   =  (id * 100) + t

fn :: main => ()
      main =
        contatore = agent (somma visita) 10
        send 5 to contatore
        send 7 to contatore
        v1 = receive from contatore
        v2 = receive from contatore
        stop contatore

        lavoratore = agent (elabora lotto)
        send 3 25 to lavoratore
        lotto = receive from lavoratore
        stop lavoratore
        echo "Visite:" v1 "->" v2 "| Lotto:" lotto
```

### 2. Scelta intelligente a tempo di compilazione (*Green Thread* vs. Thread Reali del Kernel)
Una domanda frequente è: *"I blocchi `||`, `||map` e gli agenti `agent` creano sempre thread del sistema operativo o girano come task leggeri?"*

In Ridgun, **il compilatore prende questa decisione per te analizzando staticamente ogni funzione**:
- **Funzioni leggere (`TierTrivial` / `StratInlineSequential`)**: Se la funzione che passi a `||`, `||map`, `||filter` o `agent` ha poca profondità (aritmetica, formattazione di stringhe, transizione di stato rapida di una sessione HTTP), riscaldare thread del sistema operativo costerebbe più del calcolo stesso. Il compilatore la esegue come un passo *green-thread* ultraleggero senza sovraccarico di `SYS_clone`.
- **Calcoli pesanti o ricorsivi profondi (`TierDynamicRecursive` / `TierHeavyCPU`)**: Se la funzione ha ricorsione profonda (come `fib` o `fact`) o algebra dei tensori (`einsum`, `hadamard`, `@`), il compilatore genera automaticamente lo smistamento multicore su **thread reali del kernel (`SYS_clone`)**, elaborando i rami `||` o la coda di messaggi dell'`agent` in vero parallelo su tutti i core della tua CPU.

### 3. Passare messaggi tramite canali limitati (`new bounded channel`)
Proprio come in Go o Erlang, oltre agli agenti puoi anche creare tubi espliciti per far comunicare le tappe:

- `new bounded channel capacita`: crea un canale con spazio per `capacita` messaggi.
- `send through valore canale` (o `chan send valore canale`): mette un messaggio nel tubo.
- `receive from canale` (o `chan recv canale`): estrae il messaggio successivo dal tubo.
- `try receive from canale`: guarda se c'è un messaggio senza restare in attesa; restituisce `Some valore` o `None`.
- `receive from timeout canale tick`: attende un limite di tempo e restituisce `Ok valore` o `Err Timeout`.

```ridgun
fn :: main => ()
      main =
        tubo = new bounded channel 4
        send through "Attività A completata" tubo
        send through "Attività B completata" tubo
        primo = receive from tubo
        secondo = receive from tubo
        echo primo "|" secondo
```

### 4. Agenti pozzo (*fire-and-forget* `agent sink`), caselle globali (`agent ::`) e test deterministici (`with agent`)
Quando hai bisogno di audit asincrono, metriche, tracce o *rate limiting* trasversale senza sporcare tutte le firme con un parametro extra né accumulare risposte non lette in una coda di uscita, Ridgun offre **agenti pozzo (`agent sink`)** e **caselle globali di livello superiore (`agent ::`)**:
- `rec = agent sink (passo) [stato_iniziale], mailbox N drop|block, drain 2_s`: elabora ogni messaggio in ordine FIFO (`S M => S` o `M => ()`), libera lo stato precedente con `RMM1`/`RMM2` e **non accumula coda di uscita** (`receive from`, `try receive from` e `ask` su un `SinkAgent` sono errori di compilazione).
- `agent :: audit_log = sink (passo) [], mailbox 10_000 drop, drain 2_s`: dichiara un agente pozzo globale inizializzato prima di `main` e svuotato ordinatamente all'uscita del programma.
- `agent dropped ag`, `agent flush ag`, `agent state ag` e `with agent audit_log = spia do ...`: permettono di osservare i messaggi scartati per contropressione (`drop`), svuotare la casella, ispezionare lo stato e reindirizzare temporaneamente una casella globale a un agente spia isolato nei test.
- Inoltre, i descrittori di `Channel`, `Agent` e `SinkAgent` possono essere condivisi liberamente tra più worker (`send ch 1 to w1`, `send ch 2 to w2`), mentre i dati inviati attraverso il canale mantengono la loro proprietà affine (`ErrUseAfterSend`).

E ora, allaccia le cinture per il **Capitolo 08**, il gran finale: **tensori con dimensioni verificate in compilazione, variabili di ambito (`context`/`shared`), regioni di memoria deterministiche, accesso diretto all'hardware MMIO e programmazione di sistema UNIX/POSIX**.
