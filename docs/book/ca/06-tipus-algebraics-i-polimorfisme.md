# Capítol 06: Tipus de Dades Algebraics (ADTs), Polimorfisme i per què aquí no volem `null` ni `Any`

El 1965, Tony Hoare va inventar la referència nul·la (`null` / `nil`). Quaranta anys després va demanar perdó públicament i la va anomenar *"el meu error de mil milions de dòlars"*.

Per què? Perquè en els llenguatges amb `null`, una funció et promet a la seva signatura que et retornarà un `Usuari`... i quan menys t'ho esperes et retorna `null` i et tomba el servidor a les tres de la matinada.

I el mateix passa amb l'herència d'objectes i el tipus `Any` (o `Object`): fiques un número i un text en una llista `[1, "dos"]`, el llenguatge s'arronsa d'espatlles i diu *"d'acord, doncs ara això és una `List[Any]`, bona sort endevinant què hi ha a dins quan la recorris"*.

En Ridgun tallem aquests dos problemes de soca-rel amb **Tipus de Dades Algebraics (ADTs)** i **Polimorfisme Paramètric**. Sona a nom d'assignatura dura, però en cinc minuts veuràs que és la manera més natural del món de modelar dades.

---

## 6.1. Tipus Producte (Registres): Els teus `struct` de tota la vida, però amb superpoders

Quan vols agrupar diverses dades que pertanyen a una mateixa entitat (per exemple, un servidor amb el seu nom, la seva IP i el seu port), defineixes un **`type`** amb els seus camps:

```ridgun
type Servidor = host: String, port: Int, tls_actiu: Bool
```

Només escrivint aquesta línia, Ridgun et regala **quatre coses** automàticament:

### 1. El constructor `Servidor`
```ridgun
el meu node => Servidor
el meu node =  Servidor "api.exemple.com" 443 True
```

### 2. Una funció *getter* pura per a cada camp (`host`, `port`, `tls_actiu`)
No has d'escriure `s.getHost()` ni res semblant; cada nom de camp és directament una funció que extreu aquella dada:

```ridgun
url connexio Servidor => String
url connexio srv      =  "Connectar a " + (host srv) + " al port {port srv}"
```

### 3. Actualització funcional de registres (`with camp: valor`)
Imagina un registre de configuració amb 12 o 15 camps (com les opcions d'una ordre `ls` o d'un servidor web) i vols canviar només un o dos camps sense tocar la resta. En lloc de reconstruir el registre passant els 15 camps a mà, fas servir **`with`** i dos punts **`:`** (exactament igual que en la definició del `type`):

```ridgun
activar mode dev Servidor => Servidor
activar mode dev srv      =  srv with port: 8080, tls_actiu: False
```

El millor dels dos mons:
- Al teu codi és **100% immutable i segur** (el compilador comprova que `port` i `tls_actiu` existeixin a `Servidor` i tinguin el tipus correcte).
- Per sota, si `srv` no està compartit amb ningú més, l'executable natiu reutilitza la seva memòria *in-place* (`Arc::try_unwrap`) sense copiar la resta de camps.

### 4. *Pattern matching* complet per si vols obrir el registre en canal
```ridgun
es port segur Servidor              => Bool
es port segur (Servidor _ 443 True) =  True
es port segur _                     =  False
```

---

## 6.2. Tipus Suma (Variants amb `|`): Com jubilar `null`, les excepcions i l'herència

Ara ve el millor.
Un registre normal té `host` **I** `port` **I** `tls_actiu`.
Però al món real moltes vegades necessites dir: *"Un mètode de pagament és **O BÉ** una targeta amb el seu número, **O BÉ** una transferència amb el seu IBAN, **O BÉ** efectiu (que no porta cap dada extra)"*.

En orientació a objectes hauries de crear una interfície `MetodePagament`, tres subclasses en tres fitxers diferents, constructors, `instanceof`... En Ridgun és **una línia**:

```ridgun
type MetodePagament = Targeta String Int | Transferencia String | Efectiu
```

I mira què passa quan processes un `MetodePagament` en una funció:

```ridgun
descriure pagament MetodePagament       => String
descriure pagament (Targeta num _)      =  "Pagament amb targeta acabada en {num}"
descriure pagament (Transferencia iban) =  "Transferència des del compte {iban}"
descriure pagament Efectiu              =  "Pagament en metàl·lic a finestreta"
```

Cada variant (`Targeta`, `Transferencia`, `Efectiu`) porta enganxades únicament les dades que tenen sentit per a ella. És **impossible** construir un pagament en `Efectiu` que tingui un `iban` penjant per error.

---

