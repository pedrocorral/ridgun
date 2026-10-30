# 05. kapitulua: Zerrendak, Tuplak eta Sekuentzien ninja trikimailua

Aldi bakoitzean zenbaki bat edo testu bat bakarrik mugitzen duen programa batek ezer gutxirako balio du. Bizitza errealean fitxategi-zerrendak, datu-base bateko errenkadak, sare-paketeak edo koordenatuak erabiltzen dituzu.

Horretarako, Ridgunek hiru ontzi desberdin ematen dizkizu, bakoitza lan oso zehatz baterako pentsatua:
1. **Zerrendak (`[T]`)**: *"Mota bereko elementu asko ditut (edo bat ere ez) eta zeharkatu egin nahi ditut"*.
2. **Tuplak (`(A, B)`)**: *"Gauza desberdinen bikote edo hirukote bat elkarrekin itzuli nahi dut mota berri bat sortu gabe"*.
3. **Sekuentziak eta maskarak (`s(_ + _)`, `(+ _ _ +)`)**: *"Argumentuak hegaldian iragazi edo berrantolatu nahi ditut iragazki matematiko bat banu bezala"*.

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
batu zerrenda [Int]  => Int
batu zerrenda []     =  0
batu zerrenda (x:xs) =  x + (batu zerrenda xs)

zenbatu elementuak [A]    => Int
zenbatu elementuak []     =  0
zenbatu elementuak (_:xs) =  1 + (zenbatu elementuak xs)
```

Eta eguna alaituko dizun xehetasun tekniko bat: Ridgunen, `(x:xs)` ereduan `xs` isatsa ateratzeak **ez du gainerako zerrenda memorian kopiatzen**. Barnean bektore beraren gaineko ikuspegi bat da, hasierako erakuslea `1`ean aurreratzen duena soilik (berehalako $O(1)$).

### Hainbat elementu kolpe batez agerian utz ditzakezu
`:` ereduak joko handia ematen du komandoak edo protokoloak analizatzen ari zarenean:

```ridgun
interpretatu komandoa [String]                   => String
interpretatu komandoa []                         =  "Ez duzu ezer idatzi"
interpretatu komandoa ("laguntza":_)             =  "Laguntza erakusten..."
interpretatu komandoa ("kopiatu":jatorria:helm:[]) = "{jatorria}-tik {helm}-ra kopiatzen"
interpretatu komandoa (cmd:_)                    =  "Komando ezezaguna: {cmd}"
```

Begira hirugarren errenkadari: `("kopiatu":jatorria:helm:[])` ereduak kolpe bakar batez egiaztatzen du zerrendak **zehazki 3 elementu** dituela, lehenengoa `"kopiatu"` dela, eta bigarrena eta hirugarrena erretiluan zerbitzatuta uzten dizkizu `jatorria` eta `helm` aldagaietan. Saiatu hori C edo Javan idazten eta ikusiko duzu zenbat `args.length == 3 && args[0].equals("kopiatu")` lerro ateratzen zaizkizun.

### Zerrendak bi puntu bikoitzekin (`::`) lotzea
`=` ikurraren eskuinaldean zaudenean (adierazpen batean) eta bi zerrenda itsatsi nahi dituzunean, **`::`** erabiltzen duzu:

```ridgun
itsatsi zerrendak [Int] [Int] => [Int]
itsatsi zerrendak a     b     =  a :: b

gehitu atzean [Int] Int => [Int]
gehitu atzean xs    x   =  xs :: [x]
```

*(Erregela mnemotekniko azkarra: `:` bakar batek ereduetan zerrenda desmuntatzen du; bi `::`-k adierazpenetan bi zerrenda itsasten dituzte).*

Eta benetan 5. elementua zuzenean atera nahi baduzu ezer zeharkatu gabe? Erabili izenari itsatsitako kortxeteak: `nire_zerrenda[5]`.

---

## 5.2. Funtzio bariadikoak (`T...`): "Pasa iezazkidazu nahi dituzun guztiak!"

Batzuetan nahi duzu zure funtzioari deitzen dionak `maximoa 4 19 2 88 7` eroso idatzi ahal izatea, zenbakiak `[4, 19, 2, 88, 7]` kortxete artean biltzera behartu gabe.

Jarri hiru puntu **`...`** zure sinadurako azken motaren atzean, eta zure funtzioaren barruan zerrenda gisa paketatuta jasoko duzu automatikoki:

```ridgun
batu hainbat Int... => Int
batu hainbat zenb   =  batu zerrenda zenb

main => ()
main =
  echo (batu hainbat 10 20 30)       -- 60 inprimatzen du
  echo (batu hainbat 1 2 3 4 5 6 7)  -- 28 inprimatzen du
