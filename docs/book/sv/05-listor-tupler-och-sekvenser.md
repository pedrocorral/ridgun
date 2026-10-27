# Kapitel 05: Listor, tupler och ninjatricket med sekvenser

Ett program som bara flyttar ett tal eller en text i taget gör inte mycket nytta. I verkliga livet hanterar du fillistor, rader från en databas, nätverkspaket eller koordinater.

För det ger Ridgun dig tre olika behållare, var och en utformad för en mycket specifik uppgift:
1. **Listor (`[T]`)**: *"Jag har många element av samma typ (eller inga alls) och vill gå igenom dem"*.
2. **Tupler (`(A, B)`)**: *"Jag vill returnera ett par eller en trio av olika saker tillsammans utan att skapa en ny typ"*.
3. **Sekvenser och masker (`s(_ + _)`, `(+ _ _ +)`)**: *"Jag vill filtrera eller stuva om argument i farten som om jag hade ett matematiskt durkslag"*.

Vi tar dem en i taget.

---

## 5.1. Listor (`[T]`): Vårt dagliga bröd

Om du i Ridgun sätter hakparenteser runt en typ har du en lista av den typen:
- `[Int]` är en lista med heltal: `[10, 20, 30]`.
- `[String]` är en lista med texter: `["apple", "paron"]`.
- `[]` är den tomma listan (jokertecknet som passar till varje `[T]`).

> *"Hallå, kan jag stoppa in ett tal och en text tillsammans i samma lista, typ `[1, "tva"]`?"*
> Som den står, **nej** (och tacka kompilatorn för att den hindrar dig, för på så sätt kommer en summering i produktion aldrig att explodera när den stöter på en oväntad text). I Kapitel 06 ska vi se hur man löser fallet `[1, "tva"]` med fullständig elegans med hjälp av en algebraisk datatyp (precis som i Haskell).

### Hur man delar upp en lista utan index `i`, `j`, `k`: `[]` och `(x:xs)`
I imperativa språk innebär det oftast `for (int i = 0; i < lista.size(); i++)` att gå igenom en lista, med den klassiska risken att räkna ett steg fel (*off-by-one*).

I Ridgun räknar du inte index; **du plockar isär listan från huvudet**:
- `[]`: matchar om listan är tom.
- `(x:xs)`: matchar om listan har minst ett element. Den lägger det första elementet i `x` (**huvudet**) och resten av listan i `xs` (**svansen**).

Titta så smidigt det är att summera en lista eller räkna hur många element den har:

```ridgun
summera_lista [Int]  => Int
summera_lista []     =  0
summera_lista (x:xs) =  x + (summera_lista xs)

rakna_element [A]    => Int
rakna_element []     =  0
rakna_element (_:xs) =  1 + (rakna_element xs)
```

Och en teknisk detalj som kommer att göra dig glad: i Ridgun **kopierar inte `(x:xs)` resten av listan i minnet** när svansen `xs` plockas ut. Internt är det en vy över samma vektor som bara flyttar fram startpekaren med `1` (omedelbart i $O(1)$).

### Du kan plocka fram flera element i ett svep
Mönstret `:` är otroligt användbart när du tolkar kommandon eller protokoll:

```ridgun
tolka_kommando [String]                 => String
tolka_kommando []                       =  "Du har inte skrivit något"
tolka_kommando ("hjalp":_)              =  "Visar hjälpen..."
tolka_kommando ("kopiera":kalla:mal:[]) =  "Kopierar från {kalla} till {mal}"
tolka_kommando (cmd:_)                  =  "Okänt kommando: {cmd}"
```

Titta på tredje raden: `("kopiera":kalla:mal:[])` kontrollerar i ett enda slag att listan har **exakt 3 element**, att det första är `"kopiera"`, och serverar det andra och tredje på silverfat i `kalla` och `mal`. Försök skriva det i C eller Java så får du se hur många rader med `args.length == 3 && args[0].equals("kopiera")` det blir.

### Slå ihop listor med dubbla kolon (`::`)
När du befinner dig till höger om `=` (i ett uttryck) och vill foga ihop två listor använder du **`::`**:

```ridgun
foga_listor [Int] [Int] => [Int]
foga_listor a     b     =  a :: b

lagg_till_sist [Int] Int => [Int]
lagg_till_sist xs    x   =  xs :: [x]
```

*(Snabb minnesregel: ett enkelt `:` i mönster plockar isär listan; dubbla `::` i uttryck fogar ihop två listor).*

Och om du verkligen vill hämta element nummer 5 direkt utan att stega igenom något? Använd hakparenteser direkt efter namnet: `min_lista[5]`.

---

## 5.2. Variadiska funktioner (`T...`): "Skicka in hur många du vill!"

