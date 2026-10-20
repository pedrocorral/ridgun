# Capítulo 05: Listas, Tuplas e o truque ninja das Sequências

Um programa que só move um número ou um texto de cada vez serve de pouco. Na vida real lida com listas de ficheiros, linhas de uma base de dados, pacotes de rede ou coordenadas.

Para isso, o Ridgun dá-lhe três recipientes distintos, cada um pensado para um trabalho muito concreto:
1. **Listas (`[T]`)**: *"Tenho muitos elementos do mesmo tipo (ou nenhum) e quero percorrê-los"*.
2. **Tuplas (`(A, B)`)**: *"Quero devolver um par ou um trio de coisas diferentes juntas sem criar um tipo novo"*.
3. **Sequências e máscaras (`s["-+-"]`)**: *"Quero filtrar ou reordenar argumentos em tempo de voo como se tivesse um coador matemático"*.

Vamos uma por uma.

---

## 5.1. Listas (`[T]`): O pão nosso de cada dia

Em Ridgun, se puser parênteses retos à volta de um tipo, tem uma lista desse tipo:
- `[Int]` é uma lista de inteiros: `[10, 20, 30]`.
- `[String]` é uma lista de textos: `["maca", "pera"]`.
- `[]` é a lista vazia (o curinga que encaixa com qualquer `[T]`).

> *"Olha lá, posso meter um número e um texto juntos na mesma lista tipo `[1, "dois"]`?"*
> Tal e qual, **não** (e agradeça ao compilador por o impedir, porque assim nunca lhe explodirá uma soma em produção ao encontrar um texto surpresa). No Capítulo 06 veremos como resolver o caso de `[1, "dois"]` com elegância total usando um Tipo Algébrico (tal como faz o Haskell).

### Como se fatia uma lista sem usar índices `i`, `j`, `k`: `[]` e `(x:xs)`
Nas linguagens imperativas, percorrer uma lista costuma implicar `for (int i = 0; i < lista.size(); i++)`, com o clássico risco de se passar por um (*off-by-one*).

Em Ridgun não conta índices; **desmonta a lista pela cabeça**:
- `[]`: encaixa se a lista estiver vazia.
- `(x:xs)`: encaixa se a lista tiver pelo menos um elemento. Coloca o primeiro elemento em `x` (a **cabeça**) e o resto da lista em `xs` (a **cauda**).

Veja que gosto dá somar uma lista ou contar quantos elementos tem:

```ridgun
somar_lista [Int]  => Int
somar_lista []     =  0
somar_lista (x:xs) =  x + (somar_lista xs)

contar_elementos [A]    => Int
contar_elementos []     =  0
contar_elementos (_:xs) =  1 + (contar_elementos xs)
```

E um detalhe técnico que lhe vai alegrar o dia: em Ridgun, extrair a cauda `xs` em `(x:xs)` **não copia o resto da lista em memória**. Internamente é uma vista sobre o mesmo vetor que só avança o ponteiro de início em `1` ($O(1)$ instantâneo).

### Pode destapar vários elementos de uma assentada
O padrão `:` dá imenso jeito quando está a analisar comandos ou protocolos:

```ridgun
interpretar_comando [String]                  => String
interpretar_comando []                        =  "Não escreveste nada"
interpretar_comando ("ajuda":_)               =  "A mostrar a ajuda..."
interpretar_comando ("copiar":origem:dest:[]) =  "A copiar de {origem} para {dest}"
interpretar_comando (cmd:_)                   =  "Comando desconhecido: {cmd}"
```

Repare na terceira linha: `("copiar":origem:dest:[])` verifica de uma só vez que a lista tem **exatamente 3 elementos**, que o primeiro é `"copiar"`, e deixa-lhe o segundo e o terceiro servidos numa bandeja em `origem` e `dest`. Tente escrever isso em C ou Java e verá quantas linhas de `args.length == 3 && args[0].equals("copiar")` lhe saem.

### Unir listas com duplos dois pontos (`::`)
Quando está do lado direito do `=` (numa expressão) e quer colar duas listas, usa **`::`**:

```ridgun
colar_listas [Int] [Int] => [Int]
colar_listas a     b     =  a :: b

adicionar_atras [Int] Int => [Int]
adicionar_atras xs    x   =  xs :: [x]
```

*(Regra mnemónica rápida: um único `:` nos padrões desmonta a lista; dois `::` nas expressões colam duas listas).*

