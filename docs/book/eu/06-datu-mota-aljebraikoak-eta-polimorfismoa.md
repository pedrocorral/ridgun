# 06. kapitulua: Datu-Mota Aljebraikoak (ADTak), Polimorfismoa eta zergatik hemen ez dugun `null` edo `Any` nahi

1965ean, Tony Hoarek erreferentzia nulua (`null` / `nil`) asmatu zuen. Berrogei urte geroago barkamena eskatu zuen jendaurrean eta *"nire mila milioi dolarreko akatsa"* deitu zion.

Zergatik? `null` duten lengoaietan, funtzio batek bere sinaduran hitzematen dizulako `Erabiltzailea` bat itzuliko dizula... eta gutxien espero duzunean `null` itzultzen dizulako eta goizeko hiruretan zerbitzaria lurrera botatzen dizulako.

Eta beste horrenbeste gertatzen da objektuen herentziarekin eta `Any` (edo `Object`) motarekin: zenbaki bat eta testu bat `[1, "bi"]` zerrenda batean sartzen dituzu, lengoaiak sorbaldak jasotzen ditu eta esaten du *"ados, ba orain hau `List[Any]` bat da, zorte on barruan zer dagoen asmatzen zeharkatzen duzunean"*.

Ridgunen bi arazo horiek errotik mozten ditugu **Datu-Mota Aljebraikoekin (ADTak)** eta **Polimorfismo Parametrikoarekin**. Ikasgai gogorreko izena duela dirudi, baina bost minutuan ikusiko duzu datuak modelatzeko munduko modurik naturalena dela.

---

## 6.1. Biderkadura-Motak (Erregistroak): Betiko zure `struct`-ak, baina superbotereekin

Entitate berari dagozkion hainbat datu elkartu nahi dituzunean (adibidez, zerbitzari bat bere izenarekin, bere IParekin eta bere atakarekin), **`type`** bat definitzen duzu bere eremuekin:

```ridgun
type Zerbitzaria = ostalaria: String, ataka: Int, tls_aktibo: Bool
```

Lerro hori idazte hutsarekin, Ridgunek **lau gauza** oparitzen dizkizu automatikoki:

### 1. `Zerbitzaria` eraikitzailea
```ridgun
nire_nodoa => Zerbitzaria
nire_nodoa =  Zerbitzaria "api.adibidea.eus" 443 True
```

### 2. *Getter* funtzio puru bat eremu bakoitzerako (`ostalaria`, `ataka`, `tls_aktibo`)
Ez duzu `s.getOstalaria()` edo antzekorik idatzi behar; eremu-izen bakoitza zuzenean datu hori ateratzen duen funtzio bat da:

```ridgun
konexio_urla Zerbitzaria => String
konexio_urla zrb         =  "Konektatu hona: " + (ostalaria zrb) + " {ataka zrb} atakan"
```

### 3. Erregistroen eguneratze funtzionala (`with eremua: balioa`)
Imajinatu 12 edo 15 eremuko konfigurazio-erregistro bat (`ls` komando baten edo web-zerbitzari baten aukerak bezala) eta eremu bat edo bi bakarrik aldatu nahi dituzula gainerakoak ukitu gabe. Erregistroa 15 eremuak eskuz pasatuz berreraiki beharrean, **`with`** eta bi puntu **`:`** erabiltzen dituzu (`type`-aren definizioan bezalaxe):

```ridgun
aktibatu_garapen_modua Zerbitzaria => Zerbitzaria
aktibatu_garapen_modua zrb         =  zrb with ataka: 8080, tls_aktibo: False
```

Bi munduetako onena:
- Zure kodean **% 100ean aldaezina eta segurua** da (konpiladoreak egiaztatzen du `ataka` eta `tls_aktibo` `Zerbitzaria`-n existitzen direla eta mota zuzena dutela).
- Azpitik, `zrb` beste inorekin partekatuta ez badago, exekutagarri natiboak bere memoria *in-place* berrerabiltzen du (`Arc::try_unwrap`) gainerako eremuak kopiatu gabe.

