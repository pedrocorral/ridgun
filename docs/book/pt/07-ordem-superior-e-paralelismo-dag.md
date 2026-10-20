# Capítulo 07: Funções de Ordem Superior e Paralelismo sem Suor (Nem `Mutex`, nem `Deadlocks`)

Em quase todas as linguagens de programação há um momento dramático na vida de um projeto: o dia em que alguém diz numa reunião:

> *"Isto está lento. É preciso paralelizar com threads."*

Faz-se silêncio na sala. Toda a gente sabe o que vem a seguir: semanas a caçar *race conditions* fantasma que só acontecem às terças-feiras de lua cheia, bloqueios mútuos (*deadlocks*) e erros irreprodutíveis.

Em Ridgun, quando alguém diz *"é preciso paralelizar"*, `map` e `filter` já são paralelos por omissão, ou coloca os seus cálculos num bloco paralelo `||` com setas `->` e vai tomar um café.

Porquê? Porque **quando as suas funções são puras e os seus dados são imutáveis por omissão, dois núcleos de CPU a trabalhar ao mesmo tempo jamais podem pisar os calcanhares um do outro**.

Vamos ver isto passo a passo.

---

## 7.1. Funções que recebem funções: `map`, `seq_map`, `filter`, `seq_filter` e `fold`

Em Ridgun uma função é mais um valor. Pode passá-la por parâmetro tal como passa o número `7`.

A linguagem traz de série os combinadores de coleções para transformar listas sem escrever uma única recursão manual:

### 1. `map` (paralelo por omissão) e `seq_map` (sequencial)
Suponha que tem uma função `pesado Int => Int` e uma lista com números:

```ridgun
pesado Int => Int
pesado x   =  (x * x) + (x * 3)

main => ()
main =
  dados = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Paralelo multicore por omissão:
  r1 = map pesado dados
  -- Sequencial estrito da esquerda para a direita:
  r2 = seq_map pesado dados
  echo r1
  echo r2
```

- Com **`map`**, o runtime do Ridgun distribui os elementos de `dados` pelas threads trabalhadoras do seu processador e reconstrói a lista final **exatamente pela mesma ordem**, garantindo que `map f xs == seq_map f xs`.
- E se a sua função fizer efeitos de entrada/saída (como imprimir no ecrã ou escrever num ficheiro) e quiser forçar a que vá estritamente da esquerda para a direita, um por um? Usa **`seq_map`**.

### 2. `filter` (paralelo) e `seq_filter` (sequencial): Ficar apenas com os que cumprem uma condição
Passa-lhe uma função que devolva `Bool` (um *predicado*) e uma lista:

```ridgun
e_positivo Int => Bool
e_positivo n   =  n > 0

main => ()
main =
  limpos = filter e_positivo [-5, 10, 0, -2, 42]
  echo limpos  -- Imprime [10, 42]
```

### 3. `fold`: Reduzir toda uma lista a um único resultado
Passa-lhe uma função combinadora de dois argumentos `(Acumulado Elemento => Acumulado)`, o valor inicial e a lista:

```ridgun
acumular_produto Int Int => Int
acumular_produto acc x   =  acc * x

main => ()
main =
  echo (fold acumular_produto 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### Como escrevo eu a minha própria função que receba outra função?
Muito fácil: na assinatura de tipos coloca a assinatura da função convidada entre parênteses `(Entrada => Saida)`:

```ridgun
executar_duas_vezes (A => A) A => A
executar_duas_vezes f        x =  f (f x)
```

---

## 7.2. A joia da coroa: Blocos `||` com `->` como Grafos Paralelos (DAGs)

É aqui que o Ridgun muda a sua forma de pensar.

Numa linguagem imperativa normal, quando escreve três linhas seguidas:
1. Primeiro executa-se a linha 1.
2. Depois a linha 2 (mesmo que não tenha nada a ver com a linha 1).
3. Depois a linha 3.

Isso é obrigar o computador a trabalhar com antolhos. Em Ridgun, quando usa barras paralelas **`||`** com setas **`->`** (sem necessidade de escrever nenhuma palavra-chave como `where`), não está a dar ordens sequenciais: está a desenhar um **Grafo Acíclico Dirigido (DAG)** que diz que cálculo alimenta que variável:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_calculo => Int
super_calculo =  ramo_esquerdo + ramo_direito
  || fib 10 -> ramo_esquerdo
  || fact 6 -> ramo_direito
```

