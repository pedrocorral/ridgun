# 05. kapitulua: Zerrendak, Tuplak eta Sekuentzien ninja trikimailua

Aldi bakoitzean zenbaki bat edo testu bat bakarrik mugitzen duen programa batek ezer gutxirako balio du. Bizitza errealean fitxategi-zerrendak, datu-base bateko errenkadak, sare-paketeak edo koordenatuak erabiltzen dituzu.

Horretarako, Ridgunek hiru ontzi desberdin ematen dizkizu, bakoitza lan oso zehatz baterako pentsatua:
1. **Zerrendak (`[T]`)**: *"Mota bereko elementu asko ditut (edo bat ere ez) eta zeharkatu egin nahi ditut"*.
2. **Tuplak (`(A, B)`)**: *"Gauza desberdinen bikote edo hirukote bat elkarrekin itzuli nahi dut mota berri bat sortu gabe"*.
3. **Sekuentziak eta maskarak (`s["-+-"]`)**: *"Argumentuak hegaldian iragazi edo berrantolatu nahi ditut iragazki matematiko bat banu bezala"*.

Goazen banan-banan.

---

## 5.1. Zerrendak (`[T]`): Eguneroko ogia

Ridgunen, mota baten inguruan kortxeteak jartzen badituzu, mota horretako zerrenda bat duzu:
- `[Int]` osokoen zerrenda bat da: `[10, 20, 30]`.
- `[String]` testuen zerrenda bat da: `["sagarra", "udarea"]`.
- `[]` zerrenda hutsa da (edozein `[T]`-rekin bat datorren komodina).

> *"Aizu, sar ditzaket zenbaki bat eta testu bat elkarrekin `[1, "bi"]` moduko zerrenda berean?"*
> Bere horretan, **ez** (eta eskerrak eman konpiladoreari hori eragozteagatik, horrela ez zaizulako inoiz batuketa bat lehertuko ekoizpenean ezusteko testu batekin topo egitean). 06. kapituluan ikusiko dugu nola ebatzi `[1, "bi"]` kasua dotorezia osoz Datu-Mota Aljebraiko bat erabiliz (Haskellek egiten duen bezalaxe).

### Nola zatitzen den zerrenda bat `i`, `j`, `k` indizeak erabili gabe: `[]` eta `(x:xs)`
Lengoaia inperatiboetan, zerrenda bat zeharkatzeak `for (int i = 0; i < zerrenda.size(); i++)` ekarri ohi du, batez pasatzeko (*off-by-one*) arrisku klasikoarekin.

Ridgunen ez dituzu indizeak zenbatzen; **zerrenda burutik desmuntatzen duzu**:
- `[]`: zerrenda hutsik badago bat dator.
- `(x:xs)`: zerrendak gutxienez elementu bat badu bat dator. Lehenengo elementua `x`-n sartzen du (**burua**) eta gainerako zerrenda `xs`-n (**isatsa**).

Begira zein gozamena den zerrenda bat batzea edo zenbat elementu dituen zenbatzea:

```ridgun
batu_zerrenda [Int]  => Int
batu_zerrenda []     =  0
batu_zerrenda (x:xs) =  x + (batu_zerrenda xs)

zenbatu_elementuak [A]    => Int
zenbatu_elementuak []     =  0
zenbatu_elementuak (_:xs) =  1 + (zenbatu_elementuak xs)
```

Eta eguna alaituko dizun xehetasun tekniko bat: Ridgunen, `(x:xs)` ereduan `xs` isatsa ateratzeak **ez du gainerako zerrenda memorian kopiatzen**. Barnean bektore beraren gaineko ikuspegi bat da, hasierako erakuslea `1`ean aurreratzen duena soilik (berehalako $O(1)$).

### Hainbat elementu kolpe batez agerian utz ditzakezu
`:` ereduak joko handia ematen du komandoak edo protokoloak analizatzen ari zarenean:

```ridgun
interpretatu_komandoa [String]                   => String
interpretatu_komandoa []                         =  "Ez duzu ezer idatzi"
interpretatu_komandoa ("laguntza":_)             =  "Laguntza erakusten..."
interpretatu_komandoa ("kopiatu":jatorria:helm:[]) = "{jatorria}-tik {helm}-ra kopiatzen"
interpretatu_komandoa (cmd:_)                    =  "Komando ezezaguna: {cmd}"
```

Begira hirugarren errenkadari: `("kopiatu":jatorria:helm:[])` ereduak kolpe bakar batez egiaztatzen du zerrendak **zehazki 3 elementu** dituela, lehenengoa `"kopiatu"` dela, eta bigarrena eta hirugarrena erretiluan zerbitzatuta uzten dizkizu `jatorria` eta `helm` aldagaietan. Saiatu hori C edo Javan idazten eta ikusiko duzu zenbat `args.length == 3 && args[0].equals("kopiatu")` lerro ateratzen zaizkizun.

### Zerrendak bi puntu bikoitzekin (`::`) lotzea
`=` ikurraren eskuinaldean zaudenean (adierazpen batean) eta bi zerrenda itsatsi nahi dituzunean, **`::`** erabiltzen duzu:

```ridgun
itsatsi_zerrendak [Int] [Int] => [Int]
itsatsi_zerrendak a     b     =  a :: b

gehitu_atzean [Int] Int => [Int]
gehitu_atzean xs    x   =  xs :: [x]
```

