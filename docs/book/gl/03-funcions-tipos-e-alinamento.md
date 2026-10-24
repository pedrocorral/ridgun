# Capítulo 03: Funcións, sinaturas de tipos e a arte de escribir código coma unha táboa

Hai unha pregunta que todo programador se fai a primeira vez que ve código funcional:

> *"Se aquí non hai clases, nin obxectos, nin variables que mudan de valor... entón onde meto a miña lóxica?"*

En **funcións**. Pero non nesas funcións de 200 liñas cheas de bandeiras booleanas que todos sufrimos algunha vez, senón en funcións pequenas, directas e tan fáciles de ler que parecen unha táboa nun encerado.

Imos ver como se constrúen.

---

## 3.1. Dúas formas de presentar unha función (Ti escolles o traxe)

En Ridgun toda función comeza coa súa **sinatura de tipos** (que entra e que sae tras `=>`) e debaixo van as súas **cláusulas de implementación** (con `=`).

Podes escribir a cabeceira de dúas maneiras:

### Opción A: Directa ao gran (sen prefixo)
```ridgun
aplicar_desconto Int   Int         => Int
aplicar_desconto prezo porcentaxe  =  prezo - (prezo * porcentaxe / 100)
```

### Opción B: Con etiqueta explícita (`fn ::`)
```ridgun
fn :: aplicar_desconto Int   Int         => Int
      aplicar_desconto prezo porcentaxe  =  prezo - (prezo * porcentaxe / 100)
```

*"Ouve, e por que existen as dúas?"*
Porque para gustos, as cores:
- Hai quen prefire que as funcións comecen pegadas á marxe esquerda sen escribir `fn ::` cada vez (ao fin e ao cabo, a frecha `=>` xa berra aos catro ventos que esa liña é unha sinatura de tipos).
- E hai quen prefire ter unha columna esquerda dedicada ás etiquetas (`fn ::`, `op ::`, `type`, `import`) para escanear o ficheiro visualmente.

O compilador e `stable format` entenden ambas á perfección. Ademais, as palabras `fn` e `op` poden usarse libremente como parte do nome de calquera función ou operador (por exemplo `fn :: op`, `op :: fn` ou `op :: op`), e se unha función devolve múltiples valores, en modo canónico/estrito os tipos de saída escríbense separados por espazos tras `=>` (`dividir_con_resto Int Int => Int Int`).

---

## 3.2. A maxia das columnas: por que os teus ollos descansan

Mira esta función que calcula o custo dun envío segundo o país e se é urxente:

```ridgun
custo_envio String    Bool  Int  => Int
custo_envio "ES"      False _    =  5
custo_envio "ES"      True  _    =  12
custo_envio _         False peso =  10 + (peso * 2)
custo_envio _         True  peso =  25 + (peso * 4)
```

Fai a proba: tapa a metade dereita da pantalla e mira só as tres columnas de entrada:
- Primeira columna (`String`): `"ES"`, `"ES"`, `_`, `_`.
- Segunda columna (`Bool`): `False`, `True`, `False`, `True`.
- Terceira columna (`Int`): `_`, `_`, `peso`, `peso`.

Ves algún burato lóxico? Ningún: están as 4 combinacións posibles diante dos teus fociños, aliñadas verticalmente debaixo de `String`, `Bool` e `Int`. Nun bloque de `if / else` tradicional terías que ler 18 liñas para estar seguro de que non deixaches ningún caso solto.

---

## 3.3. Os tipos básicos e un agasallo para non contar ceros (`_KB`, `_MB`, `_GB`)

Os tipos escalares de Ridgun son directos e sen sorpresas:

| Tipo | Que é en realidade | Exemplos |
|---|---|---|
| `Int` | Enteiro de 64 bits con signo (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `U64` | Enteiro de 64 bits sen signo (`u64`) con aritmética modular e bit a bit nativa | `u64 0`, `u64 0x6a09e667f3bcc908`, `a ^ b`, `a << u64 13` |
| `Float` / `Real` | Decimal de dobre precisión (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Cadea de texto inmutable | `"Ola"`, `'ruta\crua'` |
| `Char` | Código de carácter | Devolto por `str_char_at` |
| `Bool` | Booleano de toda a vida | `True`, `False` |
| `()` | Baleiro (*Unit*, cando só imprimes ou fas E/S) | `()` |

### Canso de escribir `65536` ou `1048576` e rezar para non comer un díxito?
En Ridgun os literais numéricos aceptan directamente os sufixos **`_KB`**, **`_MB`** e **`_GB`**, ademais de guións baixos `_` para separar grupos de cifras:

```ridgun
tamano_buffer => Int
tamano_buffer =  64_KB      -- O compilador tradúceo a 65536

limite_ficheiro => Int
limite_ficheiro =  16_MB    -- O compilador tradúceo a 16777216

mascara_octeto => Int
mascara_octeto =  0xFF_00   -- Hexadecimal limpo e lexible
```

---

## 3.4. Comiñas dobres (`"..."`) vs. Comiñas simples (`'...'`)

En moitas linguaxes as comiñas simples e dobres fan exactamente o mesmo (un desperdicio). En Ridgun cada unha ten unha misión clarísima:

### 1. Comiñas dobres (`"..."`): Intelixentes e interpoladas
Interpretan escapes (`\n`, `\t`, `\"`, `\\`) e **avalían calquera variable ou expresión que metas entre chaves `{...}`**:

```ridgun
resumo_pedido String Int Int   => String
resumo_pedido item   uds prezo =
  "Pediches {uds}x {item}. Total a pagar: {uds * prezo} euros."
```

*(Truco: se precisas escribir unha chave literal dentro de comiñas dobres —por exemplo ao xerar un script de shell `"$\{VAR:-default\}"` ou un JSON—, podes escapala con barra invertida `\{` e `\}` ou duplicala `{{` e `}}`).*

### 2. Comiñas simples (`'...'`): Crúas e literais (*Raw Strings*)
O que escribes entre comiñas simples sae **tal cal**, sen tocar nin unha barra invertida `\`, nin unha chave `{}`. Perfecto para cando xeras código noutra linguaxe, escribes comandos de shell ou traballas con rutas cheas de barras:

```ridgun
comando_sed => String
comando_sed =  's/\([0-9]+\)/[\1]/g'
```

### A túa caixa de ferramentas para cadeas (`String`)
Unir cadeas é tan simple como sumalas con `+`: `"Ola, " + nome`. E cando precisas facer cirurxía fina sobre un texto, tes estas funcións nativas listas sen importar nada:

- `str_len s` $\rightarrow$ lonxitude de `s`.
- `str_char_at s i` $\rightarrow$ código numérico (`Int`) do carácter na posición `i` (`-1` se saes fóra).
- `str_slice s inicio fin` $\rightarrow$ recorta desde `inicio` ata `fin` (sen incluír `fin`).
- `char_from_code c` $\rightarrow$ converte un código numérico (`Int`, p. ex. `10` para `\n` ou `34` para `"`) nun `String` de 1 carácter.
- `str_contains s agulla` e `str_starts_with s prefixo` $\rightarrow$ devolven `True` ou `False`.
- `int_to_str n` e `str_to_int s` $\rightarrow$ converten de número a texto e viceversa (`str_to_int` entende mesmo `"0xFF"`!).

---

## 3.5. Bloques de varias liñas, a regra universal do `=` e variables `mut`

Cando unha función non cabe nunha soa liña, fas un salto de liña despois do `=` e sangras o bloque.

Mira como se le un bloque paso a paso:

```ridgun
calcular_factura Int  Int     => Int
calcular_factura base ive_pct =
  impostos = base * ive_pct / 100
  gastos_xestion = 5
  echo "Desagregación -> Base:" base "Impostos:" impostos
  base + impostos + gastos_xestion
```

Catro regras de ouro que fan que os bloques en Ridgun sexan limpos e uniformes:
1. **Inmutable por defecto sen `let` nin `const`**: escribes `impostos = ...` e xa tes a túa constante local inmutable. Se por descoido intentas sobrescribir `impostos = 99` máis abaixo no mesmo bloque, o compilador fréate en seco.
2. **Variables mutables explícitas con `mut`**: cando de verdade queres ir actualizando un acumulador local paso a paso dentro dunha función, decláralo con **`mut`** e logo reasígnalo libremente con `=`:
   ```ridgun
   aplicar_recargos Int   => Int
   aplicar_recargos prezo =
     mut total = prezo
     total = total + 10
     total = total * 2
     total
   ```
   *(E se `total` garda unha lista ou estrutura en memoria, a política **`RMM2`** de Ridgun suma `+1` ao novo valor antes de descontar `-1` ao antigo, liberándoo ao instante se ninguén máis o usa).*
3. **A regra universal do `=`**: detrás de **calquera `=`** (nunha función, nun operador, nunha variable local `x =` ou nunha rama condicional) podes poñer sempre calquera das tres formas de bloque de Ridgun:
   - **`(nada)`**: liñas secuenciais sangradas (como arriba).
   - **`|`**: unha árbore de gardas condicionais.
   - **`||`**: un grafo de cálculos en paralelo con `->`.
4. **A última expresión é sempre o resultado**: `base + impostos + gastos_xestion` é o que devolve `calcular_factura`. Sen `return`.

No **Capítulo 04** imos ver como tomar decisións complexas —incluíndo árbores de decisión de varios niveis con `|.`— sen escribir xamais un `if/else` nin un bucle `while`: benvido ao mundo das **gardas booleanas** e a **recursión de cola de custo cero**.
