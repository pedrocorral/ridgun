# Capítol 01: El teu primer contacte amb Ridgun (Sense cascs, sense claus i sense punts i coma)

D'acord, ja t'he convençut al Capítol 00 que no estem bojos per crear Ridgun. Ara segurament deus estar pensant:

> *"Molt bonic el discurs de les taules i els 16 nuclis, però ensenya'm codi de debò. Quant triga un a escriure alguna cosa que funcioni sense barallar-se amb el compilador?"*

Som-hi, anem per feina!

---

## 1.1. "Hola, món!", però amb substància

En la majoria dels llibres de programació t'ensenyen un `print("Hola món")` insípid i passen de pàgina. Nosaltres escriurem directament una funció amb lògica real perquè vegis com respira Ridgun des del minut u.

Crea un fitxer anomenat `hola.rg` i escriu això:

```ridgun
salutacio String => String
salutacio ""     =  "Hola, viatger misteriós! (No m'has dit el teu nom)"
salutacio "Root" =  "Home, Root! Compte amb el que esborres avui."
salutacio nom    =  "Hola, {nom}! Benvingut a Ridgun."

main => ()
main =
  echo (salutacio "Ada")
  echo (salutacio "Root")
  echo (salutacio "")
```

Per executar-ho ara mateix:

```bash
ridgunc run hola.rg
```

I veuràs al teu terminal:

```text
Hola, Ada! Benvingut a Ridgun.
Home, Root! Compte amb el que esborres avui.
Hola, viatger misteriós! (No m'has dit el teu nom)
```

Atura't un moment i mira el bloc de `salutacio` a dalt. Notes què **NO** hi ha?
- **No hi ha `function`, ni `def`, ni `pub fn`** (si vols posar `fn ::` davant de la signatura pots fer-ho, però és opcional).
- **No hi ha parèntesis `(String nom)` ni claus `{ ... }`** embrutant la pantalla.
- **No hi ha `if (nom == "") ... else if (nom == "Root") ... else ...`**.
- **No hi ha `return`**.

---

## 1.2. Com llegeix el teu cervell un fitxer `.rg`

Destripem aquestes quatre línies de `salutacio`, perquè aquí ja hi ha el 50% de la filosofia de Ridgun:

```ridgun
salutacio String => String
salutacio ""     =  "Hola, viatger misteriós! (No m'has dit el teu nom)"
salutacio "Root" =  "Home, Root! Compte amb el que esborres avui."
salutacio nom    =  "Hola, {nom}! Benvingut a Ridgun."
```

1. **La primera línia és el contracte (`salutacio String => String`)**:
   Diu: *"Em dic `salutacio`, rebo un `String` i et retorno (`=>`) un altre `String`"*. Punt. Si algú intenta cridar-me passant-me el número `42`, el compilador li donarà un toc a l'espatlla abans fins i tot d'executar el programa.
2. **Les línies de sota són els casos (de dalt a baix)**:
   - M'has passat la cadena buida `""`? Retorno la primera frase.
   - M'has passat exactament `"Root"`? Retorno la segona frase.
   - M'has passat qualsevol altra cosa? La deso a la variable `nom` i la fico dins del text fent servir `{nom}`.
3. **I què és `main => ()`?**:
   Com que `main` no rep arguments, posem `=>` directament després del nom. I retorna `()` (el tipus buit o *Unit*, per als amics), perquè la seva única feina és treure coses per pantalla amb `echo`.

---

## 1.3. "Espera... he d'alinear aquests espais a mà com un monjo copista?"

Ni parlar-ne! Si haguessis de prémer la barra espaiadora comptant columnes a ull, abandonaries Ridgun als deu minuts (i amb raó).

Tu escrius el codi de pressa, amb un sol espai entre cada paraula:

```ridgun
salutacio String => String
salutacio "" = "Hola, viatger misteriós!"
salutacio nom = "Hola, {nom}!"
```

