# Capítulo 06: Tipos de Datos Alxébricos (ADTs), Polimorfismo e por que aquí non queremos `null` nin `Any`

En 1965, Tony Hoare inventou a referencia nula (`null` / `nil`). Corenta anos despois pediu perdón publicamente e chamouna *"o meu erro de mil millóns de dólares"*.

Por que? Porque nas linguaxes con `null`, unha función prométeche na súa sinatura que che vai devolver un `Usuario`... e cando menos o agardas devólveche `null` e bótache abaixo o servidor ás tres da mañá.

E outro tanto ocorre coa herdanza de obxectos e o tipo `Any` (ou `Object`): metes un número e un texto nunha lista `[1, "dous"]`, a linguaxe encolle os ombreiros e di *"vale, pois agora isto é unha `List[Any]`, boa sorte adiviñando que hai dentro cando a percorras"*.

En Ridgun cortamos eses dous problemas de raíz con **Tipos de Datos Alxébricos (ADTs)** e **Polimorfismo Paramétrico**. Soa a nome de materia dura, pero en cinco minutos vas ver que é a forma máis natural do mundo de modelar datos.

---

## 6.1. Tipos Produto (Rexistros): Os teus `struct` de toda a vida, pero con superpoderes

Cando queres agrupar varios datos que pertencen a unha mesma entidade (por exemplo, un servidor co seu nome, a súa IP e o seu porto), defines un **`type`** cos seus campos:

```ridgun
type Servidor = host: String, porto: Int, tls_activo: Bool
```

Con só escribir esa liña, Ridgun agasállache **catro cousas** automaticamente:

### 1. O construtor `Servidor`
```ridgun
meu_nodo => Servidor
meu_nodo =  Servidor "api.exemplo.com" 443 True
```

### 2. Unha función *getter* pura para cada campo (`host`, `porto`, `tls_activo`)
Non tes que escribir `s.getHost()` nin nada parecido; cada nome de campo é directamente unha función que extrae ese dato:

```ridgun
url_conexion Servidor => String
url_conexion srv      =  "Conectar a " + (host srv) + " no porto {porto srv}"
```

### 3. Actualización funcional de rexistros (`with campo: valor`)
Imaxina un rexistro de configuración con 12 ou 15 campos (como as opcións dun comando `ls` ou dun servidor web) e queres mudar só un ou dous campos sen tocar o resto. En vez de reconstruír o rexistro pasando os 15 campos á man, usas **`with`** e dous puntos **`:`** (exactamente igual ca na definición do `type`):

```ridgun
activar_modo_dev Servidor => Servidor
activar_modo_dev srv      =  srv with porto: 8080, tls_activo: False
```

O mellor dos dous mundos:
- No teu código é **100% inmutable e seguro** (o compilador comproba que `porto` e `tls_activo` existan en `Servidor` e teñan o tipo correcto).
- Por baixo, se `srv` non está compartido con ninguén máis, o executable nativo reutiliza a súa memoria *in-place* (`Arc::try_unwrap`) sen copiar o resto de campos.

### 4. *Pattern matching* completo por se queres abrir o rexistro en canle
```ridgun
e_porto_seguro Servidor              => Bool
e_porto_seguro (Servidor _ 443 True) =  True
e_porto_seguro _                     =  False
```

---

## 6.2. Tipos Suma (Variantes con `|`): Como xubilar a `null`, ás excepcións e á herdanza

Agora vén o bo.
Un rexistro normal ten `host` **E** `porto` **E** `tls_activo`.
Pero no mundo real moitas veces precisas dicir: *"Un método de pagamento é **OU BEN** unha tarxeta co seu número, **OU BEN** unha transferencia co seu IBAN, **OU BEN** efectivo (que non leva ningún dato extra)"*.

En orientación a obxectos terías que crear unha interface `MetodoPagamento`, tres subclases en tres ficheiros distintos, construtores, `instanceof`... En Ridgun é **unha liña**:

```ridgun
type MetodoPagamento = Tarxeta String Int | Transferencia String | Efectivo
```

E mira que pasa cando procesas un `MetodoPagamento` nunha función:

```ridgun
describir_pagamento MetodoPagamento      => String
describir_pagamento (Tarxeta num _)      =  "Pagamento con tarxeta rematada en {num}"
describir_pagamento (Transferencia iban) =  "Transferencia desde a conta {iban}"
describir_pagamento Efectivo             =  "Pagamento en metálico en portelo"
```

