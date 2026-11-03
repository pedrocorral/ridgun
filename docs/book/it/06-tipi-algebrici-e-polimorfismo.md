# Capitolo 06: Tipi di Dati Algebrici (ADT), Polimorfismo e perché qui non vogliamo `null` né `Any`

Nel 1965, Tony Hoare inventò il riferimento nullo (`null` / `nil`). Quarant'anni dopo chiese pubblicamente scusa e lo definì *"il mio errore da un miliardo di dollari"*.

Perché? Perché nei linguaggi con `null`, una funzione ti promette nella sua firma che ti restituirà un `Utente`... e quando meno te lo aspetti ti restituisce `null` e ti butta giù il server alle tre del mattino.

E altrettanto succede con l'ereditarietà degli oggetti e il tipo `Any` (o `Object`): metti un numero e un testo in una lista `[1, "due"]`, il linguaggio alza le spalle e dice *"va bene, allora adesso questa è una `List[Any]`, buona fortuna a indovinare cosa c'è dentro quando la percorrerai"*.

In Ridgun tagliamo entrambi i problemi alla radice con i **Tipi di Dati Algebrici (ADT)** e il **Polimorfismo Parametrico**. Suona come il nome di un esame tosto, ma in cinque minuti vedrai che è il modo più naturale del mondo per modellare i dati.

---

## 6.1. Tipi Prodotto (Record): I tuoi soliti `struct`, ma con i superpoteri

Quando vuoi raggruppare diversi dati che appartengono a una stessa entità (ad esempio, un server con il suo nome, il suo IP e la sua porta), definisci un **`type`** con i suoi campi:

```ridgun
type Server = host: String, porta: Int, tls_attivo: Bool
```

Scrivendo solo quella riga, Ridgun ti regala **quattro cose** automaticamente:

### 1. Il costruttore `Server`
```ridgun
fn :: mio nodo => Server
      mio nodo =  Server "api.esempio.it" 443 True
```

### 2. Una funzione *getter* pura per ogni campo (`host`, `porta`, `tls_attivo`)
Non devi scrivere `s.getHost()` né nulla di simile; ogni nome di campo è direttamente una funzione che estrae quel dato:

```ridgun
fn :: url connessione Server => String
      url connessione srv    =  "Connettere a " + (host srv) + " sulla porta {porta srv}"
```

### 3. Aggiornamento funzionale dei record (`with campo: valore`)
Immagina un record di configurazione con 12 o 15 campi (come le opzioni di un comando `ls` o di un server web) e vuoi cambiare solo uno o due campi senza toccare il resto. Invece di ricostruire il record passando i 15 campi a mano, usi **`with`** e i due punti **`:`** (esattamente come nella definizione del `type`):

```ridgun
fn :: attiva modalita dev Server => Server
      attiva modalita dev srv    =  srv with porta: 8080, tls_attivo: False
```

Il meglio dei due mondi:
- Nel tuo codice è **100% immutabile e sicuro** (il compilatore controlla che `porta` e `tls_attivo` esistano in `Server` e abbiano il tipo corretto).
- Sotto il cofano, se `srv` non è condiviso con nessun altro, l'eseguibile nativo riutilizza la sua memoria *in-place* (`Arc::try_unwrap`) senza copiare il resto dei campi.

### 4. *Pattern matching* completo se vuoi aprire il record da cima a fondo
```ridgun
fn :: e porta sicura Server             => Bool
      e porta sicura (Server _ 443 True) =  True
      e porta sicura _                   =  False
```

---

## 6.2. Tipi Somma (Varianti con `|`): Come mandare in pensione `null`, le eccezioni e l'ereditarietà

Ora viene il bello.
Un record normale ha `host` **E** `porta` **E** `tls_attivo`.
Ma nel mondo reale molte volte hai bisogno di dire: *"Un metodo di pagamento è **O** una carta con il suo numero, **O** un bonifico con il suo IBAN, **O** contanti (che non portano alcun dato extra)"*.

Nella programmazione orientata agli oggetti dovresti creare un'interfaccia `MetodoPagamento`, tre sottoclassi in tre file diversi, costruttori, `instanceof`... In Ridgun è **una riga**:

```ridgun
type MetodoPagamento = Carta String Int | Bonifico String | Contanti
```

E guarda cosa succede quando elabori un `MetodoPagamento` in una funzione:

```ridgun
fn :: descrivi pagamento MetodoPagamento => String
      descrivi pagamento (Carta num _)   =  "Pagamento con carta che termina con {num}"
      descrivi pagamento (Bonifico iban) =  "Bonifico dal conto {iban}"
      descrivi pagamento Contanti        =  "Pagamento in contanti allo sportello"
```

Ogni variante (`Carta`, `Bonifico`, `Contanti`) porta attaccati unicamente i dati che hanno senso per lei. È **impossibile** costruire un pagamento in `Contanti` che abbia un `iban` appeso per errore.

