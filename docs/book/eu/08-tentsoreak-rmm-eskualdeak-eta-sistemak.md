# 08. kapitulua: Tentsoreak, RMM Memoria Konpilatua (`RMM1`/`RMM2`), Eskualdeak eta Sistemak

Honaino Ridgunen alderdirik atseginena, dotoreena eta matematikoena ikusi dugu: funtzio puruak, datu-mota aljebraikoak, *pattern matching*-a, `|` / `|.` bidezko erabaki-zuhaitzak eta zure prozesadorearen nukleo guztiak `Mutex` triste bat ere eskatu gabe aprobetxatzen dituzten `->` gezidun `||` grafo paraleloak.

Puntu honetara iritsita, sistemetako programatzaile beteranoak eskua altxatu ohi du ikasgelaren atzealdean irribarre erdiarekin eta honako hau galdetu:

> *"Hau guztia ederra da fakturak kalkulatzeko edo ASTak konpilatzeko, baina zer gertatzen da milioika koma higikorreko matrizeak abiadura bizian biderkatu behar ditudanean? Zer gertatzen da memoriarekin? Ba al dago alfonbra azpian ezkutatutako zabor-biltzaile (Garbage Collector) bat unerik txarrenaren zain nire programa 200 milisegundoz izozteko? Eta nola hitz egiten dut benetako Unix sistema eragilearekin?"*

Galdera bikainak. Altxa dezagun Ridgunen kapota sistemen, zenbakizko kalkuluaren eta memoria deterministaren lokatzetara jaistea tokatzen denean nola moldatzen den ikusteko.

---

## 8.1. Memoriaren dilema: ez Garbage Collector-ik, ez Borrow Checker-arekiko borrokarik (`RMM1` eta `RMM2`)

Lengoaia modernoen munduan bi alde adiskidetu ezinak egon ohi dira:

1. **Garbage Collector-aren aldea (Java, Go, Python, JS, Haskell, OCaml):** zuk memoria alai eskatzen duzu eta, noizean behin, zabor-kamioi ikusezin batek zure programaren trafikoa gelditzen du zein objektuk jarraitzen duten bizirik eta zeintzuek ez arakatzeko. Oso erosoa da... sistemako tresna ultra-azkar bat edo latentzia zorrotzeko zerbitzari bat egiten ari zaren arte eta kamioiak bigarren ilaran aparkatzea erabakitzen duen arte.
2. **Eskuzko kontrolaren / Borrow Checker-aren aldea (C, C++, Rust):** ez dago zabor-biltzailerik, baina trukean erakusleak eskuz kudeatu behar dituzu (`Segmentation fault` bat edo *use-after-free* bat jokatuz) edo arratsalde erdia *borrow checker*-arekin negoziatzen eman behar duzu zergatik `'a` ez den `'b` bezainbeste bizi azaltzeko.

Ridgunek dilema hori errotik ebazten du **Ridgun Memory Management (`RMM`)** bidez, bi politika osagarriz (**`RMM1`** eta **`RMM2`**) osatutako sistema determinista bat, **eskualde lexikoekin (`with region`)** konbinatua:

### `RMM1` politika — Memoria Kudeaketa Konpilatua (CMM Lineala eta Baldintzazkoa)
Konpiladoreak funtzio baten barruko aldagai lokalen fluxua estatikoki ezagutzen duenean:
- **CMM Lineala**: `ridgunc`-ek konpilazio-garaian kalkulatzen du zein den aldagai lokal bakoitza (`a`, `b`, ...) irakurtzen den **azken lerroa** eta berehala bere askapen determinista (`rg_cmm_drop`) txertatzen du, edo bere jabetza kopiarik gabe transferitzen du (`rg_cmm_move`) aldagaia emaitza gisa itzultzen denean.
- **CMM Baldintzazkoa (`ptr(a) != ptr(c)`)**: eta `aukeratu cond a b` bezalako funtzio batek exekuzio-garaiko baldintza baten arabera `a` edo `b` itzultzen badu? `ridgunc`-ek arbasoen taula eraikitzen du eta **PUZ ziklo 1eko** erakusle-identitatearen zain bat igortzen du: `b` erabiltzeari uzten bazaio `c` bizirik dagoen bitartean, `if ptr(b) != ptr(c) { free(b) }` egiaztatzen du. Aukeratu ez den adarra berehala askatzen da eta aukeratutakoak osorik irauten du.

