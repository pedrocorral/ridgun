# Capítol 04: Adéu a l'`if/else`, adéu al `while` (Pattern Matching, Guardes i TCO)

Quan li expliques a algú que en Ridgun **no existeix la paraula clau `if`, ni `else`, ni `switch`, ni `for`, ni `while`**, sol mirar-te com si li haguessis dit que construiràs una casa sense martell ni claus:

> *"Que no hi ha `if` ni `while`? I com nassos prenc una decisió o recorro un milió de dades?"*

Doncs resulta que `if/else` i `while` són eines força tosques heretades de com funcionaven els salts (`GOTO`) als anys 50. En Ridgun els substituïm per tres peces que encaixen com un guant:
1. ***Pattern Matching*** (quan decideixes segons la **forma o valor exacte** de la dada).
2. **Guardes booleanes `|`** (quan decideixes segons una **condició o rang**).
3. **Recursió de cua amb TCO** (que el compilador converteix per sota en un bucle `loop` natiu ultraràpid).

Vegem-les en acció.

---

## 4.1. *Pattern Matching*: Quan l'argument ja et dóna la resposta

Al capítol anterior ja en vam veure un avançament. En lloc de rebre una variable genèrica `x` i obrir dins de la funció cinc `if (x == ...)`, en Ridgun poses els casos directament a la porta d'entrada de la funció:

```ridgun
codi_http Int => String
codi_http 200 =  "OK: Tot ha anat sobre rodes"
codi_http 301 =  "Mogut permanentment"
codi_http 404 =  "No trobat (has mirat sota el sofà?)"
codi_http 500 =  "Foc al servidor"
codi_http n   =  "Codi desconegut: {n}"
```

Ridgun prova les files **de dalt a baix**:
- Si entra `404`, salta directe a la tercera fila.
- Si entra `418`, cap de les quatre primeres files coincideix, així que cau a l'última (`n`), que atrapa qualsevol enter i l'anomena `n` perquè puguis imprimir-lo.
- I si en l'últim cas ni tan sols t'importa quin número era? Poses un guió baix `_` (*comodí*) i te n'oblides: `codi_http _ = "Un altre codi"`.

---

## 4.2. Guardes booleanes (`|`): El teu bisturí per a rangs, variables condicionals i arbres de decisió

*"D'acord, el pattern matching mola quan busco el `200` o el `404`. Però què faig si vull comprovar si `nota >= 5` o si `edat > 18 and edat < 65`? No escriuré pas 47 files amb tots els números del 18 al 65!"*

És clar que no! Per a això hi ha les **guardes (`|`)**.

Quan el resultat depèn d'una desigualtat o d'una combinació lògica, després de l'`=` de la funció (o de qualsevol variable local) obres una escala de barres verticals `|`:

```ridgun
qualificar Int  => String
qualificar nota =
  | nota < 0   = "Nota impossible (punts negatius?)"
  | nota < 5   = "Suspès"
  | nota < 7   = "Aprovat"
  | nota < 9   = "Notable"
  | nota <= 10 = "Excel·lent"
  | otherwise  = "T'has passat de l'escala"
```

Mira-t'ho bé:
- El signe `=` de la capçalera (`qualificar nota =`) s'alinea sota `=>` igual que en qualsevol altra funció.
- A sota es llegeix de dalt a baix igual que una taula de tarifes: cada línia `| condicio = resultat` es comprova en ordre. Tan bon punt una dóna `True`, retorna aquell resultat i s'ha acabat.
- Al final poses **`| otherwise = ...`**, que significa literalment *"en qualsevol altre cas"* (la teva xarxa de seguretat perquè mai no quedi un camí sense retorn).

### Lògica booleana en minúscules clares (`and`, `or`, `xor`, `not`)
T'has fixat que molts llenguatges fan servir `|` per a bits, `||` per a booleans, `!` per negar... i quan llegeixes una condició complexa sembla que un gat hagi caminat sobre el teclat (`if (!a && (b || c))`)?

