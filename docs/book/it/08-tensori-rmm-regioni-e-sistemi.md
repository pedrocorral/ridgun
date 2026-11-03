# Capitolo 08: Tensori, Memoria Compilata RMM (`RMM1`/`RMM2`), Regioni e Sistemi

Fin qui abbiamo visto il lato più amichevole, elegante e matematico di Ridgun: funzioni pure, tipi algebrici, *pattern matching*, alberi decisionali con `|` / `|.` e grafi paralleli `||` con `->` che sfruttano tutti i core del tuo processore senza chiederti nemmeno un misero `Mutex`.

Arrivati a questo punto, il programmatore veterano di sistemi di solito alza la mano in fondo all'aula con un mezzo sorriso e chiede:

> *"Tutto questo è bellissimo per calcolare fatture o compilare AST, ma cosa succede quando devo moltiplicare matrici di milioni di numeri in virgola mobile a velocità vertiginosa? Che ne è della memoria? C'è un garbage collector nascosto sotto il tappeto che aspetta il momento peggiore per congelare il mio programma per 200 millisecondi? E come parlo davvero con il sistema operativo Unix?"*

Domande eccellenti. Alziamo il cofano di Ridgun per vedere come si comporta quando tocca sporcarsi le mani con i sistemi, il calcolo numerico e la memoria deterministica.

---

## 8.1. Il dilemma della memoria: né Garbage Collector né litigi con il Borrow Checker (`RMM1` e `RMM2`)

Nel mondo dei linguaggi moderni ci sono di solito due fazioni inconciliabili:

1. **La fazione del Garbage Collector (Java, Go, Python, JS, Haskell, OCaml):** tu chiedi memoria allegramente e, di tanto in tanto, un camion della spazzatura invisibile ferma il traffico del tuo programma per rintracciare quali oggetti sono ancora vivi e quali no. È comodissimo... finché non stai realizzando uno strumento di sistema ultraveloce o un server con latenze strette e il camion decide di parcheggiare in doppia fila.
2. **La fazione del controllo manuale / Borrow Checker (C, C++, Rust):** non c'è garbage collector, ma in cambio devi gestire i puntatori a mano (rischiando un `Segmentation fault` o uno *use-after-free*) o passare mezzo pomeriggio a negoziare con il *borrow checker* sul perché `'a` non viva quanto `'b`.

Ridgun risolve questo dilemma alla radice con **Ridgun Memory Management (`RMM`)**, un sistema deterministico a due politiche complementari (**`RMM1`** e **`RMM2`**) combinato con **regioni lessicali (`with region`)**:

### Politica `RMM1` — Gestione della Memoria Compilata (CMM Lineare e Condizionale)
Quando il compilatore conosce staticamente il flusso delle variabili locali dentro una funzione:
- **CMM Lineare**: `ridgunc` calcola a tempo di compilazione qual è l'**ultima riga** in cui viene letta ogni variabile locale (`a`, `b`, ...) e inserisce subito dopo la sua liberazione deterministica (`rg_cmm_drop`), oppure ne trasferisce la proprietà senza copie (`rg_cmm_move`) quando la variabile viene restituita come risultato.
- **CMM Condizionale (`ptr(a) != ptr(c)`)**: e se una funzione come `scegli cond a b` restituisce `a` o `b` in base a una condizione a tempo di esecuzione? `ridgunc` costruisce la tabella degli antenati ed emette una guardia di identità dei puntatori da **1 ciclo di CPU**: se `b` smette di essere usata mentre `c` è ancora viva, controlla `if ptr(b) != ptr(c) { free(b) }`. Il ramo non scelto viene liberato all'istante e quello scelto sopravvive intatto.

### Politica `RMM2` — Conteggio per Assegnazione e Cascata Strutturale
E cosa succede quando metti strutture dentro altre strutture (`xs = [a, b]`), riassegni variabili mutabili (`mut x = ...`) o concateni chiamate complesse? Qui entra in gioco **`RMM2`**, che governa l'intero ciclo di vita con quattro regole matematiche senza falle:

1. **Gli argomenti in ingresso di una funzione non si toccano (`+0` all'entrata, `-0` all'uscita)**: passare una lista o un record a una funzione non incrementa né decrementa mai i contatori invano.
2. **Ogni assegnazione a una variabile locale interna o cella di contenitore somma `+1`**:
   - `a = [10, 20]` $\rightarrow$ il blocco `M1` nasce con contatore `1`.
   - `xs = [a, b]` $\rightarrow$ la lista `xs` nasce con `1`, e poiché conserva riferimenti ad `a` e `b`, entrambi salgono a `2`.
   - Se riassegni una variabile mutabile (`mut x = ...` e poi `x = nuovo`), `RMM2` applica prima **`+1`** al valore nuovo prima di applicare **`-1`** al vecchio.
3. **All'uscita dalla funzione, le variabili locali che NON vengono restituite ricevono `-1`**: se il contatore di una struttura arriva a `0`, la sua memoria viene liberata all'istante e **propaga `-1` a cascata, uno per uno, a ciascuno dei suoi figli diretti**.
4. **Il valore restituito dalla funzione è esentato in transito**: riceve il suo `-1` di variabile locale ma non viene distrutto attraversando il `return`, in modo che quando il chiamante fa `c = mia funzione ()`, quel `+1` dell'assegnazione lo lascia esattamente a `1`.

```ridgun
scegli Bool [Int] [Int] => [Int]
scegli cond a     b     =
  | cond      = a
  | otherwise = b

esempio rmm2 Bool => Int
esempio rmm2 cond =
  a = [10, 20, 30]         -- M1 (rc = 1)
  b = [40, 50, 60]         -- M2 (rc = 1)
  c = scegli cond a b      -- `c` riceve +1; il non scelto muore proprio qui (rc -> 0)
  (conta a) + (conta c)    -- Al termine, `a` e `c` ricevono -1 e tutto resta a 0 blocchi vivi
```

---

## 8.2. Regioni Lessicali con Quota (`with region`): Firewall di memoria in $O(1)$

Oltre a `RMM1` e `RMM2`, quando stai elaborando un pacchetto di rete esterno, un file gigantesco o un lotto di dati non affidabili e vuoi imporre un **tetto stretto di memoria RAM**, avvolgi il calcolo in un blocco **`with region`**:

```ridgun
elabora trama String => Result
elabora trama grezzo =
  with region 64_KB do
    pulite = map pulisci riga (dividi righe grezzo)
    conta validi pulite
```

1. **Quota garantita in hardware/runtime**: se dentro il blocco si tenta di riservare anche un solo byte oltre `64_KB` (`65.536` byte), il runtime interrompe in modo pulito il blocco, libera tutta l'arena temporanea in tempo costante $O(1)$ e restituisce `Err OutOfMemory` senza far cadere il processo.
2. **Liberazione istantanea all'uscita**: non appena termina il blocco `with region`, tutta la memoria temporanea dell'arena scompare in un colpo solo senza lasciare frammentazione.

---

## 8.3. Tensori Nativi, Contrazione di Einstein (`@`) e Dimensioni Simboliche

Se hai mai programmato in Python con NumPy o PyTorch, sicuramente hai sofferto il classico errore al minuto 41 di esecuzione:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

In Ridgun, i **`Tensor`** sono cittadini nativi di prima classe e le loro dimensioni fanno parte della firma dei tipi:

```ridgun
-- Se entra (N × K) e (K × M), per forza esce (N × M)!
moltiplica matrici Tensor[N, K] Tensor[K, M] => Tensor[N, M]
moltiplica matrici a            b            =  a_ik @ b_kj
```

Nota due dettagli spettacolari:
1. **Verifica statica delle dimensioni (`Tensor[N, K]`)**: l'asse interno `K` della prima matrice deve coincidere con il primo asse `K` della seconda. Se provi a passare dimensioni incompatibili, `ridgunc check` ti ferma prima di eseguire alcunché.
2. **Notazione dei pedici di Einstein (`a_ik @ b_kj`) e Hadamard (`a_ij * b_j`)**:
   - Con **`@`**, i pedici ripetuti in tutti gli operandi (`k`) si contraggono (si sommano) e quelli unici (`i`, `j`) sopravvivono nel tensore risultato.
   - Con **`+`, `-`, `*`, `/`**, i pedici allineano le dimensioni e fanno *broadcasting* automatico (`a_ij * b_j` moltiplica ogni riga `i` di `a` per il vettore `b_j` senza bisogno di scrivere `unsqueeze` né `reshape`).
