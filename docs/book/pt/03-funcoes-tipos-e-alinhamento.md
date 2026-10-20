# Capítulo 03: Funções, assinaturas de tipos e a arte de escrever código como uma tabela

Há uma pergunta que todo o programador faz na primeira vez que vê código funcional:

> *"Se aqui não há classes, nem objetos, nem variáveis que mudam de valor... então onde é que eu meto a minha lógica?"*

Em **funções**. Mas não nessas funções de 200 linhas cheias de bandeiras booleanas que todos já sofremos alguma vez, e sim em funções pequenas, diretas e tão fáceis de ler que parecem uma tabela num quadro.

Vamos ver como se constroem.

---

## 3.1. Duas formas de apresentar uma função (Você escolhe o fato)

Em Ridgun toda a função começa com a sua **assinatura de tipos** (o que entra e o que sai após `=>`) e por baixo vão as suas **cláusulas de implementação** (com `=`).

Pode escrever o cabeçalho de duas maneiras:

### Opção A: Direta ao assunto (sem prefixo)
```ridgun
aplicar_desconto Int   Int         => Int
aplicar_desconto preco percentagem =  preco - (preco * percentagem / 100)
```

### Opção B: Com etiqueta explícita (`fn ::`)
```ridgun
fn :: aplicar_desconto Int   Int         => Int
      aplicar_desconto preco percentagem =  preco - (preco * percentagem / 100)
```

*"Olha lá, e porque é que existem as duas?"*
Porque gostos não se discutem:
- Há quem prefira que as funções comecem encostadas à margem esquerda sem escrever `fn ::` de cada vez (afinal de contas, a seta `=>` já grita aos quatro ventos que essa linha é uma assinatura de tipos).
- E há quem prefira ter uma coluna esquerda dedicada às etiquetas (`fn ::`, `op ::`, `type`, `import`) para percorrer o ficheiro visualmente.

O compilador e o `stable format` entendem ambas na perfeição.

---

## 3.2. A magia das colunas: porque é que os seus olhos descansam

Veja esta função que calcula o custo de um envio segundo o país e se é urgente:

```ridgun
custo_envio String Bool  Int  => Int
custo_envio "PT"   False _    =  5
custo_envio "PT"   True  _    =  12
custo_envio _      False peso =  10 + (peso * 2)
custo_envio _      True  peso =  25 + (peso * 4)
```

Faça o teste: tape a metade direita do ecrã e olhe apenas para as três colunas de entrada:
- Primeira coluna (`String`): `"PT"`, `"PT"`, `_`, `_`.
- Segunda coluna (`Bool`): `False`, `True`, `False`, `True`.
- Terceira coluna (`Int`): `_`, `_`, `peso`, `peso`.

Vê algum buraco lógico? Nenhum: estão as 4 combinações possíveis mesmo à frente dos seus olhos, alinhadas verticalmente debaixo de `String`, `Bool` e `Int`. Num bloco de `if / else` tradicional teria de ler 18 linhas para ter a certeza de que não deixou nenhum caso solto.

---

## 3.3. Os tipos básicos e um presente para não contar zeros (`_KB`, `_MB`, `_GB`)

Os tipos escalares do Ridgun são diretos e sem surpresas:

