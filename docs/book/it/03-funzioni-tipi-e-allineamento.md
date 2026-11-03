# Capitolo 03: Funzioni, firme dei tipi e l'arte di scrivere codice come una tabella

C'è una domanda che ogni programmatore si fa la prima volta che vede codice funzionale:

> *"Se qui non ci sono classi, né oggetti, né variabili che cambiano valore... allora dove metto la mia logica?"*

Nelle **funzioni**. Ma non in quelle funzioni da 200 righe piene di flag booleani che tutti abbiamo sofferto qualche volta, bensì in funzioni piccole, dirette e così facili da leggere che sembrano una tabella su una lavagna.

Vediamo come si costruiscono.

---

## 3.1. Due modi di presentare una funzione (Scegli tu l'abito)

In Ridgun ogni funzione inizia con la sua **firma dei tipi** (cosa entra e cosa esce dopo `=>`) e sotto vanno le sue **clausole di implementazione** (con `=`).

Puoi scrivere l'intestazione in due modi:

### Opzione A: Dritta al punto (senza prefisso)
```ridgun
applica sconto Int    Int         => Int
applica sconto prezzo percentuale =  prezzo - (prezzo * percentuale / 100)
```

### Opzione B: Con etichetta esplicita (`fn ::`)
```ridgun
fn :: applica sconto Int    Int         => Int
      applica sconto prezzo percentuale =  prezzo - (prezzo * percentuale / 100)
```

*"Ehi, perché usiamo spazi in `applica sconto` invece di `applica_sconto`?"*
Perché in Ridgun tutti i tipi iniziano con la maiuscola (`Int`, `String`, `A`..`Z`), `[` o `(`, mentre le parole del nome della funzione vanno in minuscolo. Così puoi scrivere nomi di più parole con spazi naturali (`applica sconto`, `costo spedizione`, `str len`, `read file`) senza alcuna ambiguità per il compilatore.

*"E perché esistono entrambe le opzioni (con `fn ::` e senza)?"*
Perché i gusti sono gusti:
- C'è chi preferisce che le funzioni inizino attaccate al margine sinistro senza scrivere `fn ::` ogni volta (in fin dei conti, la freccia `=>` grida già ai quattro venti che quella riga è una firma dei tipi).
- E c'è chi preferisce avere una colonna sinistra dedicata alle etichette (`fn ::`, `op ::`, `type`, `import`) per scansionare visivamente il file.

Il compilatore e `stable format` capiscono entrambe alla perfezione.

---

## 3.2. La magia delle colonne: perché i tuoi occhi riposano

Guarda questa funzione che calcola il costo di una spedizione in base al paese e all'urgenza:

```ridgun
fn :: costo spedizione String Bool  Int  => Int
      costo spedizione "IT"   False _    =  5
      costo spedizione "IT"   True  _    =  12
      costo spedizione _      False peso =  10 + (peso * 2)
      costo spedizione _      True  peso =  25 + (peso * 4)
```

Fai la prova: copri la metà destra dello schermo e guarda solo le tre colonne di ingresso:
- Prima colonna (`String`): `"IT"`, `"IT"`, `_`, `_`.
- Seconda colonna (`Bool`): `False`, `True`, `False`, `True`.
- Terza colonna (`Int`): `_`, `_`, `peso`, `peso`.

Vedi qualche buco logico? Nessuno: ci sono tutte le 4 combinazioni possibili davanti ai tuoi occhi, allineate verticalmente sotto `String`, `Bool` e `Int`. In un blocco `if / else` tradizionale dovresti leggere 18 righe per essere sicuro di non aver lasciato fuori nessun caso.

---

## 3.3. I tipi di base e un regalo per non contare gli zeri (`_KB`, `_MB`, `_GB`)

I tipi scalari di Ridgun sono diretti e senza sorprese:

