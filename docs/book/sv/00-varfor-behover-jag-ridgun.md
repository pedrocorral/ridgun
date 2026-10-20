# Kapitel 00: Varför behöver jag Ridgun? Jaså? Det visste jag inte... Berätta mer!

Låt oss vara ärliga: när någon säger *"vi har skapat ett nytt programmeringsspråk"* är din första naturliga — och mycket sunda — reaktion att höja på ögonbrynet och tänka:

> *"Ännu ett? Men jag har ju redan Python när det ska gå fort, Rust eller C när jag behöver prestanda, och Bash för att klistra ihop saker i terminalen. Varför i hela friden skulle jag behöva lära mig Ridgun?"*

Det är en utmärkt fråga. Och det korta svaret är: **därför att du har vant dig vid att lida av tre dagliga plågor i tron att de var oundvikliga**.

Låt oss sätta namn på dem.

---

## Plåga nr 1: "Tvåvärldssyndromet" (Prototypa i ett språk, skriva om i ett annat)

Du har säkert varit med om den här filmen:

1. Du påbörjar ett verktyg eller en beräkningsmotor i **Python**, **JavaScript** eller **Ruby** eftersom du vill tänka på problemet, inte på pekare eller kompilatorn.
2. Koden blir kort och vacker... men när du matar den med en fil på 500 MB eller försöker utnyttja alla 16 kärnor i din dator kryper den fram. Och om du vill distribuera ditt program till en ren server måste du paketera en halv gigabyte med virtuell miljö, tolk och dynamiska bibliotek.
3. Uppgiven bestämmer du dig för att skriva om det i **C**, **C++** eller **Rust**. Nu flyger det fram och tar bara några hundra kilobyte, men din kod på 40 rader har förvandlats till 300 rader fulla av `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, måsvingar `{}` och semikolon `;`.

**Vad förändras med Ridgun?**
I Ridgun skriver du kod som är **kortare och renare än i Python**, men när du kör `ridgunc build` får du **en enda inbyggd ELF-binär på ~350 KB** utan tolk, utan extern virtuell maskin och utan skräpsamlare (*Garbage Collector*). Det finns ingen fas där man säger *"vi skriver om det i det snabba språket senare"*: den rena koden där du formulerar problemet **är redan** produktionsbinären.

---

## Plåga nr 2: "Att läsa andras kod (eller din egen från för 6 månader sedan) är som att leka detektiv"

Titta på hur vi skriver villkorslogik i nästan alla vanliga språk:

```text
if (status == AKTIV && (roll == ADMIN || (roll == REDAKTOR && harBehorighet))) {
    if (kvot > 0) {
        return bearbeta(anvandare);
    } else {
        return neka("Ingen kvot");
    }
} else {
    return neka("Obehörig");
}
```

Våra ögon har inte utvecklats för att para ihop nästlade måsvingar eller nysta upp trappstegsformade `if / else`-träd. När ingenjörer, matematiker eller fysiker vill förstå komplexa regler utan att göra fel skriver de inte stycken av `if / else`: **de ritar en tabell**.

I Ridgun **är koden den tabellen**:

```ridgun
auktorisera String  String     Bool  Int  => String
auktorisera "aktiv" "admin"    _     kvot =
  | kvot > 0  = "Bearbetar begäran"
  | otherwise = "Nekad: ingen kvot"
auktorisera "aktiv" "redaktor" True  kvot =
  | kvot > 0  = "Bearbetar begäran"
  | otherwise = "Nekad: ingen kvot"