3. **Tensori tipizzati (`Tensor[T * d1 * d2]`), pedici matematici `t_(i, j)`, viste `t_(i,)` e mappatura *in-place* (`in`)**:
   Puoi dichiarare tensori multidimensionali con tipo scalare esplicito (`U64`, `Int`, `Float`, `Byte`) inizializzati a zero in una sola riga, indicizzarli con pedici matematici `t_(i, j)`, estrarre viste di riga `t_(i,)` o colonna `t_(,j)` senza copiare memoria, destrutturare ritorni multipli direttamente sulle celle del tensore senza allocare tuple nell'heap, e applicare funzioni *in-place* lungo un asse con `map ... in` o `||map ... in`:
   ```ridgun
   fn :: blamka p16 Tensor[U64 * 16] => ()
         blamka p16 v                =
           v_(0), v_(4), v_(8), v_(12) = blamka g v_(0) v_(4) v_(8) v_(12)

   fn :: comprimi blocco Tensor[U64 * 8 * 16] Tensor[U64 * 8 * 16] => Tensor[U64 * 8 * 16]
         comprimi blocco x                    y                    =
           r_ij = x_ij xor y_ij
           z_ij = r_ij
           ||map blamka p16 in z_(i,)
           ||map blamka p16 in z_(,j)
           z_ij xor r_ij
   ```

---

## 8.4. Accesso all'Hardware (`hardware ::`) e Primitive POSIX di Sistema

Lo stesso compilatore `ridgunc`, il gestore `stable` e utilità di sistema Unix sono scritti in Ridgun. A tale scopo, il linguaggio include blocchi di registri mappati in memoria (`hardware ::`) e primitive POSIX dirette:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

E per lavorare con il sistema operativo:

| Primitiva | Firma | Cosa fa |
|---|---|---|
| `cli args` | `=> [String]` | Argomenti della riga di comando (`argv`). |
| `read file` / `write file` | `String => String` / `String String => ()` | Lettura e scrittura integrale di file su disco. |
| `read bytes` / `write bytes` | `String => [Int]` / `String [Int] => ()` | Lettura e scrittura binaria esatta byte per byte (`0..255`). |
| `list dir` / `file lstat` | `String => [String]` / `String => ...` | Elenco di directory e ispezione dei metadati POSIX (`lstat`). |
| `sha256 file` / `sha256 str` | `String => String` | Hash crittografico SHA-256 nativo in esadecimale (64 caratteri). |
| `sha256 raw` / `sha256 bytes` | `String => String` | Digest SHA-256 binario grezzo da 32 byte (con supporto completo per byte `0x00` intermedi e zero conversioni hex). |
| `sys exec` / `shell exec` | `... => Int` | Esecuzione di processi del sistema operativo. |
| `sys getcwd` / `sys chdir` | `=> String` / `String => Int` | Consultare o cambiare la directory di lavoro. |
| `sys getenv` / `sys setenv` | `String => String` / `String String => Int` | Variabili d'ambiente del processo. |
| `sys getuid` / `sys getgid` | `=> Int` | UID e GID reali del processo (`doas`, strumenti di sicurezza). |
| `sys open mode` / `sys close` / `sys poll` | `String String => Int` / `Int => Int` / `Int Int Int => Int` | Descrittori PAL multipiattaforma e `poll` limitato da `with timeout`. |
| `sys exit` | `Int => ()` | Terminare il processo con codice di uscita. |

---

## 8.5. Caso di Studio Reale: Costruire `rg-wc`, un'utilità Unix parallela

Uniamo tutto ciò che abbiamo imparato dal Capitolo 01 fino a qui in un vero programma di sistema: una versione parallela dello strumento Unix `wc` (contatore di righe e byte per più file) scritta in puro Ridgun:

```ridgun
-- 1. Modelliamo le metriche di un file con un record ADT (Capitolo 06)
type Metriche = file: String, righe: Int, byte: Int

-- 2. Contiamo le interruzioni di riga (codice ASCII 10) con ricorsione di coda TCO (Capitolo 04)
fn :: conta ritorni String Int Int  Int  => Int
      conta ritorni testo  pos fine acum =
        | pos >= fine                   = acum
        | (str char at testo pos) == 10 = conta ritorni testo (pos + 1) fine (acum + 1)
        | otherwise                     = conta ritorni testo (pos + 1) fine acum

fn :: numero di righe String => Int
      numero di righe testo  =  conta ritorni testo 0 (str len testo) 0

-- 3. Analizziamo un file e restituiamo la sua struttura Metriche
fn :: analizza file String   => Metriche
      analizza file percorso =
        contenuto = read file percorso
        || numero di righe contenuto -> n_righe
        || str len contenuto         -> n_byte ||.
        Metriche percorso n_righe n_byte

-- 4. Formattiamo ogni riga e sommiamo i totali con `fold` e `||` (Capitolo 07)
fn :: formatta metrica Metriche => String
      formatta metrica m        =  "{righe m}\t{byte m}\t{file m}"

fn :: somma righe Int Metriche => Int
      somma righe acc m        =  acc + (righe m)

fn :: somma byte Int Metriche => Int
      somma byte acc m        =  acc + (byte m)

fn :: genera rapporto [String] => String
      genera rapporto percorsi =
        metriche = ||map analizza file percorsi
        || map formatta metrica metriche -> righe_fmt
        || fold somma righe 0 metriche   -> totale_r
        || fold somma byte 0 metriche    -> totale_b ||.
        "{righe_fmt}\nTotale: {totale_r} righe, {totale_b} byte"

fn :: main => ()
      main =
        echo (genera rapporto ["README.md", "AGENTS.md"])
```

Fermati un secondo a guardare quelle ~40 righe di codice:
- Non c'è nemmeno un singolo `null`, né un'eccezione incontrollata, né un `Mutex`.
- `conta ritorni` viene compilata in un `loop` nativo con 0 byte di stack grazie alla TCO automatica.
- `||map analizza file percorsi` elabora i file in parallelo su tutti i core della tua CPU, e il blocco `||` calcola simultaneamente le righe formattate, il totale delle righe e il totale dei byte.
- La memoria temporanea viene liberata deterministicamente mediante **`RMM1`/`RMM2`**.
- E quando esegui `ridgunc build rg_wc.rg -o rg-wc`, ottieni un binario nativo autonomo da ~350 KB pronto da copiare in `/usr/local/bin`.

---

## 8.6. Tabella di Marcia Finale: Le 10 Regole d'Oro del Programmatore Ridgun

1. **Scrivi sempre prima il contratto (`=>`) e poi le equazioni (`=`):** pensare prima ai tipi fa sì che il compilatore lavori per te.
2. **Lascia che `stable format` impagini le tue tabelle:** scrivi con uno spazio e lascia che lo strumento allinei colonne, `=>`, `=` e `->`.
3. **Ricorda la regola universale dell'`=`:** dietro qualsiasi `=` puoi aprire un blocco sequenziale, un albero di guardie `|` o un grafo parallelo `||`.
4. **Usa `|.` e `||.` solo quando chiudi un blocco annidato per tornare a un livello superiore:** mantieni gli alberi decisionali profondi compatti e senza ambiguità.
5. **Immutabile per impostazione predefinita (`x = ...`), mutabile esplicito (`mut x = ...`):** usa `mut` unicamente quando un accumulatore locale lo richiede davvero.
6. **Usa operatori booleani chiari in minuscolo (`and`, `or`, `xor`, `not`) e chiudi sempre le tue guardie con `| otherwise =`.**
7. **Modella il tuo dominio con ADT (`type`):** usa record con `with campo: valore` e tipi somma (`Option`, `Result`) invece di `null`.
8. **Parallelizza dichiarando le dipendenze con `|| expr -> var` e `||map` / `||filter`:** lascia che il compilatore verifichi l'assenza di cicli e distribuisca il lavoro tra i core.
9. **Dai dimensioni simboliche ai tuoi Tensori (`Tensor[N, K]`) e pedici alle tue contrazioni (`a_ik @ b_kj`).**
10. **Affidati a `RMM` (`RMM1`/`RMM2`), delimita gli input esterni con `with region` e verifica sempre con `stable check` e `stable test`.**

Buon viaggio programmando in Ridgun!
