# Capítulo 04: Adeus ao `if/else`, adeus ao `while` (Pattern Matching, Guardas e TCO)

Quando conta a alguém que em Ridgun **não existe a palavra-chave `if`, nem `else`, nem `switch`, nem `for`, nem `while`**, a pessoa costuma olhar para si como se lhe tivesse dito que vai construir uma casa sem martelo nem pregos:

> *"Como assim não há `if` nem `while`? E como raio tomo uma decisão ou percorro um milhão de dados?"*

Pois acontece que `if/else` e `while` são ferramentas bastante toscas herdadas de como funcionavam os saltos (`GOTO`) nos anos 50. Em Ridgun substituímo-los por três peças que encaixam como uma luva:
1. ***Pattern Matching*** (quando decide segundo a **forma ou valor exato** do dado).
2. **Guardas booleanas `|`** (quando decide segundo uma **condição ou intervalo**).
3. **Recursão de cauda com TCO** (que o compilador converte por baixo num ciclo `loop` nativo ultrarrápido).

Vamos vê-las em ação.

---

## 4.1. *Pattern Matching*: Quando o argumento já lhe dá a resposta

No capítulo anterior já vimos uma amostra. Em vez de receber uma variável genérica `x` e abrir dentro da função cinco `if (x == ...)`, em Ridgun coloca os casos diretamente à porta de entrada da função:

```ridgun
codigo_http Int => String
codigo_http 200 =  "OK: Tudo correu sobre rodas"
codigo_http 301 =  "Movido permanentemente"
codigo_http 404 =  "Não encontrado (já procuraste debaixo do sofá?)"
codigo_http 500 =  "Fogo no servidor"
codigo_http n   =  "Código desconhecido: {n}"
```

O Ridgun testa as linhas **de cima para baixo**:
- Se entrar `404`, salta direto para a terceira linha.
- Se entrar `418`, nenhuma das quatro primeiras linhas coincide, pelo que cai na última (`n`), que apanha qualquer inteiro e lhe dá o nome `n` para que o possa imprimir.
- E se no último caso nem sequer lhe importar que número era? Põe um sublinhado `_` (*wildcard*) e esquece: `codigo_http _ = "Outro código"`.

---

## 4.2. Guardas booleanas (`|`): O seu bisturi para intervalos, variáveis condicionais e árvores de decisão

*"Certo, o pattern matching é ótimo quando procuro o `200` ou o `404`. Mas o que faço se quiser verificar se `nota >= 5` ou se `idade > 18 and idade < 65`? Não vou escrever 47 linhas com todos os números de 18 a 65!"*

Claro que não! Para isso existem as **guardas (`|`)**.

Quando o resultado depende de uma desigualdade ou de uma combinação lógica, depois do `=` da função (ou de qualquer variável local) abre uma escada de barras verticais `|`:

```ridgun
classificar Int  => String
classificar nota =
  | nota < 0   = "Nota impossível (pontos negativos?)"
  | nota < 5   = "Reprovado"
  | nota < 7   = "Suficiente"
  | nota < 9   = "Bom"
  | nota <= 10 = "Excelente"
  | otherwise  = "Ultrapassaste a escala"
```

Repare bem:
- O sinal `=` do cabeçalho (`classificar nota =`) alinha-se debaixo de `=>` tal como em qualquer outra função.
- Por baixo lê-se de cima para baixo tal como uma tabela de preços: cada linha `| condicao = resultado` é verificada por ordem. Assim que uma dá `True`, devolve esse resultado e acabou.
- No final põe **`| otherwise = ...`**, que significa literalmente *"em qualquer outro caso"* (a sua rede de segurança para que nunca fique um caminho sem retorno).

### Lógica booleana em minúsculas claras (`and`, `or`, `xor`, `not`)
Já reparou que muitas linguagens usam `|` para bits, `||` para booleanos, `!` para negar... e quando lê uma condição complexa parece que um gato caminhou sobre o teclado (`if (!a && (b || c))`)?

