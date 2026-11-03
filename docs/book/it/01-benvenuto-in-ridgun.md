# Capitolo 01: Il tuo primo contatto con Ridgun (Senza caschi, senza parentesi graffe e senza punti e virgola)

Bene, nel Capitolo 00 ti ho già convinto che non siamo pazzi per aver creato Ridgun. Ora probabilmente starai pensando:

> *"Molto bello il discorso sulle tabelle e sui 16 core, ma mostrami del codice vero. Quanto ci mette uno a scrivere qualcosa che funzioni senza litigare con il compilatore?"*

Dai, andiamo al sodo!

---

## 1.1. "Ciao, mondo!", ma con sostanza

Nella maggior parte dei libri di programmazione ti mostrano uno sciapo `print("Ciao mondo")` e voltano pagina. Noi scriveremo direttamente una funzione con logica reale per farti vedere come respira Ridgun fin dal primo minuto.

Crea un file chiamato `ciao.rg` e scrivi questo:

```ridgun
saluto String => String
saluto ""     =  "Ciao, viaggiatore misterioso! (Non mi hai detto il tuo nome)"
saluto "Root" =  "Ehilà, Root! Attento a quello che cancelli oggi."
saluto nome   =  "Ciao, {nome}! Benvenuto in Ridgun."

main => ()
main =
  echo (saluto "Ada")
  echo (saluto "Root")
  echo (saluto "")
```

Per eseguirlo subito:

```bash
ridgunc run ciao.rg
```

E vedrai nel tuo terminale:

```text
Ciao, Ada! Benvenuto in Ridgun.
Ehilà, Root! Attento a quello che cancelli oggi.
Ciao, viaggiatore misterioso! (Non mi hai detto il tuo nome)
```

Fermati un attimo e guarda il blocco di `saluto` qui sopra. Noti cosa **NON** c'è?
- **Non c'è `function`, né `def`, né `pub fn`** (se vuoi mettere `fn ::` davanti alla firma puoi farlo, ma è facoltativo).
- **Non ci sono parentesi `(String nome)` né parentesi graffe `{ ... }`** a sporcare lo schermo.
- **Non c'è `if (nome == "") ... else if (nome == "Root") ... else ...`**.
- **Non c'è `return`**.

---

## 1.2. Come il tuo cervello legge un file `.rg`

Analizziamo quelle quattro righe di `saluto`, perché qui c'è già il 50% della filosofia di Ridgun:

```ridgun
saluto String => String
saluto ""     =  "Ciao, viaggiatore misterioso! (Non mi hai detto il tuo nome)"
saluto "Root" =  "Ehilà, Root! Attento a quello che cancelli oggi."
saluto nome   =  "Ciao, {nome}! Benvenuto in Ridgun."
```

1. **La prima riga è il contratto (`saluto String => String`)**:
   Dice: *"Mi chiamo `saluto`, ricevo uno `String` e ti restituisco (`=>`) un altro `String`"*. Punto. Se qualcuno prova a chiamarmi passandomi il numero `42`, il compilatore gli batterà sulla spalla prima ancora di eseguire il programma.
