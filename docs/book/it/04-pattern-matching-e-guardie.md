# Capitolo 04: Addio a `if/else`, addio a `while` (Pattern Matching, Guardie e TCO)

Quando racconti a qualcuno che in Ridgun **non esiste la parola chiave `if`, né `else`, né `switch`, né `for`, né `while`**, di solito ti guarda come se gli avessi detto che costruirai una casa senza martello né chiodi:

> *"Come sarebbe che non c'è `if` né `while`? E come diavolo prendo una decisione o percorro un milione di dati?"*

Beh, risulta che `if/else` e `while` sono attrezzi piuttosto grezzi ereditati da come funzionavano i salti (`GOTO`) negli anni '50. In Ridgun li sostituiamo con tre pezzi che calzano a pennello:
1. ***Pattern Matching*** (quando decidi in base alla **forma o al valore esatto** del dato).
2. **Guardie booleane `|`** (quando decidi in base a una **condizione o a un intervallo**).
3. **Ricorsione di coda con TCO** (che il compilatore trasforma sotto il cofano in un ciclo `loop` nativo ultraveloce).

Vediamoli in azione.

---

## 4.1. *Pattern Matching*: Quando l'argomento ti dà già la risposta

Nel capitolo precedente ne abbiamo già visto un assaggio. Invece di ricevere una variabile generica `x` e aprire dentro la funzione cinque `if (x == ...)`, in Ridgun metti i casi direttamente sulla porta d'ingresso della funzione:

```ridgun
fn :: codice http Int => String
      codice http 200 =  "OK: Tutto è andato liscio"
      codice http 301 =  "Spostato permanentemente"
      codice http 404 =  "Non trovato (hai guardato sotto il divano?)"
      codice http 500 =  "Fuoco nel server"
      codice http n   =  "Codice sconosciuto: {n}"
```

Ridgun prova le righe **dall'alto verso il basso**:
- Se entra `404`, salta dritto alla terza riga.
- Se entra `418`, nessuna delle prime quattro righe corrisponde, quindi cade nell'ultima (`n`), che cattura qualsiasi intero e lo chiama `n` affinché tu possa stamparlo.
- E se nell'ultimo caso non ti importa nemmeno quale numero fosse? Metti un trattino basso `_` (*jolly*) e te ne dimentichi: `codice http _ = "Altro codice"`.

---

## 4.2. Guardie booleane (`|`): Il tuo bisturi per intervalli, variabili condizionali e alberi decisionali

*"Ok, il pattern matching è forte quando cerco il `200` o il `404`. Ma cosa faccio se voglio controllare se `voto >= 6` o se `eta > 18 and eta < 65`? Non scriverò mica 47 righe con tutti i numeri dal 18 al 65!"*

Certo che no! Per questo ci sono le **guardie (`|`)**.

Quando il risultato dipende da una disuguaglianza o da una combinazione logica, dopo l'`=` della funzione (o di qualsiasi variabile locale) apri una scala di barre verticali `|`:

```ridgun
valuta Int  => String
valuta voto =
  | voto < 0   = "Voto impossibile (punti negativi?)"
  | voto < 6   = "Insufficiente"
  | voto < 7   = "Sufficiente"
  | voto < 9   = "Buono"
  | voto <= 10 = "Ottimo"
  | otherwise  = "Sei uscito dalla scala"
```

Guardalo bene:
- Il segno `=` dell'intestazione (`valuta voto =`) si allinea sotto `=>` proprio come in qualsiasi altra funzione.
- Sotto si legge dall'alto verso il basso proprio come un tariffario: ogni riga `| condizione = risultato` viene controllata in ordine. Non appena una dà `True`, restituisce quel risultato ed è finita.
- Alla fine metti **`| otherwise = ...`**, che significa letteralmente *"in qualsiasi altro caso"* (la tua rete di sicurezza affinché non rimanga mai un percorso senza ritorno).

### Logica booleana in minuscolo chiaro (`and`, `or`, `xor`, `not`)
Hai notato che molti linguaggi usano `|` per i bit, `||` per i booleani, `!` per negare... e quando leggi una condizione complessa sembra che un gatto abbia camminato sulla tastiera (`if (!a && (b || c))`)?