auktorisera _       _          _     _    =  "Nekad: obehörig"
```

Titta på kolumnerna:
- Kolumn 1: statusen (`"aktiv"` eller `_`).
- Kolumn 2: rollen (`"admin"`, `"redaktor"` eller `_`).
- Kolumn 3: om behörighet finns (`True` eller `_`).
- Kolumn 4: `kvot`.

Du behöver inte köra programmet mentalt rad för rad för att veta vad som händer när en `"redaktor"` med behörigheten `False` kommer in: blicken glider vertikalt nedför tabellen och du ser det på en halv sekund.

---

## Plåga nr 3: "Min dator har 16 kärnor, men mitt program använder bara 1 (för att jag får panik av att röra trådar)"

I dag har till och med den enklaste telefonen 8 kärnor, och varje server eller arbetsdator har mellan 12 och 32. Ändå körs 95 % av alla vardagliga program fortfarande i en enda sekventiell tråd.

Varför? Därför att i imperativa språk innebär parallellisering att öppna Pandoras ask:
- Tänk om två trådar ändrar samma uppslagsverk samtidigt? (*Data race*).
- Tänk om jag låser `Mutex` A och sedan B i en tråd, och B och sedan A i en annan? (*Deadlock*).
- Tänk om jag förorenar hela min kodbas med `async` och `await` uppifrån och ner?

I Ridgun **är varje funktion ren och all data oföränderlig (*immutable*) som standard**. Det får en magisk konsekvens: **två uttryck som inte är beroende av varandra kan aldrig någonsin störa varandra**.

Därför behöver du inte hantera trådar i Ridgun för att utnyttja din processor. Du deklarerar bara **vad som beror på vad** med parallella streck `||` och pilar `->`:

```ridgun
manadsrapport Data => Rapport
manadsrapport d    =  kombinera nat_matt disk_matt cpu_matt
  || analysera_nat d  -> nat_matt
  || analysera_disk d -> disk_matt
  || analysera_cpu d  -> cpu_matt
```

Du har bara skrivit tre rena rader som anger varifrån varje datamängd kommer. Kompilatorn ser att de tre grenarna är oberoende och vet att den kan starta dem parallellt utan minsta risk för vare sig *data race* eller *deadlock*.

---

## Plåga nr 4: "Skräpsamlaren bestämmer sig för att pausa hela världen i exakt fel ögonblick"

Klassiska funktionella språk (Haskell, OCaml, Erlang, Clojure) är underbara för att resonera kring kod, men nästan alla är beroende av en **skräpsamlare (*Garbage Collector*)** vid körning. Det utesluter dem när du behöver:
- Förutsägbara svarstider på mikrosekundnivå.
- Exakt kontroll över hur mycket RAM-minne en operation får förbruka innan den avbryts snyggt.
- Skriva operativsystemverktyg (`ls`, `find`, `sh`, `doas`, `make`) eller arbeta direkt mot hårdvaruregister (`MMIO`).

Ridgun ger dig **hela elegansen från den rent funktionella världen, men med Ridguns minneshantering (`RMM`: statisk `RMM1` och kaskadräknad `RMM2`) plus lexikala regioner med exakt kvot (`with region`)**:

```ridgun
tolka_paket String => Result
tolka_paket radata =
  with region 16_KB do
    avkoda_ram radata
```

Varje tillfällig struktur frigörs deterministiskt av kompilatorn (`RMM1` / `RMM2`) i samma ögonblick som den slutar användas, och om en angripare skickar ett skadligt paket utformat för att spränga minnet klipps regionen omedelbart när den passerar byte 16 384, frigör sin arena i $O(1)$ och returnerar `Err OutOfMemory`. Inga kraschade processer, inga GC-pauser och inga minnesläckor.

---

## Sammanfattningsvis: När glänser Ridgun?

Ridgun är skapat för dig om du någonsin har velat:

1. **Skriva systemverktyg, kompilatorer, parsrar eller CLI-verktyg** som startar på mikrosekunder, väger några hundra KB och inte kan krascha på grund av null-pekare eller dolda sidoeffekter.
2. **Programmera algoritmer, datapipelines eller tensoralgebra** där kompilatorn kontrollerar ända ner till matrisdimensionerna åt dig (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) innan något ens körs.
3. **Njuta av att läsa din egen kod**: låta varje `.rg`-fil se ut som en sida ur en välformgiven bok tack vare den automatiska tabellformateraren (`stable format`).

Har vi väckt din nyfikenhet? Gå vidare till **Kapitel 01** så skriver vi vårt första program på under två minuter.
