# 00. kapitulua: Zergatik behar dut Ridgun? Bai, ala? Ez nekien ba... Kontaidazu gehiago!

Izan gaitezen zintzoak: norbaitek *"programazio-lengoaia berri bat sortu dugu"* esaten dizunean, zure lehen erreakzio naturala —eta oso osasuntsua— bekaina altxatzea eta honako hau pentsatzea da:

> *"Beste bat? Baina dagoeneko badut Python azkar ibiltzeko, Rust edo C abiadura behar dudanerako, eta Bash terminalean gauzak lotzeko. Zertarako arraio behar dut nik Ridgun ikasi?"*

Galdera bikaina da. Eta erantzun laburra hauxe da: **eguneroko hiru min jasatera ohitu zarelako, saihestezinak zirela pentsatuz**.

Jar diezaiegun izena.

---

## 1. mina: "Bi munduen sindromea" (Batean prototipatu, bestean berridatzi)

Ziur film hau bizi izan duzula:

1. Tresna bat edo kalkulu-motor bat **Python**, **JavaScript** edo **Ruby** lengoaian hasten duzu, arazoan pentsatu nahi duzulako, ez erakusleetan edo konpiladorean.
2. Kodea laburra eta polita geratzen da... baina 500 MB-ko fitxategi bat pasatzen diozunean edo zure makinaren 16 nukleoak erabiltzen saiatzen zarenean, herrestan dabil. Eta zure programa zerbitzari garbi batera banatu nahi baduzu, ingurune birtual, interpretatzaile eta liburutegi dinamikoz osatutako gigabyte erdi bat paketatu behar duzu.
3. Etsita, **C**, **C++** edo **Rust** lengoaian berridaztea erabakitzen duzu. Orain hegan egiten du eta ehunka kilobyte gutxi batzuk baino ez ditu hartzen, baina zure 40 lerroko kodea `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, giltza `{}` eta puntu eta komaz `;` betetako 300 lerro bihurtu da.

**Zer aldatzen da Ridgunekin?**
Ridgunen **Pythonen baino kode laburragoa eta garbiagoa** idazten duzu, baina `ridgunc build` exekutatzen duzunean, **~350 KB-ko ELF bitar natibo bakar bat** lortzen duzu, interpretatzailerik gabe, kanpoko makina birtualik gabe eta zabor-biltzailerik gabe. Ez dago *"gero lengoaia azkarrean berridatziko dugu"* faserik: arazoa pentsatzen duzun kode garbia **bada dagoeneko** ekoizpeneko bitar natiboa.

---

## 2. mina: "Inoren kodea (edo duela 6 hilabeteko zurea) irakurtzea detektibe izatera jolastea da"

Begira nola idazten dugun baldintzazko logika ia lengoaia nagusi guztietan:

```text
if (egoera == AKTIBO && (rola == ADMIN || (rola == EDITOREA && baimenaDu))) {
    if (kuota > 0) {
        return prozesatu(erabiltzailea);
    } else {
        return ukatu("Kuotarik gabe");
    }
} else {
    return ukatu("Baimenik gabe");
}
```

Gure begiek ez zuten eboluzionatu habiaratutako giltzak parekatzeko, ezta mailakatutako `if / else` zuhaitzak askatzeko ere. Ingeniariek, matematikariek edo fisikariek arau konplexuak hutsegiterik gabe ulertu nahi dituztenean, ez dituzte `if / else` paragrafoak idazten: **taula bat marrazten dute**.

Ridgunen, **kodea taula hori bera da**:

```ridgun
baimendu String   String     Bool  Int   => String
baimendu "aktibo" "admin"    _     kuota =
  | kuota > 0 = "Eskaera prozesatzen"
  | otherwise = "Ukatua: kuotarik gabe"
baimendu "aktibo" "editorea" True  kuota =
  | kuota > 0 = "Eskaera prozesatzen"
  | otherwise = "Ukatua: kuotarik gabe"
baimendu _        _          _     _     =  "Ukatua: baimenik gabe"
```

Begira zutabeei:
- 1. zutabea: egoera (`"aktibo"` edo `_`).
- 2. zutabea: rola (`"admin"`, `"editorea"` edo `_`).
- 3. zutabea: baimena duen (`True` edo `_`).
- 4. zutabea: `kuota`.

Ez duzu programa buruz lerroz lerro exekutatu behar `False` baimena duen `"editorea"` bat sartzen denean zer gertatzen den jakiteko: zureek begiek bertikalki egiten dute behera taulan eta segundo erdian ikusten dute.

---

## 3. mina: "Nire ordenagailuak 16 nukleo ditu, baina nire programak 1 baino ez du erabiltzen (hariak ukitzeak izua ematen didalako)"

Gaur egun telefonorik xumeenak ere 8 nukleo ditu, eta edozein zerbitzarik edo laneko eramangarrik 12 eta 32 artean. Hala ere, eguneroko programen % 95ek hari sekuentzial bakarrean exekutatzen jarraitzen dute.

Zergatik? Lengoaia inperatiboetan paralelizatu nahi izateak Pandoraren kutxa irekitzea esan nahi duelako:
- Eta bi harik hiztegi bera aldi berean aldatzen badute? (*Data race*).
- Eta hari batean A `Mutex`-a eta gero B blokeatzen baditut, eta beste batean B eta gero A? (*Deadlock*).
- Eta nire kode-oinarri osoa goitik behera `async` eta `await`-ez kutsatzen badut?

Ridgunen, **funtzio oro purua da eta datu oro aldaezina lehenespenez**. Horrek ondorio magiko bat du: **elkarren menpe ez dauden bi adierazpenek ezin dute inoiz elkar oztopatu**.

Horregatik, Ridgunen ez duzu haririk kudeatu behar zure PUZa aprobetxatzeko. **Zer zeren menpe dagoen** baino ez duzu adierazten `||` barra paraleloekin eta `->` geziekin:

```ridgun
hileko_txostena Datuak => Txostena
hileko_txostena d      =  konbinatu sare_metrikak disko_metrikak puz_metrikak
  || aztertu_sarea d  -> sare_metrikak
  || aztertu_diskoa d -> disko_metrikak
  || aztertu_puza d   -> puz_metrikak
