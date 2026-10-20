# Kapitel 04: Adjö till `if/else`, adjö till `while` (Mönstermatchning, vakter och TCO)

När du berättar för någon att det i Ridgun **varken finns nyckelorden `if`, `else`, `switch`, `for` eller `while`**, brukar de titta på dig som om du just sagt att du tänker bygga ett hus utan hammare och spik:

> *"Finns det inget `if` och inget `while`? Hur i hela friden fattar jag då ett beslut eller går igenom en miljon datapunkter?"*

Det visar sig att `if/else` och `while` är ganska grovhuggna verktyg som vi har ärvt från hur hoppinstruktioner (`GOTO`) fungerade på 50-talet. I Ridgun ersätter vi dem med tre pusselbitar som passar som handen i handsken:
1. **Mönstermatchning (*Pattern Matching*)** (när du väljer väg utifrån datans **form eller exakta värde**).
2. **Booleska vakter `|`** (när du väljer väg utifrån ett **villkor eller intervall**).
3. **Svansrekursion med TCO** (som kompilatorn under huven omvandlar till en blixtsnabb inbyggd `loop`-snurra).

Låt oss se dem i aktion.

---

## 4.1. Mönstermatchning: När argumentet redan ger dig svaret

I föregående kapitel fick vi redan en förhandstitt. I stället för att ta emot en generisk variabel `x` och öppna fem `if (x == ...)` inuti funktionen lägger du i Ridgun fallen direkt vid funktionens ingång:

```ridgun
http_kod Int => String
http_kod 200 =  "OK: Allt gick som på räls"
http_kod 301 =  "Permanent flyttad"
http_kod 404 =  "Hittades inte (har du tittat under soffan?)"
http_kod 500 =  "Det brinner i servern"
http_kod n   =  "Okänd kod: {n}"
```

Ridgun provar raderna **uppifrån och ner**:
- Om `404` kommer in hoppar den direkt till tredje raden.
- Om `418` kommer in stämmer ingen av de fyra första raderna, så den faller ner till den sista (`n`), som fångar upp vilket heltal som helst och ger det namnet `n` så att du kan skriva ut det.
- Och om du i det sista fallet inte ens bryr dig om vilket tal det var? Då sätter du ett understreck `_` (*jokertecken*) och glömmer det: `http_kod _ = "Annan kod"`.

---

## 4.2. Booleska vakter (`|`): Din skalpell för intervall, villkorsstyrda variabler och beslutsträd

*"Okej, mönstermatchning är häftigt när jag letar efter `200` eller `404`. Men vad gör jag om jag vill kontrollera om `betyg >= 5` eller om `alder > 18 and alder < 65`? Jag tänker ju inte skriva 47 rader med alla tal från 18 till 65!"*

Naturligtvis inte! Det är precis vad **vakter (`|`)** är till för.

När resultatet beror på en olikhet eller en logisk kombination öppnar du efter funktionens `=` (eller efter vilken lokal variabel som helst) en trappa av lodräta streck `|`:

```ridgun
bedom Int   => String
bedom betyg =
  | betyg < 0   = "Omöjligt betyg (minuspoäng?)"
  | betyg < 5   = "Underkänt"
  | betyg < 7   = "Godkänt"
  | betyg < 9   = "Väl godkänt"
  | betyg <= 10 = "Mycket väl godkänt"
  | otherwise   = "Du har sprängt skalan"
```

Titta noga:
- Likhetstecknet `=` i rubrikraden (`bedom betyg =`) justeras rakt under `=>` precis som i vilken annan funktion som helst.
- Därunder läses det uppifrån och ner precis som en pristabell: varje rad `| villkor = resultat` kontrolleras i tur och ordning. Så fort en ger `True` returneras det resultatet och allt är klart.
- På slutet sätter du **`| otherwise = ...`**, som bokstavligen betyder *"i alla andra fall"* (ditt skyddsnät så att ingen väg någonsin blir utan returvärde).

### Boolesk logik med tydliga gemener (`and`, `or`, `xor`, `not`)
Har du lagt märke till att många språk använder `|` för bitar, `||` för booleska värden, `!` för negation... och när du läser ett komplext villkor ser det ut som om en katt har promenerat över tangentbordet (`if (!a && (b || c))`)?

