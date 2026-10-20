# 01. kapitulua: Zure lehen kontaktua Ridgunekin (Kaskorik gabe, giltzarik gabe eta puntu eta komarik gabe)

Ados, 00. kapituluan konbentzitu zaitut ez gaudela zoratuta Ridgun sortzeagatik. Orain ziurrenik hau pentsatzen ari zara:

> *"Oso polita taulen eta 16 nukleoen diskurtsoa, baina erakutsi benetako kodea. Zenbat denbora behar da funtzionatzen duen zerbait idazteko konpiladorearekin borrokatu gabe?"*

Goazen ba harira!

---

## 1.1. "Kaixo, mundua!", baina mamiarekin

Programazio-liburu gehienetan `print("Kaixo mundua")` motel bat erakusten dizute eta orrialdea pasatzen dute. Guk zuzenean benetako logika duen funtzio bat idatziko dugu, Ridgunek lehen minututik nola arnasten duen ikus dezazun.

Sortu `kaixo.rg` izeneko fitxategi bat eta idatzi hau:

```ridgun
agurra String => String
agurra ""     =  "Kaixo, bidaiari misteriotsua! (Ez didazu zure izena esan)"
agurra "Root" =  "Hara, Root! Kontuz gaur ezabatzen duzunarekin."
agurra izena  =  "Kaixo, {izena}! Ongi etorri Ridgunera."

main => ()
main =
  echo (agurra "Ada")
  echo (agurra "Root")
  echo (agurra "")
```

Oraintxe bertan exekutatzeko:

```bash
ridgunc run kaixo.rg
```

Eta zure terminalean hau ikusiko duzu:

```text
Kaixo, Ada! Ongi etorri Ridgunera.
Hara, Root! Kontuz gaur ezabatzen duzunarekin.
Kaixo, bidaiari misteriotsua! (Ez didazu zure izena esan)
```

Gelditu une batez eta begiratu goiko `agurra` blokeari. Nabaritzen duzu zer **EZ** dagoen?
- **Ez dago `function`, ez `def`, ez `pub fn`** (sinaduraren aurrean `fn ::` jarri nahi baduzu, egin dezakezu, baina hautazkoa da).
- **Ez dago `(String izena)` parentesirik, ezta `{ ... }` giltzarik ere** pantaila zikintzen.
- **Ez dago `if (izena == "") ... else if (izena == "Root") ... else ...`**.
- **Ez dago `return`-ik**.

---

## 1.2. Nola irakurtzen duen zure garunak `.rg` fitxategi bat

Goazen `agurra`-ren lau lerro horiek xehatzera, hemen baitago dagoeneko Ridgunen filosofiaren % 50a:

```ridgun
agurra String => String
agurra ""     =  "Kaixo, bidaiari misteriotsua! (Ez didazu zure izena esan)"
agurra "Root" =  "Hara, Root! Kontuz gaur ezabatzen duzunarekin."
agurra izena  =  "Kaixo, {izena}! Ongi etorri Ridgunera."
```

1. **Lehenengo lerroa kontratua da (`agurra String => String`)**:
   Honela dio: *"`agurra` dut izena, `String` bat jasotzen dut eta beste `String` bat itzultzen dizut (`=>`)"*. Kitto. Norbait `42` zenbakia pasatuz deitzen saiatzen bada, konpiladoreak sorbaldan ukitu bat emango dio programa exekutatu aurretik ere.
2. **Beheko lerroak kasuak dira (goitik behera)**:
   - `""` kate hutsa pasatu didazu? Lehenengo esaldia itzultzen dut.
   - Zehazki `"Root"` pasatu didazu? Bigarren esaldia itzultzen dut.
   - Beste edozer pasatu didazu? `izena` aldagaian gordetzen dut eta testuaren barruan sartzen dut `{izena}` erabiliz.
3. **Eta zer da `main => ()`?**:
   `main`-ek argumenturik jasotzen ez duenez, `=>` zuzenean izenaren ondoren jartzen dugu. Eta `()` itzultzen du (mota hutsa edo *Unit*, lagunentzat), bere lan bakarra `echo`-rekin gauzak pantailatik ateratzea delako.

---

## 1.3. "Itxaron... zuriune horiek eskuz lerrokatu behar ditut fraide kopiatzaile baten moduan?"

Inola ere ez! Zutabeak begiz zenbatuz zuriune-barrari eman beharko bazenio, hamar minutura utziko zenuke Ridgun (eta arrazoi osoz).

Zuk kodea azkar idazten duzu, hitz bakoitzaren artean zuriune bakar batekin:

```ridgun
agurra String => String
agurra "" = "Kaixo, bidaiari misteriotsua!"
agurra izena = "Kaixo, {izena}!"
```