*(Erregela mnemotekniko azkarra: `:` bakar batek ereduetan zerrenda desmuntatzen du; bi `::`-k adierazpenetan bi zerrenda itsasten dituzte).*

Eta benetan 5. elementua zuzenean atera nahi baduzu ezer zeharkatu gabe? Erabili izenari itsatsitako kortxeteak: `nire_zerrenda[5]`.

---

## 5.2. Funtzio bariadikoak (`T...`): "Pasa iezazkidazu nahi dituzun guztiak!"

Batzuetan nahi duzu zure funtzioari deitzen dionak `maximoa 4 19 2 88 7` eroso idatzi ahal izatea, zenbakiak `[4, 19, 2, 88, 7]` kortxete artean biltzera behartu gabe.

Jarri hiru puntu **`...`** zure sinadurako azken motaren atzean, eta zure funtzioaren barruan zerrenda gisa paketatuta jasoko duzu automatikoki:

```ridgun
batu_hainbat Int... => Int
batu_hainbat zenb   =  batu_zerrenda zenb

main => ()
main =
  echo (batu_hainbat 10 20 30)       -- 60 inprimatzen du
  echo (batu_hainbat 1 2 3 4 5 6 7)  -- 28 inprimatzen du
```

---

## 5.3. Tuplak: Funtzio batek gauza bat baino gehiago itzuli nahi duenean

Lengoaia askotan funtzio batetik bi gauza itzultzea buruko mina da: edo `EmaitzaPosizioarekin` klase laguntzaile lelo bat sortzen duzu, edo irteerako erakusleak erreferentziaz pasatzen dituzu.

Ridgunen `(A, B)` **tupla** bat itzultzen duzu:

```ridgun
zatitu_eta_hondarra Int Int => (Int, Int)
zatitu_eta_hondarra a   b   =  (a / b, a % b)
```

Parentesiak ere aurrez ditzakezu sinaduraren lerroan garbiago iruditzen bazaizu:
`zatitu_eta_hondarra Int Int => Int Int`.

### Nola ireki tupla bat
`(a, b)`-rekin sortzen duzun bezalaxe, edozein funtzioren argumentuetan `(zatidura, hondarra)`-rekin irekitzen duzu:

```ridgun
azaldu_zatiketa (Int, Int)           => String
azaldu_zatiketa (zatidura, hondarra) =  "{zatidura} aldiz sartzen da eta {hondarra} geratzen dira"
```

### Xehetasun izarra: Despaketatze automatikoa funtzioen artean
Demagun `zatitu_eta_hondarra` (2 osokoko tupla bat itzultzen duena) eta beste funtzio bat `batu_bikotea Int Int => Int` (2 osoko solte espero dituena) dituzula. Ridgunen ez duzu tupla eskuz ireki behar tarteko aldagai batean; funtzio bat bestearen barruan zuzenean entxufatu dezakezu:

```ridgun
batu_bikotea Int Int => Int
batu_bikotea x   y   =  x + y

main => ()
main =
  -- zatitu_eta_hondarra 17 5 deiak (3, 2) itzultzen du, eta batu_bikotea-k 3 eta 2 zuzenean jasotzen ditu:
  echo (batu_bikotea (zatitu_eta_hondarra 17 5))  -- 5 inprimatzen du
```

---

## 5.4. Ninja trikimailua: Sekuentziak eta Maskara Posizionalak (`s["-+-"]`)

Hemen dator Ridgunen bitxirik originalenetako bat, J eta APL bezalako lengoaia bektorialetatik zuzenean oinordetzan hartua.

Imajinatu argumentu-sorta bat jasotzen duzula **`(s)`** sekuentzia-ereduarekin eta batzuekin bakarrik geratu nahi duzula eta besteak bota, asmatutako izenak dituzten bost aldagai deklaratu gabe (`_a`, `b`, `_c`, `d`...).

`s`-ri **`+` (geratu horrekin) eta `-` (bota ezazu) ikurren maskara bat** aplikatzen diozu:

- **`s["-+-"]`**: 3 elementutik, bota lehenengoa (`-`), geratu bigarrenarekin (`+`) eta bota hirugarrena (`-`).
- **`s["+-+"]`**: geratu lehenengoarekin eta hirugarrenarekin; itzuli bi horiek dituen sekuentzia.
- **`s["-- +"]`** (adi azken `+` aurreko zuriuneari): bota lehenengo biak (`--`) eta aplikatu `+` **atzetik datozen gainerako guztiei**, edozein izanda ere haien kopurua.

Begira nola funtzionatzen duen:

```ridgun
erdikoa Int Int Int => Int
erdikoa (s)         =  s["-+-"]

baztertu_lehen_biak Int... => [Int]
baztertu_lehen_biak (s)    =  s["-- +"]

main => ()
main =
  echo (erdikoa 100 42 999)              -- 42 inprimatzen du
  echo (baztertu_lehen_biak 1 2 10 20 30) -- [10, 20, 30] inprimatzen du
```

Gainera, parentesietatik kanpo `,` koma eragilea erabiltzen baduzu (`zerrenda1 , zerrenda2`), Ridgunek bi bildumak sekuentzia jarraitu bakar batean lautzen ditu.

**06. kapituluan** programatzaile funtzional bat lehen mailako arkitekto bihurtzen duen urratsa emango dugu: **zure Datu-Mota Aljebraikoak (ADTak) sortzea, `A`..`Z`-rekin funtzio polimorfikoak idaztea eta neurrira egindako zure eragile propioak fabrikatzea**.
