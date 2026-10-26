# 07. kapitulua: Goi-Mailako Funtzioak eta Izerdirik Gabeko Paralelismoa (Ez `Mutex`-ik, ez `Deadlock`-ik)

Ia programazio-lengoaia guztietan une dramatiko bat egoten da proiektu baten bizitzan: bilera batean norbaitek honako hau esaten duen eguna:

> *"Hau motel doa. Hariekin paralelizatu behar da."*

Isiltasuna nagusitzen da aretoan. Mundu guztiak daki zer datorren ondoren: asteak ilargi beteko astearteetan bakarrik gertatzen diren *race condition* mamuak, elkar-blokeatzeak (*deadlock*-ak) eta erreproduzitu ezinezko erroreak ehizatzen.

Ridgunen, norbaitek *"paralelizatu egin behar da"* esaten duenean, nahikoa da zerrenda-eragiketen aurrean `||` jartzea (**`||map`** eta **`||filter`**) edo zure kalkuluak `->` geziak dituen `||` bloke paralelo batean jartzea eta kafe bat hartzera joatea.

Zergatik? **Zure funtzioak puruak direnean eta zure datuak aldaezinak direnean lehenespenez, aldi berean lanean ari diren bi PUZ nukleok ezin diotelako inoiz elkarri mahuka zapaldu**.

Ikus dezagun urratsez urrats.

---

## 7.1. Funtzioak jasotzen dituzten funtzioak: `map`, `||map`, `filter`, `||filter` eta `fold`

Ridgunen funtzio bat beste balio bat gehiago da. Parametro bidez pasa dezakezu `7` zenbakia pasatzen duzun bezalaxe.

Lengoaiak bilduma-konbinatzaileak dakartza seriean, zerrendak eskuzko errekurtsio bakar bat ere idatzi gabe eraldatzeko, bai modu sekuentzialean (`map`, `filter`, `fold`) bai nukleo anitzeko modu paraleloan `||` aurrizkiarekin (**`||map`**, **`||filter`**):

### 1. `map` (sekuentziala) eta `||map` (nukleo anitzeko paraleloa)
Demagun `garestia Int => Int` funtzio bat eta zenbakiak dituen zerrenda bat dituzula:

```ridgun
garestia Int => Int
garestia x   =  (x * x) + (x * 3)

main => ()
main =
  datuak = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Sekuentzial zorrotza ezkerretik eskuinera:
  r1 = map garestia datuak
  -- Nukleo anitzeko paraleloa `||` aurrizkiarekin:
  r2 = ||map garestia datuak
  echo r1
  echo r2
```

- **`map`**-ekin, Ridgunek funtzioa elementuz elementu aplikatzen du ezkerretik eskuinera uneko harian (zerrenda txikietarako edo ordenatutako sarrera/irteera efektuak dituzten funtzioetarako bikaina).
- **`||map`**-ekin, Ridgunen runtime-ak `datuak` zerrendako elementuak zure prozesadoreko hari langileen artean banatzen ditu eta azken zerrenda **zehazki ordena berean** berreraikitzen du, `||map f xs == map f xs` bermatuz.

### 2. `filter` (sekuentziala) eta `||filter` (paraleloa): Baldintza bat betetzen dutenekin bakarrik geratzea
`Bool` itzultzen duen funtzio bat (*predikatu* bat) eta zerrenda bat pasatzen dizkiozu:

```ridgun
positiboa_da Int => Bool
positiboa_da n   =  n > 0

main => ()
main =
  garbiak = filter positiboa_da [-5, 10, 0, -2, 42]
  garbiak_par = ||filter positiboa_da [-5, 10, 0, -2, 42]
  echo garbiak      -- [10, 42] inprimatzen du
  echo garbiak_par  -- [10, 42] inprimatzen du
```

### 3. `fold`: Zerrenda oso bat emaitza bakar batera murriztea
Bi argumentuko funtzio konbinatzaile bat `(Metatua Elementua => Metatua)`, hasierako balioa eta zerrenda pasatzen dizkiozu:

```ridgun
metatu_biderkadura Int Int => Int
metatu_biderkadura acc x   =  acc * x

main => ()
main =
  echo (fold metatu_biderkadura 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### Nola idazten dut nik beste funtzio bat jasotzen duen nire funtzio propioa?
Oso erraz: mota-sinaduran funtzio gonbidatuaren sinadura parentesi artean jartzen duzu `(Sarrera => Irteera)`:

```ridgun
exekutatu_bi_aldiz (A => A) A => A
exekutatu_bi_aldiz f        x =  f (f x)
```

### 4. Itxitura lexikoak eta funtzio anonimoak (`\x -> expr`, `\acc x -> expr`)
Unean bertan funtzio labur bat pasa nahi duzunean edo uneko esparruko aldagai lokalak (desplazamendu bat, aurrizki bat edo saio aktibo bat) atzeman nahi dituzunean funtzio global laguntzaile bat deklaratu gabe, **itxitura lexiko** bat erabiltzen duzu **`\`** eta **`->`**-rekin:

```ridgun
fn :: prozesatu saioarekin => [Int]
      prozesatu saioarekin =
        oinarria    = 10
        hobaria     = 3
        batuak      = map (\x -> x + oinarria) [1, 2, 3]
        iragaziak   = filter (\x -> x >= hobaria) [1, 2, 3, 4]
        guztira     = fold (\acc x -> acc + x + hobaria) 0 [1, 2, 3]
        batuak :: iragaziak :: [guztira]