Leia em voz alta:
- *"Quero calcular `ramo_esquerdo + ramo_direito`, enquanto em paralelo (`||`) `fib 10` vai para `ramo_esquerdo` (`->`) e `fact 6` vai para `ramo_direito` (`->`)."*

### O que faz o `ridgunc` nos bastidores com as suas linhas `||`:
1. Olha para as setas `->` e monta a árvore de dependências (DAG).
2. **Caça ciclos estaticamente**: se por engano escrever `|| a + 1 -> b` e `|| b + 1 -> a`, o compilador diz-lhe na hora *"Alto lá! Há uma dependência circular"* e não o deixa compilar um bloqueio infinito.
3. Vê que `fib 10` e `fact 6` não dependem um do outro, pelo que têm luz verde para correr em paralelo antes de se somarem em `ramo_esquerdo + ramo_direito`.

Pode inclusive montar um pipeline de vários andares dentro do mesmo bloco `||` — seja no rodapé da expressão ou logo depois do `=` — e o compilador deduzirá sozinho que andares podem avançar ao mesmo tempo e quais têm de esperar:

```ridgun
balanco_trimestral Int  => Int
balanco_trimestral base =
  || base * 100                   -> vendas_brutas
  || base * 40                    -> custos_fixos
  || vendas_brutas - custos_fixos -> lucro_bruto ||.
  lucro_bruto * 80 / 100
```

Repare no detalhe **`||.`** no final da última linha `||`: tal como `|.` fecha uma árvore de guardas aninhada, **`||.`** fecha o bloco paralelo `||` quando por baixo continuam instruções sequenciais normais. Aqui `vendas_brutas` e `custos_fixos` arrancam em paralelo; quando ambos estão prontos calcula-se `lucro_bruto`, e finalmente devolve-se `lucro_bruto * 80 / 100`. Tudo sem um único `async`, `Future`, `Promise` nem `Mutex`.

---

## 7.3. O atalho `||` sem nomes: Condutas paralelas que devolvem uma tupla

E se só quiser lançar dois ou três cálculos em paralelo e recolhê-los juntos numa tupla sem sequer inventar nomes de variáveis com `->`?

Usa `||` diretamente:

```ridgun
par_paralelo Int => (Int, Int)
par_paralelo n   =
  || fib n
  || fact n
```

Direto, visual e devolve a tupla `(fib n, fact n)`.

---

## 7.4. Quando quer o volante manual: `spawn`, `join` e Canais CSP

O paralelismo automático de blocos `||` e `map` cobre 90% dos casos. Mas às vezes está a programar um sistema de atores, uma fila de trabalhos ou um pipeline produtor-consumidor e quer controlar você mesmo as tarefas e as mensagens.

Para isso tem duas ferramentas limpas:

### 1. Lançar tarefas com `spawn` e recolher o resultado com `join`
```ridgun
processar_lote Int => Int
processar_lote id  =  id * 100

main => ()
main =
  tarefa1 = spawn processar_lote 1
  tarefa2 = spawn processar_lote 2
  -- Entretanto poderia fazer outras coisas aqui...
  res1 = join tarefa1
  res2 = join tarefa2
  echo "Terminaram com:" res1 "e" res2
```

### 2. Passar mensagens por canais limitados (`new_bounded_channel`)
Tal como em Go ou Erlang, em vez de partilhar memória entre threads, envia valores imutáveis através de um tubo seguro:

- `new_bounded_channel capacidade`: cria um canal com espaço para `capacidade` mensagens.
- `chan_send valor canal` (ou `send_through valor canal`): coloca uma mensagem no tubo.
- `chan_recv canal` (ou `receive_from canal`): retira a mensagem seguinte do tubo.
- `chan_try_recv canal`: verifica se há mensagem sem ficar à espera; devolve `Some valor` ou `None`.
- `receive_from_timeout canal ticks`: aguarda um limite de tempo e devolve `Ok valor` ou `Err Timeout`.

```ridgun
main => ()
main =
  tubo = new_bounded_channel 4
  _ = chan_send "Tarefa A concluída" tubo
  _ = chan_send "Tarefa B concluída" tubo
  primeiro = chan_recv tubo
  segundo = chan_recv tubo
  echo primeiro "|" segundo
```

E agora, aperte o cinto de segurança para o **Capítulo 08**, o grande final: **tensores com dimensões verificadas na compilação, variáveis de âmbito (`context`/`shared`), regiões de memória determinísticas, acesso direto a hardware MMIO e programação de sistemas UNIX/POSIX**.
