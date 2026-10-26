# Kapitel 06: Algebraiska datatyper (ADT), polymorfism och varför vi inte vill ha `null` eller `Any` här

År 1965 uppfann Tony Hoare null-referensen (`null` / `nil`). Fyrtio år senare bad han offentligt om ursäkt och kallade den *"mitt miljarddollarsmisstag"*.

Varför? Därför att i språk med `null` lovar en funktion i sin signatur att den ska ge dig en `Anvandare`... och när du minst anar det returnerar den `null` och sänker servern klockan tre på natten.

Och precis samma sak händer med objektarv och typen `Any` (eller `Object`): du stoppar in ett tal och en text i en lista `[1, "tva"]`, språket rycker på axlarna och säger *"okej, då är det här en `List[Any]` nu, lycka till med att gissa vad som ligger i den när du går igenom den"*.

I Ridgun rycker vi upp de två problemen med rötterna med hjälp av **algebraiska datatyper (ADT)** och **parametrisk polymorfism**. Det låter som namnet på en tung universitetskurs, men om fem minuter kommer du att se att det är världens mest naturliga sätt att modellera data.

---

## 6.1. Produkttyper (Poster): Dina vanliga `struct`, men med superkrafter

När du vill gruppera flera uppgifter som hör till samma enhet (till exempel en server med dess namn, IP-adress och port) definierar du en **`type`** med dess fält:

```ridgun
type Server = host: String, port: Int, tls_aktiv: Bool
```

Bara genom att skriva den enda raden ger Ridgun dig **fyra saker** helt automatiskt:

### 1. Konstruktorn `Server`
```ridgun
min_nod => Server
min_nod =  Server "api.exempel.se" 443 True
```

### 2. En ren *getter*-funktion för varje fält (`host`, `port`, `tls_aktiv`)
Du behöver inte skriva `s.getHost()` eller något liknande; varje fältnamn är direkt en funktion som plockar ut det värdet:

```ridgun
anslutnings_url Server => String
anslutnings_url srv    =  "Anslut till " + (host srv) + " på port {port srv}"
```

### 3. Funktionell uppdatering av poster (`with falt: varde`)
Föreställ dig en konfigurationspost med 12 eller 15 fält (som flaggorna till ett `ls`-kommando eller en webbserver) där du bara vill ändra ett eller två fält utan att röra resten. I stället för att bygga om posten genom att skicka in alla 15 fält för hand använder du **`with`** och kolon **`:`** (exakt som i `type`-definitionen):

```ridgun
aktivera_dev_lage Server => Server
aktivera_dev_lage srv    =  srv with port: 8080, tls_aktiv: False
```

Det bästa av två världar:
- I din kod är det **100 % oföränderligt och säkert** (kompilatorn kontrollerar att `port` och `tls_aktiv` finns i `Server` och har rätt typ).
- Under huven återanvänder den inbyggda körbara filen minnet *in-place* (`Arc::try_unwrap`) utan att kopiera övriga fält om `srv` inte delas med någon annan.

### 4. Fullständig mönstermatchning om du vill öppna posten direkt
```ridgun
ar_saker_port Server              => Bool
ar_saker_port (Server _ 443 True) =  True
ar_saker_port _                   =  False
```

---

## 6.2. Summatyper (Varianter med `|`): Hur man pensionerar `null`, undantag och arv

Nu kommer det riktigt fina.
En vanlig post har `host` **OCH** `port` **OCH** `tls_aktiv`.
Men i verkliga livet behöver du ofta säga: *"Ett betalningssätt är **ANTINGEN** ett kort med dess nummer, **ELLER** en överföring med dess IBAN, **ELLER** kontanter (som inte bär på någon extra data)"*.

I objektorientering skulle du behöva skapa ett gränssnitt `Betalningssatt`, tre underklasser i tre olika filer, konstruktorer, `instanceof`... I Ridgun är det **en enda rad**:

```ridgun
type Betalningssatt = Kort String Int | Overforing String | Kontant
```

Och titta vad som händer när du bearbetar ett `Betalningssatt` i en funktion:

```ridgun
beskriv_betalning Betalningssatt    => String
beskriv_betalning (Kort num _)      =  "Betalning med kort som slutar på {num}"
beskriv_betalning (Overforing iban) =  "Överföring från konto {iban}"
beskriv_betalning Kontant           =  "Kontant betalning i kassan"
```

Varje variant (`Kort`, `Overforing`, `Kontant`) bär endast med sig de data som är meningsfulla för just den. Det är **omöjligt** att skapa en `Kontant`-betalning som av misstag har ett `iban` hängande på släp.