## 6.3. "I com fico `[1, "dos"]` en una llista sense fer servir `Any`?"

Tornem a la pregunta del milió. Imagina que estàs llegint un fitxer CSV o JSON on una cel·la pot ser un número enter, un text o estar buida.

Si tinguessis un tipus `Any`, hi ficaries `[1, "dos"]` i perdries tota l'ajuda del compilador: a partir d'aquell moment qualsevol operació sobre la llista seria caminar amb els ulls embenats.

En Ridgun (igual que en Haskell o Rust), crees en dos segons un tipus suma que explica exactament quines coses poden viure dins d'aquesta llista:

```ridgun
type ValorCella = Enter Int | Text String | Buit

formatar cella ValorCella => String
formatar cella (Enter n)  =  "Número: {n}"
formatar cella (Text s)   =  "Text: {s}"
formatar cella Buit       =  "(buit)"

la meva fila => [ValorCella]
la meva fila =  [Enter 1, Text "dos", Buit]
```

Hi veus la diferència?
- Amb `Any`, el compilador no sap si a la llista hi ha enters, cadenes o una cafetera connectada per USB.
- Amb `[ValorCella]`, pots barrejar números i textos a la mateixa llista, **però el compilador sap al 100% que només existeixen aquestes tres possibilitats** i t'obliga a desempaquetar cada cas (`Enter n`, `Text s`, `Buit`) abans de fer-lo servir. Seguretat total sense perdre ni un brí de flexibilitat.

---

## 6.4. `Option` i `Result`: Quan alguna cosa pot no ser-hi o pot fallar

Com que en Ridgun no existeix `null` ni existeixen excepcions que saltin pels aires (`throw new Exception()`), el llenguatge porta integrats dos tipus suma universals:

1. **`Option`**: o tens **`Some valor`**, o tens **`None`** (res).
2. **`Result`**: o l'operació ha sortit bé (**`Ok valor`**), o ha fallat per un motiu concret (**`Err error`**).

```ridgun
cercar divisio Int Int => Result
cercar divisio _   0   =  Err "Ei! No es pot dividir per zero"
cercar divisio a   b   =  Ok (a / b)

imprimir res Result    => ()
imprimir res (Ok n)    =  echo "El resultat és {n}"
imprimir res (Err msg) =  echo "Fallada controlada: {msg}"
```

Ningú pot ignorar un error per descuit perquè el mateix tipus `Result` t'obliga a mirar si a dins hi ha un `Ok` o un `Err`.

---

## 6.5. Polimorfisme Paramètric: Funcions genèriques amb `A`, `B`, `T`...

Suposa que escrius una funció que inverteix un parell `(x, y)` o que treu el primer element d'una llista. De debò importa si la llista és d'`Int`, de `String` o de `Servidor`? En absolut! L'algorisme és idèntic.

En Ridgun, **qualsevol lletra majúscula individual (`A` a `Z`)** en una signatura de tipus funciona automàticament com un **tipus comodí polimòrfic (variable de tipus)**:

```ridgun
cap segur [A]   A          => A
cap segur []    per_defecte =  per_defecte
cap segur (x:_) _          =  x

girar parell (A, B) => (B, A)
girar parell (x, y) =  (y, x)
```

Fixa't en la màgia de `cap segur [A] A => A`:
- No és un `Any` descontrolat: diu que **el tipus de la llista `[A]`, el tipus del valor `per_defecte` (`A`) i el tipus retornat (`A`) han de ser el mateix**.
- Si crides `cap segur [10, 20] 0`, el compilador lliga caps (`A = Int`) i et retorna un `Int`.
- Si crides `cap segur ["a", "b"] "cap"`, lliga caps (`A = String`) i et retorna un `String`.
- Però si intentes fer trampa i crides `cap segur [10, 20] "cap"`, zas! El compilador et frena en sec perquè el primer argument diu que `A` és `Int` i el segon diu que `A` és `String`.

---

## 6.6. Crea els teus propis operadors (`op ::`): Des de vectors fins a frases a mida

Per què només els números natius haurien de tenir dret a fer servir `+` o `*`? I per què conformar-se amb els operadors de sempre quan pots inventar la sintaxi perfecta per al teu problema?

