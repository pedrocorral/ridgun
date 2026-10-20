# 04. kapitulua: Agur `if/else`-ri, agur `while`-ri (Eredu Bat-etortzea, Zainak eta TCO)

Norbaiti kontatzen diozunean Ridgunen **ez dela existitzen `if` hitz gakoa, ez `else`, ez `switch`, ez `for`, ez `while`**, etxe bat mailurik etailtzerik gabe eraikiko duzula esan bazenio bezala begiratu ohi dizu:

> *"Ez dagoela `if` ezta `while` ere? Eta nola arraio hartzen dut erabaki bat edo zeharkatzen ditut milioi bat datu?"*

Bada, kontua da `if/else` eta `while` 50eko hamarkadan jauziek (`GOTO`) funtzionatzen zuten modutik oinordetzan hartutako tresna nahiko zakarrak direla. Ridgunen eskularru bat bezala doitzen diren hiru piezarekin ordezkatzen ditugu:
1. **Eredu Bat-etortzea (*Pattern Matching*)** (datuaren **forma edo balio zehatzaren** arabera erabakitzen duzunean).
2. **`|` zain boolearrak** (**baldintza edo tarte baten** arabera erabakitzen duzunean).
3. **Isats-errekurtsioa TCOrekin** (konpiladoreak azpitik `loop` begizta natibo ultra-azkar bihurtzen duena).

Ikus ditzagun martxan.

---

## 4.1. *Pattern Matching*: Argumentuak berak erantzuna ematen dizunean

Aurreko kapituluan aurrerapen bat ikusi genuen. `x` aldagai generiko bat jaso eta funtzioaren barruan bost `if (x == ...)` ireki beharrean, Ridgunen kasuak zuzenean funtzioaren sarrerako atean jartzen dituzu:

```ridgun
http_kodea Int => String
http_kodea 200 =  "OK: Dena primeran joan da"
http_kodea 301 =  "Betiko lekuz aldatua"
http_kodea 404 =  "Ez da aurkitu (begiratu duzu sofaren azpian?)"
http_kodea 500 =  "Sua zerbitzarian"
http_kodea n   =  "Kode ezezaguna: {n}"
```

Ridgunek errenkadak **goitik behera** probatzen ditu:
- `404` sartzen bada, zuzenean hirugarren errenkadara egiten du jauzi.
- `418` sartzen bada, lehenengo lau errenkadetako bat ere ez dator bat, beraz azkenekoan (`n`) erortzen da, zeinak edozein osoko harrapatzen duen eta `n` izendatzen duen inprimatu ahal izan dezazun.
- Eta azken kasuan zein zenbaki zen ere axola ez bazaizu? `_` azpimarra bat (*komodina*) jartzen duzu eta ahaztu egiten zara: `http_kodea _ = "Beste kode bat"`.

---

## 4.2. Zain boolearrak (`|`): Zure bisturia tarteetarako, baldintzazko aldagaietarako eta erabaki-zuhaitzetarako

*"Ados, pattern matching-a bikaina da `200` edo `404` bilatzen dudanean. Baina zer egiten dut `nota >= 5` edo `adina > 18 and adina < 65` den egiaztatu nahi badut? Ez ditut 47 errenkada idatziko 18tik 65erako zenbaki guztiekin!"*

Noski ezetz! Horretarako daude **zainak (`|`)**.

Emaitza desberdintza baten edo konbinazio logiko baten menpe dagoenean, funtzioaren (edo edozein aldagai lokalen) `=` ikurraren ondoren `|` barra bertikalen eskailera bat irekitzen duzu:

```ridgun
kalifikatu Int  => String
kalifikatu nota =
  | nota < 0   = "Nota ezinezkoa (puntu negatiboak?)"
  | nota < 5   = "Gutxiegi"
  | nota < 7   = "Nahiko"
  | nota < 9   = "Oso ongi"
  | nota <= 10 = "Bikain"
  | otherwise  = "Eskalatik pasa zara"
```

Begiratu ondo:
- Goiburuko `=` ikurra (`kalifikatu nota =`) `=>` azpian lerrokatzen da beste edozein funtziotan bezala.
- Azpian goitik behera irakurtzen da tarifa-taula bat bezalaxe: `| baldintza = emaitza` lerro bakoitza ordenan egiaztatzen da. Batek `True` ematen duen bezain laster, emaitza hori itzultzen du eta kitto.
- Amaieran **`| otherwise = ...`** jartzen duzu, hitzez hitz *"beste edozein kasutan"* esan nahi duena (zure segurtasun-sarea, inoiz itzulerarik gabeko biderik gera ez dadin).