En Ridgun, com que `|` ja és el símbol sagrat de les guardes i dels tipus algebraics, i `||` és l'operador de paral·lelisme, **els operadors booleans s'escriuen amb paraules clares en minúscules**:

- **`and`**: es compleixen totes dues coses (`edat >= 18 and te_carnet`).
- **`or`**: se'n compleix almenys una (`dia == "dissabte" or dia == "diumenge"`).
- **`xor`**: es compleix l'una o l'altra, però no totes dues alhora.
- **`not`**: inverteix el booleà (`not (es_buit text)`).

Mira que net queda el clàssic problema dels anys de traspàs:

```ridgun
es_de_traspas Int => Bool
es_de_traspas a   =
  | (a % 400) == 0                  = True
  | (a % 4) == 0 and (a % 100) != 0 = True
  | otherwise                       = False
```

Zero símbols críptics. Ho llegeix algú que no sap Ridgun i ho entén a la primera.

### Variables locals condicionals (`x =` + `|`)
Com que en Ridgun tot `=` segueix la mateixa regla, **també pots fer servir `|` per assignar una variable local** sense haver de crear una funció auxiliar a part:

```ridgun
preu_bitllet Int  Bool                => Int
preu_bitllet base es_familia_nombrosa =
  descompte =
    | es_familia_nombrosa = 20
    | base > 100          = 10
    | otherwise           = 0
  base - (base * descompte / 100)
```

### Arbres de decisió imbricats i el limitador compacte `|.`
*"I si dins d'una branca `| cond =` o `| otherwise =` vull obrir un altre subarbre de guardes `|` de 3 o 4 nivells de profunditat i després tornar a un nivell superior?"*

Pots imbricar `|` dins de `|` tants nivells com vulguis. I quan un bloc `|` imbricat acaba però a sota continuen més branques d'un nivell pare (o més sentències del bloc), col·loques **`|.`** al final de la seva última línia (`| otherwise = valor |.`) per indicar sense cap ambigüitat que aquell subarbre es tanca i tornes al nivell anterior:

```ridgun
encaminar_peticio Int   Int Bool    Bool     Int     Int     => Int
encaminar_peticio metode rol signada es_admin mida_kb limitat =
  | metode == 0 =
    | mida_kb == 0 = 204
    | otherwise    = 200 |.
  | metode == 1 =
    | not signada = 401
    | otherwise =
      -- Nivell 2: petició POST signada
      | limitat > 0 =
        -- Nivell 3: control de rate-limit
        | es_admin =
          -- Nivell 4: excepció per a administradors
          | mida_kb > 10000 = 413
          | otherwise       = 202 |.
        | otherwise = 429 |.
      | mida_kb > 1000 =
        -- Nivell 3: hem tornat des del Nivell 4 gràcies a `|.`
        | rol >= 2 and es_admin = 201
        | otherwise             = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Fixa't en com n'és, de net:
- En un arbre simple d'1 nivell (o al final de tota la funció) **mai no cal posar `|.`** (seria soroll innecessari).
- Només escrius `|.` en tancar una branca imbricada quan a sota continua una branca d'un nivell superior.

### Blocs de diverses línies dins d'una guarda (`| cond =` + bloc sagnat)
Igual que després de l'`=` d'una funció normal pots obrir un bloc sagnat de diverses línies, **després de l'`=` de qualsevol guarda `| cond =` o `| otherwise =` també pots fer un salt de línia i obrir un bloc seqüencial**:

```ridgun
ajustar_finestra Int Int   => Int
ajustar_finestra idx limit =
  | idx >= limit =
      topall = limit - 1
      escalat = topall * 2
      escalat + 10
  | otherwise =
      seguent = idx + 1
      seguent * 2
