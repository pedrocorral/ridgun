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

## 7.4. Eskuzko bolantea nahi duzunean: `spawn`, `join` eta CSP Kanalak

`||` eta `map`-en paralelismo automatikoak kasuen % 90a estaltzen du. Baina batzuetan aktore-sistema bat, lan-ilara bat edo ekoizle-kontsumitzaile hodi bat programatzen ari zara eta zuk zeuk kontrolatu nahi dituzu atazak eta mezuak.

Horretarako bi tresna garbi dituzu:

### 1. Atazak `spawn`-ekin abiarazi eta emaitza `join`-ekin jaso
```ridgun
prozesatu_sorta Int => Int
prozesatu_sorta id  =  id * 100

main => ()
main =
  ataza1 = spawn prozesatu_sorta 1
  ataza2 = spawn prozesatu_sorta 2
  -- Bitartean beste gauza batzuk egin zenitzake hemen...
  em1 = join ataza1
  em2 = join ataza2
  echo "Honekin amaitu dute:" em1 "eta" em2
```

### 2. Mezuak kanal mugatuetatik pasatzea (`new_bounded_channel`)
Go edo Erlangen bezalaxe, harien artean memoria partekatu beharrean, balio aldaezinak bidaltzen dituzu hodi seguru baten bidez:

- `new_bounded_channel edukiera`: `edukiera` mezurentzako lekua duen kanal bat sortzen du.
- `chan_send balioa kanala` (edo `send_through balioa kanala`): mezu bat hodian sartzen du.
- `chan_recv kanala` (edo `receive_from kanala`): hurrengo mezua hoditik ateratzen du.
- `chan_try_recv kanala`: mezurik dagoen begiratzen du zain geratu gabe; `Some balioa` edo `None` itzultzen du.
- `receive_from_timeout kanala ticks`: denbora-muga bat itxaroten du eta `Ok balioa` edo `Err Timeout` itzultzen du.

```ridgun
main => ()
main =
  hodia = new_bounded_channel 4
  _ = chan_send "A ataza osatuta" hodia
  _ = chan_send "B ataza osatuta" hodia
  lehena = chan_recv hodia
  bigarrena = chan_recv hodia
  echo lehena "|" bigarrena
```

Eta orain, lotu gerrikoa **08. kapitulurako**, amaiera handirako: **konpilazio-garaian egiaztatutako dimentsioak dituzten tentsoreak, esparru-aldagaiak (`context`/`shared`), memoria-eskualde deterministak, MMIO hardwarerako sarbide zuzena eta UNIX/POSIX sistemen programazioa**.