### Logika boolearra letra xehe argietan (`and`, `or`, `xor`, `not`)
Konturatu zara lengoaia askok bitetarako `|`, boolearretarako `||`, ukatzeko `!`... erabiltzen dituztela eta baldintza konplexu bat irakurtzen duzunean katu bat teklatuaren gainetik ibili dela dirudiela (`if (!a && (b || c))`)?

Ridgunen, `|` dagoeneko zainen eta datu-mota aljebraikoen ikur sakratua denez, eta `||` paralelismo-eragilea denez, **eragile boolearrak letra xeheko hitz argiekin idazten dira**:

- **`and`**: bi gauzak betetzen dira (`adina >= 18 and gidabaimena_du`).
- **`or`**: gutxienez bat betetzen da (`eguna == "larunbata" or eguna == "igandea"`).
- **`xor`**: bata edo bestea betetzen da, baina ez biak batera.
- **`not`**: boolearra alderantzikatzen du (`not (hutsik_dago testua)`).

Begira zein garbi geratzen den bisurte-urteen problema klasikoa:

```ridgun
bisurtea_da Int => Bool
bisurtea_da u   =
  | (u % 400) == 0                  = True
  | (u % 4) == 0 and (u % 100) != 0 = True
  | otherwise                       = False
```

Zero ikur kriptiko. Ridgun ez dakien norbaitek irakurtzen du eta lehenengoan ulertzen du.

### Baldintzazko aldagai lokalak (`x =` + `|`)
Ridgunen `=` orok arau bera jarraitzen duenez, **`|` aldagai lokal bat esleitzeko ere erabil dezakezu**, aparteko funtzio laguntzaile bat sortu beharrik izan gabe:

```ridgun
txartel_prezioa Int     Bool             => Int
txartel_prezioa oinarria familia_ugaria_da =
  beherapena =
    | familia_ugaria_da = 20
    | oinarria > 100    = 10
    | otherwise         = 0
  oinarria - (oinarria * beherapena / 100)
```

### Habiaratutako erabaki-zuhaitzak eta `|.` mugatzaile trinkoa
*"Eta `| cond =` edo `| otherwise =` adar baten barruan 3 edo 4 sakonera-mailako beste `|` zain-azpizuhaitz bat ireki nahi badut eta gero goiko maila batera itzuli?"*

`|` barruan `|` habiaratu dezakezu nahi adina mailatan. Eta habiaratutako `|` bloke bat amaitzen denean baina azpian guraso-maila bateko adar gehiago (edo blokeko sententzia gehiago) jarraitzen dutenean, **`|.`** jartzen duzu bere azken lerroaren amaieran (`| otherwise = balioa |.`) inolako anbiguotasunik gabe adierazteko azpizuhaitz hori ixten dela eta aurreko mailara itzultzen zarela:

```ridgun
bideratu_eskaera Int     Int  Bool     Bool       Int        Int      => Int
bideratu_eskaera metodoa rola sinatua  admin_da   tamaina_kb mugatua  =
  | metodoa == 0 =
    | tamaina_kb == 0 = 204
    | otherwise       = 200 |.
  | metodoa == 1 =
    | not sinatua = 401
    | otherwise =
      -- 2. maila: POST eskaera sinatua
      | mugatua > 0 =
        -- 3. maila: rate-limit kontrola
        | admin_da =
          -- 4. maila: salbuespena administratzaileentzat
          | tamaina_kb > 10000 = 413
          | otherwise          = 202 |.
        | otherwise = 429 |.
      | tamaina_kb > 1000 =
        -- 3. maila: 4. mailatik itzuli gara `|.`-ri esker
        | rola >= 2 and admin_da = 201
        | otherwise              = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Erreparatu zein garbia den:
- Maila 1eko zuhaitz sinple batean (edo funtzio osoaren amaieran) **ez da inoiz `|.` jarri behar** (beharrezkoa ez den zarata litzateke).
- Habiaratutako adar bat ixtean soilik idazten duzu `|.`, azpian goiko maila bateko adar batek jarraitzen duenean.

### Lerro anitzeko blokeak zain baten barruan (`| cond =` + koskadun blokea)
Funtzio arrunt baten `=` ikurraren ondoren lerro anitzeko koskadun bloke bat ireki dezakezun bezalaxe, **edozein `| cond =` edo `| otherwise =` zainen `=` ikurraren ondoren ere lerro-jauzi bat egin dezakezu eta bloke sekuentzial bat ireki**:

```ridgun
doitu_leihoa Int Int  => Int
doitu_leihoa idx muga =
  | idx >= muga =
      goia = muga - 1
      eskalatua = goia * 2
      eskalatua + 10
  | otherwise =
      hurrengoa = idx + 1
      hurrengoa * 2