In Ridgun, poiché `|` è già il simbolo sacro delle guardie e dei tipi algebrici, e `||` è l'operatore di parallelismo, **gli operatori booleani si scrivono con parole chiare in minuscolo**:

- **`and`**: si verificano entrambe le cose con valutazione a cortocircuito (`eta >= 18 and ha_patente`: se il lato sinistro è `False`, il destro non viene nemmeno valutato).
- **`or`**: se ne verifica almeno una con valutazione a cortocircuito (`giorno == "sabato" or giorno == "domenica"`: se il lato sinistro è `True`, il destro non viene valutato).
- **`xor`**: si verifica l'una o l'altra, ma non entrambe contemporaneamente.
- **`not`**: inverte il booleano (`not (e vuoto testo)`).
- **`<`, `>`, `<=`, `>=`**: confrontano sia numeri (`Int`, `Float`) sia stringhe di testo **`String` in ordine lessicografico UTF-8** (`"alfa" < "beta"`).

Guarda come viene pulito il classico problema degli anni bisestili:

```ridgun
fn :: e bisestile Int => Bool
      e bisestile a   =
        | (a % 400) == 0                  = True
        | (a % 4) == 0 and (a % 100) != 0 = True
        | otherwise                       = False
```

Zero simboli criptici. Lo legge qualcuno che non conosce Ridgun e lo capisce al primo colpo.

### Variabili locali condizionali (`x =` + `|`)
Poiché in Ridgun ogni `=` segue la stessa regola, **puoi usare `|` anche per assegnare una variabile locale** senza dover creare una funzione ausiliaria a parte:

```ridgun
fn :: prezzo biglietto Int  Bool => Int
      prezzo biglietto base vip  =
        sconto =
          | vip        = 20
          | base > 100 = 10
          | otherwise  = 0
        base - (base * sconto / 100)
```

### Alberi decisionali annidati e il delimitatore compatto `|.`
*"E se dentro un ramo `| cond =` o `| otherwise =` voglio aprire un altro sotto-albero di guardie `|` profondo 3 o 4 livelli e poi tornare a un livello superiore?"*

Puoi annidare `|` dentro `|` per tutti i livelli che vuoi. E quando un blocco `|` annidato finisce ma sotto continuano altri rami di un livello padre (o altre istruzioni del blocco), metti **`|.`** alla fine della sua ultima riga (`| otherwise = valore |.`) per indicare senza alcuna ambiguità che quel sotto-albero si chiude e torni al livello precedente:

```ridgun
fn :: instrada richiesta Int    Int   Bool    Bool  Int  Int => Int
      instrada richiesta metodo ruolo firmata admin kb   lim =
        | metodo == 0 =
          | kb == 0   = 204
          | otherwise = 200 |.
        | metodo == 1 =
          | not firmata = 401
          | otherwise =
            -- Livello 2: richiesta POST firmata
            | lim > 0 =
              -- Livello 3: controllo di rate-limit
              | admin =
                -- Livello 4: eccezione per gli amministratori
                | kb > 10000 = 413
                | otherwise  = 202 |.
              | otherwise = 429 |.
            | kb > 1000 =
              -- Livello 3: siamo tornati dal Livello 4 grazie a `|.`
              | ruolo >= 2 and admin = 201
              | otherwise            = 413 |.
            | otherwise = 201 |.
        | otherwise = 405
```

Nota quanto è pulito:
- In un albero semplice di 1 livello (o alla fine di tutta la funzione) **non serve mai mettere `|.`** (sarebbe rumore inutile).
- Scrivi `|.` solo quando chiudi un ramo annidato sotto il quale continua un ramo di un livello superiore.

### Blocchi su più righe dentro una guardia (`| cond =` + blocco indentato)
Proprio come dopo l'`=` di una funzione normale puoi aprire un blocco indentato su più righe, **anche dopo l'`=` di qualsiasi guardia `| cond =` o `| otherwise =` puoi andare a capo e aprire un blocco sequenziale**:

```ridgun
fn :: regola finestra Int Int    => Int
      regola finestra idx limite =
        | idx >= limite =
            tetto = limite - 1
            scalato = tetto * 2
            scalato + 10
        | otherwise =
            successivo = idx + 1
            successivo * 2
```