E se realmente quiser extrair o elemento número 5 diretamente sem percorrer nada? Use parênteses retos colados ao nome: `minha_lista[5]`.

---

## 5.2. Funções variádicas (`T...`): "Passe-me todos os que quiser!"

Às vezes quer que quem chama a sua função possa escrever `maximo_de 4 19 2 88 7` comodamente, sem o obrigar a envolver os números entre parênteses retos `[4, 19, 2, 88, 7]`.

Ponha três pontos **`...`** atrás do último tipo da sua assinatura, e dentro da sua função recebê-lo-á automaticamente empacotado como uma lista:

```ridgun
somar_varios Int... => Int
somar_varios nums   =  somar_lista nums

main => ()
main =
  echo (somar_varios 10 20 30)       -- Imprime 60
  echo (somar_varios 1 2 3 4 5 6 7)  -- Imprime 28
```

---

## 5.3. Tuplas: Quando uma função quer devolver mais do que uma coisa

Em muitas linguagens devolver duas coisas a partir de uma função é uma dor de cabeça: ou cria uma classe auxiliar tonta `ResultadoComPosicao`, ou passa ponteiros de saída por referência.

Em Ridgun devolve uma **tupla** `(A, B)`:

```ridgun
dividir_e_resto Int Int => (Int, Int)
dividir_e_resto a   b   =  (a / b, a % b)
```

Pode inclusive poupar os parênteses na linha da assinatura se lhe parecer mais limpo:
`dividir_e_resto Int Int => Int Int`.

### Como abrir uma tupla
Tal como a cria com `(a, b)`, abre-a nos argumentos de qualquer função com `(quociente, resto)`:

```ridgun
explicar_divisao (Int, Int)         => String
explicar_divisao (quociente, resto) =  "Cabe {quociente} e sobram {resto}"
```

### O detalhe estrela: Desempacotamento automático entre funções
Suponha que tem `dividir_e_resto` (que devolve uma tupla de 2 inteiros) e outra função `somar_par Int Int => Int` (que espera 2 inteiros soltos). Em Ridgun não tem de abrir a tupla à mão numa variável intermédia; pode ligar uma função dentro da outra diretamente:

```ridgun
somar_par Int Int => Int
somar_par x   y   =  x + y

main => ()
main =
  -- dividir_e_resto 17 5 devolve (3, 2), e somar_par recebe 3 e 2 diretamente:
  echo (somar_par (dividir_e_resto 17 5))  -- Imprime 5
```

---

## 5.4. O truque ninja: Sequências e Máscaras Posicionais (`s["-+-"]`)

Aqui vem uma das joias mais originais do Ridgun, herdada diretamente das linguagens vetoriais como J e APL.

Imagine que recebe uma fieira de argumentos com o padrão de sequência **`(s)`** e quer ficar apenas com alguns e descartar outros sem declarar cinco variáveis com nomes inventados (`_a`, `b`, `_c`, `d`...).

Aplica a `s` uma **máscara de sinais `+` (fica com ele) e `-` (deita fora)**:

- **`s["-+-"]`**: de 3 elementos, deita fora o primeiro (`-`), fica com o segundo (`+`) e deita fora o terceiro (`-`).
- **`s["+-+"]`**: fica com o primeiro e o terceiro; devolve a sequência com esses dois.
- **`s["-- +"]`** (atenção ao espaço antes do último `+`): deita fora os dois primeiros (`--`) e aplica `+` **a todos os demais que vierem atrás**, sejam quantos forem.

Veja isto a funcionar:

```ridgun
o_do_meio Int Int Int => Int
o_do_meio (s)         =  s["-+-"]

descartar_dois_primeiros Int... => [Int]
descartar_dois_primeiros (s)    =  s["-- +"]

main => ()
main =
  echo (o_do_meio 100 42 999)                 -- Imprime 42
  echo (descartar_dois_primeiros 1 2 10 20 30)  -- Imprime [10, 20, 30]
```

Além disso, se usar o operador vírgula `,` fora de parênteses (`lista1 , lista2`), o Ridgun achata ambas as coleções numa única sequência contínua.

No **Capítulo 06** vamos dar o passo que transforma um programador funcional num arquiteto de primeira: **criar os seus próprios Tipos de Dados Algébricos (ADTs), escrever funções polimórficas com `A`..`Z` e fabricar os seus próprios operadores por medida**.