### 4. *Pattern matching* osoa erregistroa erditik ireki nahi baduzu
```ridgun
ataka_segurua_da Zerbitzaria                    => Bool
ataka_segurua_da (Zerbitzaria _ 443 True)       =  True
ataka_segurua_da _                              =  False
```

---

## 6.2. Batuketa-Motak (`|` bidezko aldaerak): Nola erretiratu `null`, salbuespenak eta herentzia

Orain dator onena.
Erregistro arrunt batek `ostalaria` **ETA** `ataka` **ETA** `tls_aktibo` ditu.
Baina mundu errealean askotan hau esan behar duzu: *"Ordainketa-metodo bat **EDO** bere zenbakia duen txartel bat da, **EDO** bere IBANa duen transferentzia bat da, **EDO** eskudirua da (datu gehigarririk ez daramana)"*.

Objektuetara bideratutako programazioan `OrdainketaMetodoa` interfaze bat, hiru azpiklase hiru fitxategi desberdinetan, eraikitzaileak, `instanceof`... sortu beharko zenituzke. Ridgunen **lerro bakarra** da:

```ridgun
type OrdainketaMetodoa = Txartela String Int | Transferentzia String | Eskudirua
```

Eta begira zer gertatzen den funtzio batean `OrdainketaMetodoa` bat prozesatzen duzunean:

```ridgun
deskribatu_ordainketa OrdainketaMetodoa      => String
deskribatu_ordainketa (Txartela zenb _)      =  "{zenb}-rekin amaitutako txartel bidezko ordainketa"
deskribatu_ordainketa (Transferentzia ibana) =  "Transferentzia {ibana} kontutik"
deskribatu_ordainketa Eskudirua              =  "Eskudirutan ordaintzea leihatilan"
```

Aldaera bakoitzak (`Txartela`, `Transferentzia`, `Eskudirua`) berarentzat zentzua duten datuak soilik daramatza itsatsita. **Ezinezkoa** da hutsez `ibana` bat zintzilik duen `Eskudirua` ordainketa bat eraikitzea.

---

## 6.3. "Eta nola sartzen dut `[1, "bi"]` zerrenda batean `Any` erabili gabe?"

Itzul gaitezen milioiaren galderara. Imajinatu CSV edo JSON fitxategi bat irakurtzen ari zarela, non gelaxka bat zenbaki osoko bat, testu bat edo hutsa izan daitekeen.

`Any` mota bat bazenu, `[1, "bi"]` sartuko zenuke eta konpiladorearen laguntza guztia galduko zenuke: une horretatik aurrera zerrendaren gaineko edozein eragiketa begiak estalita ibiltzea litzateke.

Ridgunen (Haskell edo Rusten bezalaxe), bi segundotan batuketa-mota bat sortzen duzu, zerrenda horren barruan zein gauza bizi daitezkeen zehatz-mehatz azaltzen duena:

```ridgun
type GelaxkaBalioa = Osokoa Int | Testua String | Hutsa

formateatu_gelaxka GelaxkaBalioa => String
formateatu_gelaxka (Osokoa n)    =  "Zenbakia: {n}"
formateatu_gelaxka (Testua s)    =  "Testua: {s}"
formateatu_gelaxka Hutsa         =  "(hutsik)"

nire_errenkada => [GelaxkaBalioa]
nire_errenkada =  [Osokoa 1, Testua "bi", Hutsa]
```

Ikusten duzu aldea?
- `Any`-rekin, konpiladoreak ez daki zerrendan osokoak, kateak ala USB bidez konektatutako kafe-makina bat dauden.
- `[GelaxkaBalioa]`-rekin, zenbakiak eta testuak zerrenda berean nahas ditzakezu, **baina konpiladoreak % 100ean daki hiru aukera horiek baino ez direla existitzen** eta kasu bakoitza (`Osokoa n`, `Testua s`, `Hutsa`) erabili aurretik despaketatzera behartzen zaitu. Segurtasun osoa malgutasun izpi bat ere galdu gabe.

---