Eta **`stable format`** exekutatzen duzunean (edo Emacsen `ridgun-mode`-rekin `TAB` sakatzen / fitxategia gordetzen duzunean), formateatzaile kanonikoak parametro bakoitza bere motaren azpian kokatzen du eta `=` guztiak zehaztasun milimetrikoz lerrokatzen ditu. Zuk azkar idazten duzu; makinak taula maketatzen du.

---

## 1.4. Script azkarretik borrokako bitarrera komando bakarrean

`ridgunc run kaixo.rg` egiten duzunean, programa hegaldian konpilatzen eta abiarazten ari zara. Baina imajinatu zure tresna amaitu duzula eta ekoizpen-zerbitzari batera eraman nahi duzula edo Ridgun instalatuta ez duen lankide batekin partekatu nahi duzula.

Hau exekutatzen duzu:

```bash
ridgunc build kaixo.rg -o kaixo
```

Eta baduzu `./kaixo`: **Linux x86_64rako ELF exekutagarri natibo bat**, garbia, kode hilik gabe (*Tree-Shaking*), esteka osoko optimizazioarekin (*LTO*) eta kanpoko inongo interpretatzaileren menpe egon gabe.

---

## 1.5. Txuleta zintzoa: Nondik dator Ridgunen ideia bakoitza?

Ridgunek ez du gurpil karratua berrasmatu nahi; konplexurik gabe hartzen du maileguan lau tradizioren onena:

| Norengandik | Zer hartzen du Ridgunek | Zer uzten du kanpoan (zure osasun mentalagatik) |
|---|---|---|
| **Haskell / ML** | Funtzio puruak, kasukako *pattern matching*-a, datu-mota aljebraikoak (`Option`, `Result`) eta polimorfismoa (`A`..`Z`). | Monada abstraktuak, 40 `LANGUAGE pragma`-k eta zabor-biltzailea. |
| **J / APL** | Kodearen forma taularatuarekiko obsesioa, tentsore natiboak eta sekuentzia-maskarak (`s["-+-"]`). | Teklatu arrunt batean idazteko ezinezkoak diren ikur hieroglifikoak. |
| **Rust / C** | ELF bitar natibo txikiak, zero GC, memoriaren kontrola (`with region`) eta POSIX sistema-deiak. | *Borrow checker*-arekiko etengabeko borroka, `'a` *lifetime*-ak eta berritsukeria sintaktikoa. |
| **Erlang / Go** | Kanal bidezko konkurrentzia (`chan_send`, `chan_recv`) eta ataza arinak (`spawn`, `join`). | `nil` erakusleak eta deskuiduz partekatutako mutazioak. |

---

## 1.6. Eta garrantzitsuena: Zer egiten du Ridgunek beste INORK ez duena?

Klasikoak aitortzea gizalegezkoa da, baina Ridgun beste lengoaia batzuen "arrakasta handien bilduma" hutsa balitz, ez zinateke liburu hau irakurtzen ariko.

Badira Ridgunen diseinatu eta integratu ditugun **zazpi gauza**, egungo beste inongo lengoaiatan elkarrekin —eta horietako asko, ezta banaka ere— aurkituko ez dituzunak:

### 1. `||` bloke paraleloak `->` geziekin: benetako grafo paraleloak dira, ez azukre sintaktiko hutsa
Beste lengoaia funtzional batzuetan, aldagai lokalen bloke batek gero hari bakar batean ebaluatzen diren adierazpenak ordenatu baino ez ditu egiten.
Ridgunen, **`||` bloke bat `->` geziekin exekuzio paraleloko Grafo Azikliko Zuzendu (DAG) bat da**, `where` bezalako hitz gako gehigarririk idatzi beharrik ere izan gabe:
```ridgun
urteko_txostena Int => Int
urteko_txostena id  =  diru_sarrerak - gastuak
  || kalkulatu_salmentak id -> diru_sarrerak
  || kalkulatu_kostuak id   -> gastuak
```
Zuk fluxu-geziak (`->`) marrazten dituzu. Konpiladoreak aztertzen du zer dagoen zeren menpe, **estatikoki egiaztatzen du ez duzula begizta infinitorik sortu**, eta adar independenteak paraleloan abiarazten ditu zuk `async`, `await`, `Future` edo `Mutex` bakar bat ere idatzi gabe.

### 2. Kodea bi dimentsioko taula gisa, non sinadura zutabeen goiburua den
Beste edozein lengoaiatan, mota-sinadura bere aldetik doa lerro batean eta funtzioaren gorputza azpian doa testu arrunteko paragrafo baten moduan.
Ridgunen, **mota-sinadura hitzez hitz taula baten goiburua da**, eta azpiko kasu bakoitzak eredu bakoitza bere motaren bertikalean bertan lerrokatzen du, eta `=` bakoitza `=>`-ren azpian:
```ridgun
zatitu Int Int => Option
zatitu _   0   =  None
zatitu a   b   =  Some (a / b)
```
Beste inork ez ditu sinadura eta ekuazioak konpiladoreak egiaztatutako eta `stable format`-ek automatikoki maketatutako matrize bisual bakar gisa tratatzen.