I quan executes **`stable format`** (o prems `TAB` / deses el fitxer a Emacs amb `ridgun-mode`), el formatador canònic col·loca cada paràmetre sota el seu tipus i alinea tots els `=` amb precisió mil·limètrica. Tu escrius ràpid; la màquina maqueta la taula.

---

## 1.4. De script ràpid a binari de combat en una ordre

Quan fas `ridgunc run hola.rg`, estàs compilant i llançant el programa al vol. Però imagina que ja has acabat la teva eina i te la vols emportar a un servidor de producció o compartir-la amb un company que no té instal·lat Ridgun.

Executes:

```bash
ridgunc build hola.rg -o hola
```

I ja tens `./hola`: un **executable natiu ELF de Linux x86_64**, net, sense codi mort (*Tree-Shaking*), amb optimització d'enllaç complet (*LTO*) i sense dependre de cap intèrpret extern.

---

## 1.5. La xuleta honesta: D'on ve cada idea de Ridgun?

Ridgun no pretén reinventar la roda quadrada; manlleva sense complexos el millor de quatre tradicions:

| De qui | Què pren Ridgun | Què deixa fora (per la teva salut mental) |
|---|---|---|
| **Haskell / ML** | Funcions pures, *pattern matching* per casos, tipus algebraics (`Option`, `Result`) i polimorfisme (`A`..`Z`). | Les mònades abstractes, els 40 `LANGUAGE pragmas` i el recol·lector de brossa. |
| **J / APL** | L'obsessió per la forma tabular del codi, tensors natius i màscares de seqüències (`s["-+-"]`). | Els símbols jeroglífics impossibles d'escriure en un teclat normal. |
| **Rust / C** | Binaris ELF natius petits, zero GC, control de memòria (`with region`) i crides al sistema POSIX. | La baralla constant amb el *borrow checker*, els *lifetimes* `'a` i la verbositat sintàctica. |
| **Erlang / Go** | Agents aïllats (`agent`, `send ... to`, `receive from`) i concurrència per canals (`new bounded channel`). | Els punters `nil` i les mutacions compartides per descuit. |

---

## 1.6. I el més important: Què fa Ridgun que NO té ningú més?

Reconèixer els clàssics és de bona educació, però si Ridgun fos només un "recopilatori de grans èxits" d'altres llenguatges, no estaries llegint aquest llibre.

Hi ha **set coses** que hem dissenyat i integrat a Ridgun que no trobaràs juntes —i moltes d'elles, ni tan sols per separat— en cap altre llenguatge actual:

### 1. Blocs paral·lels `||` amb `->` que són grafs paral·lels reals, no simple sucre sintàctic
En altres llenguatges funcionals un bloc de variables locals només ordena expressions que després s'avaluen en un únic fil.
En Ridgun, **un bloc `||` amb fletxes `->` és un Graf Acíclic Dirigit (DAG) d'execució paral·lela** sense ni tan sols necessitar escriure paraules clau extra com `where`:
```ridgun
informe_anual Int => Int
informe_anual id  =  ingressos - despeses
  || calcular_vendes id -> ingressos
  || calcular_costos id -> despeses
```
Tu dibuixes les fletxes de flux (`->`). El compilador analitza qui depèn de qui, **verifica estàticament que no hagis creat cap cicle infinit**, i llança les branques independents en paral·lel sense que escriguis ni un sol `async`, `await`, `Future` ni `Mutex`.

### 2. El codi com a taula bidimensional on la signatura és la capçalera de les columnes
En qualsevol altre llenguatge, la signatura de tipus va per lliure en una línia i el cos de la funció va a sota com un paràgraf de text normal.
En Ridgun, **la signatura de tipus és literalment la capçalera d'una taula**, i cada cas a sota alinea cada patró just en la vertical del seu tipus i cada `=` sota el `=>`:
```ridgun
dividir Int Int => Option
dividir _   0   =  None
dividir a   b   =  Some (a / b)
```
Ningú més tracta la signatura i les equacions com una única matriu visual verificada pel compilador i maquetada automàticament per `stable format`.