## 6.4. `Option` eta `Result`: Zerbait ez egon daitekeenean edo huts egin dezakeenean

Ridgunen `null` existitzen ez denez eta airean lehertzen diren salbuespenik (`throw new Exception()`) existitzen ez denez, lengoaiak bi batuketa-mota unibertsal integratuta dakartza:

1. **`Option`**: edo **`Some balioa`** duzu, edo **`None`** (ezer ez) duzu.
2. **`Result`**: edo eragiketa ondo atera da (**`Ok balioa`**), edo arrazoi zehatz bategatik huts egin du (**`Err errorea`**).

```ridgun
bilatu_zatiketa Int Int => Result
bilatu_zatiketa _   0   =  Err "Ei! Ezin da zeroz zatitu"
bilatu_zatiketa a   b   =  Ok (a / b)

inprimatu_em Result    => ()
inprimatu_em (Ok n)    =  echo "Emaitza {n} da"
inprimatu_em (Err msg) =  echo "Hutsegite kontrolatua: {msg}"
```

Inork ezin du errore bat deskuiduz alde batera utzi, `Result` motak berak barruan `Ok` bat ala `Err` bat dagoen begiratzera behartzen zaituelako.

---

## 6.5. Polimorfismo Parametrikoa: Funtzio generikoak `A`, `B`, `T`...-rekin

Demagun `(x, y)` bikote bat alderantzikatzen duen edo zerrenda bateko lehen elementua ateratzen duen funtzio bat idazten duzula. Benetan axola du zerrenda `Int`, `String` ala `Zerbitzaria` motakoa den? Inola ere ez! Algoritmoa berdin-berdina da.

Ridgunen, mota-sinadura bateko **edozein letra larri banakok (`A`-tik `Z`-ra)** automatikoki **komodin-mota polimorfiko (mota-aldagai)** gisa funtzionatzen du:

```ridgun
buru_segurua [A]    A          => A
buru_segurua []     lehenetsia =  lehenetsia
buru_segurua (x:_)  _          =  x

biratu_bikotea (A, B) => (B, A)
biratu_bikotea (x, y) =  (y, x)
```

Erreparatu `buru_segurua [A] A => A`-ren magiari:
- Ez da kontrolik gabeko `Any` bat: **`[A]` zerrendaren motak, `lehenetsia` balioaren motak (`A`) eta itzulitako motak (`A`) bera izan behar dutela** dio.
- `buru_segurua [10, 20] 0` deitzen baduzu, konpiladoreak hariak lotzen ditu (`A = Int`) eta `Int` bat itzultzen dizu.
- `buru_segurua ["a", "b"] "bat_ere_ez"` deitzen baduzu, hariak lotzen ditu (`A = String`) eta `String` bat itzultzen dizu.
- Baina tranpa egiten saiatzen bazara eta `buru_segurua [10, 20] "bat_ere_ez"` deitzen baduzu, zas! Konpiladoreak lehorrean gelditzen zaitu, lehen argumentuak `A` `Int` dela dioelako eta bigarrenak `A` `String` dela.

---

## 6.6. Sortu zure eragile propioak (`op ::`): Bektoreetatik neurrira egindako esaldietara

Zergatik zenbaki natiboek bakarrik izan behar zuten `+` edo `*` erabiltzeko eskubidea? Eta zergatik konformatu betiko eragileekin zure arazorako sintaxi ezin hobea asma dezakezunean?

**`op ::`**-rekin (edo zuzenean aurrizkirik gabe eragile-ereduak erabiltzen badituzu) bi trebezia egin ditzakezu:

### 1. `+`, `-`, `*`, `/`, `%` eragileei zure mota propioekin eragiketak egiten irakastea
```ridgun
type Konplexua = erreala: Int, irudikaria: Int

op :: Konplexua + Konplexua => Konplexua
      a         + b         =  Konplexua ((erreala a) + (erreala b)) ((irudikaria a) + (irudikaria b))
```