---

## 6.3. "E come metto `[1, "due"]` in una lista senza usare `Any`?"

Torniamo alla domanda da un milione di dollari. Immagina di leggere un file CSV o JSON in cui una cella può essere un numero intero, un testo o essere vuota.

Se avessi un tipo `Any`, metteresti `[1, "due"]` e perderesti tutto l'aiuto del compilatore: da quel momento in poi qualsiasi operazione sulla lista sarebbe camminare bendati.

In Ridgun (proprio come in Haskell o Rust), crei in due secondi un tipo somma che spiega esattamente quali cose possono vivere dentro quella lista:

```ridgun
type ValoreCella = Intero Int | Testo String | Vuoto

fn :: formatta cella ValoreCella => String
      formatta cella (Intero n)  =  "Numero: {n}"
      formatta cella (Testo s)   =  "Testo: {s}"
      formatta cella Vuoto       =  "(vuoto)"

fn :: mia riga => [ValoreCella]
      mia riga =  [Intero 1, Testo "due", Vuoto]
```

Vedi la differenza?
- Con `Any`, il compilatore non sa se nella lista ci sono interi, stringhe o una caffettiera collegata via USB.
- Con `[ValoreCella]`, puoi mescolare numeri e testi nella stessa lista, **ma il compilatore sa al 100% che esistono solo quelle tre possibilità** e ti obbliga a spacchettare ogni caso (`Intero n`, `Testo s`, `Vuoto`) prima di usarlo. Sicurezza totale senza perdere nemmeno un briciolo di flessibilità.

---

## 6.4. `Option` e `Result`: Quando qualcosa può non esserci o può fallire

Poiché in Ridgun non esiste `null` né esistono eccezioni che saltano per aria (`throw new Exception()`), il linguaggio porta integrati due tipi somma universali:

1. **`Option`**: o hai **`Some valore`**, o hai **`None`** (niente).
2. **`Result`**: o l'operazione è andata bene (**`Ok valore`**), o è fallita per un motivo preciso (**`Err errore`**).

```ridgun
fn :: cerca divisione Int Int => Result
      cerca divisione _   0   =  Err "Ehi! Non si può dividere per zero"
      cerca divisione a   b   =  Ok (a / b)

fn :: stampa ris Result    => ()
      stampa ris (Ok n)    =  echo "Il risultato è {n}"
      stampa ris (Err msg) =  echo "Errore controllato: {msg}"
```

Nessuno può ignorare un errore per distrazione perché lo stesso tipo `Result` ti obbliga a guardare se dentro c'è un `Ok` o un `Err`.

---

## 6.5. Polimorfismo Parametrico: Funzioni generiche con `A`, `B`, `T`...

Supponi di scrivere una funzione che inverte una coppia `(x, y)` o che estrae il primo elemento di una lista. Importa davvero se la lista è di `Int`, di `String` o di `Server`? Proprio per niente! L'algoritmo è identico.

In Ridgun, **qualsiasi lettera maiuscola singola (`A`..`Z`)** in una firma dei tipi funziona automaticamente come un **tipo jolly polimorfico (variabile di tipo)**:

```ridgun
fn :: testa sicura [A]   A           => A
      testa sicura []    predefinito =  predefinito
      testa sicura (x:_) _           =  x

fn :: gira coppia (A B)  => B A
      gira coppia (x, y) =  (y, x)
```

Nota la magia di `testa sicura [A] A => A` e `gira coppia (A B) => B A`:
- Non è un `Any` incontrollato: dice che **il tipo della lista `[A]`, il tipo del valore `predefinito` (`A`) e il tipo restituito (`A`) devono essere lo stesso**.
- Se chiami `testa sicura [10, 20] 0`, il compilatore tira le somme (`A = Int`) e ti restituisce un `Int`.
- Se chiami `testa sicura ["a", "b"] "nessuno"`, tira le somme (`A = String`) e ti restituisce uno `String`.
- Ma se provi a barare e chiami `testa sicura [10, 20] "nessuno"`, zac! Il compilatore ti ferma su due piedi perché il primo argomento dice che `A` è `Int` e il secondo dice che `A` è `String`.

---

## 6.6. Crea i tuoi operatori (`op ::`): Dai vettori alle frasi su misura

Perché solo i numeri nativi dovrebbero avere il diritto di usare `+` o `*`? E perché accontentarsi dei soliti operatori quando puoi inventare la sintassi perfetta per il tuo problema?

Con **`op ::`** (o direttamente senza prefisso se usi pattern di operatore) puoi fare due prodezze:

### 1. Insegnare a `+`, `-`, `*`, `/`, `%` a operare con i tuoi tipi
```ridgun
type Complesso = reale: Int, immag: Int

op :: Complesso + Complesso => Complesso
      a         + b         =  Complesso ((reale a) + (reale b)) ((immag a) + (immag b))
```

