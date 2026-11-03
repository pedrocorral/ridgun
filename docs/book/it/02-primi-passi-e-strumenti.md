# Capitolo 02: I tuoi due migliori amici: `ridgunc` e `stable` (Zero file YAML, promesso)

Ci sono linguaggi il cui compilatore è meraviglioso, ma il cui sistema di progetti sembra progettato dal tuo peggior nemico: ora un `Makefile` di 400 righe con tabulazioni invisibili, ora un `pom.xml` infinito, ora un `webpack.config.js` che smette di funzionare se lo guardi fisso...

In Ridgun ci siamo fatti una promessa semplicissima fin dal primo giorno:

> *"Ci saranno solo due eseguibili in tutto l'ecosistema (`ridgunc` e `stable`), entrambi saranno scritti nello stesso Ridgun, e il file di configurazione del progetto (`build.rg`) sarà normale codice Ridgun. Né JSON, né YAML, né TOML, né invenzioni strane."*

Vediamo come si usano.

---

## 2.1. `ridgunc`: Il cecchino per file singoli

Quando hai per le mani un singolo file `.rg` e vuoi provare un'idea veloce, analizzarne i tipi o compilare un eseguibile, parli direttamente con **`ridgunc`**.

Ha solo 5 comandi che devi davvero ricordare:

```bash
# 1. "Compila questo o ho combinato un pasticcio con qualche tipo?"
ridgunc check esperimento.rg

# 2. "Eseguilo subito!" (Compila ed esegue in un colpo solo)
ridgunc run esperimento.rg

# 3. "Fammi un binario nativo ELF64 pronto da portare via"
ridgunc build esperimento.rg -o mio-programma

# 4. "Compilami una libreria riutilizzabile (.rglib e .so ELF64 senza bisogno di main)"
ridgunc build --lib utilita.rg -o target/utilita.rglib
ridgunc build --so  utilita.rg -o target/libutilita.so

# 5. "Tirami fuori l'artefatto intermedio di bytecode (.rgc)"
ridgunc compile esperimento.rg -o esperimento.rgc
```

### Il superpotere nascosto di `ridgunc check`
Quando lanci `ridgunc check`, non ti dice solo *"0 errori"*. Ti svela anche quale strategia ha scelto l'analizzatore statico per ciascuna delle tue funzioni:
- **`InlineSequential`**: *"Questa funzione è piccolina e diretta; la eseguirò in linea senza aggiungere sovraccarico di pianificazione"*.
- **`LazyStealableTask`**: *"Qui c'è ricorsione o un grafo parallelo `||`; la preparo affinché altri core della CPU possano rubare lavoro se necessario"*.

### Il bisturi di `ridgunc build` (Perché i tuoi binari non pesano 20 MB)
Quando esegui `ridgunc build`, il compilatore non si limita a sputare fuori tutto il codice delle librerie che hai importato:
1. Parte dalla tua funzione `main` e percorre il grafo delle chiamate per vedere **quali funzioni usi davvero**. Se hai importato una libreria enorme da 80 funzioni ma ne chiami solo 2, le altre 78 vengono scartate prima ancora di toccare l'assembler (*Tree-Shaking*).
2. Cerca tutte le funzioni ricorsive di coda e le converte in cicli `loop` nativi che consumano **0 byte di stack**.
3. Passa il collegamento finale con ottimizzazione globale (*fat LTO*) e pulisce le informazioni di debug DWARF superflue per lasciarti un binario compatto e affilato (~350 KB).

---

## 2.2. `stable`: Quando il tuo progetto cresce e vuoi ordine

Un file singolo è fantastico per uno script, ma non appena hai più moduli, librerie condivise e test, hai bisogno di un direttore d'orchestra. Quello è **`stable`**.

La struttura delle cartelle di un progetto Ridgun non ha misteri:

```text
mio-super-strumento/
├── build.rg                  # Il manifesto del progetto (è codice Ridgun!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # I tuoi moduli riutilizzabili (`import utilita`)
│   │       └── app/
│   │           └── main.rg   # Punto di ingresso (`main => ()`)
│   └── test/
│       └── ridgun/           # Le tue batterie di test (`test *.rg`)
│           └── test tutto.rg
└── target/                   # Dove compaiono i binari compilati
```

---

## 2.3. `build.rg`: Un file di configurazione che non ti mentirà mai

Perché ci rifiutiamo di usare YAML o TOML per configurare un progetto Ridgun?
Perché in YAML sbagli due spazi di indentazione e non te ne accorgi finché non fallisce il deploy. Invece, poiché **`build.rg` è un file Ridgun**, ha tipi statici, passa attraverso `stable check` e si allinea da solo con `stable format`:

