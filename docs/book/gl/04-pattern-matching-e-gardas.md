# Capítulo 04: Adeus ao `if/else`, adeus ao `while` (Pattern Matching, Gardas e TCO)

Cando lle contas a alguén que en Ridgun **non existe a palabra chave `if`, nin `else`, nin `switch`, nin `for`, nin `while`**, adoita mirarte coma se lle dixeses que vas construír unha casa sen martelo nin cravos:

> *"Que non hai `if` nin `while`? E como demo tomo unha decisión ou percorro un millón de datos?"*

Pois resulta que `if/else` e `while` son ferramentas bastante toscas herdadas de como funcionaban os saltos (`GOTO`) nos anos 50. En Ridgun substituímolos por tres pezas que encaixan coma unha luva:
1. ***Pattern Matching*** (cando decides segundo a **forma ou valor exacto** do dato).
2. **Gardas booleanas `|`** (cando decides segundo unha **condición ou rango**).
3. **Recursión de cola con TCO** (que o compilador converte por baixo nun bucle `loop` nativo ultrarrápido).

Imos velas en acción.

---

## 4.1. *Pattern Matching*: Cando o argumento xa che dá a resposta

No capítulo anterior xa vimos un adianto. En lugar de recibir unha variable xenérica `x` e abrir dentro da función cinco `if (x == ...)`, en Ridgun pos os casos directamente na porta de entrada da función:

```ridgun
codigo_http Int => String
codigo_http 200 =  "OK: Todo foi sobre rodas"
codigo_http 301 =  "Movido permanentemente"
codigo_http 404 =  "Non atopado (miraches debaixo do sofá?)"
codigo_http 500 =  "Lume no servidor"
codigo_http n   =  "Código descoñecido: {n}"
```

Ridgun proba as filas **de arriba abaixo**:
- Se entra `404`, salta directo á terceira fila.
- Se entra `418`, ningunha das catro primeiras filas coincide, así que cae na última (`n`), que atrapa calquera enteiro e o nomea `n` para que poidas imprimilo.
- E se no último caso nin sequera che importa que número era? Pos un guión baixo `_` (*comodín*) e esquéceste: `codigo_http _ = "Outro código"`.

---

## 4.2. Gardas booleanas (`|`): O teu bisturí para rangos, variables condicionais e árbores de decisión

*"Vale, o pattern matching mola cando busco o `200` ou o `404`. Pero que fago se quero comprobar se `nota >= 5` ou se `idade > 18 and idade < 65`? Non vou escribir 47 filas con todos os números do 18 ao 65!"*

Claro que non! Para iso están as **gardas (`|`)**.

Cando o resultado depende dunha desigualdade ou dunha combinación lóxica, despois do `=` da función (ou de calquera variable local) abres unha escaleira de barras verticais `|`:

```ridgun
cualificar Int  => String
cualificar nota =
  | nota < 0   = "Nota imposible (puntos negativos?)"
  | nota < 5   = "Suspenso"
  | nota < 7   = "Aprobado"
  | nota < 9   = "Notable"
  | nota <= 10 = "Sobresaliente"
  | otherwise  = "Pasácheste da escala"
```

Mírao ben:
- O signo `=` da cabeceira (`cualificar nota =`) alíñase debaixo de `=>` igual ca en calquera outra función.
- Debaixo lese de arriba abaixo igual ca unha táboa de tarifas: cada liña `| condicion = resultado` compróbase en orde. En canto unha dá `True`, devolve ese resultado e rematou.
- Ao final pos **`| otherwise = ...`**, que significa literalmente *"en calquera outro caso"* (a túa rede de seguridade para que nunca quede un camiño sen retorno).

### Lóxica booleana en minúsculas claras (`and`, `or`, `xor`, `not`)
Fixácheste en que moitas linguaxes usan `|` para bits, `||` para booleanos, `!` para negar... e cando les unha condición complexa parece que un gato camiñou sobre o teclado (`if (!a && (b || c))`)?