| Tipo | O que é na realidade | Exemplos |
|---|---|---|
| `Int` | Inteiro de 64 bits com sinal (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `Real` | Decimal de precisão dupla (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Cadeia de texto imutável | `"Olá"`, `'caminho\bruto'` |
| `Char` | Código de carácter | Devolvido por `str_char_at` |
| `Bool` | Booleano clássico | `True`, `False` |
| `()` | Vazio (*Unit*, quando só imprime ou faz I/O) | `()` |

### Cansado de escrever `65536` ou `1048576` e rezar para não ter engolido um dígito?
Em Ridgun os literais numéricos aceitam diretamente os sufixos **`_KB`**, **`_MB`** e **`_GB`**, além de sublinhados `_` para separar grupos de algarismos:

```ridgun
tamanho_buffer => Int
tamanho_buffer =  64_KB      -- O compilador traduz para 65536

limite_ficheiro => Int
limite_ficheiro =  16_MB     -- O compilador traduz para 16777216

mascara_octeto => Int
mascara_octeto =  0xFF_00    -- Hexadecimal limpo e legível
```

---

## 3.4. Aspas duplas (`"..."`) vs. Aspas simples (`'...'`)

Em muitas linguagens as aspas simples e duplas fazem exatamente o mesmo (um desperdício). Em Ridgun cada uma tem uma missão claríssima:

### 1. Aspas duplas (`"..."`): Inteligentes e interpoladas
Interpretam escapes (`\n`, `\t`, `\"`, `\\`) e **avaliam qualquer variável ou expressão que coloque entre chavetas `{...}`**:

```ridgun
resumo_encomenda String Int Int   => String
resumo_encomenda item   un  preco =
  "Encomendaste {un}x {item}. Total a pagar: {un * preco} euros."
```

*(Truque: se precisar de escrever uma chaveta literal dentro de aspas duplas — por exemplo ao gerar um script de shell `"$\{VAR:-default\}"` ou um JSON —, pode escapá-la com barra invertida `\{` e `\}` ou duplicá-la `{{` e `}}`).*

### 2. Aspas simples (`'...'`): Brutas e literais (*Raw Strings*)
O que escreve entre aspas simples sai **tal e qual**, sem tocar numa única barra invertida `\`, nem numa chaveta `{}`. Perfeito para quando gera código noutra linguagem, escreve comandos de shell ou trabalha com caminhos cheios de barras:

```ridgun
comando_sed => String
comando_sed =  's/\([0-9]+\)/[\1]/g'
```

### A sua caixa de ferramentas para cadeias (`String`)
Unir cadeias é tão simples como somá-las com `+`: `"Olá, " + nome`. E quando precisa de fazer cirurgia fina sobre um texto, tem estas funções nativas prontas sem importar nada:

- `str_len s` $\rightarrow$ comprimento de `s`.
- `str_char_at s i` $\rightarrow$ código numérico (`Int`) do carácter na posição `i` (`-1` se sair fora dos limites).
- `str_slice s inicio fim` $\rightarrow$ recorta desde `inicio` até `fim` (sem incluir `fim`).
- `char_from_code c` $\rightarrow$ converte um código numérico (`Int`, p. ex. `10` para `\n` ou `34` para `"`) numa `String` de 1 carácter.
- `str_contains s agulha` e `str_starts_with s prefixo` $\rightarrow$ devolvem `True` ou `False`.
- `int_to_str n` e `str_to_int s` $\rightarrow$ convertem de número para texto e vice-versa (o `str_to_int` entende inclusive `"0xFF"`!).

---

## 3.5. Blocos de várias linhas, a regra universal do `=` e variáveis `mut`

Quando uma função não cabe numa única linha, faz uma quebra de linha depois do `=` e indenta o bloco.

Veja como se lê um bloco passo a passo:

```ridgun
calcular_fatura Int  Int     => Int
calcular_fatura base iva_pct =
  impostos = base * iva_pct / 100
  despesas_gestao = 5
  echo "Detalhe -> Base:" base "Impostos:" impostos
  base + impostos + despesas_gestao
```

Quatro regras de ouro que tornam os blocos em Ridgun limpos e uniformes:
1. **Imutável por omissão sem `let` nem `const`**: escreve `impostos = ...` e já tem a sua constante local imutável. Se por descuido tentar sobrescrever `impostos = 99` mais abaixo no mesmo bloco, o compilador trava-o a fundo.
2. **Variáveis mutáveis explícitas com `mut`**: quando realmente quer ir atualizando um acumulador local passo a passo dentro de uma função, declara-o com **`mut`** e depois reatribui-o livremente com `=`:
   ```ridgun
   aplicar_sobretaxas Int   => Int
   aplicar_sobretaxas preco =
     mut total = preco
     total = total + 10
     total = total * 2
     total
   ```
   *(E se `total` guardar uma lista ou estrutura em memória, a política **`RMM2`** do Ridgun soma `+1` ao novo valor antes de descontar `-1` ao antigo, libertando-o no instante se mais ninguém o usar).*
3. **A regra universal do `=`**: depois de **qualquer `=`** (numa função, num operador, numa variável local `x =` ou num ramo condicional) pode pôr sempre qualquer uma das três formas de bloco do Ridgun:
   - **`(nada)`**: linhas sequenciais indentadas (como acima).
   - **`|`**: uma árvore de guardas condicionais.
   - **`||`**: um grafo de cálculos em paralelo com `->`.
4. **A última expressão é sempre o resultado**: `base + impostos + despesas_gestao` é o que devolve `calcular_fatura`. Sem `return`.

No **Capítulo 04** vamos ver como tomar decisões complexas — incluindo árvores de decisão de vários níveis com `|.` — sem escrever jamais um `if/else` nem um ciclo `while`: bem-vindo ao mundo das **guardas booleanas** e da **recursão de cauda de custo zero**.
