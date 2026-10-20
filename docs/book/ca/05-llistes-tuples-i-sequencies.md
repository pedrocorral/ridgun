# Capítol 05: Llistes, Tuples i el truc ninja de les Seqüències

Un programa que només mou un número o un text alhora serveix de ben poc. A la vida real maneges llistes de fitxers, files d'una base de dades, paquets de xarxa o coordenades.

Per a això, Ridgun et dóna tres envasos diferents, cadascun pensat per a una feina molt concreta:
1. **Llistes (`[T]`)**: *"Tinc molts elements del mateix tipus (o cap) i vull recórrer-los"*.
2. **Tuples (`(A, B)`)**: *"Vull retornar un parell o un trio de coses diferents juntes sense crear un tipus nou"*.
3. **Seqüències i màscares (`s["-+-"]`)**: *"Vull filtrar o reordenar arguments al vol com si tingués un colador matemàtic"*.

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
sumar_llista [Int]  => Int
sumar_llista []     =  0
sumar_llista (x:xs) =  x + (sumar_llista xs)

comptar_elements [A]    => Int
comptar_elements []     =  0
comptar_elements (_:xs) =  1 + (comptar_elements xs)
```

I un detall tècnic que t'alegrarà el dia: en Ridgun, treure la cua `xs` a `(x:xs)` **no copia la resta de la llista en memòria**. Internament és una vista sobre el mateix vector que només avança el punter d'inici en `1` ($O(1)$ instantani).

### Pots destapar diversos elements de cop
El patró `:` dóna moltíssim joc quan estàs analitzant ordres o protocols:

```ridgun
interpretar_ordre [String]                => String
interpretar_ordre []                      =  "No has escrit res"
interpretar_ordre ("ajuda":_)             =  "Mostrant l'ajuda..."
interpretar_ordre ("copiar":origen:dest:[]) = "Copiant de {origen} a {dest}"
interpretar_ordre (cmd:_)                 =  "Ordre desconeguda: {cmd}"
```

Mira la tercera fila: `("copiar":origen:dest:[])` comprova d'un sol cop que la llista tingui **exactament 3 elements**, que el primer sigui `"copiar"`, i et deixa el segon i el tercer servits en safata a `origen` i `dest`. Intenta escriure això en C o Java i veuràs quantes línies d'`args.length == 3 && args[0].equals("copiar")` et surten.

### Unir llistes amb doble dos punts (`::`)
Quan ets al costat dret de l'`=` (en una expressió) i vols enganxar dues llistes, fas servir **`::`**:

```ridgun
enganxar_llistes [Int] [Int] => [Int]
enganxar_llistes a     b     =  a :: b

afegir_darrere [Int] Int => [Int]
afegir_darrere xs    x   =  xs :: [x]
```

*(Regla mnemotècnica ràpida: un sol `:` als patrons desmunta la llista; dos `::` a les expressions enganxen dues llistes).*

I si de debò vols treure l'element número 5 directament sense recórrer res? Fes servir claudàtors enganxats al nom: `la_meva_llista[5]`.

---

## 5.2. Funcions variàdiques (`T...`): "Passa'm tots els que vulguis!"

De vegades vols que qui cridi la teva funció pugui escriure `maxim_de 4 19 2 88 7` còmodament, sense obligar-lo a envoltar els números entre claudàtors `[4, 19, 2, 88, 7]`.

Posa tres punts **`...`** darrere de l'últim tipus de la teva signatura, i dins de la teva funció ho rebràs automàticament empaquetat com una llista:

```ridgun
sumar_diversos Int... => Int
sumar_diversos nums   =  sumar_llista nums

main => ()
main =
  echo (sumar_diversos 10 20 30)      -- Imprimeix 60
  echo (sumar_diversos 1 2 3 4 5 6 7) -- Imprimeix 28
```

---

## 5.3. Tuples: Quan una funció vol retornar més d'una cosa

En molts llenguatges retornar dues coses des d'una funció és un maldecap: o crees una classe auxiliar ximple `ResultatAmbPosicio`, o passes punters de sortida per referència.

En Ridgun retornes una **tupla** `(A, B)`:

```ridgun
dividir_i_residu Int Int => (Int, Int)
dividir_i_residu a   b   =  (a / b, a % b)
```

Fins i tot et pots estalviar els parèntesis a la línia de la signatura si et resulta més net:
`dividir_i_residu Int Int => Int Int`.

### Com obrir una tupla
Igual que la crees amb `(a, b)`, l'obres als arguments de qualsevol funció amb `(quocient, residu)`:

```ridgun
explicar_divisio (Int, Int)         => String
explicar_divisio (quocient, residu) =  "Hi cap a {quocient} i en sobren {residu}"
```

### El detall estrella: Desempaquetament automàtic entre funcions
Suposa que tens `dividir_i_residu` (que retorna una tupla de 2 enters) i una altra funció `sumar_parell Int Int => Int` (que espera 2 enters solts). En Ridgun no has d'obrir la tupla a mà en una variable intermèdia; pots endollar una funció dins de l'altra directament:

```ridgun
sumar_parell Int Int => Int
sumar_parell x   y   =  x + y

main => ()
main =
  -- dividir_i_residu 17 5 retorna (3, 2), i sumar_parell rep 3 i 2 directament:
  echo (sumar_parell (dividir_i_residu 17 5))  -- Imprimeix 5
```

---

## 5.4. El truc ninja: Seqüències i Màscares Posicionals (`s["-+-"]`)

Aquí ve una de les joies més originals de Ridgun, heretada directament dels llenguatges vectorials com J i APL.

Imagina que reps una tirallonga d'arguments amb el patró de seqüència **`(s)`** i vols quedar-te només amb alguns i llençar-ne d'altres sense declarar cinc variables amb noms inventats (`_a`, `b`, `_c`, `d`...).

Li apliques a `s` una **màscara de signes `+` (queda-te'l) i `-` (llença'l)**:

- **`s["-+-"]`**: de 3 elements, llença el primer (`-`), queda't amb el segon (`+`) i llença el tercer (`-`).
- **`s["+-+"]`**: queda't amb el primer i el tercer; retorna la seqüència amb aquests dos.
- **`s["-- +"]`** (compte amb l'espai abans de l'últim `+`): llença els dos primers (`--`) i aplica `+` **a tots els altres que vinguin darrere**, siguin quants siguin.

Mira-ho funcionant:

```ridgun
el_del_mig Int Int Int => Int
el_del_mig (s)         =  s["-+-"]

descartar_dos_primers Int... => [Int]
descartar_dos_primers (s)    =  s["-- +"]

main => ()
main =
  echo (el_del_mig 100 42 999)             -- Imprimeix 42
  echo (descartar_dos_primers 1 2 10 20 30) -- Imprimeix [10, 20, 30]
```

A més, si fas servir l'operador coma `,` fora de parèntesis (`llista1 , llista2`), Ridgun aplana totes dues col·leccions en una única seqüència contínua.

Al **Capítol 06** farem el pas que converteix un programador funcional en un arquitecte de primera: **crear els teus propis Tipus de Dades Algebraics (ADTs), escriure funcions polimòrfiques amb `A`..`Z` i fabricar els teus propis operadors a mida**.