En Ridgun, como `|` xa é o símbolo sagrado das gardas e dos tipos alxébricos, e `||` é o operador de paralelismo, **os operadores booleanos escríbense con palabras claras en minúsculas**:

- **`and`**: cúmprense as dúas cousas (`idade >= 18 and ten_carne`).
- **`or`**: cúmprese polo menos unha (`dia == "sabado" or dia == "domingo"`).
- **`xor`**: cúmprese unha ou outra, pero non as dúas á vez.
- **`not`**: inverte o booleano (`not (esta_baleiro texto)`).

Mira que limpo queda o clásico problema dos anos bisestos:

```ridgun
e_bisesto Int => Bool
e_bisesto a   =
  | (a % 400) == 0                  = True
  | (a % 4) == 0 and (a % 100) != 0 = True
  | otherwise                       = False
```

Cero símbolos crípticos. Leo alguén que non sabe Ridgun e enténdeo á primeira.

### Variables locais condicionais (`x =` + `|`)
Como en Ridgun todo `=` segue a mesma regra, **tamén podes usar `|` para asignar unha variable local** sen ter que crear unha función auxiliar á parte:

```ridgun
prezo_billete Int  Bool                => Int
prezo_billete base e_familia_numerosa  =
  desconto =
    | e_familia_numerosa = 20
    | base > 100         = 10
    | otherwise          = 0
  base - (base * desconto / 100)
```

### Árbores de decisión aniñadas e o limitador compacto `|.`
*"E se dentro dunha rama `| cond =` ou `| otherwise =` quero abrir outra sub-árbore de gardas `|` de 3 ou 4 niveis de profundidade e logo volver a un nivel superior?"*

Podes aniñar `|` dentro de `|` tantos niveis como queiras. E cando un bloque `|` aniñado remata pero debaixo seguen máis ramas dun nivel pai (ou máis sentenzas do bloque), colocas **`|.`** ao final da súa última liña (`| otherwise = valor |.`) para indicar sen ningunha ambigüidade que esa sub-árbore se pecha e volves ao nivel anterior:

```ridgun
encaminar_peticion Int    Int Bool     Bool    Int       Int      => Int
encaminar_peticion metodo rol asinada  e_admin tamano_kb limitado =
  | metodo == 0 =
    | tamano_kb == 0 = 204
    | otherwise      = 200 |.
  | metodo == 1 =
    | not asinada = 401
    | otherwise =
      -- Nivel 2: petición POST asinada
      | limitado > 0 =
        -- Nivel 3: control de rate-limit
        | e_admin =
          -- Nivel 4: excepción para administradores
          | tamano_kb > 10000 = 413
          | otherwise         = 202 |.
        | otherwise = 429 |.
      | tamano_kb > 1000 =
        -- Nivel 3: volvemos desde o Nivel 4 grazas a `|.`
        | rol >= 2 and e_admin = 201
        | otherwise            = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Fíxate no limpo que é:
- Nunha árbore simple de 1 nivel (ou ao final de toda a función) **nunca fai falta poñer `|.`** (sería ruído innecesario).
- Só escribes `|.` ao pechar unha rama aniñada cando debaixo continúa unha rama dun nivel superior.

### Bloques de varias liñas dentro dunha garda (`| cond =` + bloque sangrado)
Igual que despois do `=` dunha función normal podes abrir un bloque sangrado de varias liñas, **despois do `=` de calquera garda `| cond =` ou `| otherwise =` tamén podes facer un salto de liña e abrir un bloque secuencial**:

```ridgun
axustar_fiestra Int Int    => Int
axustar_fiestra idx limite =
  | idx >= limite =
      tope = limite - 1
      escalado = tope * 2
      escalado + 10
  | otherwise =
      seguinte = idx + 1
      seguinte * 2