```ridgun
fn :: project name => String
      project name =  "mio-super-strumento"

fn :: project version => String
      project version =  "0.1.0"

-- "exe" (eseguibile), "lib" (libreria .rglib + .so) o "both" (entrambi)
fn :: project kind => String
      project kind =  "both"

-- Opzionale: modalità stretta (proibisce '_' nei nomi fn/op ed esige ritorni '=> Int Int')
fn :: strict mode => Bool
      strict mode =  True

fn :: main entry => String
      main entry =  "src/main/ridgun/app/main.rg"

fn :: source dir => String
      source dir =  "src/main/ridgun"

fn :: test dir => String
      test dir =  "src/test/ridgun"

fn :: target dir => String
      target dir =  "target"

fn :: dependencies => [String]
      dependencies =  []

fn :: plugins => [String]
      plugins =  []

fn :: task verificare tutto => String
      task verificare tutto =  "./bin/stable check && ./bin/stable test"
```

Se sbagli a scrivere un campo o un tipo, è lo stesso compilatore ad avvisarti. E nota che tutte le funzioni di configurazione usano **spazi naturali** (`project name`, `project kind`, `source dir`, `task verificare tutto`) invece di trattini bassi.

---

## 2.4. La tua routine quotidiana con `stable` (I fantastici 4)

Quando lavori all'interno del tuo progetto, la tua giornata si riduce a quattro comandi:

### 1. `stable format` — La fine delle discussioni sullo stile nel team
```bash
stable format
```
Il tuo collega mette tre spazi prima di `=>` e tu ne metti uno? Non importa. Esegui `stable format` e in meno di un secondo lascia **tutti** i file `.rg` del repository allineati come una tabella svizzera.

### 2. `stable check` — Il radar istantaneo
```bash
stable check
```
Percorre tutti i moduli di `src/main/ridgun/`, verifica tipi, costruttori, arità e dimensioni dei tensori, e ti dà il verdetto modulo per modulo.

### 3. `stable test` — Dormire tranquilli la notte
```bash
stable test
```
Cerca tutte le suite `src/test/ridgun/test *.rg`, le esegue e controlla ogni `assert equals` e `assert true`.

```ridgun
-- Esempio di src/test/ridgun/test matematica.rg
import test

doppio Int => Int
doppio x   =  x * 2

main => ()
main =
  assert equals (doppio 21) 42
  assert true ((doppio 5) > 0)
```

### 4. `stable built` (e `stable clean`) — In produzione
```bash
stable built
```
Compila tutti gli obiettivi nativi in `target/`. E se un giorno vuoi cancellare `target/` e ripartire da zero: `stable clean`.

---

## 2.5. Creare e usare Librerie Riutilizzabili (`.rglib` e `.so` ELF64) e Plugin di `stable`

Una libreria non ha la funzione `main => ()`: offre tipi (`type`, `expand type`), funzioni (`fn ::`) e operatori (`op ::`) affinché altri progetti li importino.

### 1. Creare un progetto di libreria con `stable`
```bash
stable new --lib geometria
cd geometria
stable built lib
```
Compilando in modalità libreria (`project kind = "lib"` o `stable built lib`), il compilatore disattiva la potatura da `main` per conservare **tutte** le funzioni e i tipi esportati, e genera due artefatti in `target/`:
- **`target/geometria.rglib`**: pacchetto autocontenuto di libreria Ridgun (con tutti i suoi sorgenti e dipendenze interne risolte), pronto per essere importato da qualsiasi altro progetto con `import geometria` o `import "target/geometria.rglib"`.
- **`target/libgeometria.so`**: libreria dinamica nativa ELF64 (`ET_DYN`, per `x86_64` o `arm64-linux`).

```ridgun
-- src/main/ridgun/lib/geometria.rg (Senza funzione main!)
type Punto = x: Int, y: Int

fn :: sposta punto Punto Int Int => Punto
      sposta punto p     dx  dy  =  Punto ((x p) + dx) ((y p) + dy)

fn :: coordinate punto Punto => Int Int
      coordinate punto p     =  (x p, y p)
```

### 2. Come importo un modulo o una libreria da un altro file? (`import`)

Senza percorsi relativi infernali tipo `../../../lib/cose.rg`. Se hai un modulo `src/main/ridgun/lib/geometria.rg` o un pacchetto `geometria.rglib` (in `target/`, `lib/` o `.stable/deps/` dopo aver eseguito `stable deps`), in qualsiasi altro file scrivi in cima:

```ridgun
import geometria
```

E fatto: tutte le funzioni, gli operatori e i tipi di `geometria` sono disponibili come se fossero nel tuo stesso file. Se più moduli fanno `import geometria`, il caricatore di Ridgun ricorda quali file canonici ha già letto e **lo include una sola volta**.

