# 03. kapitulua: Funtzioak, mota-sinadurak eta kodea taula bat bezala idaztearen artea

Badago galdera bat programatzaile orok bere buruari egiten diona kode funtzionala ikusten duen lehen aldian:

> *"Hemen klaserik, objekturik edo balioz aldatzen diren aldagairik ez badago... orduan non sartzen dut nire logika?"*

**Funtzioetan**. Baina ez guztiok noizbait pairatu ditugun bandera boolearrez betetako 200 lerroko funtzio horietan, baizik eta funtzio txiki, zuzen eta irakurtzeko hain errazetan, ezen arbel bateko taula bat baitirudite.

Ikus dezagun nola eraikitzen diren.

---

## 3.1. Funtzio bat aurkezteko bi modu (Zuk aukeratzen duzu trajea)

Ridgunen funtzio oro bere **mota-sinadurarekin** hasten da (zer sartzen den eta zer ateratzen den `=>` ondoren) eta azpian bere **inplementazio-klausulak** doaz (`=` ikurrarekin).

Goiburua bi modutara idatz dezakezu:

### A aukera: Zuzenean harira (aurrizkirik gabe)
```ridgun
aplikatu_beherapena Int     Int      => Int
aplikatu_beherapena prezioa ehunekoa =  prezioa - (prezioa * ehunekoa / 100)
```

### B aukera: Etiketa esplizituarekin (`fn ::`)
```ridgun
fn :: aplikatu_beherapena Int     Int      => Int
      aplikatu_beherapena prezioa ehunekoa =  prezioa - (prezioa * ehunekoa / 100)
```

*"Aizu, eta zergatik existitzen dira biak?"*
Gustuak askotarikoak direlako:
- Bada nahiago duena funtzioak ezkerreko marjinari itsatsita hastea aldi bakoitzean `fn ::` idatzi gabe (azken finean, `=>` geziak lau haizeetara oihukatzen du lerro hori mota-sinadura bat dela).
- Eta bada nahiago duena ezkerreko zutabe bat etiketei (`fn ::`, `op ::`, `type`, `import`) eskainita edukitzea fitxategia bisualki eskaneatzeko.

Konpiladoreak eta `stable format`-ek biak ezin hobeto ulertzen dituzte. Gainera, `fn` eta `op` hitzak askatasunez erabil daitezke edozein funtzio edo eragileren izenaren parte gisa (adibidez `fn :: op`, `op :: fn` edo `op :: op`), eta funtzio batek balio anitz itzultzen baditu, modu kanoniko/zorrotzean irteera-motak zuriunez bereizita idazten dira `=>` ondoren (`zatitu_hondarrarekin Int Int => Int Int`).

---

## 3.2. Zutabeen magia: zergatik zure begiek atseden hartzen duten

Begira bidalketa baten kostua herrialdearen eta premiazkoa den ala ez kontuan hartuta kalkulatzen duen funtzio honi:

```ridgun
bidalketa_kostua String    Bool  Int   => Int
bidalketa_kostua "EH"      False _     =  5
bidalketa_kostua "EH"      True  _     =  12
bidalketa_kostua _         False pisua =  10 + (pisua * 2)
bidalketa_kostua _         True  pisua =  25 + (pisua * 4)
```

Egin proba: estali pantailaren eskuineko erdia eta begiratu sarrerako hiru zutabeei bakarrik:
- Lehenengo zutabea (`String`): `"EH"`, `"EH"`, `_`, `_`.
- Bigarren zutabea (`Bool`): `False`, `True`, `False`, `True`.
- Hirugarren zutabea (`Int`): `_`, `_`, `pisua`, `pisua`.

Ikusten duzu zulo logikorik? Bat ere ez: 4 konbinazio posibleak zure sudurraren aurrean daude, `String`, `Bool` eta `Int`-en azpian bertikalki lerrokatuta. Ohiko `if / else` bloke batean 18 lerro irakurri beharko zenituzke kasu solterik utzi ez duzula ziurtatzeko.

