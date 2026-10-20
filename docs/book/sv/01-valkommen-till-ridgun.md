# Kapitel 01: Din första kontakt med Ridgun (Utan hjälm, utan måsvingar och utan semikolon)

Okej, i Kapitel 00 övertygade jag dig om att vi inte är galna som har skapat Ridgun. Nu tänker du säkert:

> *"Mycket fint snack om tabeller och 16 kärnor, men visa mig riktig kod. Hur lång tid tar det att skriva något som fungerar utan att behöva slåss med kompilatorn?"*

Då kör vi — rakt på sak!

---

## 1.1. "Hej, världen!", men med substans

I de flesta programmeringsböcker visar man ett trist `print("Hej världen")` och vänder blad. Vi ska gå direkt på att skriva en funktion med riktig logik så att du ser hur Ridgun andas från första minuten.

Skapa en fil som heter `hej.rg` och skriv det här:

```ridgun
halsning String => String
halsning ""     =  "Hej, mystiska resenär! (Du har inte sagt vad du heter)"
halsning "Root" =  "Men se där, Root! Var försiktig med vad du raderar i dag."
halsning namn   =  "Hej, {namn}! Välkommen till Ridgun."

main => ()
main =
  echo (halsning "Ada")
  echo (halsning "Root")
  echo (halsning "")
```

För att köra det direkt:

```bash
ridgunc run hej.rg
```

Och du kommer att se i din terminal:

```text
Hej, Ada! Välkommen till Ridgun.
Men se där, Root! Var försiktig med vad du raderar i dag.
Hej, mystiska resenär! (Du har inte sagt vad du heter)
```

Stanna upp ett ögonblick och titta på `halsning`-blocket ovan. Märker du vad som **INTE** finns där?
- **Det finns inget `function`, inget `def` och inget `pub fn`** (om du vill sätta `fn ::` framför signaturen går det bra, men det är valfritt).
- **Det finns inga parenteser `(String namn)` eller måsvingar `{ ... }`** som skräpar ner skärmen.
- **Det finns inget `if (namn == "") ... else if (namn == "Root") ... else ...`**.
- **Det finns inget `return`**.

---

## 1.2. Hur din hjärna läser en `.rg`-fil

Låt oss plocka isär de fyra raderna i `halsning`, för här finns redan 50 % av Ridguns filosofi:

```ridgun
halsning String => String
halsning ""     =  "Hej, mystiska resenär! (Du har inte sagt vad du heter)"
halsning "Root" =  "Men se där, Root! Var försiktig med vad du raderar i dag."
halsning namn   =  "Hej, {namn}! Välkommen till Ridgun."
```

1. **Den första raden är kontraktet (`halsning String => String`)**:
   Den säger: *"Jag heter `halsning`, jag tar emot en `String` och jag ger dig tillbaka (`=>`) en annan `String`"*. Punkt. Om någon försöker anropa mig och skicka in talet `42` kommer kompilatorn att knacka dem på axeln innan programmet ens körs.
2. **Raderna nedanför är fallen (uppifrån och ner)**:
   - Har du skickat in den tomma strängen `""`? Då returnerar jag den första meningen.
   - Har du skickat in exakt `"Root"`? Då returnerar jag den andra meningen.
   - Har du skickat in vad som helst annat? Då sparar jag det i variabeln `namn` och stoppar in det i texten med hjälp av `{namn}`.
3. **Och vad är `main => ()`?**:
   Eftersom `main` inte tar några argument sätter vi `=>` direkt efter namnet. Och den returnerar `()` (den tomma typen eller *Unit*, vänner emellan), eftersom dess enda uppgift är att skriva ut saker på skärmen med `echo`.

---

## 1.3. "Vänta... måste jag rada upp de där mellanslagen för hand som en medeltida skrivarmunk?"

Absolut inte! Om du var tvungen att trycka på mellanslagstangenten och räkna kolumner med ögonmått skulle du överge Ridgun efter tio minuter (och det med rätta).

Du skriver koden snabbt, med ett enda mellanslag mellan varje ord:

```ridgun
halsning String => String
halsning "" = "Hej, mystiska resenär!"
halsning namn = "Hej, {namn}!"
```

Och när du kör **`stable format`** (eller trycker `TAB` / sparar filen i Emacs med `ridgun-mode`) placerar den kanoniska formateraren varje parameter under sin typ och justerar alla `=` med millimeterprecision. Du skriver snabbt; maskinen formger tabellen.

---

## 1.4. Från snabbt skript till stridsduglig binär med ett enda kommando

När du kör `ridgunc run hej.rg` kompilerar och startar du programmet i farten. Men föreställ dig att du har blivit klar med ditt verktyg och vill ta med det till en produktionsserver eller dela det med en kollega som inte har Ridgun installerat.

Du kör:

```bash
ridgunc build hej.rg -o hej
```

Och så har du `./hej`: en **inbyggd ELF-körbar fil för Linux x86_64**, ren, utan död kod (*Tree-Shaking*), med länkoptimering över hela programmet (*LTO*) och helt oberoende av någon extern tolk.

---

## 1.5. Den ärliga fusklappen: Varifrån kommer varje idé i Ridgun?

Ridgun försöker inte uppfinna ett fyrkantigt hjul på nytt; det lånar skamlöst det bästa från fyra traditioner:

| Från vem | Vad Ridgun lånar | Vad det lämnar utanför (för din mentala hälsas skull) |
|---|---|---|
| **Haskell / ML** | Rena funktioner, mönstermatchning (*pattern matching*) per fall, algebraiska datatyper (`Option`, `Result`) och polymorfism (`A`..`Z`). | De abstrakta monaderna, de 40 `LANGUAGE`-pragmana och skräpsamlaren. |
| **J / APL** | Besattheten av kodens tabellform, inbyggda tensorer och sekvensmasker (`s["-+-"]`). | De hieroglyfiska symbolerna som är omöjliga att skriva på ett vanligt tangentbord. |
| **Rust / C** | Små inbyggda ELF-binärer, noll GC, minneskontroll (`with region`) och POSIX-systemanrop. | Den ständiga kampen med *borrow checker*, livstider `'a` och syntaktisk mångordighet. |
| **Erlang / Go** | Samtidighet via kanaler (`chan_send`, `chan_recv`) och lättviktiga uppgifter (`spawn`, `join`). | `nil`-pekare och delade muteringar av misstag. |

---

## 1.6. Och det viktigaste: Vad gör Ridgun som INGEN annan har?

Att erkänna klassikerna hör till god ton, men om Ridgun bara vore en "Greatest Hits-samling" från andra språk skulle du inte läsa den här boken.

Det finns **sju saker** som vi har konstruerat och integrerat i Ridgun som du inte kommer att hitta tillsammans — och många av dem inte ens var för sig — i något annat nutida språk:

### 1. Parallella `||`-block med `->` som är äkta parallella grafer, inte bara syntaktiskt socker
I andra funktionella språk ordnar ett block med lokala variabler bara uttryck som sedan evalueras i en enda tråd.
I Ridgun är **ett `||`-block med pilar `->` en riktad acyklisk graf (DAG) för parallell körning** utan att du ens behöver skriva extra nyckelord som `where`:
```ridgun
arsrapport Int => Int
arsrapport id  =  intakter - utgifter
  || berakna_forsaljning id -> intakter
  || berakna_kostnader id   -> utgifter
```
Du ritar flödespilarna (`->`). Kompilatorn analyserar vem som beror på vem, **verifierar statiskt att du inte har skapat någon oändlig cykel** och startar de oberoende grenarna parallellt utan att du skriver ett enda `async`, `await`, `Future` eller `Mutex`.

### 2. Koden som en tvådimensionell tabell där signaturen är kolumnrubriken
I alla andra språk lever typsignaturen sitt eget liv på en rad och funktionskroppen ligger nedanför som ett vanligt textstycke.
I Ridgun **är typsignaturen bokstavligen tabellens rubrikrad**, och varje fall nedanför justerar varje mönster rakt under sin typ och varje `=` under `=>`:
```ridgun
dividera Int Int => Option
dividera _   0   =  None
dividera a   b   =  Some (a / b)
```
Ingen annan behandlar signaturen och ekvationerna som en enda visuell matris som verifieras av kompilatorn och formges automatiskt av `stable format`.

