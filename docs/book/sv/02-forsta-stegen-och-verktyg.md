# Kapitel 02: Dina två bästa vänner: `ridgunc` och `stable` (Noll YAML-filer, jag lovar)

Det finns språk vars kompilator är underbar, men vars projektsystem verkar vara konstruerat av din värsta fiende: än är det en `Makefile` på 400 rader med osynliga tabulatorer, än en oändlig `pom.xml`, än en `webpack.config.js` som slutar fungera om du tittar för länge på den...

I Ridgun gav vi oss själva ett mycket enkelt löfte redan från första dagen:

> *"Det ska bara finnas två körbara program i hela ekosystemet (`ridgunc` och `stable`), båda ska vara skrivna i Ridgun självt, och projektets konfigurationsfil (`build.ridgun`) ska vara helt vanlig Ridgun-kod. Ingen JSON, ingen YAML, ingen TOML och inga konstiga påhitt."*

Låt oss se hur de används.

---

## 2.1. `ridgunc`: Prickskytten för enskilda filer

När du har en enskild `.ridgun`-fil framför dig och vill testa en snabb idé, analysera dess typer eller kompilera en körbar fil pratar du direkt med **`ridgunc`**.

Den har bara 3 kommandon som du verkligen behöver komma ihåg:

```bash
# 1. "Kompilerar det här eller har jag gjort bort mig med någon typ?"
ridgunc check experiment.ridgun

# 2. "Kör det nu!" (Kompilerar och kör i ett svep)
ridgunc run experiment.ridgun

# 3. "Gör en inbyggd ELF-binär färdig att ta med"
ridgunc build experiment.ridgun -o mitt_program
```

### Den dolda superkraften i `ridgunc check`
När du kör `ridgunc check` säger den inte bara *"0 fel"*. Den avslöjar också vilken strategi den statiska analysatorn har valt för var och en av dina funktioner:
- **`InlineSequential`**: *"Den här funktionen är liten och rak; jag kör den direkt i linje utan att lägga på någon schemaläggningskostnad"*.
- **`LazyStealableTask`**: *"Här finns rekursion eller en parallell graf `||`; jag förbereder den så att andra processorkärnor kan stjäla arbete om det behövs"*.

### Skalpellprecisionen i `ridgunc build` (Varför dina binärer inte väger 20 MB)
När du kör `ridgunc build` nöjer sig kompilatorn inte med att spotta ur sig all kod från de bibliotek du har importerat:
1. Den börjar i din `main`-funktion och vandrar genom anropsgrafen för att se **vilka funktioner du faktiskt använder**. Om du har importerat ett enormt bibliotek med 80 funktioner men bara anropar 2, kastas de andra 78 bort innan de ens når assemblern (*Tree-Shaking*).
2. Den letar upp alla svansrekursiva funktioner och omvandlar dem till inbyggda `loop`-snurror som förbrukar **0 byte stackminne**.
3. Den kör slutlänkningen med global optimering (*fat LTO*) och rensar bort DWARF-felsökningsskräp för att ge dig en kompakt och knivskarp binär (~350 KB).

---

## 2.2. `stable`: När ditt projekt växer och du vill ha ordning

En enskild fil är toppen för ett skript, men så fort du har flera moduler, delade bibliotek och tester behöver du en dirigent. Det är **`stable`**.

Mappstrukturen i ett Ridgun-projekt rymmer inga mysterier:

```text
mitt-superverktyg/
├── build.ridgun              # Projektmanifestet (det är Ridgun-kod!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Dina återanvändbara moduler (`import verktyg`)
│   │       └── app/
│   │           └── main.ridgun # Startpunkt (`main => ()`)
│   └── test/
│       └── ridgun/           # Dina testsviter (`test *.ridgun`)
│           └── test allt.ridgun
└── target/                   # Där de kompilerade binärerna dyker upp
```

---

## 2.3. `build.ridgun`: En konfigurationsfil som aldrig ljuger för dig