---

## 3.3. Oinarrizko motak eta opari bat zeroak ez zenbatzeko (`_KB`, `_MB`, `_GB`)

Ridgunen mota eskalarrak zuzenak eta ezustekorik gabeak dira:

| Mota | Zer den benetan | Adibideak |
|---|---|---|
| `Int` | Zeinudun 64 biteko osokoa (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `U64` | Zeinurik gabeko 64 biteko osokoa (`u64`) aritmetika modular eta bit-eragiketa natiboekin | `u64 0`, `u64 0x6a09e667f3bcc908`, `a ^ b`, `a << u64 13` |
| `Float` / `Real` | Doitasun bikoitzeko hamartarra (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Testu-kate aldaezina | `"Kaixo"`, `'bide\gordina'` |
| `Char` | Karaktere-kodea | `str_char_at`-ek itzulia |
| `Bool` | Betiko boolearra | `True`, `False` |
| `()` | Hutsa (*Unit*, inprimatu edo I/O bakarrik egiten duzunean) | `()` |

### Nazkatuta `65536` edo `1048576` idazteaz eta digitu bat jan ez izateko otoitz egiteaz?
Ridgunen zenbakizko literalek zuzenean onartzen dituzte **`_KB`**, **`_MB`** eta **`_GB`** atzizkiak, zifra-taldeak bereizteko `_` azpimarrez gain:

```ridgun
buffer_tamaina => Int
buffer_tamaina =  64_KB      -- Konpiladoreak 65536ra itzultzen du

fitxategi_muga => Int
fitxategi_muga =  16_MB      -- Konpiladoreak 16777216ra itzultzen du

zortzikote_maskara => Int
zortzikote_maskara =  0xFF_00 -- Hamaseitar garbia eta irakurgarria
```

---

## 3.4. Komatxo bikoitzak (`"..."`) vs. Komatxo bakunak (`'...'`)

Lengoaia askotan komatxo bakunek eta bikoitzek gauza bera egiten dute zehazki (alferrikako xahuketa). Ridgunen bakoitzak eginkizun oso argia du:

### 1. Komatxo bikoitzak (`"..."`): Adimendunak eta interpolatuak
Ihes-sekuentziak (`\n`, `\t`, `\"`, `\\`) interpretatzen dituzte eta **`{...}` giltzen artean sartzen duzun edozein aldagai edo adierazpen ebaluatzen dute**:

```ridgun
eskaera_laburpena String Int  Int     => String
eskaera_laburpena gaia   kop  prezioa =
  "{kop}x {gaia} eskatu duzu. Ordaintzeko guztira: {kop * prezioa} euro."
```

*(Trikimailua: komatxo bikoitzen barruan giltza literal bat idatzi behar baduzu —adibidez `"$\{VAR:-default\}"` shell script bat edo JSON bat sortzean—, alderantzizko barrarekin ihes egin diezaiokezu `\{` eta `\}` erabiliz edo bikoiztu `{{` eta `}}`).*

### 2. Komatxo bakunak (`'...'`): Gordinak eta literalak (*Raw Strings*)
Komatxo bakunen artean idazten duzuna **bere horretan** ateratzen da, alderantzizko barra `\` bakar bat edo `{}` giltza bat ere ukitu gabe. Ezin hobea beste lengoaia batean kodea sortzen duzunerako, shell komandoak idazten dituzunerako edo barraz betetako bideekin lan egiten duzunerako:

```ridgun
sed_komandoa => String
sed_komandoa =  's/\([0-9]+\)/[\1]/g'
```

### Testu-kateetarako (`String`) zure tresna-kutxa
Kateak lotzea `+` ikurrarekin batzea bezain sinplea da: `"Kaixo, " + izena`. Eta testu baten gainean kirurgia fina egin behar duzunean, funtzio natibo hauek prest dituzu ezer inportatu gabe:

- `str_len s` $\rightarrow$ `s`-ren luzera.
- `str_char_at s i` $\rightarrow$ `i` posizioko karakterearen zenbakizko kodea (`Int`) (`-1` kanpora ateratzen bazara).
- `str_slice s hasiera amaiera` $\rightarrow$ `hasiera`-tik `amaiera`-ra mozten du (`amaiera` sartu gabe).
- `char_from_code c` $\rightarrow$ zenbakizko kode bat (`Int`, adib. `10` `\n`-rako edo `34` `"`-rako) karaktere 1eko `String` bihurtzen du.
- `str_contains s orratza` eta `str_starts_with s aurrizkia` $\rightarrow$ `True` edo `False` itzultzen dute.
- `int_to_str n` eta `str_to_int s` $\rightarrow$ zenbakitik testura eta alderantziz bihurtzen dute (`str_to_int`-ek `"0xFF"` ere ulertzen du!).

---

## 3.5. Lerro anitzeko blokeak, `=`-ren arau unibertsala eta `mut` aldagaiak

Funtzio bat lerro bakarrean sartzen ez denean, `=` ondoren lerro-jauzi bat egiten duzu eta blokeari koska ematen diozu.

Begira nola irakurtzen den bloke bat urratsez urrats:

```ridgun
kalkulatu_faktura Int     Int     => Int
kalkulatu_faktura oinarria bez_eh =
  zergak = oinarria * bez_eh / 100
  kudeaketa_gastuak = 5
  echo "Xehakapena -> Oinarria:" oinarria "Zergak:" zergak
  oinarria + zergak + kudeaketa_gastuak
```

Ridguneko blokeak garbiak eta uniformeak bihurtzen dituzten urrezko lau arau:
1. **Aldaezina lehenespenez `let` eta `const` gabe**: `zergak = ...` idazten duzu eta baduzu zure konstante lokal aldaezina. Deskuiduz bloke berean beherago `zergak = 99` gainidazten saiatzen bazara, konpiladoreak lehorrean gelditzen zaitu.
2. **Aldagai aldakor esplizituak `mut`-ekin**: funtzio baten barruan metatzaile lokal bat urratsez urrats eguneratzen joan nahi duzunean benetan, **`mut`**-ekin deklaratzen duzu eta gero askatasunez berresleitzen duzu `=`-rekin:
   ```ridgun
   aplikatu_gainkarguak Int     => Int
   aplikatu_gainkarguak prezioa =
     mut guztira = prezioa
     guztira = guztira + 10
     guztira = guztira * 2
     guztira
   ```
   *(Eta `guztira`-k memorian zerrenda edo egitura bat gordetzen badu, Ridgunen **`RMM2`** politikak `+1` gehitzen dio balio berriari zaharrari `-1` kendu aurretik, eta berehala askatzen du beste inork erabiltzen ez badu).*
3. **`=`-ren arau unibertsala**: **edozein `=`-ren** atzean (funtzio batean, eragile batean, `x =` aldagai lokal batean edo baldintzazko adar batean) Ridgunen hiru bloke-formetako edozein jar dezakezu beti:
   - **`(ezer ez)`**: koska duten lerro sekuentzialak (goian bezala).
   - **`|`**: baldintzazko zainen zuhaitz bat.
   - **`||`**: kalkulu paraleloen grafo bat `->` geziekin.
4. **Azken adierazpena da beti emaitza**: `oinarria + zergak + kudeaketa_gastuak` da `kalkulatu_faktura`-k itzultzen duena. `return` gabe.

**04. kapituluan** ikusiko dugu nola hartu erabaki konplexuak —`|.` bidezko maila anitzeko erabaki-zuhaitzak barne— inoiz `if/else` bat edo `while` begizta bat idatzi gabe: ongi etorri **zain boolearren** eta **zero kostuko isats-errekurtsioaren** mundura.