### 3. Typade och justerade frasoperatorer (*N-ära Mixfix*) (`op ::`)
I de flesta språk får du antingen nöja dig med `+`, `-`, `*` eller på sin höjd definiera en kryptisk binär operator som `<|>` som ingen vet vad den betyder.
I Ridgun kan du skapa **operatorer som är läsbara fraser med så många typade platser du vill** (inklusive kontextuella ord som `type` eller `with`):
```ridgun
op :: Int begransad_mellan Int och Int => Int
      x   begransad_mellan min och max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
Och sedan skriver du i din kod `hastighet begransad_mellan 0 och 120`. Det läses som vanlig svenska (eller engelska), men är till 100 % typat och kompilerat till maskinkod.

### 4. Visuella masker över sekvenser (`s(+ _)` och `s["-+-"]`)
Har du någonsin behövt skriva en hel sallad av index `filter(\(i, x) -> i % 2 == 0)` bara för att behålla jämna element eller plocka ut ett rytmiskt mönster ur en lista?
I Ridgun skickar du direkt in en **visuell mask**:
- `data["-+-"]`: kastar det första (`-`), behåller det andra (`+`), kastar det tredje (`-`).
- `data["+-~"]`: symbolen `~` upprepar mönstret `+-` i en loop ända till slutet av listan (alla jämna index i ett svep).
Noll indexaritmetik, noll *off-by-one*-fel.

### 5. Polymorfism med "noll brus" (`A`..`Z`) styrd av din domän
I Rust, TypeScript eller Java måste du fylla raden med vinkelparenteser när en funktion är generisk: `fn byt_plats<A, B>(par: (A, B)) -> (B, A)`.
I Ridgun använder du helt enkelt en fristående versal:
```ridgun
byt_plats (A, B) => (B, A)
byt_plats (x, y) =  (y, x)
```
*"Men tänk om jag i mitt program vill ha en riktig typ som heter `type A`?"* — Inga problem: i Ridgun **är det dina `type`-deklarationer som bestämmer**. Om `type A` inte finns är `A` generisk; i samma ögonblick som du definierar `type A = ...` blir den din konkreta typ i hela modulen.

### 6. Noll konstiga konfigurationsfiler: `build.rg` är ren Ridgun
Glöm att behöva lära dig TOML för Cargo, JSON för npm, XML för Maven eller den arkaiska syntaxen i `Makefile` med osynliga tabulatorer. I Ridgun är receptet som bygger ditt projekt (`build.rg`) **bara ännu en `.rg`-fil**, med samma rena funktioner och samma mönstermatchning som resten av din kod.

### 7. Den "heliga treenigheten" som verkade omöjlig: Haskell-nivå + RMM-minne utan GC eller Lifetimes + Binärer på ~350 KB
Fram till i dag var du tvungen att välja:
- Om du ville ha ren funktionell uttrycksfullhet (Haskell, OCaml, Elixir) betalade du med en skräpsamlare och en tung körtidsmiljö.
- Om du ville ha pyttesmå systembinärer utan skräpsamlare (C, Rust, Zig) betalade du genom att hantera pekare eller brottas med *borrow checker* och skriva imperativ kod full av `let mut`.

Ridgun bryter det dilemmat genom att kombinera **Ridgun Memory Management (`RMM`: statisk `RMM1` och kaskadräknad `RMM2`)**, **lexikala regioner (`with region`)** som frigör hela arenor i $O(1)$, **svansrekursion som omvandlas till inbyggda loopar (`loop`)** samt **beskärning av anropsgrafen (*Tree-Shaking*)** från `main`. Resultatet: du skriver deklarativ kod på allra högsta nivå och får en fristående ELF-körbar fil på **~350 KB** som kan mäta sig öga mot öga med verktyg skrivna i C.

Nu ligger korten på bordet: låt oss gå vidare till **Kapitel 02** för att sätta **`ridgunc`** och **`stable`** i arbete.
