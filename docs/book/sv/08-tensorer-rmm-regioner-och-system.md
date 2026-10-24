# Kapitel 08: Tensorer, kompilerat RMM-minne (`RMM1`/`RMM2`), regioner och system

Hittills har vi sett den mest vänliga, eleganta och matematiska sidan av Ridgun: rena funktioner, algebraiska datatyper, mönstermatchning, beslutsträd med `|` / `|.` och parallella `||`-grafer med `->` som utnyttjar alla kärnor i din processor utan att kräva ett enda ynka `Mutex`.

Vid det här laget brukar den erfarna systemprogrammeraren längst bak i salen räcka upp handen med ett snett leende och fråga:

> *"Allt det här är jättefint för att räkna på fakturor eller kompilera AST-träd, men vad händer när jag behöver multiplicera matriser med miljontals flyttal i svindlande fart? Vad händer med minnet? Ligger det en skräpsamlare (Garbage Collector) gömd under mattan och väntar på sämsta tänkbara ögonblick för att frysa mitt program i 200 millisekunder? Och hur pratar jag med operativsystemet Unix på riktigt?"*

Utmärkta frågor. Låt oss lyfta på motorhuven till Ridgun och se hur det beter sig när det är dags att kavla upp ärmarna i systemprogrammering, numeriska beräkningar och deterministiskt minne.

---

## 8.1. Minnesdilemmat: varken Garbage Collector eller bråk med Borrow Checker (`RMM1` och `RMM2`)

I de moderna språkens värld brukar det finnas två oförenliga läger:

1. **Garbage Collector-lägret (Java, Go, Python, JS, Haskell, OCaml):** du begär glatt mer minne och då och då stannar en osynlig sopbil all trafik i ditt program för att spåra vilka objekt som fortfarande lever och vilka som är döda. Det är hur bekvämt som helst... ända tills du bygger ett blixtsnabbt systemverktyg eller en server med strikta svarstider och sopbilen bestämmer sig för att dubbelparkera.
2. **Manuell kontroll / Borrow Checker-lägret (C, C++, Rust):** det finns ingen skräpsamlare, men i gengäld måste du hantera pekare för hand (med risk för `Segmentation fault` eller *use-after-free*) eller ägna en halv eftermiddag åt att förhandla med *borrow checker* om varför `'a` inte lever lika länge som `'b`.

Ridgun löser detta dilemma från grunden med **Ridgun Memory Management (`RMM`)**, ett deterministiskt system med två kompletterande policyer (**`RMM1`** och **`RMM2`**) kombinerat med **lexikala regioner (`with region`)**:

### Policy `RMM1` — Kompilerad minneshantering (Linjär och villkorlig CMM)
När kompilatorn statiskt känner till flödet av lokala variabler inuti en funktion:
- **Linjär CMM**: `ridgunc` beräknar vid kompileringstillfället vilken som är den **sista raden** där varje lokal variabel (`a`, `b`, ...) läses och skjuter direkt efter den in dess deterministiska frigörning (`rg_cmm_drop`), eller överför ägarskapet utan kopiering (`rg_cmm_move`) när variabeln returneras som resultat.
- **Villkorlig CMM (`ptr(a) != ptr(c)`)**: men vad händer om en funktion som `valj cond a b` returnerar `a` eller `b` beroende på ett villkor vid körning? Då bygger `ridgunc` upp härkomsttabellen och genererar en pekaridentitetsvakt på **1 CPU-cykel**: om `b` slutar användas medan `c` fortfarande lever, kontrollerar den `if ptr(b) != ptr(c) { free(b) }`. Den gren som inte valdes frigörs omedelbart och den valda överlever intakt.

### Policy `RMM2` — Tilldelningsräkning och strukturell kaskad
Och vad händer när du stoppar in strukturer i andra strukturer (`xs = [a, b]`), tilldelar om muterbara variabler (`mut x = ...`) eller kedjar ihop komplexa anrop? Där kliver **`RMM2`** in och styr hela livscykeln med fyra vattentäta matematiska regler:

1. **Inkommande funktionsargument rörs inte (`+0` vid inträde, `-0` vid utträde)**: att skicka en lista eller en post till en funktion ökar eller minskar aldrig några räknare i onödan.
2. **Varje tilldelning till en intern lokal variabel eller behållarcell lägger till `+1`**:
   - `a = [10, 20]` $\rightarrow$ blocket `M1` föds med räknaren `1`.
   - `xs = [a, b]` $\rightarrow$ listan `xs` föds med `1`, och eftersom den sparar referenser till `a` och `b` stiger båda till `2`.
   - Om du tilldelar om en muterbar variabel (`mut x = ...` och sedan `x = ny`), lägger `RMM2` först på **`+1`** på det nya värdet innan den drar av **`-1`** från det gamla.