---

## 6.3. "Och hur stoppar jag in `[1, "tva"]` i en lista utan att använda `Any`?"

Låt oss återvända till tiotusenkronorsfrågan. Föreställ dig att du läser en CSV- eller JSON-fil där en cell kan vara ett heltal, en text eller helt tom.

Om du hade en typ `Any` skulle du stoppa in `[1, "tva"]` och förlora all hjälp från kompilatorn: från det ögonblicket skulle varje operation på listan vara som att gå med förbundna ögon.

I Ridgun (precis som i Haskell eller Rust) skapar du på två sekunder en summatyp som beskriver exakt vilka saker som kan bo i den listan:

```ridgun
type Cellvarde = Heltal Int | Text String | Tom

formatera_cell Cellvarde  => String
formatera_cell (Heltal n) =  "Tal: {n}"
formatera_cell (Text s)   =  "Text: {s}"
formatera_cell Tom        =  "(tom)"

min_rad => [Cellvarde]
min_rad =  [Heltal 1, Text "tva", Tom]
```

Ser du skillnaden?
- Med `Any` vet kompilatorn inte om det ligger heltal, strängar eller en USB-ansluten kaffebryggare i listan.
- Med `[Cellvarde]` kan du blanda tal och texter i samma lista, **men kompilatorn vet till 100 % att endast dessa tre möjligheter existerar** och tvingar dig att packa upp varje fall (`Heltal n`, `Text s`, `Tom`) innan du använder det. Total säkerhet utan att förlora en millimeter i flexibilitet.

---

## 6.4. `Option` och `Result`: När något kan saknas eller gå fel

Eftersom det varken finns `null` eller undantag som exploderar i luften (`throw new Exception()`) i Ridgun, har språket två universella summatyper inbyggda från start:

1. **`Option`**: antingen har du **`Some varde`**, eller så har du **`None`** (ingenting).
2. **`Result`**: antingen gick operationen bra (**`Ok varde`**), eller så misslyckades den av en konkret anledning (**`Err fel`**).

```ridgun
saker_division Int Int => Result
saker_division _   0   =  Err "Hallå där! Det går inte att dividera med noll"
saker_division a   b   =  Ok (a / b)

skriv_ut_res Result    => ()
skriv_ut_res (Ok n)    =  echo "Resultatet är {n}"
skriv_ut_res (Err msg) =  echo "Kontrollerat fel: {msg}"
```

Ingen kan ignorera ett fel av slarv eftersom själva typen `Result` tvingar dig att titta efter om det ligger ett `Ok` eller ett `Err` inuti.

---

## 6.5. Parametrisk polymorfism: Generiska funktioner med `A`, `B`, `T`...

Anta att du skriver en funktion som vänder på ett par `(x, y)` eller hämtar det första elementet i en lista. Spelar det verkligen någon roll om listan består av `Int`, `String` eller `Server`? Inte det minsta! Algoritmen är identisk.

I Ridgun fungerar **vilken enskild versal som helst (`A` till `Z`)** i en typsignatur automatiskt som en **polymorf jokertyp (typvariabel)**:

```ridgun
sakert_huvud [A]   A        => A
sakert_huvud []    standard =  standard
sakert_huvud (x:_) _        =  x

vand_par (A, B) => (B, A)
vand_par (x, y) =  (y, x)
```

Lägg märke till magin i `sakert_huvud [A] A => A`:
- Det är inte ett okontrollerat `Any`: det säger att **listans typ `[A]`, typen på värdet `standard` (`A`) och den returnerade typen (`A`) måste vara exakt samma**.
- Om du anropar `sakert_huvud [10, 20] 0` knyter kompilatorn ihop säcken (`A = Int`) och ger dig en `Int`.
- Om du anropar `sakert_huvud ["a", "b"] "ingen"` knyter den ihop säcken (`A = String`) och ger dig en `String`.
- Men om du försöker fuska och anropar `sakert_huvud [10, 20] "ingen"` — pang! Kompilatorn tvärbromsar dig eftersom det första argumentet säger att `A` är `Int` medan det andra säger att `A` är `String`.

---

## 6.6. Skapa dina egna operatorer (`op ::`): Från vektorer till skräddarsydda fraser

Varför skulle bara de inbyggda talen ha rätt att använda `+` eller `*`? Och varför nöja sig med de gamla vanliga operatorerna när du kan uppfinna den perfekta syntaxen för ditt problem?

Med **`op ::`** (eller direkt utan prefix om du använder operatormönster) kan du göra två konststycken:

### 1. Lära `+`, `-`, `*`, `/`, `%` att räkna med dina egna typer
```ridgun
type Komplext = real: Int, imag: Int

op :: Komplext + Komplext => Komplext
      a        + b        =  Komplext ((real a) + (real b)) ((imag a) + (imag b))
```

### 2. Skapa *Mixfix*-operatorer (som läses som naturliga meningar, inklusive `type` och `with`)
I en operatorsignatur är **ord med inledande versal (`Int`, `String`, `A`..`Z`) eller inom hakparenteser/parenteser (`[Int]`, `(A, B)`) platserna för argumenten**, och **orden med gemener är en del av operatorns fras** (även så vanliga ord som `type` eller `with`, som i Ridgun är kontextuella och aldrig låser dig):

```ridgun
op :: om Bool sa A annars A => A
      om True sa v annars _ =  v
      om False sa _ annars f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  meddelande = om (10 > 5) sa "Tio vinner!" annars "Omöjligt"
  echo meddelande
  echo (format "panel" type "bordered" with 80)
```

Du har precis tillverkat din egen polymorfa ternära operator och ett formaterings-DSL på **3 rader** i Ridgun.

---

## 6.7. Delade konstruktorer, nakna typvarianter, `expand type` och naturliga mellanslag i `fn ::`

Ridgun gör algebraiska datatyper och funktioner ännu mer naturliga och utbyggbara:

1. **Delade konstruktornamn mellan typer**: Olika `type`-deklarationer kan återanvända samma konstruktornamn (t.ex. `Error`, `Var`, `Lit`) med samma eller olika aritet — typkontrollanten avgör vilken typ som avses utifrån kolumnens signatur.
2. **Nakna typvarianter utan upprepning (`type Something = String | Int | MyStruct Float Int`)**: När en variant är en inbyggd typ (`String`, `Int`, `Float`/`Real`, `Bool`, `Char`) behöver du inte skriva `Int Int` eller `String String`. Du kan skicka in nakna värden (`"hej"`, `42`) eller explicita konstruktorer (`String "hej"`, `Int 42`), och matcha både litteraler (`"admin"`, `0`) och typade mönster (`(String s)`, `(Int n)`).
3. **Öppen typutvidgning (`expand type`) och automatisk sammanslagning av `fn ::`-klausuler**: Med `expand type` kan du lägga till nya varianter i en summatyp eller nya fält i en posttyp. Om du deklarerar `fn ::` igen för samma funktion slås de nya mönsterklausulerna ihop automatiskt **före** en eventuell `_`-reservklausul (utan att du behöver skriva `expand fn`).
4. **Naturliga mellanslag `" "` istället för `_` i `fn ::` och filnamn**: Precis som i `op ::` kan funktionsnamn i `fn ::`, anrop till inbyggda funktioner (`assert equals`, `str len`, `read file`) och `.rg`-filnamn (`test core language.rg`) skrivas med naturliga mellanslag:

```ridgun
type Something = String | Int | MyStruct Float Int

fn :: beskriv nagot Something           => String
      beskriv nagot "admin"             =  "special_admin"
      beskriv nagot 0                   =  "noll"
      beskriv nagot (String   s)        =  "text:{s}"
      beskriv nagot (Int      n)        =  "heltal:{n}"
      beskriv nagot (MyStruct kvot ant) =  "struktur:{kvot}:{ant}"
      beskriv nagot _                   =  "annat"

expand type Something = Bool

fn :: beskriv nagot Something => String
      beskriv nagot (Bool b)  =  "boolesk:{b}"
```

### 5. Egna generiska typer (`type Result T E`, `type Page T`) och modulnamnrymder (`import ... as`, `mod.Typ`)
Utöver polymorfa funktioner kan du deklarera **egna generiska summatyper och posttyper** med typparametrar (`A`..`Z`), samt organisera typer med samma namn i olika moduler utan namnkrockar (`module ::`, `import db as d`, `http.Config`, `d.Config`):

```ridgun
type Result T E = Ok T | Err E
type Page T     = items: [T], total: Int

fn :: packa upp ok (Result A String) A => A
      packa upp ok (Ok v)            _ =  v
      packa upp ok (Err _)           d =  d
```

I **Kapitel 07** ska vi sätta alla kärnor i din processor i arbete samtidigt utan att fälla en enda svettdroppe: **högre ordningens funktioner (`map`, `||map`, `filter`, `||filter`, `fold`), lexikala closures (`(x => expr)`), parallella `||`-grafer med `->` och samtidiga kanaler**.