### 3. Estendere `stable` con attività (`fn :: task`) e plugin (`plugins/*.rg`)
Vuoi aggiungere comandi personalizzati per il tuo framework web, le tue migrazioni di database o il tuo flusso di deploy?
- **In `build.rg`**: dichiara qualsiasi funzione `fn :: task <parole...> => String` (ad esempio, `fn :: task avvia server => String`) ed eseguila con `stable avvia server`.
- **In `plugins/*.rg` o `.stable/plugins/*.rg`**: inserisci moduli `.rg` che definiscano attività `fn :: task ...` o il proprio `fn :: main => ()`, oppure estendi il tipo aperto `expand type StableCommand` di `stable`. Esegui `stable tasks` e `stable plugins` per ispezionarli in qualsiasi momento.

### 4. La modalità stretta opzionale (`--strict` e `strict mode = True`)
Per impostazione predefinita, né `ridgunc` né i nuovi progetti creati con `stable new` o `stable init` attivano la modalità stretta. Tuttavia, quando vuoi garantire nel tuo progetto che tutto il team segua al 100% la convenzione canonica degli spazi naturali di Ridgun, puoi passare `--strict` a `ridgunc` (`ridgunc check --strict`, `ridgunc build --strict`) o dichiarare `strict mode = True` nel tuo `build.rg`. La modalità stretta trasforma in **errore di compilazione**:
1. Qualsiasi trattino basso `_` all'interno del nome di una dichiarazione `fn ::` o `op ::` (dovendo scrivere `fn :: calcola totale`, mai `fn :: calcola_totale`; le variabili locali e i campi dei record possono invece usare `_`).
2. Qualsiasi tipo di ritorno multiplo scritto con parentesi o virgole dopo `=>` (dovendo scrivere `=> Int Int` o `=> RToken [RToken]`, mai `=> (Int, Int)`).

---

## 2.6. L'Ecosistema di Librerie Standard e Crittografiche (`ridgun-libs`)

Ridgun dispone di una suite ufficiale di **32 librerie pure** (`ridgun-libs`), compilate come pacchetti `.rglib` e librerie dinamiche `.so` ELF64 pronte da importare con `import <nome>`:

| Famiglia | Librerie (`import ...`) | Cosa portano nei tuoi progetti |
|---|---|---|
| **1. Testo, Formati e Template** | `str`, `fmt`, `regex`, `diff`, `template`, `json`, `csv`, `ini`, `codec` | Manipolazione avanzata di stringhe, formattazione tabellare, espressioni regolari Thompson NFA, differenze Myers (`diff`), template senza logica, parser/serializzatori `json`/`csv`/`ini` e codifica esadecimale/Base64 (`codec`). |
| **2. Collezioni, Matematica e Algebra Tensoriale** | `list`, `btree`, `math`, `tensor`, `linalg` | Operazioni funzionali su liste, B-tree ordinati in memoria (`btree`), aritmetica avanzata (`math`), viste e costruttori di tensori tipizzati (`tensor`) e decomposizione/algebra lineare (`linalg`). |
| **3. Sistema Operativo, File e CLI** | `posix`, `io`, `path`, `glob`, `cli`, `time`, `log`, `uuid`, `test` | Descrittori e segnali POSIX (`posix`), I/O con `with timeout` (`io`), percorsi e pattern (`path`, `glob`), argomenti CLI tipizzati (`cli`), orologi monotonici (`time`), logging strutturato (`log`), RFC 4122 `uuid` e asserzioni (`test`). |
| **4. Crittografia e Sicurezza** | `crypto`, `argon2id`, `jwt` | SHA-256 binario diretto (`sha256 raw` / `sha256 bytes` in 32 byte grezzi), HMAC-SHA-256, PBKDF2-HMAC-SHA-256, HKDF, ChaCha20-Poly1305 AEAD (`crypto`), hashing delle password RFC 9106 `argon2id` su `Tensor[U64 * 8 * 16]` con permutazione BlaMka senza allocare tuple nell'heap (`argon2id`), e token firmati (`jwt`). |
| **5. Reti, Protocolli e Agenti** | `socket`, `http`, `ws`, `agent`, `pool`, `net_agent` | Socket TCP/UDP POSIX (`socket`), client/server HTTP/1.1 (`http`), WebSocket RFC 6455 (`ws`), supervisori di agenti (`agent`), pool di worker (`pool`) e server reattivi orientati agli agenti (`net_agent`). |

Ora che hai la cassetta degli attrezzi e le librerie sotto controllo, passiamo al **Capitolo 03** per padroneggiare le funzioni con spazi naturali, le firme dei tipi e i blocchi.