3. **När funktionen avslutas får lokala variabler som INTE returneras `-1`**: om en strukturs räknare når `0` frigörs dess minne på fläcken och **sprider `-1` i kaskad, ett i taget, till vart och ett av dess direkta barn**.
4. **Värdet som returneras av funktionen undantas under transporten**: det får sitt `-1` som lokal variabel men förstörs inte när det passerar `return`, så att när anroparen skriver `c = min_funktion ()`, lämnar tilldelningens `+1` räknaren på exakt `1`.

```ridgun
valj Bool [Int] [Int] => [Int]
valj cond a     b     =
  | cond      = a
  | otherwise = b

exempel_rmm2 Bool => Int
exempel_rmm2 cond =
  a = [10, 20, 30]         -- M1 (rc = 1)
  b = [40, 50, 60]         -- M2 (rc = 1)
  c = valj cond a b        -- `c` får +1; den som inte valdes dör precis här (rc -> 0)
  (rakna a) + (rakna c)    -- Vid slutet får `a` och `c` -1 och 0 levande block återstår
```

---

## 8.2. Lexikala regioner med kvot (`with region`): Minnesbrandväggar i $O(1)$

Utöver `RMM1` och `RMM2` kan du, när du bearbetar ett externt nätverkspaket, en enorm fil eller ett parti opålitliga data och vill sätta ett **strikt tak för RAM-minnet**, kapsla in beräkningen i ett **`with region`**-block:

```ridgun
bearbeta_ram String => Result
bearbeta_ram radata =
  with region 64_KB do
    rena = map rensa_rad (dela_rader radata)
    rakna_giltiga rena
```

1. **Garanterad kvot i hårdvara/körtidsmiljö**: om något inuti blocket försöker reservera ens en enda byte över `64_KB` (`65 536` byte) avbryter körtidsmiljön blocket snyggt, frigör hela den tillfälliga arenan på konstant tid $O(1)$ och returnerar `Err OutOfMemory` utan att krascha processen.
2. **Omedelbar frigörning vid utträde**: så fort `with region`-blocket avslutas försvinner allt tillfälligt minne i arenan i ett enda slag utan att lämna någon fragmentering.

---

## 8.3. Inbyggda tensorer, Einsteinkontraktion (`@`) och symboliska dimensioner

Om du någonsin har programmerat i Python med NumPy eller PyTorch har du garanterat råkat ut för det klassiska felet efter 41 minuters körning:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

I Ridgun är **`Tensor`** förstklassiga inbyggda medborgare och deras dimensioner är en del av typsignaturen:

```ridgun
-- Om (N × K) och (K × M) går in, måste det ovillkorligen komma ut (N × M)!
multiplicera_matriser Tensor[N, K] Tensor[K, M] => Tensor[N, M]
multiplicera_matriser a            b            =  a_ik @ b_kj
```

Lägg märke till två spektakulära detaljer:
1. **Statisk dimensionsverifiering (`Tensor[N, K]`)**: den inre axeln `K` i den första matrisen måste stämma överens med den första axeln `K` i den andra. Om du försöker skicka in inkompatibla dimensioner stoppar `ridgunc check` dig innan något ens körs.
2. **Einsteins indexnotation (`a_ik @ b_kj`) och Hadamard (`a_ij * b_j`)**:
   - Med **`@`** kontraheras (summeras) de index som upprepas i alla operander (`k`), medan de unika (`i`, `j`) överlever i resultattensorn.
   - Med **`+`, `-`, `*`, `/`** justerar indexen dimensionerna och utför automatisk *broadcasting* (`a_ij * b_j` multiplicerar varje rad `i` i `a` med vektorn `b_j` utan att du behöver skriva `unsqueeze` eller `reshape`).
3. **Högpresterande typade tensorer (`Tensor[U64 * N]`) och mutering *in-place* med `t_(i, j)`**:
   I kryptografiska system, fysiksimuleringar eller linjär algebra kan du deklarera platta tensorer över ett sammanhängande block av teckenlösa 64-bitars heltal (`Tensor[U64 * 4]`, `Tensor[U64 * 8 * 16]`), operera parallellt med `^` (inbyggd block-XOR) och läsa eller skriva element på $O(1)$-tid med den uttryckliga indexsyntaxen `t_(i)` eller `t_(i, j)`:
   ```ridgun
   skapa_tillstandsblock => Tensor[U64 * 2 * 2]
   skapa_tillstandsblock =
     mut m = tensor fill [2, 2] (u64 0)
     m_(0, 1) = u64 0x6a09e667f3bcc908
     m
   ```

---

## 8.4. Kontextvariabler (`context ::`) och atomärt delat tillstånd (`shared ::`)