### `RMM2` politika — Esleipen bidezko Kontaketa eta Kaskada Estrukturala
Eta zer gertatzen da egiturak beste egitura batzuen barruan sartzen dituzunean (`xs = [a, b]`), aldagai aldakorrak berresleitzen dituzunean (`mut x = ...`) edo dei konplexuak kateatzen dituzunean? Hor sartzen da **`RMM2`**, bizi-ziklo osoa pitzadurarik gabeko lau arau matematikorekin gobernatzen duena:

1. **Funtzio baten sarrerako argumentuak ez dira ukitzen (`+0` sartzean, `-0` irtetean)**: zerrenda edo erregistro bat funtzio bati pasatzeak ez ditu inoiz kontagailuak alferrik handitzen ez txikitzen.
2. **Barneko aldagai lokal batera edo edukiontzi-gelaxka batera egindako esleipen orok `+1` batzen du**:
   - `a = [10, 20]` $\rightarrow$ `M1` blokea `1` kontagailuarekin jaiotzen da.
   - `xs = [a, b]` $\rightarrow$ `xs` zerrenda `1`-ekin jaiotzen da, eta `a` zein `b`-rako erreferentziak gordetzen dituenez, biak `2`-ra igotzen dira.
   - Aldagai aldakor bat berresleitzen baduzu (`mut x = ...` eta gero `x = berria`), `RMM2`-k lehenengo **`+1`** aplikatzen dio balio berriari zaharrari **`-1`** aplikatu aurretik.
3. **Funtziotik irtetean, itzultzen EZ diren aldagai lokalek `-1` jasotzen dute**: egitura baten kontagailua `0`-ra iristen bada, bere memoria berehala askatzen da eta **`-1` kaskadan hedatzen dio, banan-banan, bere seme-alaba zuzen bakoitzari**.
4. **Funtzioak itzulitako balioa iraganean salbuesten da**: aldagai lokaleko bere `-1` jasotzen du baina ez da suntsitzen `return`-a gurutzatzean; horrela, deitu duenak `c = nire_funtzioa ()` egiten duenean, esleipenaren `+1` horrek zehazki `1`-ean uzten du.

```ridgun
aukeratu Bool [Int] [Int] => [Int]
aukeratu cond a     b     =
  | cond      = a
  | otherwise = b

adibidea_rmm2 Bool => Int
adibidea_rmm2 cond =
  a = [10, 20, 30]           -- M1 (rc = 1)
  b = [40, 50, 60]           -- M2 (rc = 1)
  c = aukeratu cond a b      -- `c`-k +1 jasotzen du; aukeratu ez dena hemen bertan hiltzen da (rc -> 0)
  (zenbatu a) + (zenbatu c)  -- Amaitzean, `a`-k eta `c`-k -1 jasotzen dute eta dena 0 bloke bizitan geratzen da
```

---

## 8.2. Kuotadun Eskualde Lexikoak (`with region`): Memoriako suhesiak $O(1)$-ean

`RMM1` eta `RMM2`-z gain, kanpoko sare-pakete bat, fitxategi erraldoi bat edo fidagarriak ez diren datu-sorta bat prozesatzen ari zarenean eta **RAM memoriaren sabai zorrotz bat** jarri nahi duzunean, kalkulua **`with region`** bloke batean biltzen duzu:

```ridgun
prozesatu_bilbea String => Result
prozesatu_bilbea gordina =
  with region 64_KB do
    garbiak = map garbitu_lerroa (banatu_lerroak gordina)
    zenbatu_baliozkoak garbiak
```

