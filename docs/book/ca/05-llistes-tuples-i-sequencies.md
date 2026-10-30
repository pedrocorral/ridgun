# Capítol 05: Llistes, Tuples i el truc ninja de les Seqüències

Un programa que només mou un número o un text alhora serveix de ben poc. A la vida real maneges llistes de fitxers, files d'una base de dades, paquets de xarxa o coordenades.

Per a això, Ridgun et dóna tres envasos diferents, cadascun pensat per a una feina molt concreta:
1. **Llistes (`[T]`)**: *"Tinc molts elements del mateix tipus (o cap) i vull recórrer-los"*.
2. **Tuples (`(A, B)`)**: *"Vull retornar un parell o un trio de coses diferents juntes sense crear un tipus nou"*.
3. **Seqüències i màscares (`s(_ + _)`, `(+ _ _ +)`)**: *"Vull filtrar o reordenar arguments al vol com si tingués un colador matemàtic"*.

Anem una per una.

---

## 5.1. Llistes (`[T]`): El pa de cada dia

En Ridgun, si poses claudàtors al voltant d'un tipus, tens una llista d'aquell tipus:
- `[Int]` és una llista d'enters: `[10, 20, 30]`.
- `[String]` és una llista de textos: `["poma", "pera"]`.
- `[]` és la llista buida (el comodí que encaixa amb qualsevol `[T]`).

> *"Escolta, puc ficar un número i un text junts a la mateixa llista tipus `[1, "dos"]`?"*
> Tal qual, **no** (i dóna les gràcies al compilador per impedir-t'ho, perquè així mai no t'explotarà una suma en producció en trobar-se un text sorpresa). Al Capítol 06 veurem com resoldre el cas de `[1, "dos"]` amb elegància total fent servir un Tipus Algebraic (igual que fa Haskell).

### Com es trosseja una llista sense fer servir índexs `i`, `j`, `k`: `[]` i `(x:xs)`
En els llenguatges imperatius, recórrer una llista sol implicar `for (int i = 0; i < llista.size(); i++)`, amb el clàssic risc de passar-te per un (*off-by-one*).

En Ridgun no comptes índexs; **desmuntes la llista pel cap**:
- `[]`: encaixa si la llista és buida.
- `(x:xs)`: encaixa si la llista té almenys un element. Fica el primer element a `x` (el **cap**) i la resta de la llista a `xs` (la **cua**).

Mira quin goig fa sumar una llista o comptar quants elements té:

```ridgun
sumar llista [Int]  => Int
sumar llista []     =  0
sumar llista (x:xs) =  x + (sumar llista xs)

comptar elements [A]    => Int
comptar elements []     =  0
comptar elements (_:xs) =  1 + (comptar elements xs)
```

I un detall tècnic que t'alegrarà el dia: en Ridgun, treure la cua `xs` a `(x:xs)` **no copia la resta de la llista en memòria**. Internament és una vista sobre el mateix vector que només avança el punter d'inici en `1` ($O(1)$ instantani).

### Pots destapar diversos elements de cop
El patró `:` dóna moltíssim joc quan estàs analitzant ordres o protocols:

```ridgun
interpretar ordre [String]                => String
interpretar ordre []                      =  "No has escrit res"
interpretar ordre ("ajuda":_)             =  "Mostrant l'ajuda..."
interpretar ordre ("copiar":origen:dest:[]) = "Copiant de {origen} a {dest}"
interpretar ordre (cmd:_)                 =  "Ordre desconeguda: {cmd}"
```

Mira la tercera fila: `("copiar":origen:dest:[])` comprova d'un sol cop que la llista tingui **exactament 3 elements**, que el primer sigui `"copiar"`, i et deixa el segon i el tercer servits en safata a `origen` i `dest`. Intenta escriure això en C o Java i veuràs quantes línies d'`args.length == 3 && args[0].equals("copiar")` et surten.

### Unir llistes amb doble dos punts (`::`)
Quan ets al costat dret de l'`=` (en una expressió) i vols enganxar dues llistes, fas servir **`::`**:

```ridgun
enganxar llistes [Int] [Int] => [Int]
enganxar llistes a     b     =  a :: b

afegir darrere [Int] Int => [Int]
afegir darrere xs    x   =  xs :: [x]
```

*(Regla mnemotècnica ràpida: un sol `:` als patrons desmunta la llista; dos `::` a les expressions enganxen dues llistes).*

I si de debò vols treure l'element número 5 directament sense recórrer res? Fes servir claudàtors enganxats al nom: `la_meva_llista[5]`.

---

## 5.2. Funcions variàdiques (`T...`): "Passa'm tots els que vulguis!"

