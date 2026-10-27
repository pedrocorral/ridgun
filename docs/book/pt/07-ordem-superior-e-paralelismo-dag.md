# Capítulo 07: Funções de Ordem Superior e Paralelismo sem Suor (Nem `Mutex`, nem `Deadlocks`)

Em quase todas as linguagens de programação há um momento dramático na vida de um projeto: o dia em que alguém diz numa reunião:

> *"Isto está lento. É preciso paralelizar com threads."*

Faz-se silêncio na sala. Toda a gente sabe o que vem a seguir: semanas a caçar *race conditions* fantasma que só acontecem às terças-feiras de lua cheia, bloqueios mútuos (*deadlocks*) e erros irreprodutíveis.

Em Ridgun, quando alguém diz *"é preciso paralelizar"*, basta antepor `||` às suas operações de lista (**`||map`** e **`||filter`**) ou colocar os seus cálculos num bloco paralelo `||` com setas `->` e ir tomar um café.

Porquê? Porque **quando as suas funções são puras e os seus dados são imutáveis por omissão, dois núcleos de CPU a trabalhar ao mesmo tempo jamais podem pisar os calcanhares um do outro**.

Vamos ver isto passo a passo.

---

## 7.1. Funções que recebem funções: `map`, `||map`, `filter`, `||filter` e `fold`

Em Ridgun uma função é mais um valor. Pode passá-la por parâmetro tal como passa o número `7`.

A linguagem traz de série os combinadores de coleções para transformar listas sem escrever uma única recursão manual, tanto em modo sequencial (`map`, `filter`, `fold`) como em modo paralelo multicore com o prefixo `||` (**`||map`**, **`||filter`**):

### 1. `map` (sequencial) e `||map` (paralelo multicore)
Suponha que tem uma função `pesado Int => Int` e uma lista com números:

```ridgun
pesado Int => Int
pesado x   =  (x * x) + (x * 3)

main => ()
main =
  dados = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Sequencial estrito da esquerda para a direita:
  r1 = map pesado dados
  -- Paralelo multicore com o prefixo `||`:
  r2 = ||map pesado dados
  echo r1
  echo r2
```

- Com **`map`**, o Ridgun aplica a função elemento a elemento da esquerda para a direita na thread atual (ideal para listas pequenas ou funções com efeitos de entrada/saída ordenados).
- Com **`||map`**, o runtime do Ridgun distribui os elementos de `dados` pelas threads trabalhadoras do seu processador e reconstrói a lista final **exatamente pela mesma ordem**, garantindo que `||map f xs == map f xs`.

### 2. `filter` (sequencial) e `||filter` (paralelo): Ficar apenas com os que cumprem uma condição
Passa-lhe uma função que devolva `Bool` (um *predicado*) e uma lista:

```ridgun
e_positivo Int => Bool
e_positivo n   =  n > 0

main => ()
main =
  limpos = filter e_positivo [-5, 10, 0, -2, 42]
  limpos_par = ||filter e_positivo [-5, 10, 0, -2, 42]
  echo limpos      -- Imprime [10, 42]
  echo limpos_par  -- Imprime [10, 42]
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

### 4. Tubagens fluidas da esquerda para a direita (`->`) — O estilo 100% Ridgun!
Quando encadeia várias transformações (`map`, `filter`, `fold` ou as suas próprias funções e operadores `op ::`), aninhar parênteses da direita para a esquerda (`compact l (filter g (map f xs))`) obriga-o a ler de dentro para fora.

No Ridgun, o **estilo idiomático recomendado (`2b`)** lê-se da esquerda para a direita com o operador de tubagem **`->`**, onde **o que vem da esquerda entra sempre como primeiro argumento** da função ou `op ::` seguinte:

```ridgun
-- Estilo idiomático recomendado no Ridgun (2b):
xs map (x => x * 2) -> filter (x => x > 10) -> fold (acc x => acc + x) 0 -> resultado

-- E se uma função devolver uma tupla, filtra-a com uma máscara e desempacota-se sozinha:
analisar pacote "v0.9.9" -> (+ _ _ +) -> combinar codigo -> resumo
```

Além disso, qualquer expressão com efeitos secundários (escrever um ficheiro, invocar o sistema) pode ficar sozinha na sua linha sem `echo` nem variáveis mudas `_ =`, ou terminar em `-> ()` se quiser descartar explicitamente o seu retorno.

### 5. Fechos léxicos e funções anónimas (`(x => expr)`, `(acc x => expr)`)
Quando quiser passar uma função curta em linha ou capturar variáveis locais do âmbito atual (como um deslocamento, um prefixo ou uma sessão ativa) sem declarar uma função global auxiliar, usa um **fecho léxico** entre parênteses com **`=>`**:

```ridgun
fn :: processar com sessao => [Int]
      processar com sessao =
        base      = 10
        bonus     = 3
        somados   = map (x => x + base) [1, 2, 3]
        filtrados = filter (x => x >= bonus) [1, 2, 3, 4]
        total     = fold (acc x => acc + x + bonus) 0 [1, 2, 3]
        pares     = map ((a b) => a + b + base) [(1, 2), (3, 4)]
        somados :: filtrados :: [total] :: pares