Varför vägrar vi att använda YAML eller TOML för att konfigurera ett Ridgun-projekt?
Därför att i YAML råkar du skriva två mellanslag fel i indraget och märker det inte förrän driftsättningen kraschar. Eftersom **`build.ridgun` är en Ridgun-fil** har den däremot statiska typer, kontrolleras med `stable check` och justeras automatiskt med `stable format`:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "mitt-superverktyg" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"

-- Valfritt: aktivera strikt läge för signaturer och namn (inaktiverat som standard)
strict mode => Bool
strict mode =  True
```

Om du stavar fel på ett fält varnar kompilatorn själv. Inga överraskningar.

### Strikt läge (`--strict` / `strict mode = True`)
Som standard är strikt läge **inaktiverat** i både `ridgunc` och nya projekt som skapas med `stable new` eller `stable init`, så att du kan bygga prototyper i full frihet. När du vill låsa den kanoniska stilen i ett projekt (som vi gör i Ridguns egen kompilator) kan du skicka `--strict` till `ridgunc` eller lägga till `strict mode = True` i din `build.ridgun`. Strikt läge kräver två elegansregler:
1. **Namn på `fn ::` och `op ::` med naturliga mellanslag, utan `_`**: deklarationer måste använda mellanslag (`fn :: berakna skatt`, aldrig `fn :: berakna_skatt`).
2. **Flertalsreturer åtskilda med mellanslag efter `=>`**: när en funktion eller operator returnerar flera värden skrivs dess utdatasignatur som `=> Int Int` eller `=> Tillstand Int` (aldrig `=> (Int, Int)` med parenteser eller kommatecken).

---

## 2.4. Din dagliga rutin med `stable` (De 4 fantastiska)

När du arbetar inne i ditt projekt kokar din vardag ner till fyra kommandon:

### 1. `stable format` — Slutet på alla kodstilsdiskussioner i teamet
```bash
stable format
```
Sätter din kollega tre mellanslag före `=>` medan du sätter ett? Det spelar ingen roll. Du kör `stable format` och på mindre än en sekund är **alla** `.ridgun`-filer i förrådet uppradade som en schweizisk tabell.

### 2. `stable check` — Den omedelbara radarn
```bash
stable check
```
Går igenom alla moduler i `src/main/ridgun/`, verifierar typer, konstruktorer, aritet och tensordimensioner, och ger dig utslaget modul för modul.

### 3. `stable test` — Sov gott om natten
```bash
stable test
```
Letar upp alla testsviter `src/test/ridgun/test *.ridgun`, kör dem och kontrollerar varje `assert equals` och `assert true`.

```ridgun
-- Exempel på src/test/ridgun/test matte.ridgun
import test

dubbel Int => Int
dubbel x   =  x * 2

main => ()
main =
  assert equals (dubbel 21) 42
  assert true ((dubbel 5) > 0)
```

### 4. `stable built` (och `stable clean`) — Ut i produktion
```bash
stable built
```
Kompilerar alla inbyggda mål i `target/`. Och om du någon dag vill radera `target/` och börja om från rent bord: `stable clean`.

---

## 2.5. Hur importerar jag en fil från en annan? (`import`)

Inga helvetiska relativa sökvägar av typen `../../../lib/grejer.ridgun`. Om du har en fil `src/main/ridgun/lib/strangar.ridgun` skriver du helt enkelt längst upp i vilken annan fil som helst:

```ridgun
import strangar
```

Och klart: alla funktioner och typer i `strangar.ridgun` är tillgängliga precis som om de låg i din egen fil. Men vad händer om modul `A` gör `import strangar`, modul `B` också gör `import strangar` och din `main.ridgun` importerar både `A` och `B`? Ta det lugnt: Ridguns laddare kommer ihåg vilka kanoniska filer den redan har läst och **inkluderar den bara en gång**.

Nu när du har full koll på verktygslådan går vi vidare till **Kapitel 03** för att bemästra funktioner, typer, block och knep med textsträngar.