1. **Hardwarean/runtimean bermatutako kuota**: blokearen barruan `64_KB`-tik (`65.536` byte) gora byte bakar bat ere erreserbatzen saiatzen bada, runtime-ak blokea garbi abortatzen du, aldi baterako arena osoa $O(1)$ denbora konstantean askatzen du eta `Err OutOfMemory` itzultzen du prozesua bota gabe.
2. **Berehalako askapena irtetean**: `with region` blokea amaitzen den bezain laster, arenako aldi baterako memoria guztia kolpe batez desagertzen da zatikatzarik utzi gabe.

---

## 8.3. Tentsore Natiboak, Einsteinen Uzkurdura (`@`) eta Dimentsio Sinbolikoak

Inoiz Pythonen NumPy edo PyTorch-ekin programatu baduzu, ziur exekuzioko 41. minutuko errore klasikoa pairatu duzula:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

Ridgunen, **`Tensor`**-ak lehen mailako herritar natiboak dira eta haien dimentsioak mota-sinaduraren parte dira:

```ridgun
-- (N × K) eta (K × M) sartzen badira, nahitaez (N × M) ateratzen da!
biderkatu_matrizeak Tensor[N, K] Tensor[K, M] => Tensor[N, M]
biderkatu_matrizeak a            b            =  a_ik @ b_kj
```

Erreparatu bi xehetasun ikusgarri hauei:
1. **Dimentsioen egiaztapen estatikoa (`Tensor[N, K]`)**: lehen matrizearen barneko `K` ardatzak bigarrenaren lehenengo `K` ardatzarekin bat etorri behar du. Bateraezinak diren dimentsioak pasatzen saiatzen bazara, `ridgunc check`-ek ezer exekutatu aurretik gelditzen zaitu.
2. **Einsteinen azpiindizeen notazioa (`a_ik @ b_kj`) eta Hadamard (`a_ij * b_j`)**:
   - **`@`**-rekin, eragile guztietan errepikatzen diren azpiindizeak (`k`) uzkurtu egiten dira (batu egiten dira) eta bakarrak direnak (`i`, `j`) emaitza-tentsorean bizirik ateratzen dira.
   - **`+`, `-`, `*`, `/`**-rekin, azpiindizeek dimentsioak lerrokatzen dituzte eta *broadcasting* automatikoa egiten dute (`a_ij * b_j`-k `a`-ren `i` errenkada bakoitza `b_j` bektorearekin biderkatzen du `unsqueeze` edo `reshape` idatzi beharrik gabe).
3. ***In-place* mutazioa zenbakizko algoritmoetarako**:
   ```ridgun
   sortu_identitate_matrizea => Tensor
   sortu_identitate_matrizea =
     m = Tensor [[1.0, 0.0], [0.0, 1.0]]
     m[0, 1] = 0.5
     m
   ```

---

## 8.4. Testuinguru-Aldagaiak (`context ::`) eta Egoera Partekatu Atomikoa (`shared ::`)

Zure kodearen % 99an datuak parametro bidez pasatuko dituzu. Baina tarteko 40 sinadura kutsatu gabe ingurune-konfigurazioa edo harien arteko kontagailu global bat behar duzun % 1 horretarako, Ridgunek bi mekanismo esplizitu eta seguru eskaintzen ditu:

### 1. `context ::` — Ataza bakoitzeko isolatutako esparru dinamikoa (`with ... = ... do`)
```ridgun
context :: log_bidea : String = "/var/log/app.log"

erregistratu_gertaera String => ()
erregistratu_gertaera msg    =  echo "[{log_bidea}] {msg}"

main => ()
main =
  erregistratu_gertaera "Abio normala"
  with log_bidea = "/tmp/test.log" do
    erregistratu_gertaera "Test isolatuaren barruan"
```