Amb **`op ::`** (o directament sense prefix si fas servir patrons d'operador) pots fer dues filigranes:

### 1. Ensenyar a `+`, `-`, `*`, `/`, `%` a operar amb els teus propis tipus
```ridgun
type Complex = real: Int, imag: Int

op :: Complex + Complex => Complex
      a       + b       =  Complex ((real a) + (real b)) ((imag a) + (imag b))
```

### 2. Crear operadors *Mixfix* (que es llegeixen com frases naturals, inclosos `type` i `with`)
En una signatura d'operador, **les paraules amb majúscula inicial (`Int`, `String`, `A`..`Z`) o entre claudàtors/parèntesis (`[Int]`, `(A, B)`) són els buits per als arguments**, i **les paraules en minúscula són part de la frase de l'operador** (fins i tot paraules tan habituals com `type` o `with`, que en Ridgun són contextuals i mai no et bloquegen):

```ridgun
op :: si Bool aleshores A sino A => A
      si True aleshores v sino _ =  v
      si False aleshores _ sino f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  missatge = si (10 > 5) aleshores "El deu guanya!" sino "Impossible"
  echo missatge
  echo (format "panell" type "vorejat" with 80)
```

Acabes de fabricar-te el teu propi operador ternari polimòrfic i un DSL de formatat en **3 línies** de Ridgun.

---

## 6.7. Constructors compartits, variants de tipus directe, `expand type` i espais naturals a `fn ::`

Ridgun porta els tipus algebraics i les funcions un pas més enllà en expressivitat i extensibilitat:

1. **Constructors compartits entre diferents `type`**: Diversos tipus suma poden reutilitzar el mateix nom de constructor (`Error`, `Var`, `Lit`) amb igual o diferent aritat; el verificador de tipus els distingeix per la columna de la signatura.
2. **Variants amb nom de tipus directe (`type Something = String | Int | MyStruct Float Int`)**: Quan una variant és un tipus primitiu (`String`, `Int`, `Float`/`Real`, `Bool`, `Char`), no cal repetir `Int Int` ni `String String`. Pots passar valors directes (`"hola"`, `42`) o constructors explícits (`String "hola"`, `Int 42`), i fer pattern matching tant amb literals (`"admin"`, `0`) com amb patrons tipats (`(String s)`, `(Int n)`).
3. **Extensió oberta de tipus (`expand type`) i fusió automàtica de clàusules `fn ::`**: Amb `expand type` pots afegir noves variants a un tipus suma o nous camps a un registre. En tornar a declarar `fn ::` per a la mateixa funció, les noves clàusules es fusionen automàticament **abans** de qualsevol clàusula comodí `_` (sense necessitat d'escriure `expand fn`).
4. **Espais naturals `" "` en lloc de `_` a `fn ::`, funcions natives i noms de fitxer**: Igual que a `op ::`, els noms de funció a `fn ::`, les crides a funcions natives (`assert equals`, `str len`, `read file`) i els fitxers `.rg` (`test core language.rg`) es poden escriure amb espais naturals:

```ridgun
type Something = String | Int | MyStruct Float Int

fn :: descriure algo Something            => String
      descriure algo "admin"              =  "admin_especial"
      descriure algo 0                    =  "zero"
      descriure algo (String   s)         =  "text:{s}"
      descriure algo (Int      n)         =  "enter:{n}"
      descriure algo (MyStruct ratio cnt) =  "estructura:{ratio}:{cnt}"
      descriure algo _                    =  "altre"

expand type Something = Bool

fn :: descriure algo Something => String
      descriure algo (Bool b)  =  "boolea:{b}"
```

### 5. Tipus genèrics propis (`type Result T E`, `type Page T`) i espais de noms de mòdul (`import ... as`, `mod.Tipus`)
A més de funcions polimòrfiques, pots declarar **els teus propis tipus suma i registres genèrics** amb paràmetres de tipus (`A`..`Z`), així com organitzar tipus, constructors, camps i funcions amb el mateix nom en diferents mòduls sense col·lisió (`module ::`, `import db as d`, `http.Config`, `d.Config`). Cada mòdul té **visibilitat estricta per importació en 3 nivells**: resol els noms sense prefix cercant primer en **(1) les seves pròpies declaracions** (incloent múltiples fitxers amb el mateix `module :: nom`), després en **(2) els seus `import` directes** i només en últim lloc en **(3) els seus `import` transitius**, de manera que altres mòduls germans o l'aplicació principal mai contaminen una llibreria importada:

```ridgun
type Resultat T E = Exit T | Fallada E
type Pagina T     = elements: [T], total: Int

fn :: desempaquetar exit (Resultat A String) A => A
      desempaquetar exit (Exit v)            _ =  v
      desempaquetar exit (Fallada _)         d =  d
```

Al **Capítol 07** posarem tots els nuclis del teu processador a treballar alhora sense vessar ni una gota de suor: **funcions d'ordre superior (`map`, `||map`, `filter`, `||filter`, `fold`), clausures lèxiques (`(x => expr)`), grafs paral·lels `||` amb `->` i canals concurrents**.