I 99 % av din kod skickar du data som parametrar. Men för den sista procenten där du behöver miljökonfiguration eller en global räknare mellan trådar utan att förorena 40 mellanliggande signaturer erbjuder Ridgun två uttryckliga och säkra mekanismer:

### 1. `context ::` — Dynamisk räckvidd isolerad per uppgift (`with ... = ... do`)
```ridgun
context :: logg_sokvag : String = "/var/log/app.log"

logga_handelse String => ()
logga_handelse msg    =  echo "[{logg_sokvag}] {msg}"

main => ()
main =
  logga_handelse "Normal start"
  with logg_sokvag = "/tmp/test.log" do
    logga_handelse "Inuti det isolerade testet"
```

### 2. `shared ::` och `atomic` — Samtidigt tillstånd med atomärt lås per rad
```ridgun
shared :: totala_anrop : Int = 0

registrera_besok => Int
registrera_besok =
  atomic totala_anrop = totala_anrop + 1
  totala_anrop
```

---

## 8.5. Hårdvaruåtkomst (`hardware ::`) och POSIX-systemprimitiver

Själva kompilatorn `ridgunc`, bygghanteraren `stable` och Unix-systemverktyg är skrivna i Ridgun. För detta innehåller språket minnesmappade registerblock (`hardware ::`) och direkta POSIX-primitiver:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

Och för att arbeta med operativsystemet:

| Primitiv | Signatur | Vad den gör |
|---|---|---|
| `cli_args` | `=> [String]` | Kommandoradsargument (`argv`). |
| `read_file` / `write_file` | `String => String` / `String String => ()` | Läsning och skrivning av hela filer på disk. |
| `read_bytes` / `write_bytes` | `String => [Int]` / `String [Int] => ()` | Exakt binär läsning och skrivning byte för byte (`0..255`). |
| `list_dir` / `file_lstat` | `String => [String]` / `String => ...` | Listning av kataloger och inspektion av POSIX-metadata (`lstat`). |
| `sha256_file` / `sha256_str` / `sha256_raw` | `String => String` | Inbyggd kryptografisk SHA-256-hash (64 tecken hexadecimalt eller rått 32-bytes binärt sammandrag med `sha256 raw` / `sha256 bytes`). |
| `sys_exec` / `shell_exec` | `... => Int` | Körning av operativsystemprocesser. |
| `sys_getcwd` / `sys_chdir` | `=> String` / `String => Int` | Fråga efter eller byt aktuell arbetskatalog. |
| `sys_getenv` / `sys_setenv` | `String => String` / `String String => Int` | Processens miljövariabler. |
| `sys_getuid` / `sys_getgid` | `=> Int` | Processens faktiska UID och GID (`doas`, säkerhetsverktyg). |
| `sys_exit` | `Int => ()` | Avsluta processen med returkod. |

---

## 8.6. Ekosystemet av standardbibliotek (`ridgun-libs`)

Utöver kompilatorns primitiver innehåller Ridguns officiella ekosystem **32 rena bibliotek (`.rglib`)** skrivna helt i Ridgun som du kan importera med `import <namn>` i vilket projekt som helst:

| Kategori | Tillgängliga bibliotek | Vad de tillhandahåller |
|---|---|---|
| **Samlingar, text och data** | `collections`, `set`, `string`, `regex`, `utf8`, `fmt`, `csv`, `json`, `toml`, `yaml`, `xml`, `html`, `markdown`, `base64`, `hex`, `compress`, `sql` | Avbildningar, mängder, reguljära uttryck, strukturerade tolkar/serialiserare, kodning och frågemotorer. |
| **Matematik, tid och slumptal** | `math`, `random`, `datetime`, `uuid`, `log`, `cli`, `bench`, `test` | Matematiska funktioner, deterministisk och systembaserad PRNG, ISO-8601-datum, UUID, testramverk och prestandamätningar med `clock_gettime`. |
| **System, nätverk och webb** | `fs`, `path`, `process`, `env`, `net`, `http`, `uri` | Högnivåfilsystem, sökvägshantering, underprocesser, TCP/UDP-uttag samt HTTP-klient och -server. |
| **Kryptografi och säkerhet (`crypto`)** | `crypto` (`sha256`, `hmac`, `hkdf`, `pbkdf2`, `argon2id`, `chacha20`, `aes`, `x25519`, `ed25519`, `csprng`) | Kryptografisk svit verifierad mot officiella RFC/NIST-vektorer, implementerad över `U64`, `Tensor[U64 * ...]` och `sha256 raw` med tupel-inlining utan heap-allokeringar. |

---

## 8.7. Verklig fallstudie: Vi bygger `rg-wc`, ett parallellt Unix-verktyg

Låt oss knyta ihop allt vi har lärt oss från Kapitel 01 fram till hit i ett riktigt systemprogram: en parallell version av Unix-verktyget `wc` (rad- och byteräknare för flera filer) skriven i ren Ridgun:

```ridgun
-- 1. Vi modellerar mätvärdena för en fil med en ADT-post (Kapitel 06)
type Matvarden = fil: String, rader: Int, bytes: Int

-- 2. Vi räknar radbrytningar (ASCII-kod 10) med TCO-svansrekursion (Kapitel 04)
fn :: rakna_radbrytningar String Int Int  Int => Int
      rakna_radbrytningar text   pos slut ack =
        | pos >= slut                   = ack
        | (str_char_at text pos) == 10  = rakna_radbrytningar text (pos + 1) slut (ack + 1)
        | otherwise                     = rakna_radbrytningar text (pos + 1) slut ack

fn :: antal_rader String => Int
      antal_rader text   =  rakna_radbrytningar text 0 (str_len text) 0

-- 3. Vi analyserar en fil och returnerar dess Matvarden-struktur
fn :: analysera_fil String  => Matvarden
      analysera_fil sokvag  =
        innehall = read_file sokvag
        || antal_rader innehall -> n_rader
        || str_len innehall     -> n_bytes ||.
        Matvarden sokvag n_rader n_bytes

-- 4. Vi formaterar varje rad och summerar totaler med `fold` och `||` (Kapitel 07)
fn :: formatera_matvarde Matvarden => String
      formatera_matvarde m         =  "{rader m}\t{bytes m}\t{fil m}"

fn :: summera_rader Int Matvarden => Int
      summera_rader acc m         =  acc + (rader m)

fn :: summera_bytes Int Matvarden => Int
      summera_bytes acc m         =  acc + (bytes m)

fn :: generera_rapport [String] => String
      generera_rapport sokvagar =
        matvarden = ||map analysera_fil sokvagar
        || map formatera_matvarde matvarden -> rader_ut
        || fold summera_rader 0 matvarden   -> total_r
        || fold summera_bytes 0 matvarden   -> total_b ||.
        "{rader_ut}\nTotalt: {total_r} rader, {total_b} byte"

fn :: main => ()
      main =
        echo (generera_rapport ["README.md", "AGENTS.md"])
```

Stanna upp en sekund och titta på dessa ~40 rader kod:
- Det finns inte ett enda `null`, inget okontrollerat undantag och inget `Mutex`.
- `rakna_radbrytningar` kompileras till en inbyggd `loop` med 0 byte stackminne tack vare automatisk TCO.
- `||map analysera_fil sokvagar` bearbetar filerna parallellt på alla kärnor i din processor, och `||`-blocket beräknar samtidigt de formaterade raderna, totalt antal rader och totalt antal byte.
- Det tillfälliga minnet frigörs deterministiskt via **`RMM1`/`RMM2`**.
- Och när du kör `ridgunc build rg_wc.rg -o rg-wc` får du en fristående inbyggd binär på ~350 KB, färdig att kopieras till `/usr/local/bin`.

---

## 8.8. Slutlig färdplan: Ridgun-programmerarens 10 gyllene regler

1. **Skriv alltid kontraktet (`=>`) först och ekvationerna (`=`) sedan:** att tänka på typerna först får kompilatorn att arbeta åt dig.
2. **Låt `stable format` formge dina tabeller:** skriv med ett mellanslag och låt verktyget rada upp kolumner, `=>`, `=` och `->`.
3. **Kom ihåg den universella regeln för `=`:** efter vilket `=` som helst kan du öppna ett sekventiellt block, ett vaktträd `|` eller en parallell graf `||`.
4. **Använd `|.` och `||.` endast när du stänger ett nästlat block för att återvända till en högre nivå:** håll djupa beslutsträd kompakta och entydiga.
5. **Oföränderligt som standard (`x = ...`), uttryckligt föränderligt (`mut x = ...`):** använd `mut` endast när en lokal ackumulator verkligen kräver det.
6. **Använd tydliga booleska operatorer i gemener (`and`, `or`, `xor`, `not`) och avsluta alltid dina vakter med `| otherwise =`.**
7. **Modellera din domän med ADT (`type`):** använd poster med `with falt: varde` och summatyper (`Option`, `Result`) i stället för `null`.
8. **Parallellisera genom att deklarera beroenden med `|| expr -> var` samt `||map` / `||filter`:** låt kompilatorn verifiera att det inte finns några cykler och fördela arbetet mellan kärnorna.
9. **Sätt symboliska dimensioner på dina tensorer (`Tensor[N, K]`) och index på dina kontraktioner (`a_ik @ b_kj`).**
10. **Lita på `RMM` (`RMM1`/`RMM2`), avgränsa extern indata med `with region` och verifiera alltid med `stable check` och `stable test`.**

Lycka till på resan med att programmera i Ridgun!