```

Cinco regras mantêm as lambdas limpas e sem ambiguidade:
- **Parênteses obrigatórios**: toda a lambda vai sempre entre parênteses `(... => ...)`.
- **Lambda sem parâmetros (`(=> expr)`)**: tal como `fn :: main => ()` não leva `()` antes de `=>`, uma lambda sem parâmetros escreve-se `(=> expr)` (e o seu tipo é `(=> Tipo)`), nunca `(() => expr)`.
- **Vários parâmetros face a tupla (`(a b => ...)` vs. `((a b) => ...)`)**: `(acc x => ...)` recebe dois parâmetros separados; `((a b) => ...)` recebe uma única tupla e desestrutura-a.
- **Corpo de várias linhas**: se colocar uma quebra de linha após `=>`, pode escrever um bloco indentado de vários passos antes do `)` de fecho:
  ```ridgun
  dobros = map (x =>
    passo = x * 2
    passo + base
  ) [1, 2, 3]
  ```
- **Maiúsculas face a minúsculas**: `(Conn => Conn)` é um tipo de função (inicial maiúscula) e `(conn => conn)` é um valor lambda (inicial minúscula).

As variáveis capturadas (`base`, `bonus`) são empacotadas automaticamente com gestão determinística de memória (`RMM1`/`RMM2`), sem fugas e sem pausas de coletor de lixo.

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

## 7.4. Quando quer o volante manual: o Modelo Nativo de Agentes (`agent`, `send ... to`, `receive from`) e Canais CSP

O paralelismo automático de blocos `||` e `||map` cobre 90% dos casos. Mas quando está a programar um servidor persistente, sessões de utilizador com estado isolado, uma fila de trabalhos ou um pipeline produtor-consumidor, quer **agentes concorrentes com memória isolada e passagem de mensagens tipada**.

No Ridgun não é preciso inventar uma sintaxe estranha como `actor ::`: **qualquer função normal (`fn ::` ou `op ::`) transforma-se num agente concorrente numa única linha com `agent`**:

### 1. Agentes sem estado e com estado isolado (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (minha funcao)`: transforma uma função `M => R` num agente sem estado do tipo `Agent M R`.
- `ag = agent (funcao com estado) estado_inicial`: transforma uma função `S M => S` (ou `S M => S R`) num agente com estado isolado que recorda o seu estado mensagem após mensagem sem um único `Mutex`.
- `send msg to ag` (ou com vários argumentos: `send a b to ag`): envia uma mensagem tipada para a caixa de entrada do agente.
- `res = receive from ag` (ou `try receive from ag` sem bloquear): recolhe a resposta seguinte da caixa de saída do agente.
- `stop ag`: termina o agente e liberta o seu estado automaticamente através de `RMM1`/`RMM2`.

```ridgun
fn :: somar visita Int Int => Int
      somar visita acc n   =  acc + n

fn :: processar lote Int Int => Int
      processar lote id  t   =  (id * 100) + t

fn :: main => ()
      main =
        contador = agent (somar visita) 10
        send 5 to contador
        send 7 to contador
        v1 = receive from contador
        v2 = receive from contador
        stop contador

        trabalhador = agent (processar lote)
        send 3 25 to trabalhador
        lote = receive from trabalhador
        stop trabalhador
        echo "Visitas:" v1 "->" v2 "| Lote:" lote
```

### 2. Escolha inteligente em tempo de compilação (*Green Threads* vs. Threads Reais do Kernel)
Uma pergunta habitual é: *"Os blocos `||`, `||map` e os agentes `agent` criam sempre threads do sistema operativo ou correm como tarefas leves?"*

Em Ridgun, **o compilador toma essa decisão por si analisando estaticamente cada função**:
- **Funções leves (`TierTrivial` / `StratInlineSequential`)**: Se a função que passa a `||`, `||map`, `||filter` ou `agent` tiver pouca profundidade (aritmética, formatação de cadeias, transição rápida de estado de uma sessão HTTP), aquecer threads do sistema operativo custaria mais do que o próprio cálculo. O compilador executa-a como um passo *green-thread* ultraleve sem sobrecarga de `SYS_clone`.
- **Cálculos pesados ou recursivos profundos (`TierDynamicRecursive` / `TierHeavyCPU`)**: Se a função tiver recursão profunda (como `fib` ou `fact`) ou álgebra de tensores (`einsum`, `hadamard`, `@`), o compilador gera automaticamente o despacho multinúcleo sobre **threads reais do kernel (`SYS_clone`)**, processando os ramos `||` ou a fila de mensagens do `agent` em paralelo real sobre todos os núcleos do seu CPU.

### 3. Passar mensagens por canais limitados (`new bounded channel`)
Tal como em Go ou Erlang, além de agentes também pode criar tubos explícitos para ligar etapas:

- `new bounded channel capacidade`: cria um canal com espaço para `capacidade` mensagens.
- `send through valor canal` (ou `chan send valor canal`): coloca uma mensagem no tubo.
- `receive from canal` (ou `chan recv canal`): retira a mensagem seguinte do tubo.
- `try receive from canal`: verifica se há mensagem sem ficar à espera; devolve `Some valor` ou `None`.
- `receive from timeout canal ticks`: aguarda um limite de tempo e devolve `Ok valor` ou `Err Timeout`.

```ridgun
fn :: main => ()
      main =
        tubo = new bounded channel 4
        _ = send through "Tarefa A concluída" tubo
        _ = send through "Tarefa B concluída" tubo
        primeiro = receive from tubo
        segundo = receive from tubo
        echo primeiro "|" segundo
```

E agora, aperte o cinto de segurança para o **Capítulo 08**, o grande final: **tensores com dimensões verificadas na compilação, variáveis de âmbito (`context`/`shared`), regiões de memória determinísticas, acesso direto a hardware MMIO e programação de sistemas UNIX/POSIX**.