De vegades vols que qui cridi la teva funció pugui escriure `maxim de 4 19 2 88 7` còmodament, sense obligar-lo a envoltar els números entre claudàtors `[4, 19, 2, 88, 7]`.

Posa tres punts **`...`** darrere de l'últim tipus de la teva signatura, i dins de la teva funció ho rebràs automàticament empaquetat com una llista:

```ridgun
sumar diversos Int... => Int
sumar diversos nums   =  sumar llista nums

main => ()
main =
  echo (sumar diversos 10 20 30)      -- Imprimeix 60
  echo (sumar diversos 1 2 3 4 5 6 7) -- Imprimeix 28
```

---

## 5.3. Tuples: Quan una funció vol retornar més d'una cosa

En molts llenguatges retornar dues coses des d'una funció és un maldecap: o crees una classe auxiliar ximple `ResultatAmbPosicio`, o passes punters de sortida per referència.

En Ridgun retornes una **tupla** `(A, B)`:

```ridgun
dividir i residu Int Int => (Int, Int)
dividir i residu a   b   =  (a / b, a % b)
```

Fins i tot et pots estalviar els parèntesis a la línia de la signatura si et resulta més net:
`dividir i residu Int Int => Int Int`.

### Com obrir una tupla
Igual que la crees amb `(a, b)`, l'obres als arguments de qualsevol funció amb `(quocient, residu)`:

```ridgun
explicar divisio (Int, Int)         => String
explicar divisio (quocient, residu) =  "Hi cap a {quocient} i en sobren {residu}"
```

### El detall estrella: Desempaquetament automàtic entre funcions
Suposa que tens `dividir i residu` (que retorna una tupla de 2 enters) i una altra funció `sumar parell Int Int => Int` (que espera 2 enters solts). En Ridgun no has d'obrir la tupla a mà en una variable intermèdia; pots endollar una funció dins de l'altra directament:

```ridgun
sumar parell Int Int => Int
sumar parell x   y   =  x + y

main => ()
main =
  -- dividir i residu 17 5 retorna (3, 2), i sumar parell rep 3 i 2 directament:
  echo (sumar parell (dividir i residu 17 5))  -- Imprimeix 5
```

---

## 5.4. El truc ninja: Seqüències i Màscares Posicionals (`s(_ + _)`, `(+ _ _ +)`)

Aquí ve una de les joies més originals de Ridgun, heretada directament dels llenguatges vectorials com J i APL.

Imagina que reps una tirallonga d'arguments amb el patró de seqüència **`(s)`** i vols quedar-te només amb alguns i descartar-ne d'altres sense declarar cinc variables amb noms inventats (`_a`, `b`, `_c`, `d`...).

Li apliques a `s` una **màscara de tupla amb `+` (queda-te'l) i `_` (descarta'l)**:

- **`s(_ + _)`**: de 3 elements, descarta el primer (`_`), queda't amb el segon (`+`) i descarta el tercer (`_`).
- **`s(+ _ +)`**: queda't amb el primer i el tercer; retorna la seqüència amb aquests dos.
- **`s(_ _ +...)`**: descarta els dos primers (`_ _`) i aplica `+...` **a tots els altres que vinguin darrere**, siguin quants siguin.

Mira-ho funcionant:

```ridgun
el del mig Int Int Int => Int
el del mig (s)         =  s(_ + _)

descartar dos primers Int... => [Int]
descartar dos primers (s)    =  s(_ _ +...)

main => ()
main =
  echo (el del mig 100 42 999)             -- Imprimeix 42
  echo (descartar dos primers 1 2 10 20 30) -- Imprimeix [10, 20, 30]
```

I el millor de tot: pots intercalar una màscara posicional **`(+ _ _ +)`** **directament al mig d'una canonada `->`**! Si una funció retorna una tupla de diversos valors i la funció següent només en necessita dos, filtres la tupla al vol i Ridgun desempaquetarà els elements supervivents com a arguments separats de l'etapa següent:

```ridgun
-- parsejar paquet retorna 4 valors: (Int, Int, [String String], String)
-- (+ _ _ +) es queda amb el 1r (code) i el 4t (msg), i els passa a combinar codi:
parsejar paquet "v0.9.9" -> (+ _ _ +) -> combinar codi -> resum
```

A més, si fas servir l'operador coma `,` fora de parèntesis (`llista1 , llista2`), Ridgun aplana totes dues col·leccions en una única seqüència contínua.

Al **Capítol 06** farem el pas que converteix un programador funcional en un arquitecte de primera: **crear els teus propis Tipus de Dades Algebraics (ADTs), escriure funcions polimòrfiques amb `A`..`Z` i fabricar els teus propis operadors a mida**.