| Tipo | Cos'è in realtà | Esempi |
|---|---|---|
| `Int` | Intero a 64 bit con segno (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `U64` | Intero a 64 bit senza segno (`u64`) per crittografia e sistemi | `0xdeadbeefcafe0001`, `a xor b`, `x rotr 24` |
| `Byte` | Ottetto senza segno (`0..255`) in tensori e buffer binari | `Tensor[Byte * 64]` |
| `Real` / `Float` | Decimale a doppia precisione (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Stringa di testo o buffer binario immutabile con lunghezza esplicita | `"Ciao"`, `'percorso\grezzo'`, `sha256 raw "abc"` |
| `Char` | Codice carattere | Restituito da `str char at` |
| `Bool` | Booleano classico | `True`, `False` |
| `()` | Vuoto (*Unit*, quando stampi soltanto o fai I/O) | `()` |

### Operatori a livello di bit da 1 ciclo e flessibilità lessicale (`fn`, `op`, `where`)
Per la crittografia, i protocolli binari e i sistemi ad alte prestazioni, `Int` e `U64` dispongono di operatori nativi a livello di bit e rotazione compilati in una singola istruzione macchina:
- **Logici e bit a bit**: `and`, `or`, `xor`, `not`
- **Scorrimenti e rotazioni a 64 bit**: `shl` (sinistra), `shr` (destra logica senza segno), `rotl` (rotazione a sinistra), `rotr` (rotazione a destra)

Inoltre, il vocabolario di Ridgun è deliberatamente minimo e ortogonale:
- **`where` non è una parola riservata**: i grafi paralleli si esprimono esclusivamente con `||`, perciò `where` è un normale identificatore che puoi usare come nome di variabile o funzione.
- **`fn` e `op` possono far parte dei nomi**: dopo `fn ::` o `op ::`, le stesse parole `fn` e `op` possono comparire come parte del nome della tua funzione o del tuo operatore (`fn :: op Int => Int`, `op :: Int fn Int => Int`, `op :: A op B => A`).
- **Ritorni multipli separati da spazi (`=> Int Int`)**: quando una funzione restituisce più valori, la sua uscita si scrive separando i tipi con spazi (`fn :: dividi Int Int => Int Int`), e nella chiamata puoi destrutturarla direttamente senza allocare tuple nell'heap (`quoziente, resto = dividi 17 5`).

### Stanco di scrivere `65536` o `1048576` e pregare di non aver saltato una cifra?
In Ridgun i letterali numerici accettano direttamente i suffissi di memoria **`_KB`**, **`_MB`** e **`_GB`** e i suffissi di tempo **`_ms`**, **`_s`** e **`_min`**, oltre ai separatori numerici:

```ridgun
fn :: dimensione buffer => Int
      dimensione buffer =  64_KB      -- Il compilatore lo traduce in 65536

fn :: limite file => Int
      limite file =  16_MB            -- Il compilatore lo traduce in 16777216

fn :: maschera ottetto => Int
      maschera ottetto =  0xFF_00     -- Esadecimale pulito e leggibile
```

---

## 3.4. Virgolette doppie (`"..."`) vs. Virgolette singole (`'...'`)

In molti linguaggi le virgolette singole e doppie fanno esattamente la stessa cosa (uno spreco). In Ridgun ciascuna ha una missione chiarissima:

### 1. Virgolette doppie (`"..."`): Intelligenti e interpolate
Interpretano gli escape (`\n`, `\t`, `\"`, `\\`) e **valutano qualsiasi variabile o espressione che metti tra parentesi graffe `{...}`**:

```ridgun
fn :: riepilogo ordine String Int    Int    => String
      riepilogo ordine voce   unita  prezzo =
        "Hai ordinato {unita}x {voce}. Totale da pagare: {unita * prezzo} euro."
```

*(Trucco: se devi scrivere una parentesi graffa letterale dentro le virgolette doppie — ad esempio generando uno script di shell `"$\{VAR:-default\}"` o un JSON —, puoi farne l'escape con la barra rovesciata `\{` e `\}` o raddoppiarla `{{` e `}}`).*

### 2. Virgolette singole (`'...'`): Grezze e letterali (*Raw Strings*)
Quello che scrivi tra virgolette singole esce **così com'è**, senza toccare nemmeno una barra rovesciata `\`, né una parentesi graffa `{}`. Perfetto per quando generi codice in un altro linguaggio, scrivi comandi di shell o lavori con percorsi pieni di barre:

```ridgun
fn :: comando sed => String
      comando sed =  's/\([0-9]+\)/[\1]/g'
```

### La tua cassetta degli attrezzi per le stringhe (`String`)
Unire stringhe è semplice come sommarle con `+`: `"Ciao, " + nome`. E quando hai bisogno di fare chirurgia di precisione su un testo, hai queste funzioni native con spazi naturali pronte senza importare nulla:

- `str len s` $\rightarrow$ lunghezza di `s`.
- `str char at s i` $\rightarrow$ codice numerico (`Int`) del carattere nella posizione `i` (`-1` se esci dai limiti).
- `str slice s inizio fine` $\rightarrow$ ritaglia da `inizio` fino a `fine` (senza includere `fine`).
- `char from code c` $\rightarrow$ converte un codice numerico (`Int`, es. `10` per `\n` o `34` per `"`) in uno `String` di 1 carattere.
- `str contains s ago` e `str starts with s prefisso` $\rightarrow$ restituiscono `True` o `False`.
- `int to str n` e `str to int s` $\rightarrow$ convertono da numero a testo e viceversa (`str to int` capisce persino `"0xFF"`!).

---

## 3.5. Blocchi su più righe, la regola universale dell'`=` e variabili `mut`

Quando una funzione non entra in una sola riga, vai a capo dopo l'`=` e indenti il blocco.

Guarda come si legge un blocco passo dopo passo:

```ridgun
fn :: calcola fattura Int  Int => Int
      calcola fattura base iva =
        imposte = base * iva / 100
        gestione = 5
        echo "Dettaglio -> Base:" base "Imposte:" imposte
        base + imposte + gestione
```

Quattro regole d'oro che rendono i blocchi in Ridgun puliti e uniformi:
1. **Immutabile per impostazione predefinita senza `let` né `const`**: scrivi `imposte = ...` e hai già la tua costante locale immutabile. Se per distrazione provi a sovrascrivere `imposte = 99` più sotto nello stesso blocco, il compilatore ti ferma su due piedi.
2. **Variabili mutabili esplicite con `mut`**: quando vuoi davvero aggiornare un accumulatore locale passo dopo passo dentro una funzione, lo dichiari con **`mut`** e poi lo riassegni liberamente con `=`:
   ```ridgun
   fn :: applica supplementi Int    => Int
         applica supplementi prezzo =
           mut totale = prezzo
           totale = totale + 10
           totale = totale * 2
           totale
   ```
   *(E se `totale` conserva una lista o una struttura in memoria, la politica **`RMM2`** di Ridgun somma `+1` al nuovo valore prima di scalare `-1` dal vecchio, liberandolo all'istante se nessun altro lo usa).*
3. **La regola universale dell'`=`**: dietro **qualsiasi `=`** (in una funzione, in un operatore, in una variabile locale `x =` o in un ramo condizionale) puoi mettere sempre una qualsiasi delle tre forme di blocco di Ridgun:
   - **`(nulla)`**: righe sequenziali indentate (come sopra).
   - **`|`**: un albero di guardie condizionali.
   - **`||`**: un grafo di calcoli in parallelo con `->`.
4. **L'ultima espressione è sempre il risultato**: `base + imposte + gestione` è ciò che restituisce `calcola fattura`. Senza `return`.

Nel **Capitolo 04** vedremo come prendere decisioni complesse — inclusi alberi decisionali su più livelli con `|.` — senza scrivere mai un `if/else` né un ciclo `while`: benvenuto nel mondo delle **guardie booleane** e della **ricorsione di coda a costo zero**.