Cada variante (`Tarxeta`, `Transferencia`, `Efectivo`) leva pegados unicamente os datos que teñen sentido para ela. É **imposible** construír un pagamento en `Efectivo` que teña un `iban` colgado por erro.

---

## 6.3. "E como meto `[1, "dous"]` nunha lista sen usar `Any`?"

Volvamos á pregunta do millón. Imaxina que estás lendo un ficheiro CSV ou JSON onde unha cela pode ser un número enteiro, un texto ou estar baleira.

Se tiveses un tipo `Any`, meterías `[1, "dous"]` e perderías toda a axuda do compilador: a partir dese momento calquera operación sobre a lista sería camiñar cos ollos vendados.

En Ridgun (igual ca en Haskell ou Rust), creas en dous segundos un tipo suma que explica exactamente que cousas poden vivir dentro desa lista:

```ridgun
type ValorCela = Enteiro Int | Texto String | Baleiro

formatar_cela ValorCela    => String
formatar_cela (Enteiro n)  =  "Número: {n}"
formatar_cela (Texto s)    =  "Texto: {s}"
formatar_cela Baleiro      =  "(baleiro)"

mina_fila => [ValorCela]
mina_fila =  [Enteiro 1, Texto "dous", Baleiro]
```

Ves a diferenza?
- Con `Any`, o compilador non sabe se na lista hai enteiros, cadeas ou unha cafeteira conectada por USB.
- Con `[ValorCela]`, podes mesturar números e textos na mesma lista, **pero o compilador sabe ao 100% que só existen esas tres posibilidades** e obrígate a desempaquetar cada caso (`Enteiro n`, `Texto s`, `Baleiro`) antes de usalo. Seguridade total sen perder nin un chisco de flexibilidade.

---

## 6.4. `Option` e `Result`: Cando algo pode non estar ou pode fallar

Como en Ridgun non existe `null` nin existen excepcións que salten polos aires (`throw new Exception()`), a linguaxe trae integrados dous tipos suma universais:

1. **`Option`**: ou tes **`Some valor`**, ou tes **`None`** (nada).
2. **`Result`**: ou a operación saíu ben (**`Ok valor`**), ou fallou por un motivo concreto (**`Err erro`**).

```ridgun
buscar_division Int Int => Result
buscar_division _   0   =  Err "Ei! Non se pode dividir por cero"
buscar_division a   b   =  Ok (a / b)

imprimir_res Result    => ()
imprimir_res (Ok n)    =  echo "O resultado é {n}"
imprimir_res (Err msg) =  echo "Fallo controlado: {msg}"
```

Ninguén pode ignorar un erro por descoido porque o propio tipo `Result` obrígate a mirar se dentro hai un `Ok` ou un `Err`.

---

## 6.5. Polimorfismo Paramétrico: Funcións xenéricas con `A`, `B`, `T`...

Supón que escribes unha función que inverte un par `(x, y)` ou que saca o primeiro elemento dunha lista. De verdade importa se a lista é de `Int`, de `String` ou de `Servidor`? Para nada! O algoritmo é idéntico.

En Ridgun, **calquera letra maiúscula individual (`A` a `Z`)** nunha sinatura de tipos funciona automaticamente como un **tipo comodín polimórfico (variable de tipo)**:

```ridgun
cabeza_segura [A]   A           => A
cabeza_segura []    por_defecto =  por_defecto
cabeza_segura (x:_) _           =  x

xirar_par (A, B) => (B, A)
xirar_par (x, y) =  (y, x)
```

Fíxate na maxia de `cabeza_segura [A] A => A`:
- Non é un `Any` descontrolado: di que **o tipo da lista `[A]`, o tipo do valor `por_defecto` (`A`) e o tipo devolto (`A`) teñen que ser o mesmo**.
- Se chamas a `cabeza_segura [10, 20] 0`, o compilador ata cabos (`A = Int`) e devólveche un `Int`.
- Se chamas a `cabeza_segura ["a", "b"] "ningun"`, ata cabos (`A = String`) e devólveche un `String`.
- Pero se intentas facer trampa e chamas a `cabeza_segura [10, 20] "ningun"`, zas! O compilador fréate en seco porque o primeiro argumento di que `A` é `Int` e o segundo di que `A` é `String`.

---

## 6.6. Crea os teus propios operadores (`op ::`): Desde vectores ata frases á medida

Por que só os números nativos ían ter dereito a usar `+` ou `*`? E por que conformarse cos operadores de sempre cando podes inventar a sintaxe perfecta para o teu problema?

Con **`op ::`** (ou directamente sen prefixo se usas patróns de operador) podes facer dúas virguerías:

### 1. Ensinarlle a `+`, `-`, `*`, `/`, `%` a operar cos teus propios tipos
```ridgun
type Complexo = real: Int, imax: Int

op :: Complexo + Complexo => Complexo
      a        + b        =  Complexo ((real a) + (real b)) ((imax a) + (imax b))
```

### 2. Crear operadores *Mixfix* (que se len coma frases naturais, incluídos `type` e `with`)
Nunha sinatura de operador, **as palabras con maiúscula inicial (`Int`, `String`, `A`..`Z`) ou entre corchetes/parénteses (`[Int]`, `(A, B)`) son os ocos para os argumentos**, e **as palabras en minúscula son parte da frase do operador** (mesmo palabras tan habituais como `type` ou `with`, que en Ridgun son contextuais e nunca te bloquean):

```ridgun
op :: se Bool enton A senon A => A
      se True enton v senon _ =  v
      se False enton _ senon f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  mensaxe = se (10 > 5) enton "Dez gaña!" senon "Imposible"
  echo mensaxe
  echo (format "panel" type "bordered" with 80)
```

Acabas de fabricar o teu propio operador ternario polimórfico e un DSL de formatado en **3 liñas** de Ridgun.

---

## 6.7. Construtores compartidos, variantes de tipo directo, `expand type` e espazos naturais en `fn ::`

Ridgun leva os tipos alxébricos e as funcións un paso máis alá en expresividade e extensibilidade:

1. **Construtores compartidos entre distintos `type`**: Varios tipos suma poden reutilizar o mesmo nome de construtor (`Error`, `Var`, `Lit`) con igual ou distinta aridade; o verificador de tipos distíngueos pola columna da sinatura.
2. **Variantes con nome de tipo directo (`type Something = String | Int | MyStruct Float Int`)**: Cando unha variante é un tipo primitivo (`String`, `Int`, `Float`/`Real`, `Bool`, `Char`), non precisas repetir `Int Int` nin `String String`. Podes pasar valores directos (`"ola"`, `42`) ou construtores explícitos (`String "ola"`, `Int 42`), e facer pattern matching tanto con literais (`"admin"`, `0`) como con patróns tipados (`(String s)`, `(Int n)`).
3. **Extensión aberta de tipos (`expand type`) e fusión automática de cláusulas `fn ::`**: Con `expand type` podes engadir novas variantes a un tipo suma ou novos campos a un rexistro. Ao volver declarar `fn ::` para a mesma función, as novas cláusulas fusiónanse automaticamente **antes** de calquera cláusula comodín `_` (sen necesidade de escribir `expand fn`).
4. **Espazos naturais `" "` en lugar de `_` en `fn ::`, funcións nativas e nomes de ficheiro**: Igual que en `op ::`, os nomes de función en `fn ::`, as chamadas a funcións nativas (`assert equals`, `str len`, `read file`) e os ficheiros `.rg` (`test core language.rg`) pódense escribir con espazos naturais:

```ridgun
type Something = String | Int | MyStruct Float Int

fn :: describir algo Something            => String
      describir algo "admin"              =  "admin_especial"
      describir algo 0                    =  "cero"
      describir algo (String   s)         =  "texto:{s}"
      describir algo (Int      n)         =  "enteiro:{n}"
      describir algo (MyStruct ratio cnt) =  "estrutura:{ratio}:{cnt}"
      describir algo _                    =  "outro"

expand type Something = Bool

fn :: describir algo Something => String
      describir algo (Bool b)  =  "booleano:{b}"
```

### 5. Tipos xenéricos propios (`type Result T E`, `type Page T`) e espazos de nomes de módulo (`import ... as`, `mod.Tipo`)
Ademais de funcións polimórficas, podes declarar **os teus propios tipos suma e rexistros xenéricos** con parámetros de tipo (`A`..`Z`), así como organizar tipos co mesmo nome en distintos módulos sen colisión (`module ::`, `import db as d`, `http.Config`, `d.Config`):

```ridgun
type Resultado T E = Exito T | Fallo E
type Paxina T      = elementos: [T], total: Int

fn :: desempaquetar exito (Resultado A String) A => A
      desempaquetar exito (Exito v)            _ =  v
      desempaquetar exito (Fallo _)            d =  d
```

No **Capítulo 07** imos poñer todos os núcleos do teu procesador a traballar á vez sen derramar unha pinga de suor: **funcións de orde superior (`map`, `||map`, `filter`, `||filter`, `fold`), clausuras léxicas (`(x => expr)`), grafos paralelos `||` con `->` e canles concorrentes**.