### 3. Operadors frase (*Mixfix* N-aris) tipats i alineats (`op ::`)
En la majoria dels llenguatges, o t'aguantes amb `+`, `-`, `*` o com a molt defineixes un operador binari críptic com `<|>` que ningú sap què significa.
En Ridgun pots crear **operadors que són frases llegibles amb tants buits tipats com vulguis** (incloent-hi paraules contextuals com `type` o `with`):
```ridgun
op :: Int limitat_entre Int i Int => Int
      x   limitat_entre min i max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
I després al teu codi escrius `velocitat limitat_entre 0 i 120`. Es llegeix com català (o anglès), però està 100% tipat i compilat a codi natiu.

### 4. Màscares visuals sobre seqüències (`s(+ _)` i `s["-+-"]`)
Alguna vegada has hagut d'escriure una amanida d'índexs `filter(\(i, x) -> i % 2 == 0)` només per quedar-te amb els elements parells o extreure un patró rítmic d'una llista?
En Ridgun li passes directament una **màscara visual**:
- `dades["-+-"]`: descarta el primer (`-`), es queda el segon (`+`), descarta el tercer (`-`).
- `dades["+-~"]`: el símbol `~` repeteix el patró `+-` en bucle fins al final de la llista (tots els índexs parells d'un sol cop).
Zero aritmètica d'índexs, zero errors *off-by-one*.

### 5. Polimorfisme de "zero soroll" (`A`..`Z`) governat pel teu domini
En Rust, TypeScript o Java, quan una funció és genèrica has d'omplir la línia de parèntesis angulars: `fn intercanviar<A, B>(parell: (A, B)) -> (B, A)`.
En Ridgun simplement fas servir una lletra majúscula solta:
```ridgun
intercanviar (A, B) => (B, A)
intercanviar (x, y) =  (y, x)
```
*"I si al meu programa vull tenir un tipus real que es digui `type A`?"* — Cap problema: en Ridgun **les teves declaracions `type` manen**. Si no existeix `type A`, `A` és genèric; en l'instant en què defineixes `type A = ...`, passa a ser el teu tipus concret en tot el mòdul.

### 6. Zero fitxers de configuració estranys: `build.rg` és Ridgun pur
Oblida't d'aprendre TOML per a Cargo, JSON per a npm, XML per a Maven o la sintaxi arcana de `Makefile` amb tabuladors invisibles. En Ridgun, la recepta que construeix el teu projecte (`build.rg`) **és un fitxer `.rg` més**, amb les mateixes funcions pures i el mateix *pattern matching* que la resta del teu codi.

### 7. La "Santíssima Trinitat" que semblava impossible: Nivell Haskell + Memòria RMM sense GC ni Lifetimes + Binaris de ~350 KB
Fins avui havies de triar:
- Si volies expressivitat funcional pura (Haskell, OCaml, Elixir), pagaves amb un recol·lector de brossa i un runtime pesat.
- Si volies binaris diminuts de sistema sense recol·lector de brossa (C, Rust, Zig), pagaves gestionant punters o barallant-te amb el *borrow checker* i escrivint codi imperatiu ple de `let mut`.

Ridgun trenca aquest dilema combinant **Ridgun Memory Management (`RMM`: `RMM1` estàtica i `RMM2` per recompte d'assignacions en cascada)**, **regions lèxiques (`with region`)** que alliberen arenes senceres en $O(1)$, **recursió de cua transformada en bucles natius (`loop`)**, i **poda de graf de crides (*Tree-Shaking*)** des de `main`. El resultat: escrius codi declaratiu d'altíssim nivell i obtens un executable ELF autònom de **~350 KB** capaç de competir de tu a tu amb eines escrites en C.

Ara sí: amb les cartes sobre la taula, anem al **Capítol 02** per posar a treballar **`ridgunc`** i **`stable`**.