Ibland vill du att den som anropar din funktion bekvämt ska kunna skriva `max_av 4 19 2 88 7`, utan att tvingas linda in talen i hakparenteser `[4, 19, 2, 88, 7]`.

Sätt tre punkter **`...`** efter den sista typen i din signatur, så får du inuti funktionen automatiskt in argumenten paketerade som en lista:

```ridgun
summera_flera Int... => Int
summera_flera tal    =  summera_lista tal

main => ()
main =
  echo (summera_flera 10 20 30)       -- Skriver ut 60
  echo (summera_flera 1 2 3 4 5 6 7)  -- Skriver ut 28
```

---

## 5.3. Tupler: När en funktion vill returnera mer än en sak

I många språk är det en plåga att returnera två saker från en funktion: antingen skapar du en fånig hjälpklass `ResultatMedPosition`, eller så skickar du med utdatapekare via referens.

I Ridgun returnerar du en **tupel** `(A, B)`:

```ridgun
kvot_och_rest Int Int => (Int, Int)
kvot_och_rest a   b   =  (a / b, a % b)
```

Du kan till och med spara in parenteserna på signaturraden om du tycker att det ser renare ut:
`kvot_och_rest Int Int => Int Int`.

### Hur man öppnar en tupel
Precis som du skapar den med `(a, b)` öppnar du den i argumenten till vilken funktion som helst med `(kvot, rest)`:

```ridgun
forklara_division (Int, Int)   => String
forklara_division (kvot, rest) =  "Det går {kvot} gånger och blir {rest} över"
```

### Stjärndetaljen: Automatisk uppackning mellan funktioner
Anta att du har `kvot_och_rest` (som returnerar en tupel med 2 heltal) och en annan funktion `summera_par Int Int => Int` (som förväntar sig 2 fristående heltal). I Ridgun behöver du inte packa upp tupeln för hand i en mellanliggande variabel; du kan koppla in den ena funktionen rakt i den andra:

```ridgun
summera_par Int Int => Int
summera_par x   y   =  x + y

main => ()
main =
  -- kvot_och_rest 17 5 returnerar (3, 2), och summera_par tar emot 3 och 2 direkt:
  echo (summera_par (kvot_och_rest 17 5))  -- Skriver ut 5
```

---

## 5.4. Ninjatricket: Sekvenser och positionsmasker (`s(_ + _)`, `(+ _ _ +)`)

Här kommer en av Ridguns mest originella juveler, ärvd rakt från vektorspråk som J och APL.

Föreställ dig att du tar emot en rad argument med sekvensmönstret **`(s)`** och bara vill behålla några och kasta andra utan att deklarera fem variabler med påhittade namn (`_a`, `b`, `_c`, `d`...).

Då lägger du på en **tupelmask med `+` (behåll) och `_` (kasta)** på `s`:

- **`s(_ + _)`**: av 3 element, kasta det första (`_`), behåll det andra (`+`) och kasta det tredje (`_`).
- **`s(+ _ +)`**: behåll det första och det tredje; returnera sekvensen med dessa två.
- **`s(_ _ +...)`**: kasta de två första (`_ _`) och tillämpa `+...` **på alla efterföljande element**, oavsett hur många de är.

Se hur det fungerar i praktiken:

```ridgun
den_i_mitten Int Int Int => Int
den_i_mitten (s)         =  s(_ + _)

kasta_tva_forsta Int... => [Int]
kasta_tva_forsta (s)    =  s(_ _ +...)

main => ()
main =
  echo (den_i_mitten 100 42 999)        -- Skriver ut 42
  echo (kasta_tva_forsta 1 2 10 20 30)  -- Skriver ut [10, 20, 30]
```

Och det bästa av allt: du kan skjuta in en positionsmask **`(+ _ _ +)`** **rakt in i en idiomatisk `->`-pipeline**! Om en funktion returnerar en tupel med flera värden och nästa funktion bara behöver två av dem, filtrerar du tupeln i farten och Ridgun packar upp de överlevande elementen direkt som separata argument till nästa steg:

```ridgun
-- tolka paket returnerar 4 värden: (Int, Int, [String String], String)
-- (+ _ _ +) behåller det 1:a (code) och det 4:e (msg), och skickar dem till kombinera kod:
tolka paket "v0.9.9" -> (+ _ _ +) -> kombinera kod -> sammanfattning
```

Och om du dessutom använder kommaoperatorn `,` utanför parenteser (`lista1 , lista2`), plattar Ridgun ut båda samlingarna till en enda sammanhängande sekvens.

I **Kapitel 06** ska vi ta steget som förvandlar en funktionell programmerare till en förstklassig arkitekt: **att skapa dina egna algebraiska datatyper (ADT), skriva polymorfa funktioner med `A`..`Z` och skräddarsy dina egna operatorer**.