```

Cada rama da garda ten o seu propio bloque local limpo e a súa última liña é o valor que devolve esa rama.

---

## 4.3. "Sen `while`? E non vai rebentar a pila se percorro un ficheiro grande?"

Falemos do elefante na sala.

Se vés de Python, Java ou JavaScript, ensináronche desde pequeniño que *"a recursión é elegante no encerado da universidade, pero no mundo real desborda a pila (`StackOverflowError`) ás 1.000 voltas; usa un bucle `while`"*.

Iso é verdade en linguaxes que **non** optimizan as chamadas de cola. Pero nunha linguaxe funcional de sistemas como Ridgun, **unha recursión de cola É un bucle `while` disfrazado de función pura**.

### Que diferenza hai entre unha recursión normal e unha recursión de cola?
Fíxate nestas dúas funcións que contan cara a atrás desde `n` ata `0` sumando os números:

```ridgun
-- Versión A: Recursión NORMAL (deixa traballo pendente para a volta)
sumar_lento Int => Int
sumar_lento 0   =  0
sumar_lento n   =  n + (sumar_lento (n - 1))

-- Versión B: Recursión DE COLA (leva a conta ao día en `acumulado`)
sumar_rapido_loop Int Int       => Int
sumar_rapido_loop 0   acumulado =  acumulado
sumar_rapido_loop n   acumulado =  sumar_rapido_loop (n - 1) (acumulado + n)
```

- Na **Versión A**, antes de poder sumar `n + ...`, a función ten que agardar a que remate `sumar_lento (n - 1)`. Iso obriga ao ordenador a gardar `n` na pila en cada paso.
- Na **Versión B**, a chamada a `sumar_rapido_loop` **é o último que ocorre na liña**. Non queda nada pendente detrás dela. Xa lle pasas a suma actualizada en `acumulado + n`.

### O truco de maxia de `ridgunc` (TCO: *Tail-Call Optimization*)
Cando `ridgunc` compila `sumar_rapido_loop`, ve que a función se chama a si mesma ao final da cláusula e di:

> *"Para que vou crear un marco de pila novo se o actual xa non serve para nada? Vou sobrescribir `n` con `n - 1`, sobrescribir `acumulado` con `acumulado + n` e saltar ao principio cun `loop { ... continue; }` nativo."*

Resultado:
1. Podes chamar a `sumar_rapido_loop 100_000_000 0` (cen millóns de voltas) e **gastará exactamente 0 bytes extra de pila**.
2. Vai igual de rápido ca un bucle `while` escrito á man en Rust ou C, pero sen ter que declarar nin unha soa variable mutable no teu código Ridgun.

---

## 4.4. O patrón mestre que usarás en todo programa Ridgun

Cada vez que noutra linguaxe pensarías *"vou facer un bucle `while` cun índice `i` e un acumulador"*, en Ridgun escribes unha parella de funcións coma esta (a función principal limpa e a súa axudante `_loop` de cola):

```ridgun
buscar_caracter_loop String Int Int Int     => Int
buscar_caracter_loop texto  pos fin buscado =
  | pos >= fin                         = -1
  | (str_char_at texto pos) == buscado = pos
  | otherwise                          = buscar_caracter_loop texto (pos + 1) fin buscado

buscar_caracter String Int     => Int
buscar_caracter texto  buscado =  buscar_caracter_loop texto 0 (str_len texto) buscado
```

Mira as tres gardas de `buscar_caracter_loop`:
1. Cheguei ao final (`pos >= fin`)? Devolvo `-1` (fin do bucle).
2. Atopei o carácter en `pos`? Devolvo `pos` (fin do bucle).
3. Non é este? Paso ao seguinte (`pos + 1`) cunha chamada de cola (que o compilador converte en `continue;`).

Limpo, imposible de ter *bugs* de variables globais pisadas e rápido coma un raio.

No **Capítulo 05** ímoslle meter man ás coleccións de datos: **listas, tuplas, funcións que aceptan infinitos argumentos (`...`) e as máscaras de secuencias estilo J/APL**.
