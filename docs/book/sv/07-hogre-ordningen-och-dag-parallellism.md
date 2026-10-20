# Kapitel 07: Högre ordningens funktioner och svettfri parallellism (Utan `Mutex`, utan `Deadlocks`)

I nästan alla programmeringsspråk finns det ett dramatiskt ögonblick i ett projekts liv: dagen då någon på ett möte säger:

> *"Det här går långsamt. Vi måste parallellisera det med trådar."*

Det blir knäpptyst i rummet. Alla vet vad som väntar härnäst: veckor av jakt på spöklika *race conditions* som bara inträffar på tisdagar vid fullmåne, ömsesidiga låsningar (*deadlocks*) och fel som inte går att återskapa.

När någon i Ridgun säger *"vi måste parallellisera det"*, räcker det med att sätta `||` framför dina listoperationer (**`||map`** och **`||filter`**) eller lägga dina beräkningar i ett parallellt `||`-block med pilar `->` och gå och ta en kaffe.

Varför? Därför att **när dina funktioner är rena och dina data är oföränderliga (*immutable*) som standard, kan två processorkärnor som arbetar samtidigt aldrig trampa på varandras slangar**.

Låt oss gå igenom det steg för steg.

---

## 7.1. Funktioner som tar emot funktioner: `map`, `||map`, `filter`, `||filter` och `fold`

I Ridgun är en funktion ett värde som alla andra. Du kan skicka in den som parameter precis som du skickar in talet `7`.

Språket har inbyggda samlingskombinatorer för att omvandla listor utan att skriva en enda manuell rekursion, både i sekventiellt läge (`map`, `filter`, `fold`) och i flerkärnigt parallellt läge med prefixet `||` (**`||map`**, **`||filter`**):

### 1. `map` (sekventiell) och `||map` (parallell över flera kärnor)
Anta att du har en funktion `tung Int => Int` och en lista med tal:

```ridgun
tung Int => Int
tung x   =  (x * x) + (x * 3)

main => ()
main =
  data = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Strikt sekventiell från vänster till höger:
  r1 = map tung data
  -- Parallell över flera kärnor med prefixet `||`:
  r2 = ||map tung data
  echo r1
  echo r2
```

- Med **`map`** tillämpar Ridgun funktionen element för element från vänster till höger i den aktuella tråden (perfekt för små listor eller funktioner med ordnade in-/utmatningseffekter).
- Med **`||map`** fördelar Ridguns körtidsmiljö elementen i `data` mellan arbetstrådarna i din processor och bygger upp slutlistan **i exakt samma ordning**, vilket garanterar att `||map f xs == map f xs`.

### 2. `filter` (sekventiell) och `||filter` (parallell): Behåll bara dem som uppfyller ett villkor
Du skickar in en funktion som returnerar `Bool` (ett *predikat*) och en lista:

```ridgun
ar_positiv Int => Bool
ar_positiv n   =  n > 0

main => ()
main =
  rena = filter ar_positiv [-5, 10, 0, -2, 42]
  rena_par = ||filter ar_positiv [-5, 10, 0, -2, 42]
  echo rena      -- Skriver ut [10, 42]
  echo rena_par  -- Skriver ut [10, 42]
```

### 3. `fold`: Reducera en hel lista till ett enda resultat
Du skickar in en kombinerande funktion med två argument `(Ackumulerat Element => Ackumulerat)`, startvärdet och listan:

```ridgun
ackumulera_produkt Int Int => Int
ackumulera_produkt acc x   =  acc * x

main => ()
main =
  echo (fold ackumulera_produkt 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### Hur skriver jag en egen funktion som tar emot en annan funktion?
Hur enkelt som helst: i typsignaturen sätter du den inbjudna funktionens signatur inom parentes `(Indata => Utdata)`:

```ridgun
kor_tva_ganger (A => A) A => A
kor_tva_ganger f        x =  f (f x)
```

---

## 7.2. Kronjuvelen: `||`-block med `->` som parallella grafer (DAG)

Det är här Ridgun förändrar ditt sätt att tänka.

När du i ett vanligt imperativt språk skriver tre rader efter varandra:
1. Först körs rad 1.
2. Sedan rad 2 (även om den inte har det minsta med rad 1 att göra).
3. Sedan rad 3.

Det är att tvinga datorn att arbeta med skygglappar. När du i Ridgun använder parallella streck **`||`** med pilar **`->`** (utan att behöva skriva något nyckelord som `where`), ger du inte sekventiella order: du ritar en **riktad acyklisk graf (DAG)** som anger vilken beräkning som matar vilken variabel:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_berakning => Int
super_berakning =  vanster_gren + hoger_gren
  || fib 10 -> vanster_gren
  || fact 6 -> hoger_gren
```