```
Atzemandako aldagaiak (`oinarria`, `hobaria`) automatikoki paketatzen dira memoria-kudeaketa deterministarekin (`RMM1`/`RMM2`), ihesik gabe eta zabor-biltzailearen etenik gabe.

---

## 7.2. Koroaren bitxia: `||` blokeak `->` geziekin Grafo Paralelo (DAG) gisa

Hemen aldatzen du Ridgunek zure pentsamoldea.

Lengoaia inperatibo arrunt batean, hiru lerro jarraian idazten dituzunean:
1. Lehenengo 1. lerroa exekutatzen da.
2. Gero 2. lerroa (nahiz eta 1. lerroarekin inolako zerikusirik ez izan).
3. Gero 3. lerroa.

Hori ordenagailua betaurreko ilunekin lan egitera behartzea da. Ridgunen, **`||`** barra paraleloak **`->`** geziekin erabiltzen dituzunean (`where` bezalako inongo hitz gakorik idatzi beharrik gabe), ez zara agindu sekuentzialak ematen ari: zein kalkuluk zein aldagai elikatzen duen dioen **Grafo Azikliko Zuzendu (DAG)** bat marrazten ari zara:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_kalkulua => Int
super_kalkulua =  ezker_adarra + eskuin_adarra
  || fib 10 -> ezker_adarra
  || fact 6 -> eskuin_adarra
```

Irakurri ozenki:
- *"`ezker_adarra + eskuin_adarra` kalkulatu nahi dut, bitartean paraleloan (`||`) `fib 10` `ezker_adarra`-ra doalarik (`->`) eta `fact 6` `eskuin_adarra`-ra doalarik (`->`)."*

### Zer egiten duen `ridgunc`-ek oihalaren atzean zure `||` lerroekin:
1. `->` geziei begiratzen die eta mendekotasun-zuhaitza (DAG) osatzen du.
2. **Zikloak estatikoki ehizatzen ditu**: hutsez `|| a + 1 -> b` eta `|| b + 1 -> a` idazten badituzu, konpiladoreak berehala esaten dizu *"Geldi hor! Mendekotasun zirkular bat dago"* eta ez dizu blokeo infinito bat konpilatzen uzten.
3. Ikusten du `fib 10` eta `fact 6` ez daudela elkarren menpe, beraz argi berdea dute paraleloan exekutatzeko `ezker_adarra + eskuin_adarra`-n batu aurretik.

Are gehiago, hainbat solairuko hodi bat munta dezakezu `||` bloke berean —adierazpenaren oinean zein `=` ondoren bertan— eta konpiladoreak bere kabuz ondorioztatuko du zein solairu joan daitezkeen batera eta zeintzuek itxaron behar duten:

```ridgun
hiruhileko_balantzea Int => Int
hiruhileko_balantzea oinarria =
  || oinarria * 100                   -> salmenta_gordinak
  || oinarria * 40                    -> kostu_finkoak
  || salmenta_gordinak - kostu_finkoak -> irabazi_gordina ||.
  irabazi_gordina * 80 / 100
```

Erreparatu azken `||` lerroaren amaierako **`||.`** xehetasunari: `|.` ikurrak habiaratutako zain-zuhaitz bat ixten duen bezalaxe, **`||.`** ikurrak `||` bloke paraleloa ixten du azpian sententzia sekuentzial arruntek jarraitzen dutenean. Hemen `salmenta_gordinak` eta `kostu_finkoak` paraleloan abiarazten dira; biak prest daudenean `irabazi_gordina` kalkulatzen da, eta azkenik `irabazi_gordina * 80 / 100` itzultzen da. Dena `async`, `Future`, `Promise` edo `Mutex` bakar bat ere gabe.

---

## 7.3. Izenik gabeko `||` lasterbidea: Tupla bat itzultzen duten hodi paraleloak

Eta bi edo hiru kalkulu paraleloan abiarazi eta tupla batean elkarrekin jaso nahi badituzu `->` bidez aldagai-izenak asmatu ere egin gabe?

`||` zuzenean erabiltzen duzu:

```ridgun
bikote_paraleloa Int => (Int, Int)
bikote_paraleloa n   =
  || fib n
  || fact n
```

Zuzena, bisuala eta `(fib n, fact n)` tupla itzultzen du.

---

## 7.4. Eskuzko bolantea nahi duzunean: Agenteen Eredu Natiboa (`agent`, `send ... to`, `receive from`) eta CSP Kanalak

