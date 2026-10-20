# Kapitel 03: Funktioner, typsignaturer och konsten att skriva kod som en tabell

Det finns en fråga som varje programmerare ställer sig första gången de ser funktionell kod:

> *"Om det inte finns några klasser här, inga objekt och inga variabler som ändrar värde... var stoppar jag då in min logik?"*

I **funktioner**. Men inte i sådana där funktioner på 200 rader fulla av booleska flaggor som vi alla har lidit av någon gång, utan i små, raka funktioner som är så lätta att läsa att de ser ut som en tabell på en whiteboard.

Låt oss se hur de byggs upp.

---

## 3.1. Två sätt att presentera en funktion (Du väljer kostymen)

I Ridgun börjar varje funktion med sin **typsignatur** (vad som går in och vad som kommer ut efter `=>`) och därunder följer dess **implementeringsklausuler** (med `=`).

Du kan skriva rubrikraden på två sätt:

### Alternativ A: Rakt på sak (utan prefix)
```ridgun
tillampa_rabatt Int  Int     => Int
tillampa_rabatt pris procent =  pris - (pris * procent / 100)
```

### Alternativ B: Med uttrycklig etikett (`fn ::`)
```ridgun
fn :: tillampa_rabatt Int  Int     => Int
      tillampa_rabatt pris procent =  pris - (pris * procent / 100)
```

*"Hallå där, varför finns båda två?"*
Därför att smaken är som baken:
- Vissa föredrar att funktioner börjar ända ute i vänstermarginalen utan att behöva skriva `fn ::` varje gång (pilen `=>` ropar trots allt redan ut över hela rummet att den raden är en typsignatur).
- Andra föredrar att ha en vänsterkolumn vigd åt etiketterna (`fn ::`, `op ::`, `type`, `import`) för att snabbt kunna överblicka filen visuellt.

Kompilatorn och `stable format` förstår båda två till fullo.

---

## 3.2. Kolumnernas magi: varför dina ögon får vila

Titta på den här funktionen som beräknar fraktkostnaden beroende på land och om leveransen är brådskande:

```ridgun
fraktkostnad String Bool  Int  => Int
fraktkostnad "SE"   False _    =  50
fraktkostnad "SE"   True  _    =  120
fraktkostnad _      False vikt =  100 + (vikt * 20)
fraktkostnad _      True  vikt =  250 + (vikt * 40)
```

Gör testet: täck för den högra halvan av skärmen och titta bara på de tre indatakolumnerna:
- Första kolumnen (`String`): `"SE"`, `"SE"`, `_`, `_`.
- Andra kolumnen (`Bool`): `False`, `True`, `False`, `True`.
- Tredje kolumnen (`Int`): `_`, `_`, `vikt`, `vikt`.

Ser du någon logisk lucka? Ingen alls: alla 4 möjliga kombinationer ligger mitt framför näsan på dig, vertikalt uppradade under `String`, `Bool` och `Int`. I ett traditionellt `if / else`-block skulle du behöva läsa 18 rader för att vara säker på att du inte har glömt något enskilt fall.

---

## 3.3. Grundtyperna och en present så att du slipper räkna nollor (`_KB`, `_MB`, `_GB`)

De skalära typerna i Ridgun är raka och utan överraskningar:

| Typ | Vad det egentligen är | Exempel |
|---|---|---|
| `Int` | 64-bitars heltal med tecken (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `Real` | Decimaltal med dubbel precision (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Oföränderlig textsträng | `"Hej"`, `'ra\sokvag'` |
| `Char` | Teckenkod | Returneras av `str_char_at` |
| `Bool` | Klassisk boolesk typ | `True`, `False` |
| `()` | Tom (*Unit*, när du bara skriver ut eller gör I/O) | `()` |

### Trött på att skriva `65536` eller `1048576` och hålla tummarna för att du inte har tappat en siffra?
I Ridgun godtar numeriska literaler direkt suffixen **`_KB`**, **`_MB`** och **`_GB`**, utöver understreck `_` för att skilja siffergrupper åt:

```ridgun
buffertstorlek => Int
buffertstorlek =  64_KB      -- Kompilatorn översätter det till 65536

filgrans => Int
filgrans =  16_MB            -- Kompilatorn översätter det till 16777216

oktettmask => Int
oktettmask =  0xFF_00        -- Rent och läsbart hexadecimalt tal
```

---

## 3.4. Dubbla citattecken (`"..."`) kontra enkla citattecken (`'...'`)

I många språk gör enkla och dubbla citattecken exakt samma sak (ett slöseri). I Ridgun har vart och ett av dem ett glasklart uppdrag:

### 1. Dubbla citattecken (`"..."`): Smarta och interpolerade
De tolkar kontrollsekvenser (`\n`, `\t`, `\"`, `\\`) och **evaluerar varje variabel eller uttryck som du sätter inom måsvingar `{...}`**:

```ridgun
ordersammanfattning String Int   Int  => String
ordersammanfattning vara   antal pris =
  "Du har beställt {antal}x {vara}. Totalt att betala: {antal * pris} kronor."
```

*(Tips: om du behöver skriva en bokstavlig måsvinge inuti dubbla citattecken — till exempel när du genererar ett skalskript `"$\{VAR:-default\}"` eller JSON — kan du föregå den med omvänt snedstreck `\{` och `\}` eller dubblera den `{{` och `}}`).*

### 2. Enkla citattecken (`'...'`): Råa och bokstavliga (*Raw Strings*)
Det du skriver inom enkla citattecken kommer ut **exakt som det står**, utan att röra vare sig omvända snedstreck `\` eller måsvingar `{}`. Perfekt när du genererar kod i ett annat språk, skriver skalkommandon eller arbetar med sökvägar fulla av snedstreck:

```ridgun
sed_kommando => String
sed_kommando =  's/\([0-9]+\)/[\1]/g'
```

### Din verktygslåda för strängar (`String`)
Att slå ihop strängar är så enkelt som att addera dem med `+`: `"Hej, " + namn`. Och när du behöver utföra finlir på en text har du dessa inbyggda funktioner redo utan att behöva importera något:

- `str_len s` $\rightarrow$ längden på `s`.
- `str_char_at s i` $\rightarrow$ numerisk kod (`Int`) för tecknet på position `i` (`-1` om du hamnar utanför).
- `str_slice s start slut` $\rightarrow$ klipper ut från `start` till `slut` (exklusive `slut`).
- `char_from_code c` $\rightarrow$ omvandlar en numerisk kod (`Int`, t.ex. `10` för `\n` eller `34` för `"`) till en `String` med 1 tecken.
- `str_contains s nal` och `str_starts_with s prefix` $\rightarrow$ returnerar `True` eller `False`.
- `int_to_str n` och `str_to_int s` $\rightarrow$ omvandlar från tal till text och tvärtom (`str_to_int` förstår till och med `"0xFF"`!).

---

## 3.5. Flerradiga block, den universella regeln för `=` och `mut`-variabler

När en funktion inte får plats på en enda rad gör du en radbrytning efter `=` och drar in blocket.

Titta på hur ett block läses steg för steg:

```ridgun
berakna_faktura Int Int      => Int
berakna_faktura bas moms_pct =
  skatt = bas * moms_pct / 100
  expeditionsavgift = 50
  echo "Specifikation -> Bas:" bas "Skatt:" skatt
  bas + skatt + expeditionsavgift
```

Fyra gyllene regler som gör blocken i Ridgun rena och enhetliga:
1. **Oföränderligt (*immutable*) som standard utan `let` eller `const`**: du skriver `skatt = ...` och har direkt din lokala oföränderliga konstant. Om du av misstag försöker skriva över `skatt = 99` längre ner i samma block bromsar kompilatorn dig tvärt.
2. **Uttryckliga föränderliga variabler med `mut`**: när du verkligen vill uppdatera en lokal ackumulator steg för steg inuti en funktion deklarerar du den med **`mut`** och tilldelar den sedan fritt nya värden med `=`:
   ```ridgun
   tillampa_tillagg Int  => Int
   tillampa_tillagg pris =
     mut total = pris
     total = total + 10
     total = total * 2
     total
   ```
   *(Och om `total` håller en lista eller struktur i minnet lägger Ridguns **`RMM2`**-policy till `+1` på det nya värdet innan den drar av `-1` från det gamla, och frigör det omedelbart om ingen annan använder det).*
3. **Den universella regeln för `=`**: efter **vilket `=` som helst** (i en funktion, i en operator, i en lokal variabel `x =` eller i en villkorsgren) kan du alltid placera vilken som helst av Ridguns tre blockformer:
   - **`(ingenting)`**: indragna sekventiella rader (som ovan).
   - **`|`**: ett träd av villkorsvakter.
   - **`||`**: en graf av parallella beräkningar med `->`.
4. **Det sista uttrycket är alltid resultatet**: `bas + skatt + expeditionsavgift` är vad `berakna_faktura` returnerar. Utan `return`.

I **Kapitel 04** ska vi se hur man fattar komplexa beslut — inklusive beslutsträd i flera nivåer med `|.` — utan att någonsin skriva ett `if/else` eller en `while`-loop: välkommen till världen av **booleska vakter** och **svansrekursion utan extra kostnad**.