Läs det högt:
- *"Jag vill beräkna `vanster_gren + hoger_gren`, medan `fib 10` parallellt (`||`) går in i `vanster_gren` (`->`) och `fact 6` går in i `hoger_gren` (`->`)."*

### Vad `ridgunc` gör bakom kulisserna med dina `||`-rader:
1. Den tittar på pilarna `->` och bygger upp beroendeträdet (DAG).
2. **Den fångar cykler statiskt**: om du av misstag skriver `|| a + 1 -> b` och `|| b + 1 -> a`, säger kompilatorn genast ifrån: *"Stopp där! Här finns ett cirkulärt beroende"* och vägrar kompilera en oändlig låsning.
3. Den ser att `fib 10` och `fact 6` inte är beroende av varandra, så de får grönt ljus att köras parallellt innan de summeras i `vanster_gren + hoger_gren`.

Du kan till och med bygga en pipeline i flera våningar inuti samma `||`-block — antingen under uttrycket eller direkt efter `=` — och kompilatorn räknar själv ut vilka våningar som kan köras samtidigt och vilka som måste vänta:

```ridgun
kvartalsbalans Int => Int
kvartalsbalans bas =
  || bas * 100                        -> bruttoforsaljning
  || bas * 40                         -> fasta_kostnader
  || bruttoforsaljning - fasta_kostnader -> bruttovinst ||.
  bruttovinst * 80 / 100
```

Lägg märke till detaljen **`||.`** i slutet av den sista `||`-raden: precis som `|.` stänger ett nästlat vaktträd, stänger **`||.`** det parallella `||`-blocket när vanliga sekventiella satser följer nedanför. Här startar `bruttoforsaljning` och `fasta_kostnader` parallellt; när båda är klara beräknas `bruttovinst`, och slutligen returneras `bruttovinst * 80 / 100`. Allt utan ett enda `async`, `Future`, `Promise` eller `Mutex`.

---

## 7.3. Genvägen `||` utan namn: Parallella rör som returnerar en tupel

Men tänk om du bara vill starta två eller tre beräkningar parallellt och samla ihop dem i en tupel utan att ens behöva hitta på variabelnamn med `->`?

Då använder du `||` direkt:

```ridgun
parallellt_par Int => (Int, Int)
parallellt_par n   =
  || fib n
  || fact n
```

Rakt, visuellt och returnerar tupeln `(fib n, fact n)`.

---

## 7.4. När du vill hålla i ratten själv: `spawn`, `join` och CSP-kanaler

Den automatiska parallellismen i `where`-liknande DAG-block och `pmap`/`map` täcker 90 % av fallen. Men ibland programmerar du ett aktörssystem, en jobbkö eller en producent–konsument-pipeline och vill själv styra uppgifterna och meddelandena.

För det har du två rena verktyg:

### 1. Starta uppgifter med `spawn` och hämta in resultatet med `join`
```ridgun
bearbeta_parti Int => Int
bearbeta_parti id  =  id * 100

main => ()
main =
  uppgift1 = spawn bearbeta_parti 1
  uppgift2 = spawn bearbeta_parti 2
  -- Under tiden skulle du kunna göra andra saker här...
  res1 = join uppgift1
  res2 = join uppgift2
  echo "De avslutades med:" res1 "och" res2
```

### 2. Skicka meddelanden via begränsade kanaler (`new_bounded_channel`)
Precis som i Go eller Erlang skickar du oföränderliga värden genom ett säkert rör i stället för att dela minne mellan trådar:

- `new_bounded_channel kapacitet`: skapar en kanal med plats för `kapacitet` meddelanden.
- `chan_send varde kanal` (eller `send_through varde kanal`): lägger in ett meddelande i röret.
- `chan_recv kanal` (eller `receive_from kanal`): hämtar nästa meddelande ur röret.
- `chan_try_recv kanal`: tittar efter om det finns ett meddelande utan att bli stående och vänta; returnerar `Some varde` eller `None`.
- `receive_from_timeout kanal ticks`: väntar upp till en tidsgräns och returnerar `Ok varde` eller `Err Timeout`.

```ridgun
main => ()
main =
  ror = new_bounded_channel 4
  _ = chan_send "Uppgift A slutförd" ror
  _ = chan_send "Uppgift B slutförd" ror
  forsta = chan_recv ror
  andra = chan_recv ror
  echo forsta "|" andra
```

Och spänn nu fast säkerhetsbältet inför **Kapitel 08**, den stora finalen: **tensorer med kompileringstidsverifierade dimensioner, räckviddsvariabler (`context`/`shared`), deterministiska minnesregioner, direkt hårdvaruåtkomst via MMIO och UNIX/POSIX-systemprogrammering**.