2. **Le righe sotto sono i casi (dall'alto verso il basso)**:
   - Mi hai passato la stringa vuota `""`? Restituisco la prima frase.
   - Mi hai passato esattamente `"Root"`? Restituisco la seconda frase.
   - Mi hai passato qualsiasi altra cosa? La salvo nella variabile `nome` e la inserisco nel testo usando `{nome}`.
3. **E cos'è `main => ()`?**:
   Poiché `main` non riceve argomenti, mettiamo `=>` direttamente dopo il nome. E restituisce `()` (il tipo vuoto o *Unit*, per gli amici), perché il suo unico lavoro è stampare cose a schermo con `echo`.

---

## 1.3. "Aspetta... devo allineare quegli spazi a mano come un monaco amanuense?"

Neanche per sogno! Se dovessi premere la barra spaziatrice contando le colonne a occhio, abbandoneresti Ridgun dopo dieci minuti (e a ragione).

Tu scrivi il codice in fretta, con un solo spazio tra ogni parola:

```ridgun
saluto String => String
saluto "" = "Ciao, viaggiatore misterioso!"
saluto nome = "Ciao, {nome}!"
```

E quando esegui **`stable format`** (o premi `TAB` / salvi il file in Emacs con `ridgun-mode`), il formattatore canonico posiziona ogni parametro sotto il suo tipo e allinea tutti gli `=` con precisione millimetrica. Tu scrivi veloce; la macchina impagina la tabella.

---

## 1.4. Da script veloce a binario da combattimento in un comando

Quando fai `ridgunc run ciao.rg`, stai compilando e lanciando il programma al volo. Ma immagina di aver finito il tuo strumento e di volerlo portare su un server di produzione o condividerlo con un collega che non ha installato Ridgun.

Esegui:

```bash
ridgunc build ciao.rg -o ciao
```

E hai già `./ciao`: un **eseguibile nativo ELF per Linux x86_64**, pulito, senza codice morto (*Tree-Shaking*), con ottimizzazione dell'intero collegamento (*LTO*) e senza dipendere da alcun interprete esterno.

---

## 1.5. Il promemoria onesto: Da dove viene ogni idea di Ridgun?

Ridgun non pretende di reinventare la ruota quadrata; prende in prestito senza complessi il meglio di quattro tradizioni:

| Da chi | Cosa prende Ridgun | Cosa lascia fuori (per la tua salute mentale) |
|---|---|---|
| **Haskell / ML** | Funzioni pure, *pattern matching* per casi, tipi algebrici (`Option`, `Result`) e polimorfismo (`A`..`Z`). | Le monadi astratte, i 40 `LANGUAGE pragma` e il garbage collector. |
| **J / APL** | L'ossessione per la forma tabellare del codice, tensori nativi e maschere di sequenze (`s(_ + _)`). | I simboli geroglifici impossibili da digitare su una tastiera normale. |
| **Rust / C** | Binari ELF nativi piccoli, zero GC, controllo della memoria (`with region`) e chiamate di sistema POSIX. | La lotta costante con il *borrow checker*, i *lifetime* `'a` e la verbosità sintattica. |
| **Erlang / Go** | Agenti isolati (`agent`, `send ... to`, `receive from`) e concorrenza tramite canali (`new bounded channel`). | I puntatori `nil` e le mutazioni condivise per distrazione. |

---

## 1.6. E la cosa più importante: Cosa fa Ridgun che NON ha nessun altro?

Riconoscere i classici è buona educazione, ma se Ridgun fosse solo una "raccolta dei più grandi successi" di altri linguaggi, non staresti leggendo questo libro.

Ci sono **otto cose** che abbiamo progettato e integrato in Ridgun che non troverai insieme — e molte di esse, nemmeno separatamente — in nessun altro linguaggio attuale:

### 1. Blocchi paralleli `||` con `->` che sono veri grafi paralleli, non semplice zucchero sintattico
In altri linguaggi funzionali un blocco di variabili locali ordina solo espressioni che poi vengono valutate su un singolo thread.
In Ridgun, **un blocco `||` con frecce `->` è un Grafo Aciclico Diretto (DAG) di esecuzione parallela** senza nemmeno dover scrivere parole chiave extra come `where`:
```ridgun
rapporto annuale Int => Int
rapporto annuale id  =  entrate - spese
  || calcola vendite id -> entrate
  || calcola costi id   -> spese
```
Tu disegni le frecce di flusso (`->`). Il compilatore analizza chi dipende da chi, **verifica staticamente che tu non abbia creato alcun ciclo infinito**, e lancia i rami indipendenti in parallelo senza che tu scriva nemmeno un singolo `async`, `await`, `Future` o `Mutex`.

### 2. Modello Nativo di Agenti (`agent`) a zero attrito con scelta intelligente in compilazione
In altri linguaggi, programmare con attori o agenti ti obbliga a creare classi speciali, implementare *trait*, gestire *lock* o infettare le tue funzioni con `async`.
In Ridgun, **qualsiasi funzione pura normale (`fn ::` o `op ::`) si trasforma direttamente in un agente autonomo — con o senza stato isolato — usando `agent`**:
```ridgun
servi http (Sessione, String) => (Sessione, String)
...
server = agent servi http sessione_iniziale
send "GET /profilo" to server
risposta = receive from server
stop server
```
Ancora meglio: il compilatore **analizza a tempo di compilazione la profondità e il costo computazionale della funzione** sia in `agent` che in `||` e `||map`. Se la funzione è leggera, la esegue come un *green thread* istantaneo senza pagare il costo di riscaldare thread del sistema operativo; se è un calcolo pesante o ricorsivo profondo, la smista automaticamente in parallelo su thread reali del kernel (`SYS_clone`) distribuiti sui core della tua CPU.

### 3. Il codice come tabella bidimensionale in cui la firma è l'intestazione delle colonne
In qualsiasi altro linguaggio, la firma dei tipi va per conto suo su una riga e il corpo della funzione va sotto come un normale paragrafo di testo.
In Ridgun, **la firma dei tipi è letteralmente l'intestazione di una tabella**, e ogni caso sottostante allinea ogni pattern esattamente sulla verticale del suo tipo e ogni `=` sotto il `=>`:
```ridgun
dividi Int Int => Option
dividi _   0   =  None
dividi a   b   =  Some (a / b)
```
Nessun altro tratta la firma e le equazioni come un'unica matrice visiva verificata dal compilatore e impaginata automaticamente da `stable format`.

### 4. Operatori frase (*Mixfix* N-ari) tipizzati e allineati (`op ::`)
Nella maggior parte dei linguaggi, o ti accontenti di `+`, `-`, `*` o al massimo definisci un operatore binario criptico come `<|>` che nessuno sa cosa significhi.
In Ridgun puoi creare **operatori che sono frasi leggibili con tutti gli slot tipizzati che vuoi** (incluse parole contestuali come `type` o `with`):
```ridgun
op :: Int limitato tra Int e Int => Int
      x   limitato tra min e max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
E poi nel tuo codice scrivi `velocita limitato tra 0 e 120`. Si legge come italiano (o inglese), ma è tipizzato al 100% e compilato in codice nativo.

### 5. Maschere visive sulle sequenze (`s(_ + _)` e `-> (+ _ _ +) ->`)
Hai mai dovuto scrivere un'insalata di indici `filter(\(i, x) -> i % 2 == 0)` o aprire una tupla con variabili mute solo per tenerti due posizioni precise?
In Ridgun gli passi direttamente una **maschera visiva**:
- `dati(_ + _)`: scarta il primo (`_`), tiene il secondo (`+`), scarta il terzo (`_`).
- `analizza pacchetto "v0.9.9" -> (+ _ _ +) -> combina codice -> riepilogo`: filtra una tupla di 4 elementi nel bel mezzo della pipeline e passa il 1.º e il 4.º direttamente come i 2 argomenti della funzione successiva.
Zero aritmetica degli indici, zero errori *off-by-one*.

### 6. Polimorfismo a "zero rumore" (`A`..`Z`) governato dal tuo dominio
In Rust, TypeScript o Java, quando una funzione è generica devi riempire la riga di parentesi angolari: `fn scambia<A, B>(coppia: (A, B)) -> (B, A)`.
In Ridgun usi semplicemente una lettera maiuscola singola:
```ridgun
scambia (A, B) => (B, A)
scambia (x, y) =  (y, x)
```
*"E se nel mio programma voglio avere un tipo reale che si chiami `type A`?"* — Nessun problema: in Ridgun **le tue dichiarazioni `type` comandano**. Se non esiste `type A`, `A` è generico; nell'istante in cui definisci `type A = ...`, diventa il tuo tipo concreto in tutto il modulo.

### 7. Zero file di configurazione strani: `build.rg` è puro Ridgun
Dimenticati di imparare TOML per Cargo, JSON per npm, XML per Maven o la sintassi arcana di `Makefile` con tabulazioni invisibili. In Ridgun, la ricetta che costruisce il tuo progetto (`build.rg`) **è un file `.rg` come gli altri**, con le stesse funzioni pure e lo stesso *pattern matching* del resto del tuo codice.

### 8. La "Santissima Trinità" che sembrava impossibile: Livello Haskell + Memoria RMM senza GC né Lifetime + Binari da ~350 KB
Fino a oggi dovevi scegliere:
- Se volevi espressività funzionale pura (Haskell, OCaml, Elixir), pagavi con un garbage collector e un runtime pesante.
- Se volevi binari minuscoli di sistema senza garbage collector (C, Rust, Zig), pagavi gestendo puntatori o litigando con il *borrow checker* e scrivendo codice imperativo pieno di `let mut`.

Ridgun rompe questo dilemma combinando **Ridgun Memory Management (`RMM`: `RMM1` statica e `RMM2` per conteggio di assegnazioni a cascata)**, **regioni lessicali (`with region`)** che liberano intere arene in $O(1)$, **ricorsione di coda trasformata in cicli nativi (`loop`)**, e **potatura del grafo delle chiamate (*Tree-Shaking*)** a partire da `main`. Il risultato: scrivi codice dichiarativo di altissimo livello e ottieni un eseguibile ELF autonomo da **~350 KB** capace di competere alla pari con strumenti scritti in C.

Ora sì: con le carte in tavola, andiamo al **Capitolo 02** per mettere al lavoro **`ridgunc`** e **`stable`**.