Ogni ramo della guardia ha il proprio blocco locale pulito e la sua ultima riga è il valore restituito da quel ramo.

---

## 4.3. "Senza `while`? E non esploderà lo stack se percorro un file grande?"

Parliamo dell'elefante nella stanza.

Se vieni da Python, Java o JavaScript, ti hanno insegnato fin da piccolo che *"la ricorsione è elegante sulla lavagna dell'università, ma nel mondo reale fa traboccare lo stack (`StackOverflowError`) dopo 1.000 giri; usa un ciclo `while`"*.

Questo è vero nei linguaggi che **non** ottimizzano le chiamate di coda. Ma in un linguaggio funzionale di sistema come Ridgun, **una ricorsione di coda È un ciclo `while` travestito da funzione pura**.

### Che differenza c'è tra una ricorsione normale e una ricorsione di coda?
Guarda queste due funzioni che contano alla rovescia da `n` fino a `0` sommando i numeri:

```ridgun
-- Versione A: Ricorsione NORMALE (lascia lavoro in sospeso per il ritorno)
fn :: somma lento Int => Int
      somma lento 0   =  0
      somma lento n   =  n + (somma lento (n - 1))

-- Versione B: Ricorsione DI CODA (tiene il conto aggiornato in `accumulato`)
fn :: somma veloce ciclo Int Int        => Int
      somma veloce ciclo 0   accumulato =  accumulato
      somma veloce ciclo n   accumulato =  somma veloce ciclo (n - 1) (accumulato + n)
```

- Nella **Versione A**, prima di poter sommare `n + ...`, la funzione deve aspettare che finisca `somma lento (n - 1)`. Ciò obbliga il computer a salvare `n` nello stack a ogni passo.
- Nella **Versione B**, la chiamata a `somma veloce ciclo` **è l'ultima cosa che accade nella riga**. Non rimane nulla in sospeso dietro di essa. Le passi già la somma aggiornata in `accumulato + n`.

### Il trucco di magia di `ridgunc` (TCO: *Tail-Call Optimization*)
Quando `ridgunc` compila `somma veloce ciclo`, vede che la funzione chiama se stessa alla fine della clausola e dice:

> *"Perché mai dovrei creare un nuovo stack frame se quello attuale non serve più a nulla? Sovrascriverò `n` con `n - 1`, sovrascriverò `accumulato` con `accumulato + n` e salterò all'inizio con un `loop { ... continue; }` nativo."*

Risultato:
1. Puoi chiamare `somma veloce ciclo 100_000_000 0` (cento milioni di giri) e **consumerà esattamente 0 byte extra di stack**.
2. Va veloce quanto un ciclo `while` scritto a mano in Rust o C, ma senza aver dovuto dichiarare nemmeno una singola variabile mutabile nel tuo codice Ridgun.

---

## 4.4. Il pattern maestro che userai in ogni programma Ridgun

Ogni volta che in un altro linguaggio penseresti *"farò un ciclo `while` con un indice `i` e un accumulatore"*, in Ridgun scrivi una coppia di funzioni come questa (la funzione principale pulita e il suo aiutante di coda):

```ridgun
fn :: cerca carattere ciclo String Int Int  Int     => Int
      cerca carattere ciclo testo  pos fine cercato =
        | pos >= fine                        = -1
        | (str char at testo pos) == cercato = pos
        | otherwise                          = cerca carattere ciclo testo (pos + 1) fine cercato

fn :: cerca carattere String Int     => Int
      cerca carattere testo  cercato =  cerca carattere ciclo testo 0 (str len testo) cercato
```

Guarda le tre guardie di `cerca carattere ciclo`:
1. Sono arrivato alla fine (`pos >= fine`)? Restituisco `-1` (fine del ciclo).
2. Ho trovato il carattere in `pos`? Restituisco `pos` (fine del ciclo).
3. Non è questo? Passo al successivo (`pos + 1`) con una chiamata di coda (che il compilatore converte in `continue;`).

Pulito, impossibile avere *bug* di variabili globali sovrascritte e veloce come un fulmine.

Nel **Capitolo 05** metteremo le mani sulle collezioni di dati: **liste, tuple, funzioni che accettano infiniti argomenti (`...`) e le maschere di sequenze in stile J/APL**.