### 3. Esaldi-eragile (*Mixfix* N-ario) tipatuak eta lerrokatuak (`op ::`)
Lengoaia gehienetan, edo `+`, `-`, `*`-rekin konformatzen zara, edo gehienez ere inork zer esan nahi duen ez dakien `<|>` bezalako eragile bitar kriptiko bat definitzen duzu.
Ridgunen **nahi adina hutsune tipatu dituzten esaldi irakurgarriak diren eragileak** sor ditzakezu (`type` edo `with` bezalako testuinguruko hitzak barne):
```ridgun
op :: Int mugatua Int eta Int artean => Int
      x   mugatua min eta max artean =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
Eta gero zure kodean `abiadura mugatua 0 eta 120 artean` idazten duzu. Euskara (edo ingelesa) bezala irakurtzen da, baina % 100ean tipatuta eta kode natibora konpilatuta dago.

### 4. Maskara bisualak sekuentzien gainean (`s(+ _)` eta `s["-+-"]`)
Inoiz idatzi behar izan duzu `filter(\(i, x) -> i % 2 == 0)` moduko indize-entsalada bat elementu bikoitiekin geratzeko edo zerrenda batetik eredu erritmiko bat ateratzeko soilik?
Ridgunen zuzenean **maskara bisual** bat pasatzen diozu:
- `datuak["-+-"]`: lehenengoa baztertzen du (`-`), bigarrenarekin geratzen da (`+`), hirugarrena baztertzen du (`-`).
- `datuak["+-~"]`: `~` ikurrak `+-` eredua begiztan errepikatzen du zerrendaren amaierara arte (indize bikoiti guztiak kolpe batez).
Zero indize-aritmetika, zero *off-by-one* errore.

### 5. "Zerozko zarata" duen polimorfismoa (`A`..`Z`), zure domeinuak gobernatua
Rust, TypeScript edo Javan, funtzio bat generikoa denean lerroa parentesi angeluarrez bete behar duzu: `fn trukatu<A, B>(bikotea: (A, B)) -> (B, A)`.
Ridgunen letra larri solte bat erabiltzen duzu, besterik gabe:
```ridgun
trukatu (A, B) => (B, A)
trukatu (x, y) =  (y, x)
```
*"Eta nire programan `type A` deitzen den benetako mota bat eduki nahi badut?"* — Arazorik ez: Ridgunen **zure `type` deklarazioek agintzen dute**. `type A` existitzen ez bada, `A` generikoa da; `type A = ...` definitzen duzun une berean, zure mota zehatza izatera pasatzen da modulu osoan.

### 6. Zero konfigurazio-fitxategi arrotz: `build.rg` Ridgun purua da
Ahaztu Cargorako TOML, npm-rako JSON, Mavenerako XML edo tabuladore ikusezinak dituen `Makefile`-ren sintaxi arkanoa ikasteaz. Ridgunen, zure proiektua eraikitzen duen errezeta (`build.rg`) **beste `.rg` fitxategi bat gehiago da**, zure gainerako kodearen funtzio puru eta *pattern matching* berberekin.

### 7. Ezinezkoa zirudien "Hirutasun Santua": Haskell maila + RMM memoria GC eta Lifetimerik gabe + ~350 KB-ko bitarrak
Gaur arte aukeratu egin behar zenuen:
- Adierazkortasun funtzional purua nahi bazenuen (Haskell, OCaml, Elixir), zabor-biltzaile batekin eta runtime astun batekin ordaintzen zenuen.
- Zabor-biltzailerik gabeko sistemako bitar ñimiñoak nahi bazenituen (C, Rust, Zig), erakusleak kudeatuz edo *borrow checker*-arekin borrokatuz eta `let mut`-ez betetako kode inperatiboa idatziz ordaintzen zenuen.

Ridgunek dilema hori hausten du **Ridgun Memory Management (`RMM`: `RMM1` estatikoa eta `RMM2` esleipen-kontaketa kaskadakoarekin)**, arena osoak $O(1)$-ean askatzen dituzten **eskualde lexikoak (`with region`)**, **begizta natibo (`loop`) bihurtutako isats-errekurtsioa** eta `main`-etik abiatutako **dei-grafoaren inausketa (*Tree-Shaking*)** konbinatuz. Emaitza: maila goren-goreneko kode deklaratiboa idazten duzu eta C-n idatzitako tresnekin buruz buru lehiatzeko gai den **~350 KB**-ko ELF exekutagarri autonomo bat lortzen duzu.

Orain bai: kartak mahai gainean ditugula, goazen **02. kapitulura** **`ridgunc`** eta **`stable`** lanean jartzera.