### 2. *Mixfix* eragileak sortzea (esaldi natural gisa irakurtzen direnak, `type` eta `with` barne)
Eragile-sinadura batean, **hasieran letra larria duten hitzak (`Int`, `String`, `A`..`Z`) edo kortxete/parentesi artekoak (`[Int]`, `(A, B)`) argumentuetarako hutsuneak dira**, eta **letra xehez idatzitako hitzak eragilearen esaldiaren parte dira** (baita `type` edo `with` bezalako hitz ohikoak ere, Ridgunen testuingurukoak direnak eta inoiz blokeatzen ez zaituztenak):

```ridgun
op :: baldin Bool orduan A bestela A => A
      baldin True orduan v bestela _ =  v
      baldin False orduan _ bestela f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  mezua = baldin (10 > 5) orduan "Hamarrak irabazten du!" bestela "Ezinezkoa"
  echo mezua
  echo (format "panela" type "ertzduna" with 80)
```

Zure eragile hirutar polimorfiko propioa eta formateatzeko DSL bat fabrikatu berri dituzu Ridguneko **3 lerrotan**.

---

## 6.7. Eraikitzaile partekatuak, mota-aldaera zuzenak, `expand type` eta zuriune naturalak `fn ::`-n

Ridgunek datu-mota aljebraikoak eta funtzioak are naturalago eta hedagarriago bihurtzen ditu:

1. **Eraikitzaile-izen partekatuak `type` ezberdinen artean**: Batura-mota ezberdinek eraikitzaile-izen bera (`Error`, `Var`, `Lit`) berrerabil dezakete aritate berarekin edo ezberdinarekin; mota-egiaztatzaileak sinadurako zutabearen arabera bereizten ditu.
2. **Mota-izen zuzeneko aldaerak errepikapenik gabe (`type Something = String | Int | MyStruct Float Int`)**: Aldaera bat oinarrizko mota bat denean (`String`, `Int`, `Float`/`Real`, `Bool`, `Char`), ez duzu `Int Int` edo `String String` errepikatu behar. Balio zuzenak (`"kaixo"`, `42`) edo eraikitzaile esplizituak (`String "kaixo"`, `Int 42`) pasa ditzakezu, eta ereduak parekatu bai literalekin (`"admin"`, `0`) bai eredu tipatuekin (`(String s)`, `(Int n)`).
3. **Mota-hedapen irekia (`expand type`) eta `fn ::` klausulen bateratze automatikoa**: `expand type` erabiliz aldaera berriak gehitu diezazkiokezu batura-mota bati edo eremu berriak erregistro bati. Funtzio bererako `fn ::` berriro deklaratzean, klausula berriak automatikoki bateratzen dira edozein `_` komodin-klausularen **aurretik** (`expand fn` idatzi beharrik gabe).
4. **Zuriune naturalak `" "` `_`-ren ordez `fn ::`-n, funtzio natiboetan eta fitxategi-izenetan**: `op ::`-n bezala, hitz anitzeko `fn ::` izenak, funtzio natiboen deiak (`assert equals`, `str len`, `read file`) eta `.rg` fitxategi-izenak (`test core language.rg`) zuriune naturalekin idatz daitezke:

```ridgun
type Something = String | Int | MyStruct Float Int

fn :: deskribatu zerbait Something            => String
      deskribatu zerbait "admin"              =  "admin_berezia"
      deskribatu zerbait 0                    =  "zero"
      deskribatu zerbait (String   s)         =  "testua:{s}"
      deskribatu zerbait (Int      n)         =  "osoa:{n}"
      deskribatu zerbait (MyStruct ratio cnt) =  "egitura:{ratio}:{cnt}"
      deskribatu zerbait _                    =  "bestea"

expand type Something = Bool

fn :: deskribatu zerbait Something => String
      deskribatu zerbait (Bool b)  =  "boolearra:{b}"
```

**07. kapituluan** zure prozesadorearen nukleo guztiak aldi berean lanean jarriko ditugu izerdi tanta bat ere bota gabe: **goi-mailako funtzioak (`map`, `||map`, `filter`, `||filter`, `fold`), `||` grafo paraleloak `->` geziekin eta kanal konkurrenteak**.