### 2. `shared ::` eta `atomic` — Egoera konkurrentea lerro bakoitzeko blokeo atomikoarekin
```ridgun
shared :: eskaerak_guztira : Int = 0

zenbatu_bisita => Int
zenbatu_bisita =
  atomic eskaerak_guztira = eskaerak_guztira + 1
  eskaerak_guztira
```

---

## 8.5. Hardwarerako Sarbidea (`hardware ::`) eta Sistemen POSIX Primitibak

`ridgunc` konpiladorea bera, `stable` kudeatzailea eta Unix sistemetako tresnak Ridgunen idatzita daude. Horretarako, lengoaiak memorian mapatutako erregistro-blokeak (`hardware ::`) eta POSIX primitiba zuzenak barne hartzen ditu:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

Eta sistema eragilearekin lan egiteko:

| Primitiba | Sinadura | Zer egiten duen |
|---|---|---|
| `cli_args` | `=> [String]` | Komando-lerroko argumentuak (`argv`). |
| `read_file` / `write_file` | `String => String` / `String String => ()` | Diskoko fitxategien irakurketa eta idazketa osoa. |
| `read_bytes` / `write_bytes` | `String => [Int]` / `String [Int] => ()` | Bytez byteko (`0..255`) irakurketa eta idazketa bitar zehatza. |
| `list_dir` / `file_lstat` | `String => [String]` / `String => ...` | Direktorioen zerrendatzea eta POSIX metadatuen ikuskapena (`lstat`). |
| `sha256_file` / `sha256_str` | `String => String` | SHA-256 hash kriptografiko natiboa. |
| `sys_exec` / `shell_exec` | `... => Int` | Sistema eragileko prozesuen exekuzioa. |
| `sys_getcwd` / `sys_chdir` | `=> String` / `String => Int` | Laneko direktorioa kontsultatu edo aldatu. |
| `sys_getenv` / `sys_setenv` | `String => String` / `String String => Int` | Prozesuaren ingurune-aldagaiak. |
| `sys_getuid` / `sys_getgid` | `=> Int` | Prozesuaren benetako UID eta GIDa (`doas`, segurtasun-tresnak). |
| `sys_exit` | `Int => ()` | Prozesua irteera-kodearekin amaitu. |

---

## 8.6. Benetako Kasu-Azterketa: `rg-wc` eraikitzen, Unix tresna paralelo bat

Lotu dezagun 01. kapitulutik honaino ikasitako guztia sistemetako benetako programa batean: Unixeko `wc` tresnaren bertsio paralelo bat (fitxategi anitzetarako lerro- eta byte-kontagailua) Ridgun puruan idatzia:

```ridgun
-- 1. Fitxategi baten metrikak ADT erregistro batekin modelatzen ditugu (06. kapitulua)
type Metrikak = fitxategia: String, lerroak: Int, byteak: Int

-- 2. Lerro-jauziak (ASCII 10 kodea) TCO isats-errekurtsioarekin zenbatzen ditugu (04. kapitulua)
fn :: zenbatu_jauziak String Int Int Int => Int
      zenbatu_jauziak testua pos ama met =
        | pos >= ama                    = met
        | (str_char_at testua pos) == 10 = zenbatu_jauziak testua (pos + 1) ama (met + 1)
        | otherwise                     = zenbatu_jauziak testua (pos + 1) ama met

fn :: lerro_kopurua String => Int
      lerro_kopurua testua =  zenbatu_jauziak testua 0 (str_len testua) 0

-- 3. Fitxategi bat aztertzen dugu eta bere Metrikak egitura itzultzen dugu
fn :: aztertu_fitxategia String => Metrikak
      aztertu_fitxategia bidea  =
        edukia = read_file bidea
        || lerro_kopurua edukia -> n_lerro
        || str_len edukia       -> n_byte ||.
        Metrikak bidea n_lerro n_byte

-- 4. Errenkada bakoitza formateatzen dugu eta guztizkoak `fold` eta `||`-rekin batzen ditugu (07. kapitulua)
fn :: formateatu_metrika Metrikak => String
      formateatu_metrika m        =  "{lerroak m}\t{byteak m}\t{fitxategia m}"

fn :: batu_lerroak Int Metrikak => Int
      batu_lerroak acc m        =  acc + (lerroak m)

fn :: batu_byteak Int Metrikak => Int
      batu_byteak acc m        =  acc + (byteak m)

fn :: sortu_txostena [String] => String
      sortu_txostena bideak   =
        metrikak = ||map aztertu_fitxategia bideak
        || map formateatu_metrika metrikak -> errenkadak
        || fold batu_lerroak 0 metrikak    -> guztira_l
        || fold batu_byteak 0 metrikak     -> guztira_b ||.
        "{errenkadak}\nGuztira: {guztira_l} lerro, {guztira_b} byte"

fn :: main => ()
      main =
        echo (sortu_txostena ["README.md", "AGENTS.md"])
```