```

---

## 5.3. Tuplak: Funtzio batek gauza bat baino gehiago itzuli nahi duenean

Lengoaia askotan funtzio batetik bi gauza itzultzea buruko mina da: edo `EmaitzaPosizioarekin` klase laguntzaile lelo bat sortzen duzu, edo irteerako erakusleak erreferentziaz pasatzen dituzu.

Ridgunen `(A, B)` **tupla** bat itzultzen duzu:

```ridgun
zatitu eta hondarra Int Int => (Int, Int)
zatitu eta hondarra a   b   =  (a / b, a % b)
```

Parentesiak ere aurrez ditzakezu sinaduraren lerroan garbiago iruditzen bazaizu:
`zatitu eta hondarra Int Int => Int Int`.

### Nola ireki tupla bat
`(a, b)`-rekin sortzen duzun bezalaxe, edozein funtzioren argumentuetan `(zatidura, hondarra)`-rekin irekitzen duzu:

```ridgun
azaldu zatiketa (Int, Int)           => String
azaldu zatiketa (zatidura, hondarra) =  "{zatidura} aldiz sartzen da eta {hondarra} geratzen dira"
```

### Xehetasun izarra: Despaketatze automatikoa funtzioen artean
Demagun `zatitu eta hondarra` (2 osokoko tupla bat itzultzen duena) eta beste funtzio bat `batu bikotea Int Int => Int` (2 osoko solte espero dituena) dituzula. Ridgunen ez duzu tupla eskuz ireki behar tarteko aldagai batean; funtzio bat bestearen barruan zuzenean entxufatu dezakezu:

```ridgun
batu bikotea Int Int => Int
batu bikotea x   y   =  x + y

main => ()
main =
  -- zatitu eta hondarra 17 5 deiak (3, 2) itzultzen du, eta batu bikotea-k 3 eta 2 zuzenean jasotzen ditu:
  echo (batu bikotea (zatitu eta hondarra 17 5))  -- 5 inprimatzen du
```

---

## 5.4. Ninja trikimailua: Sekuentziak eta Maskara Posizionalak (`s(_ + _)`, `(+ _ _ +)`)

Hemen dator Ridgunen bitxirik originalenetako bat, J eta APL bezalako lengoaia bektorialetatik zuzenean oinordetzan hartua.

Imajinatu argumentu-sorta bat jasotzen duzula **`(s)`** sekuentzia-ereduarekin eta batzuekin bakarrik geratu nahi duzula eta besteak baztertu, asmatutako izenak dituzten bost aldagai deklaratu gabe (`_a`, `b`, `_c`, `d`...).

`s`-ri **`+` (geratu horrekin) eta `_` (baztertu) tupla-maskara bat** aplikatzen diozu:

- **`s(_ + _)`**: 3 elementutik, baztertu lehenengoa (`_`), geratu bigarrenarekin (`+`) eta baztertu hirugarrena (`_`).
- **`s(+ _ +)`**: geratu lehenengoarekin eta hirugarrenarekin; itzuli bi horiek dituen sekuentzia.
- **`s(_ _ +...)`**: baztertu lehenengo biak (`_ _`) eta aplikatu `+...` **atzetik datozen gainerako guztiei**, edozein izanda ere haien kopurua.

Begira nola funtzionatzen duen:

```ridgun
erdikoa Int Int Int => Int
erdikoa (s)         =  s(_ + _)

baztertu lehen biak Int... => [Int]
baztertu lehen biak (s)    =  s(_ _ +...)

main => ()
main =
  echo (erdikoa 100 42 999)              -- 42 inprimatzen du
  echo (baztertu lehen biak 1 2 10 20 30) -- [10, 20, 30] inprimatzen du
```

Eta onena: **`(+ _ _ +)`** maskara posizional bat **zuzenean `->` hodi baten erdian** tartean sar dezakezu! Funtzio batek hainbat baliotako tupla bat itzultzen badu eta hurrengo funtzioak horietako bi bakarrik behar baditu, tupla hegaldian iragazten duzu eta Ridgunek bizirik atera diren elementuak hurrengo urratseko argumentu bereizi gisa desegituratuko ditu:

```ridgun
-- parseatu paketea-k 4 balio itzultzen ditu: (Int, Int, [String String], String)
-- (+ _ _ +)-k 1.a (code) eta 4.a (msg) gordetzen ditu, eta konbinatu kodea-ri pasatzen dizkio:
parseatu paketea "v0.9.9" -> (+ _ _ +) -> konbinatu kodea -> laburpena
```

Gainera, parentesietatik kanpo `,` koma eragilea erabiltzen baduzu (`zerrenda1 , zerrenda2`), Ridgunek bi bildumak sekuentzia jarraitu bakar batean lautzen ditu.

**06. kapituluan** programatzaile funtzional bat lehen mailako arkitekto bihurtzen duen urratsa emango dugu: **zure Datu-Mota Aljebraikoak (ADTak) sortzea, `A`..`Z`-rekin funtzio polimorfikoak idaztea eta neurrira egindako zure eragile propioak fabrikatzea**.