```

Zainaren adar bakoitzak bere bloke lokal garbia du eta bere azken lerroa adar horrek itzultzen duen balioa da.

---

## 4.3. "`while` gabe? Eta ez al da pila lehertuko fitxategi handi bat zeharkatzen badut?"

Hitz egin dezagun gelan dagoen elefanteaz.

Python, Java edo JavaScriptetik bazatoz, txiki-txikitatik irakatsi dizute *"errekurtsioa dotorea da unibertsitateko arbelean, baina mundu errealean pila gainezkatzen du (`StackOverflowError`) 1.000 biratan; erabili `while` begizta bat"*.

Hori egia da isats-deiak optimizatzen **ez** dituzten lengoaietan. Baina Ridgun bezalako sistemetako lengoaia funtzional batean, **isats-errekurtsio bat funtzio puruz mozorrotutako `while` begizta bat DA**.

### Zein alde dago errekurtsio arrunt baten eta isats-errekurtsio baten artean?
Erreparatu `n`-tik `0`-ra atzeraka zenbatuz zenbakiak batzen dituzten bi funtzio hauei:

```ridgun
-- A bertsioa: Errekurtsio ARRUNTA (itzulerarako lana zintzilik uzten du)
batu_motel Int => Int
batu_motel 0   =  0
batu_motel n   =  n + (batu_motel (n - 1))

-- B bertsioa: ISATS-errekurtsioa (kontua egunean darama `metatua` aldagaian)
batu_azkar_loop Int Int     => Int
batu_azkar_loop 0   metatua =  metatua
batu_azkar_loop n   metatua =  batu_azkar_loop (n - 1) (metatua + n)
```

- **A bertsioan**, `n + ...` batu ahal izan aurretik, funtzioak `batu_motel (n - 1)` amaitu arte itxaron behar du. Horrek ordenagailua urrats bakoitzean `n` pilan gordetzera behartzen du.
- **B bertsioan**, `batu_azkar_loop`-erako deia **lerroan gertatzen den azken gauza da**. Ez da ezer zintzilik geratzen haren atzean. Batura eguneratua pasatzen diozu dagoeneko `metatua + n`-n.

### `ridgunc`-en magia-trikimailua (TCO: *Tail-Call Optimization*)
`ridgunc`-ek `batu_azkar_loop` konpilatzen duenean, funtzioak klausularen amaieran bere buruari deitzen diola ikusten du eta honela dio:

> *"Zertarako sortuko dut pila-marko berri bat oraingoak dagoeneko ezertarako balio ez badu? `n` gainidatziko dut `n - 1`-ekin, `metatua` gainidatziko dut `metatua + n`-rekin eta hasierara jauzi egingo dut `loop { ... continue; }` natibo batekin."*

Emaitza:
1. `batu_azkar_loop 100_000_000 0` (ehun milioi bira) deitu dezakezu eta **zehazki 0 pila-byte gehigarri gastatuko ditu**.
2. Rust edo C-n eskuz idatzitako `while` begizta bat bezain azkar doa, baina zure Ridgun kodean aldagai aldakor bakar bat ere deklaratu behar izan gabe.

---

## 4.4. Ridgun programa orotan erabiliko duzun eredu maisua

Beste lengoaia batean *"`while` begizta bat egingo dut `i` indize batekin eta metatzaile batekin"* pentsatuko zenukeen bakoitzean, Ridgunen honelako funtzio-bikote bat idazten duzu (funtzio nagusi garbia eta bere isatseko `_loop` laguntzailea):

```ridgun
bilatu_karakterea_loop String Int Int Int      => Int
bilatu_karakterea_loop testua pos ama bilatua  =
  | pos >= ama                         = -1
  | (str_char_at testua pos) == bilatua = pos
  | otherwise                          = bilatu_karakterea_loop testua (pos + 1) ama bilatua

bilatu_karakterea String Int     => Int
bilatu_karakterea testua bilatua =  bilatu_karakterea_loop testua 0 (str_len testua) bilatua
```

Begira `bilatu_karakterea_loop`-en hiru zainei:
1. Amaierara iritsi naiz (`pos >= ama`)? `-1` itzultzen dut (begiztaren amaiera).
2. Karaktere hori `pos`-en aurkitu dut? `pos` itzultzen dut (begiztaren amaiera).
3. Ez da hau? Hurrengora pasatzen naiz (`pos + 1`) isats-dei batekin (konpiladoreak `continue;` bihurtzen duena).

Garbia, zapaldutako aldagai globalen *bug*-ak edukitzea ezinezkoa eta tximista bezain azkarra.

**05. kapituluan** datu-bildumei helduko diegu: **zerrendak, tuplak, argumentu infinituak (`...`) onartzen dituzten funtzioak eta J/APL estiloko sekuentzia-maskarak**.