Gelditu segundo batez ~40 kode-lerro horiei begiratzeko:
- Ez dago `null` bakar bat ere, ez kontrolik gabeko salbuespenik, ez `Mutex`-ik.
- `zenbatu_jauziak` 0 pila-byteko `loop` natibo batera konpilatzen da TCO automatikoari esker.
- `||map aztertu_fitxategia bideak` deiak fitxategiak paraleloan prozesatzen ditu zure PUZaren nukleo guztietan, eta `||` blokeak aldi berean kalkulatzen ditu formateatutako errenkadak, lerroen guztizkoa eta byteen guztizkoa.
- Aldi baterako memoria modu deterministan askatzen da **`RMM1`/`RMM2`** bidez.
- Eta `ridgunc build rg_wc.rg -o rg-wc` exekutatzen duzunean, `/usr/local/bin`-era kopiatzeko prest dagoen ~350 KB-ko bitar natibo autonomo bat lortzen duzu.

---

## 8.7. Azken Ibilbide-Orria: Ridgun Programatzailearen Urrezko 10 Arauak

1. **Idatzi beti lehenengo kontratua (`=>`) eta ondoren ekuazioak (`=`):** motetan lehenengo pentsatzeak konpiladorea zure alde lan egitera bultzatzen du.
2. **Utzi `stable format`-i zure taulak maketatzen:** idatzi zuriune batekin eta utzi tresnari zutabeak, `=>`, `=` eta `->` lerrokatzen.
3. **Gogoratu `=`-ren arau unibertsala:** edozein `=`-ren atzean bloke sekuentzial bat, `|` zain-zuhaitz bat edo `||` grafo paralelo bat ireki dezakezu.
4. **Erabili `|.` eta `||.` habiaratutako bloke bat goiko maila batera itzultzeko ixten duzunean soilik:** mantendu erabaki-zuhaitz sakonak trinko eta anbiguotasunik gabe.
5. **Aldaezina lehenespenez (`x = ...`), aldakor esplizitua (`mut x = ...`):** erabili `mut` metatzaile lokal batek benetan eskatzen duenean soilik.
6. **Erabili eragile boolear argiak letra xehez (`and`, `or`, `xor`, `not`) eta itxi beti zure zainak `| otherwise =`-rekin.**
7. **Modelatu zure domeinua ADTekin (`type`):** erabili erregistroak `with eremua: balioa`-rekin eta batuketa-motak (`Option`, `Result`) `null`-en ordez.
8. **Paralelizatu mendekotasunak `|| adier -> ald` eta `||map` / `||filter`-ekin deklaratuz:** utzi konpiladoreari ziklorik ez dagoela egiaztatzen eta lana nukleoen artean banatzen.
9. **Jarri dimentsio sinbolikoak zure Tentsoreei (`Tensor[N, K]`) eta azpiindizeak zure uzkurdurei (`a_ik @ b_kj`).**
10. **Fido izan `RMM`-z (`RMM1`/`RMM2`), mugatu kanpoko sarrerak `with region`-ekin eta egiaztatu beti `stable check` eta `stable test`-ekin.**

Bidaia zoriontsua Ridgunen programatzen!