I Ridgun, där `|` redan är den heliga symbolen för vakter och algebraiska datatyper och `||` är parallellitetsoperatorn, **skrivs de booleska operatorerna med tydliga ord i gemener**:

- **`and`**: båda sakerna är uppfyllda (`alder >= 18 and har_korkort`).
- **`or`**: minst en är uppfylld (`dag == "lordag" or dag == "sondag"`).
- **`xor`**: antingen det ena eller det andra är uppfyllt, men inte båda samtidigt.
- **`not`**: vänder på det booleska värdet (`not (ar_tom text)`).

Titta så rent det klassiska problemet med skottår blir:

```ridgun
ar_skottar Int => Bool
ar_skottar a   =
  | (a % 400) == 0                  = True
  | (a % 4) == 0 and (a % 100) != 0 = True
  | otherwise                       = False
```

Noll kryptiska symboler. Någon som inte kan Ridgun kan läsa det och förstå det vid första anblicken.

### Villkorsstyrda lokala variabler (`x =` + `|`)
Eftersom varje `=` i Ridgun följer samma regel **kan du också använda `|` för att tilldela en lokal variabel** utan att behöva skapa en separat hjälpfunktion:

```ridgun
biljettpris Int Bool           => Int
biljettpris bas ar_storfamilj =
  rabatt =
    | ar_storfamilj = 20
    | bas > 100     = 10
    | otherwise     = 0
  bas - (bas * rabatt / 100)
```

### Nästlade beslutsträd och den kompakta avgränsaren `|.`
*"Men tänk om jag inuti en gren `| villkor =` eller `| otherwise =` vill öppna ett nytt underträd av vakter `|` på 3 eller 4 nivåers djup och sedan återvända till en högre nivå?"*

Du kan nästla `|` inuti `|` hur många nivåer du vill. Och när ett nästlat `|`-block avslutas men fler grenar på en föräldranivå (eller fler satser i blocket) följer nedanför, sätter du **`|.`** i slutet av dess sista rad (`| otherwise = varde |.`) för att utan minsta tvetydighet markera att underträdet stängs och att du återvänder till föregående nivå:

```ridgun
dirigera_anrop Int   Int  Bool     Bool     Int        Int        => Int
dirigera_anrop metod roll signerad ar_admin storlek_kb begransad =
  | metod == 0 =
    | storlek_kb == 0 = 204
    | otherwise       = 200 |.
  | metod == 1 =
    | not signerad = 401
    | otherwise =
      -- Nivå 2: signerat POST-anrop
      | begransad > 0 =
        -- Nivå 3: kontroll av rate-limit
        | ar_admin =
          -- Nivå 4: undantag för administratörer
          | storlek_kb > 10000 = 413
          | otherwise          = 202 |.
        | otherwise = 429 |.
      | storlek_kb > 1000 =
        -- Nivå 3: vi har återvänt från Nivå 4 tack vare `|.`
        | roll >= 2 and ar_admin = 201
        | otherwise              = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Lägg märke till hur rent det är:
- I ett enkelt träd med 1 nivå (eller i slutet av hela funktionen) **behöver du aldrig sätta ut `|.`** (det vore bara onödigt brus).
- Du skriver bara `|.` när du stänger en nästlad gren och en gren på en högre nivå fortsätter nedanför.

### Flerradiga block inuti en vakt (`| villkor =` + indraget block)
Precis som du efter `=` i en vanlig funktion kan öppna ett indraget block på flera rader, **kan du efter `=` i vilken vakt som helst (`| villkor =` eller `| otherwise =`) också göra en radbrytning och öppna ett sekventiellt block**:

```ridgun
justera_fonster Int Int   => Int
justera_fonster idx grans =
  | idx >= grans =
      tak = grans - 1
      skalad = tak * 2
      skalad + 10
  | otherwise =
      nasta = idx + 1
      nasta * 2