Em Ridgun, como `|` já é o símbolo sagrado das guardas e dos tipos algébricos, e `||` é o operador de paralelismo, **os operadores booleanos escrevem-se com palavras claras em minúsculas**:

- **`and`**: cumprem-se as duas coisas (`idade >= 18 and tem_carta`).
- **`or`**: cumpre-se pelo menos uma (`dia == "sabado" or dia == "domingo"`).
- **`xor`**: cumpre-se uma ou outra, mas não as duas ao mesmo tempo.
- **`not`**: inverte o booleano (`not (esta_vazio texto)`).

Veja como fica limpo o clássico problema dos anos bissextos:

```ridgun
e_bissexto Int => Bool
e_bissexto a =
  | (a % 400) == 0                  = True
  | (a % 4) == 0 and (a % 100) != 0 = True
  | otherwise                       = False
```

Zero símbolos crípticos. Alguém que não conhece Ridgun lê isto e entende à primeira.

### Variáveis locais condicionais (`x =` + `|`)
Como em Ridgun todo o `=` segue a mesma regra, **também pode usar `|` para atribuir uma variável local** sem ter de criar uma função auxiliar à parte:

```ridgun
preco_bilhete Int  Bool               => Int
preco_bilhete base e_familia_numerosa =
  desconto =
    | e_familia_numerosa = 20
    | base > 100         = 10
    | otherwise          = 0
  base - (base * desconto / 100)
```

### Árvores de decisão aninhadas e o delimitador compacto `|.`
*"E se dentro de um ramo `| cond =` ou `| otherwise =` eu quiser abrir outra subárvore de guardas `|` de 3 ou 4 níveis de profundidade e depois voltar a um nível superior?"*

Pode aninhar `|` dentro de `|` tantos níveis quantos quiser. E quando um bloco `|` aninhado termina mas por baixo continuam mais ramos de um nível pai (ou mais instruções do bloco), coloca **`|.`** no final da sua última linha (`| otherwise = valor |.`) para indicar sem qualquer ambiguidade que essa subárvore fecha e volta ao nível anterior:

```ridgun
encaminhar_pedido Int    Int   Bool     Bool    Int        Int      => Int
encaminhar_pedido metodo papel assinado e_admin tamanho_kb limitado =
  | metodo == 0 =
    | tamanho_kb == 0 = 204
    | otherwise       = 200 |.
  | metodo == 1 =
    | not assinado = 401
    | otherwise =
      -- Nível 2: pedido POST assinado
      | limitado > 0 =
        -- Nível 3: controlo de rate-limit
        | e_admin =
          -- Nível 4: exceção para administradores
          | tamanho_kb > 10000 = 413
          | otherwise          = 202 |.
        | otherwise = 429 |.
      | tamanho_kb > 1000 =
        -- Nível 3: voltámos do Nível 4 graças a `|.`
        | papel >= 2 and e_admin = 201
        | otherwise              = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Repare como é limpo:
- Numa árvore simples de 1 nível (ou no final de toda a função) **nunca é preciso pôr `|.`** (seria ruído desnecessário).
- Só escreve `|.` ao fechar um ramo aninhado quando por baixo continua um ramo de um nível superior.

### Blocos de várias linhas dentro de uma guarda (`| cond =` + bloco indentado)
Tal como depois do `=` de uma função normal pode abrir um bloco indentado de várias linhas, **depois do `=` de qualquer guarda `| cond =` ou `| otherwise =` também pode fazer uma quebra de linha e abrir um bloco sequencial**:

```ridgun
ajustar_janela Int Int    => Int
ajustar_janela idx limite =
  | idx >= limite =
      topo = limite - 1
      escalado = topo * 2
      escalado + 10
  | otherwise =
      seguinte = idx + 1
      seguinte * 2