### 2. Creare operatori *Mixfix* (che si leggono come frasi naturali, inclusi `type` e `with`)
In una firma di operatore, **le parole con iniziale maiuscola (`Int`, `String`, `A`..`Z`) o tra parentesi quadre/tonde (`[Int]`, `(A, B)`) sono gli slot per gli argomenti**, e **le parole in minuscolo fanno parte della frase dell'operatore** (incluse parole comunissime come `type` o `with`, che in Ridgun sono contestuali e non ti bloccano mai):

```ridgun
op :: se Bool allora A altrimenti A => A
      se True allora v altrimenti _ =  v
      se False allora _ altrimenti f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  messaggio = se (10 > 5) allora "Vince il dieci!" altrimenti "Impossibile"
  echo messaggio
  echo (format "panel" type "bordered" with 80)
```

Ti sei appena costruito il tuo operatore ternario polimorfico e un DSL di formattazione in **3 righe** di Ridgun.

---

## 6.7. Costruttori condivisi, varianti di tipo diretto, `expand type` e spazi naturali in `fn ::`

Ridgun porta i tipi algebrici e le funzioni un passo oltre in espressività ed estensibilità:

1. **Costruttori condivisi tra diversi `type`**: Più tipi somma possono riutilizzare lo stesso nome di costruttore (`Error`, `Var`, `Lit`) con uguale o diversa arità; il verificatore dei tipi li distingue in base alla colonna della firma.
2. **Varianti con nome di tipo diretto (`type Something = String | Int | MyStruct Float Int`)**: Quando una variante è un tipo primitivo (`String`, `Int`, `Float`/`Real`, `Bool`, `Char`), non hai bisogno di ripetere `Int Int` né `String String`. Puoi passare valori diretti (`"ciao"`, `42`) o costruttori espliciti (`String "ciao"`, `Int 42`), e fare pattern matching sia con letterali (`"admin"`, `0`) sia con pattern tipizzati (`(String s)`, `(Int n)`).
3. **Estensione aperta dei tipi (`expand type`) e fusione automatica delle clausole `fn ::`**: Con `expand type` puoi aggiungere nuove varianti a un tipo somma o nuovi campi a un record. Ridichiarando `fn ::` per la stessa funzione, le nuove clausole vengono fuse automaticamente **prima** di qualsiasi clausola jolly `_` (senza bisogno di scrivere `expand fn`).
4. **Spazi naturali `" "` invece di `_` in `fn ::`, funzioni native e nomi di file**: Proprio come in `op ::`, i nomi di funzione in `fn ::`, le chiamate a funzioni native (`assert equals`, `str len`, `read file`) e i file `.rg` (`test core language.rg`) possono essere scritti con spazi naturali:

```ridgun
type Something = String | Int | MyStruct Float Int

fn :: descrivi qualcosa Something            => String
      descrivi qualcosa "admin"              =  "admin_speciale"
      descrivi qualcosa 0                    =  "zero"
      descrivi qualcosa (String   s)         =  "testo:{s}"
      descrivi qualcosa (Int      n)         =  "intero:{n}"
      descrivi qualcosa (MyStruct ratio cnt) =  "struttura:{ratio}:{cnt}"
      descrivi qualcosa _                    =  "altro"

expand type Something = Bool

fn :: descrivi qualcosa Something => String
      descrivi qualcosa (Bool b)  =  "booleano:{b}"
```

### 5. Tipi generici personalizzati (`type Result T E`, `type Page T`) e namespace di modulo (`import ... as`, `mod.Tipo`)
Oltre alle funzioni polimorfiche, puoi dichiarare **i tuoi tipi somma e record generici** con parametri di tipo (`A`..`Z`), nonché organizzare tipi, costruttori, campi e funzioni con lo stesso nome in moduli diversi senza collisioni (`module ::`, `import db as d`, `http.Config`, `d.Config`). Ogni modulo ha **visibilità stretta per importazione su 3 livelli**: risolve i nomi senza prefisso cercando prima nelle **(1) proprie dichiarazioni** (inclusi più file che condividano `module :: nome`), poi nei **(2) suoi `import` diretti** e solo in ultimo luogo nei **(3) suoi `import` transitivi**, in modo che altri moduli fratelli o l'applicazione principale non contaminino mai una libreria importata:

```ridgun
type Risultato T E = Successo T | Fallimento E
type Pagina T      = elementi: [T], totale: Int

fn :: spacchetta successo (Risultato A String) A => A
      spacchetta successo (Successo v)         _ =  v
      spacchetta successo (Fallimento _)       d =  d
```

Nel **Capitolo 07** metteremo tutti i core del tuo processore a lavorare contemporaneamente senza versare una goccia di sudore: **funzioni di ordine superiore (`map`, `||map`, `filter`, `||filter`, `fold`), chiusure lessicali (`(x => expr)`), grafi paralleli `||` con `->` e canali concorrenti**.
