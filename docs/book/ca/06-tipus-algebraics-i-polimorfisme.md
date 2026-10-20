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
el_meu_node => Servidor
el_meu_node =  Servidor "api.exemple.com" 443 True
```

### 2. Una funció *getter* pura per a cada camp (`host`, `port`, `tls_actiu`)
No has d'escriure `s.getHost()` ni res semblant; cada nom de camp és directament una funció que extreu aquella dada:

```ridgun
url_connexio Servidor => String
url_connexio srv      =  "Connectar a " + (host srv) + " al port {port srv}"
```

### 3. Actualització funcional de registres (`with camp: valor`)
Imagina un registre de configuració amb 12 o 15 camps (com les opcions d'una ordre `ls` o d'un servidor web) i vols canviar només un o dos camps sense tocar la resta. En lloc de reconstruir el registre passant els 15 camps a mà, fas servir **`with`** i dos punts **`:`** (exactament igual que en la definició del `type`):

```ridgun
activar_mode_dev Servidor => Servidor
activar_mode_dev srv      =  srv with port: 8080, tls_actiu: False
```

El millor dels dos mons:
- Al teu codi és **100% immutable i segur** (el compilador comprova que `port` i `tls_actiu` existeixin a `Servidor` i tinguin el tipus correcte).
- Per sota, si `srv` no està compartit amb ningú més, l'executable natiu reutilitza la seva memòria *in-place* (`Arc::try_unwrap`) sense copiar la resta de camps.

### 4. *Pattern matching* complet per si vols obrir el registre en canal
```ridgun
es_port_segur Servidor              => Bool
es_port_segur (Servidor _ 443 True) =  True
es_port_segur _                     =  False
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
descriure_pagament MetodePagament       => String
descriure_pagament (Targeta num _)      =  "Pagament amb targeta acabada en {num}"
descriure_pagament (Transferencia iban) =  "Transferència des del compte {iban}"
descriure_pagament Efectiu              =  "Pagament en metàl·lic a finestreta"
```

Cada variant (`Targeta`, `Transferencia`, `Efectiu`) porta enganxades únicament les dades que tenen sentit per a ella. És **impossible** construir un pagament en `Efectiu` que tingui un `iban` penjant per error.

---

## 6.3. "I com fico `[1, "dos"]` en una llista sense fer servir `Any`?"

Tornem a la pregunta del milió. Imagina que estàs llegint un fitxer CSV o JSON on una cel·la pot ser un número enter, un text o estar buida.

Si tinguessis un tipus `Any`, hi ficaries `[1, "dos"]` i perdries tota l'ajuda del compilador: a partir d'aquell moment qualsevol operació sobre la llista seria caminar amb els ulls embenats.

En Ridgun (igual que en Haskell o Rust), crees en dos segons un tipus suma que explica exactament quines coses poden viure dins d'aquesta llista:

```ridgun
type ValorCella = Enter Int | Text String | Buit

formatar_cella ValorCella => String
formatar_cella (Enter n)  =  "Número: {n}"
formatar_cella (Text s)   =  "Text: {s}"
formatar_cella Buit       =  "(buit)"

la_meva_fila => [ValorCella]
la_meva_fila =  [Enter 1, Text "dos", Buit]
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
cercar_divisio Int Int => Result
cercar_divisio _   0   =  Err "Ei! No es pot dividir per zero"
cercar_divisio a   b   =  Ok (a / b)

imprimir_res Result    => ()
imprimir_res (Ok n)    =  echo "El resultat és {n}"
imprimir_res (Err msg) =  echo "Fallada controlada: {msg}"
```

Ningú pot ignorar un error per descuit perquè el mateix tipus `Result` t'obliga a mirar si a dins hi ha un `Ok` o un `Err`.

---

## 6.5. Polimorfisme Paramètric: Funcions genèriques amb `A`, `B`, `T`...

Suposa que escrius una funció que inverteix un parell `(x, y)` o que treu el primer element d'una llista. De debò importa si la llista és d'`Int`, de `String` o de `Servidor`? En absolut! L'algorisme és idèntic.

En Ridgun, **qualsevol lletra majúscula individual (`A` a `Z`)** en una signatura de tipus funciona automàticament com un **tipus comodí polimòrfic (variable de tipus)**:

```ridgun
cap_segur [A]   A          => A
cap_segur []    per_defecte =  per_defecte
cap_segur (x:_) _          =  x

girar_parell (A, B) => (B, A)
girar_parell (x, y) =  (y, x)
```

Fixa't en la màgia de `cap_segur [A] A => A`:
- No és un `Any` descontrolat: diu que **el tipus de la llista `[A]`, el tipus del valor `per_defecte` (`A`) i el tipus retornat (`A`) han de ser el mateix**.
- Si crides `cap_segur [10, 20] 0`, el compilador lliga caps (`A = Int`) i et retorna un `Int`.
- Si crides `cap_segur ["a", "b"] "cap"`, lliga caps (`A = String`) i et retorna un `String`.
- Però si intentes fer trampa i crides `cap_segur [10, 20] "cap"`, zas! El compilador et frena en sec perquè el primer argument diu que `A` és `Int` i el segon diu que `A` és `String`.

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

Al **Capítol 07** posarem tots els nuclis del teu processador a treballar alhora sense vessar ni una gota de suor: **funcions d'ordre superior (`map`, `||map`, `filter`, `||filter`, `fold`), grafs paral·lels `||` amb `->` i canals concurrents**.