```

Zuk hiru lerro garbi baino ez dituzu idatzi, datu bakoitza nondik ateratzen den adieraziz. Konpiladoreak ikusten du hiru adarrak independenteak direla eta badaki paraleloan abiarazi ditzakeela *data race* edo *deadlock* bat gertatzeko aukerarik txikiena ere egon gabe.

Eta postontzia eta egoera isolatua duten agente iraunkorrak behar badituzu (adibidez, milaka bezero-saio, bigarren planoko langileak edo sare-konexioak mantentzeko)? Ridgunen ez duzu `Actor` klaserik definitu edo `Mutex`-ik erabili behar: **edozein funtzio arrunt agente autonomo bihurtzen da lerro bakar batean `agent`-ekin**:

```ridgun
kontagailua = agent (gehitu bisita) 0
send 1 to kontagailua
send 5 to kontagailua
guztira = receive from kontagailua
stop kontagailua
```

Gainera, konpiladoreak **aukeraketa adimenduna egiten du konpilazio-garaian**: `||`, `||map`, `||filter` eta `agent` barruko funtzio bakoitzaren sakonera eta kostua estatikoki aztertzen ditu, funtzio arinak zero gainkargako *green-thread* urrats gisa exekutatuz eta kalkulu astun edo errekurtsiboak nukleo anitzeko kerneleko benetako harietara (`SYS_clone`) automatikoki bidaliz.

---

## 4. mina: "Zabor-biltzaileak mundua gelditzea erabakitzen du unerik txarrenean"

Lengoaia funtzional klasikoak (Haskell, OCaml, Erlang, Clojure) zoragarriak dira kodeari buruz arrazoitzeko, baina ia guztiak exekuzio-garaiko **Zabor-Biltzaile (*Garbage Collector*)** baten menpe daude. Horrek baztertu egiten ditu honako hauek behar dituzunean:
- Mikrosegundora aurreikus daitezkeen latentziak.
- Eragiketa batek zenbat RAM memoria kontsumitu dezakeen zehatz-mehatz kontrolatzea, garbi abortatu aurretik.
- Sistema eragilearen tresnak (`ls`, `find`, `sh`, `doas`, `make`) idaztea edo hardware-erregistroak (`MMIO`) ukitzea.

Ridgunek **mundu funtzional puruaren dotorezia guztia ematen dizu, baina Ridgunen Memoria Kudeaketarekin (`RMM`: `RMM1` estatikoa eta `RMM2` esleipen-kontaketa kaskadakoarekin) gehi kuota zehatzeko eskualde lexikoekin (`with region`)**:

```ridgun
analizatu_paketea String => Result
analizatu_paketea gordina =
  with region 16_KB do
    deskodetu_bilbea gordina
```

Aldi baterako egitura bakoitza modu deterministan askatzen du konpiladoreak (`RMM1` / `RMM2`) erabiltzeari uzten zaion une berean, eta erasotzaile batek memoria lehertzeko diseinatutako pakete gaizto bat bidaltzen badizu, 16.384. bytea gainditzean eskualdea berehala mozten da, bere arena $O(1)$-ean askatzen du eta `Err OutOfMemory` itzultzen dizu. Prozesua erori gabe, GC geldialdirik gabe eta memoria-ihesik gabe.

---

## Laburbilduz: Noiz egiten du distira Ridgunek?

Ridgun zuretzat egina dago inoiz honako hau nahi izan baduzu:

1. **Sistemetako tresnak, konpiladoreak, analizatzaileak edo CLI utilitateak idaztea**, mikrosegundotan abiarazten direnak, ehunka KB gutxi batzuk pisatzen dituztenak eta erakusle nuluek edo ezkutuko albo-ondorioek hautsi ezin dituztenak.
2. **Agenteen Eredu Natiboan (`agent`, `send ... to`, `receive from`, `stop`) oinarritutako sistema konkurrenteak eta zerbitzariak eraikitzea**, non edozein funtzio puru egoera isolatudun edo egoerarik gabeko agente bihurtzen den eta konpiladoreak modu adimendunean aukeratzen duen *green-thread* exekuzio ultraarinaren eta nukleo anitzeko hari natiboen artean.
3. **Algoritmoak, datu-hodiak edo tentsore-aljebra programatzea**, non konpiladoreak matrizeen dimentsioak ere (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) zure ordez egiaztatzen dituen ezer exekutatu aurretik.
4. **Zure kode propioa irakurtzen gozatzea**: `.rg` fitxategi bakoitzak ondo maketatutako liburu baten orrialdea dirudiela, formateatzaile taularatu automatikoari esker (`stable format`).

Jakin-mina piztu zaizu? Pasa zaitez **01. kapitulura** eta idatz dezagun gure lehen programa bi minutu baino gutxiagoan.