```

Cada ramo da guarda tem o seu próprio bloco local limpo e a sua última linha é o valor que esse ramo devolve.

---

## 4.3. "Sem `while`? E não vai rebentar a pilha se eu percorrer um ficheiro grande?"

Falemos do elefante na sala.

Se vem de Python, Java ou JavaScript, ensinaram-lhe desde pequenino que *"a recursão é elegante no quadro da universidade, mas no mundo real transborda a pilha (`StackOverflowError`) às 1.000 voltas; use um ciclo `while`"*.

Isso é verdade em linguagens que **não** otimizam as chamadas de cauda. Mas numa linguagem funcional de sistemas como o Ridgun, **uma recursão de cauda É um ciclo `while` disfarçado de função pura**.

### Que diferença há entre uma recursão normal e uma recursão de cauda?
Repare nestas duas funções que contam para trás desde `n` até `0` somando os números:

```ridgun
-- Versão A: Recursão NORMAL (deixa trabalho pendente para o regresso)
somar_lento Int => Int
somar_lento 0   =  0
somar_lento n   =  n + (somar_lento (n - 1))

-- Versão B: Recursão DE CAUDA (leva a conta em dia em `acumulado`)
somar_rapido_loop Int Int       => Int
somar_rapido_loop 0   acumulado =  acumulado
somar_rapido_loop n   acumulado =  somar_rapido_loop (n - 1) (acumulado + n)
```

- Na **Versão A**, antes de poder somar `n + ...`, a função tem de esperar que termine `somar_lento (n - 1)`. Isso obriga o computador a guardar `n` na pilha em cada passo.
- Na **Versão B**, a chamada a `somar_rapido_loop` **é a última coisa que acontece na linha**. Não fica nada pendente atrás dela. Já lhe passa a soma atualizada em `acumulado + n`.

### O truque de magia do `ridgunc` (TCO: *Tail-Call Optimization*)
Quando o `ridgunc` compila `somar_rapido_loop`, vê que a função se chama a si mesma no final da cláusula e diz:

> *"Para que vou criar um novo registo de pilha se o atual já não serve para nada? Vou sobrescrever `n` com `n - 1`, sobrescrever `acumulado` com `acumulado + n` e saltar para o princípio com um `loop { ... continue; }` nativo."*

Resultado:
1. Pode chamar `somar_rapido_loop 100_000_000 0` (cem milhões de voltas) e **gastará exatamente 0 bytes extra de pilha**.
2. É tão rápido quanto um ciclo `while` escrito à mão em Rust ou C, mas sem ter tido de declarar uma única variável mutável no seu código Ridgun.

---

## 4.4. O padrão mestre que usará em todo o programa Ridgun

Sempre que noutra linguagem pensaria *"vou fazer um ciclo `while` com um índice `i` e um acumulador"*, em Ridgun escreve um par de funções como este (a função principal limpa e a sua ajudante `_loop` de cauda):

```ridgun
procurar_caracter_loop String Int Int Int       => Int
procurar_caracter_loop texto  pos fim procurado =
  | pos >= fim                           = -1
  | (str_char_at texto pos) == procurado = pos
  | otherwise                            = procurar_caracter_loop texto (pos + 1) fim procurado

procurar_caracter String Int       => Int
procurar_caracter texto  procurado =  procurar_caracter_loop texto 0 (str_len texto) procurado
```

Repare nas três guardas de `procurar_caracter_loop`:
1. Cheguei ao fim (`pos >= fim`)? Devolvo `-1` (fim do ciclo).
2. Encontrei o carácter em `pos`? Devolvo `pos` (fim do ciclo).
3. Não é este? Passo ao seguinte (`pos + 1`) com uma chamada de cauda (que o compilador converte em `continue;`).

Limpo, impossível de ter *bugs* de variáveis globais atropeladas e rápido como um raio.

No **Capítulo 05** vamos pôr as mãos na massa com as coleções de dados: **listas, tuplas, funções que aceitam infinitos argumentos (`...`) e as máscaras de sequências ao estilo J/APL**.