`||` eta `||map`-en paralelismo automatikoak kasuen % 90a estaltzen du. Baina zerbitzari iraunkor bat, egoera isolatuko erabiltzaile-saioak, lan-ilara bat edo ekoizle-kontsumitzaile hodi bat programatzen ari zarenean, **memoria isolatuko agente konkurrenteak eta motadun mezu-igarotzea** nahi dituzu.

Ridgunen ez dago `actor ::` bezalako sintaxi arrotz bat asmatu beharrik: **edozein funtzio arrunt (`fn ::` edo `op ::`) agente konkurrente bihurtzen da lerro bakar batean `agent` erabiliz**:

### 1. Egoerarik gabeko eta egoera isolatuko agenteak (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (nire funtzioa)`: `M => R` funtzio bat `Agent M R` motako egoerarik gabeko agente bihurtzen du.
- `ag = agent (egoeradun funtzioa) hasierako_egoera`: `S M => S` (edo `S M => S R`) funtzio bat egoera isolatuko agente bihurtzen du, mezuz mezu bere egoera gogoratuz `Mutex` bakar bat ere gabe.
- `send msg to ag` (edo argumentu askorekin: `send a b to ag`): motadun mezu bat bidaltzen du agentearen postontzira.
- `em = receive from ag` (edo `try receive from ag` blokeatu gabe): agentearen irteerako postontziko hurrengo erantzuna jasotzen du.
- `stop ag`: agentea gelditzen du eta bere egoera automatikoki askatzen du `RMM1`/`RMM2` bidez.

```ridgun
fn :: gehitu bisita Int Int => Int
      gehitu bisita met n   =  met + n

fn :: prozesatu sorta Int Int => Int
      prozesatu sorta id  t   =  (id * 100) + t

fn :: main => ()
      main =
        kontagailua = agent (gehitu bisita) 10
        send 5 to kontagailua
        send 7 to kontagailua
        b1 = receive from kontagailua
        b2 = receive from kontagailua
        stop kontagailua

        langilea = agent (prozesatu sorta)
        send 3 25 to langilea
        sorta = receive from langilea
        stop langilea
        echo "Bisitak:" b1 "->" b2 "| Sorta:" sorta
```

### 2. Aukeraketa adimenduna konpilazio-garaian (*Green Threads* vs. Kerneleko Benetako Hariak)
Ohiko galdera bat hau da: *"`||` blokeek, `||map`-ek eta `agent` agenteek beti sortzen al dituzte sistema eragilearen hariak, ala ataza arin gisa exekutatzen dira?"*

Ridgunen, **konpiladoreak zure ordez hartzen du erabaki hori funtzio bakoitza estatikoki aztertuz**:
- **Funtzio arinak (`TierTrivial` / `StratInlineSequential`)**: `||`, `||map`, `||filter` edo `agent`-era pasatzen duzun funtzioak sakonera txikia badu (aritmetika, kateen formateatzea, HTTP saio baten egoera-trantsizio azkarra), sistema eragilearen hariak berotzeak kalkuluak berak baino gehiago balioko luke. Konpiladoreak *green-thread* urrats ultraarin gisa exekutatzen du, `SYS_clone` gainkargarik gabe.
- **Kalkulu astunak edo errekurtsibo sakonak (`TierDynamicRecursive` / `TierHeavyCPU`)**: Funtzioak errekurtsio sakona (`fib` edo `fact` bezala) edo tentsore-aljebra (`einsum`, `hadamard`, `@`) badu, konpiladoreak automatikoki sortzen du nukleo anitzeko bidalketa **kerneleko benetako harien gainean (`SYS_clone`)**, `||` adarrak edo `agent`-aren mezu-ilara zure PUZ nukleo guztietan benetako paraleloan prozesatuz.

### 3. Mezuak kanal mugatuetatik pasatzea (`new bounded channel`)
Go edo Erlangen bezalaxe, agenteez gain hodi esplizituak ere sor ditzakezu etapak komunikatzeko:

- `new bounded channel edukiera`: `edukiera` mezurentzako lekua duen kanal bat sortzen du.
- `send through balioa kanala` (edo `chan send balioa kanala`): mezu bat hodian sartzen du.
- `receive from kanala` (edo `chan recv kanala`): hurrengo mezua hoditik ateratzen du.
- `try receive from kanala`: mezurik dagoen begiratzen du zain geratu gabe; `Some balioa` edo `None` itzultzen du.
- `receive from timeout kanala ticks`: denbora-muga bat itxaroten du eta `Ok balioa` edo `Err Timeout` itzultzen du.

```ridgun
fn :: main => ()
      main =
        hodia = new bounded channel 4
        _ = send through "A ataza osatuta" hodia
        _ = send through "B ataza osatuta" hodia
        lehena = receive from hodia
        bigarrena = receive from hodia
        echo lehena "|" bigarrena
```

Eta orain, lotu gerrikoa **08. kapitulurako**, amaiera handirako: **konpilazio-garaian egiaztatutako dimentsioak dituzten tentsoreak, esparru-aldagaiak (`context`/`shared`), memoria-eskualde deterministak, MMIO hardwarerako sarbide zuzena eta UNIX/POSIX sistemen programazioa**.