```

Varje gren i vakten har sitt eget rena lokala block, och dess sista rad är värdet som den grenen returnerar.

---

## 4.3. "Utan `while`? Kommer inte stacken att sprängas om jag går igenom en stor fil?"

Låt oss prata om elefanten i rummet.

Om du kommer från Python, Java eller JavaScript har du fått lära dig sedan barnsben att *"rekursion är elegant på svarta tavlan på universitetet, men i verkligheten svämmar stacken över (`StackOverflowError`) efter 1 000 varv; använd en `while`-loop"*.

Det stämmer i språk som **inte** optimerar svansanrop. Men i ett funktionellt systemspråk som Ridgun **ÄR svansrekursion en `while`-loop förklädd till en ren funktion**.

### Vad är skillnaden mellan vanlig rekursion och svansrekursion?
Titta på dessa två funktioner som räknar baklänges från `n` till `0` och summerar talen:

```ridgun
-- Version A: VANLIG rekursion (lämnar kvar väntande arbete till tillbakavägen)
summera_langsamt Int => Int
summera_langsamt 0   =  0
summera_langsamt n   =  n + (summera_langsamt (n - 1))

-- Version B: SVANSREKURSION (håller räkningen uppdaterad i `ackumulerat`)
summera_snabbt_loop Int Int         => Int
summera_snabbt_loop 0   ackumulerat =  ackumulerat
summera_snabbt_loop n   ackumulerat =  summera_snabbt_loop (n - 1) (ackumulerat + n)
```

- I **Version A** måste funktionen vänta på att `summera_langsamt (n - 1)` blir klar innan den kan beräkna `n + ...`. Det tvingar datorn att spara `n` på stacken i varje steg.
- I **Version B** är anropet till `summera_snabbt_loop` **det absolut sista som händer på raden**. Inget väntande arbete finns kvar efter det. Du skickar redan med den uppdaterade summan i `ackumulerat + n`.

### Trolltricket i `ridgunc` (TCO: *Tail-Call Optimization*)
När `ridgunc` kompilerar `summera_snabbt_loop` ser den att funktionen anropar sig själv i slutet av klausulen och tänker:

> *"Varför skulle jag skapa en ny stackram när den nuvarande inte längre behövs till någonting? Jag skriver över `n` med `n - 1`, skriver över `ackumulerat` med `ackumulerat + n` och hoppar tillbaka till början med en inbyggd `loop { ... continue; }`."*

Resultat:
1. Du kan anropa `summera_snabbt_loop 100_000_000 0` (hundra miljoner varv) och **det kommer att förbruka exakt 0 extra byte på stacken**.
2. Det går lika snabbt som en handskriven `while`-loop i Rust eller C, men utan att du har behövt deklarera en enda muterbar variabel i din Ridgun-kod.

---

## 4.4. Mästarmönstret som du kommer att använda i varje Ridgun-program

Varje gång du i ett annat språk skulle tänka *"jag gör en `while`-loop med ett index `i` och en ackumulator"*, skriver du i Ridgun ett funktionspar som detta (den rena huvudfunktionen och dess svansrekursiva `_loop`-hjälpare):

```ridgun
sok_tecken_loop String Int Int  Int  => Int
sok_tecken_loop text   pos slut sokt =
  | pos >= slut                    = -1
  | (str_char_at text pos) == sokt = pos
  | otherwise                      = sok_tecken_loop text (pos + 1) slut sokt

sok_tecken String Int  => Int
sok_tecken text   sokt =  sok_tecken_loop text 0 (str_len text) sokt
```

Titta på de tre vakterna i `sok_tecken_loop`:
1. Har jag nått slutet (`pos >= slut`)? Returnera `-1` (slut på loopen).
2. Hittade jag tecknet på `pos`? Returnera `pos` (slut på loopen).
3. Är det inte det här tecknet? Gå vidare till nästa (`pos + 1`) med ett svansanrop (som kompilatorn omvandlar till `continue;`).

Rent, omöjligt att få buggar från överskrivna globala variabler och snabbt som blixten.

I **Kapitel 05** ska vi ta oss an datasamlingar: **listor, tupler, funktioner som tar emot oändligt många argument (`...`) och sekvensmasker i J/APL-stil**.