```

Cada branca de la guarda té el seu propi bloc local net i la seva última línia és el valor que retorna aquella branca.

---

## 4.3. "Sense `while`? I no rebentarà la pila si recorro un fitxer gran?"

Parlem de l'elefant a l'habitació.

Si véns de Python, Java o JavaScript, t'han ensenyat des de ben petit que *"la recursió és elegant a la pissarra de la universitat, però al món real desborda la pila (`StackOverflowError`) a les 1.000 voltes; fes servir un bucle `while`"*.

Això és veritat en llenguatges que **no** optimitzen les crides de cua. Però en un llenguatge funcional de sistemes com Ridgun, **una recursió de cua ÉS un bucle `while` disfressat de funció pura**.

### Quina diferència hi ha entre una recursió normal i una recursió de cua?
Fixa't en aquestes dues funcions que compten cap enrere des de `n` fins a `0` sumant els números:

```ridgun
-- Versió A: Recursió NORMAL (deixa feina pendent per a la tornada)
sumar_lent Int => Int
sumar_lent 0   =  0
sumar_lent n   =  n + (sumar_lent (n - 1))

-- Versió B: Recursió DE CUA (porta el compte al dia a `acumulat`)
sumar_rapid_loop Int Int      => Int
sumar_rapid_loop 0   acumulat =  acumulat
sumar_rapid_loop n   acumulat =  sumar_rapid_loop (n - 1) (acumulat + n)
```

- A la **Versió A**, abans de poder sumar `n + ...`, la funció ha d'esperar que acabi `sumar_lent (n - 1)`. Això obliga l'ordinador a desar `n` a la pila en cada pas.
- A la **Versió B**, la crida a `sumar_rapid_loop` **és l'última cosa que passa a la línia**. No queda res pendent darrere seu. Ja li passes la suma actualitzada a `acumulat + n`.

### El truc de màgia de `ridgunc` (TCO: *Tail-Call Optimization*)
Quan `ridgunc` compila `sumar_rapid_loop`, veu que la funció es crida a si mateixa al final de la clàusula i diu:

> *"Per a què crearé un marc de pila nou si l'actual ja no serveix per a res? Sobreescriuré `n` amb `n - 1`, sobreescriuré `acumulat` amb `acumulat + n` i saltaré al principi amb un `loop { ... continue; }` natiu."*

Resultat:
1. Pots cridar `sumar_rapid_loop 100_000_000 0` (cent milions de voltes) i **gastarà exactament 0 bytes extra de pila**.
2. Va igual de ràpid que un bucle `while` escrit a mà en Rust o C, però sense haver hagut de declarar ni una sola variable mutable al teu codi Ridgun.

---

## 4.4. El patró mestre que faràs servir en tot programa Ridgun

Cada vegada que en un altre llenguatge pensaries *"faré un bucle `while` amb un índex `i` i un acumulador"*, en Ridgun escrius una parella de funcions com aquesta (la funció principal neta i el seu ajudant `_loop` de cua):

```ridgun
cercar_caracter_loop String Int Int Int    => Int
cercar_caracter_loop text   pos fi  cercat =
  | pos >= fi                        = -1
  | (str_char_at text pos) == cercat = pos
  | otherwise                        = cercar_caracter_loop text (pos + 1) fi cercat

cercar_caracter String Int    => Int
cercar_caracter text   cercat =  cercar_caracter_loop text 0 (str_len text) cercat
```

Mira les tres guardes de `cercar_caracter_loop`:
1. He arribat al final (`pos >= fi`)? Retorno `-1` (fi del bucle).
2. He trobat el caràcter a `pos`? Retorno `pos` (fi del bucle).
3. No és aquest? Passo al següent (`pos + 1`) amb una crida de cua (que el compilador converteix en `continue;`).

Net, impossible de tenir *bugs* de variables globals trepitjades i ràpid com un llamp.

Al **Capítol 05** posarem fil a l'agulla amb les col·leccions de dades: **llistes, tuples, funcions que accepten infinits arguments (`...`) i les màscares de seqüències estil J/APL**.
