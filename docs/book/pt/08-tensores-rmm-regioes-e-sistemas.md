# Capítulo 08: Tensores, Memória Compilada RMM (`RMM1`/`RMM2`), Regiões e Sistemas

Até aqui vimos o lado mais amável, elegante e matemático do Ridgun: funções puras, tipos algébricos, *pattern matching*, árvores de decisão com `|` / `|.` e grafos paralelos `||` com `->` que aproveitam todos os núcleos do seu processador sem lhe pedir um único `Mutex`.

Chegados a este ponto, o programador veterano de sistemas costuma levantar a mão no fundo da sala com um meio sorriso e perguntar:

> *"Tudo isto é lindo para calcular faturas ou compilar ASTs, mas o que acontece quando preciso de multiplicar matrizes de milhões de números em vírgula flutuante a uma velocidade vertiginosa? O que acontece com a memória? Há um coletor de lixo (Garbage Collector) escondido debaixo do tapete à espera do pior momento para congelar o meu programa durante 200 milissegundos? E como falo com o sistema operativo Unix a sério?"*

Excelentes perguntas. Vamos levantar o capô do Ridgun para ver como ele se comporta quando toca a descer ao terreno dos sistemas, do cálculo numérico e da memória determinística.

---

## 8.1. O dilema da memória: nem Garbage Collector nem lutas com o Borrow Checker (`RMM1` e `RMM2`)

No mundo das linguagens modernas costuma haver dois campos irreconciliáveis:

1. **O campo do Garbage Collector (Java, Go, Python, JS, Haskell, OCaml):** pede memória alegremente e, de vez em quando, um camião do lixo invisível pára o trânsito do seu programa para rastrear que objetos continuam vivos e quais não. É comodíssimo... até estar a fazer uma ferramenta de sistema ultrarrápida ou um servidor com latências estritas e o camião decidir estacionar em segunda fila.
2. **O campo do controlo manual / Borrow Checker (C, C++, Rust):** não há coletor de lixo, mas em troca tem de gerir ponteiros à mão (arriscando um `Segmentation fault` ou um *use-after-free*) ou passar meia tarde a negociar com o *borrow checker* porque é que `'a` não vive tanto tempo como `'b`.

O Ridgun resolve este dilema pela raiz com o **Ridgun Memory Management (`RMM`)**, um sistema determinístico de duas políticas complementares (**`RMM1`** e **`RMM2`**) combinado com **regiões léxicas (`with region`)**:

### Política `RMM1` — Gestão de Memória Compilada (CMM Linear e Condicional)
Quando o compilador conhece estaticamente o fluxo das variáveis locais dentro de uma função:
- **CMM Linear**: o `ridgunc` calcula em tempo de compilação qual é a **última linha** em que se lê cada variável local (`a`, `b`, ...) e insere logo a seguir a sua libertação determinística (`rg_cmm_drop`), ou transfere a sua propriedade sem cópias (`rg_cmm_move`) quando a variável é devolvida como resultado.
- **CMM Condicional (`ptr(a) != ptr(c)`)**: e se uma função como `escolher cond a b` devolver `a` ou `b` segundo uma condição em tempo de execução? O `ridgunc` constrói a tabela de ancestrais e emite uma guarda de identidade de ponteiros de **1 ciclo de CPU**: se `b` deixar de ser usada enquanto `c` continua viva, verifica `if ptr(b) != ptr(c) { free(b) }`. O ramo não escolhido é libertado no instante e o escolhido sobrevive intacto.

### Política `RMM2` — Contagem por Atribuição e Cascata Estrutural
E o que acontece quando coloca estruturas dentro de outras estruturas (`xs = [a, b]`), reatribui variáveis mutáveis (`mut x = ...`) ou encadeia chamadas complexas? Aí entra a **`RMM2`**, que governa todo o ciclo de vida com quatro regras matemáticas sem falhas:

1. **Os argumentos de entrada de uma função não são tocados (`+0` ao entrar, `-0` ao sair)**: passar uma lista ou um registo a uma função jamais incrementa nem decrementa contadores em vão.
2. **Toda a atribuição a uma variável local interna ou célula de contentor soma `+1`**:
   - `a = [10, 20]` $\rightarrow$ o bloco `M1` nasce com contador `1`.
   - `xs = [a, b]` $\rightarrow$ a lista `xs` nasce com `1`, e como guarda referências a `a` e `b`, ambos sobem para `2`.
   - Se reatribuir uma variável mutável (`mut x = ...` e depois `x = novo`), a `RMM2` aplica primeiro **`+1`** ao valor novo antes de aplicar **`-1`** ao antigo.
3. **Ao sair da função, as variáveis locais que NÃO são devolvidas recebem `-1`**: se o contador de uma estrutura chegar a `0`, liberta-se a sua memória na hora e **propaga `-1` em cascata, um por um, a cada um dos seus filhos diretos**.
4. **O valor devolvido pela função fica isento em trânsito**: recebe o seu `-1` de variável local mas não é destruído ao cruzar o retorno, de modo que quando quem chamou faz `c = minha_funcao ()`, esse `+1` da atribuição deixa-o exatamente em `1`.

```ridgun
escolher Bool [Int] [Int] => [Int]
escolher cond a     b     =
  | cond      = a
  | otherwise = b

exemplo_rmm2 Bool => Int
exemplo_rmm2 cond =
  a = [10, 20, 30]         -- M1 (rc = 1)
  b = [40, 50, 60]         -- M2 (rc = 1)
  c = escolher cond a b    -- `c` recebe +1; o não escolhido morre aqui mesmo (rc -> 0)
  (contar a) + (contar c)  -- Ao terminar, `a` e `c` recebem -1 e tudo fica com 0 blocos vivos
```

---

## 8.2. Regiões Léxicas com Quota (`with region`): Corta-fogos de memória em $O(1)$

Além da `RMM1` e da `RMM2`, quando está a processar um pacote de rede externo, um ficheiro gigante ou um lote de dados não confiáveis e quer impor um **teto estrito de memória RAM**, envolve o cálculo num bloco **`with region`**:

```ridgun
processar_trama String => Result
processar_trama bruto  =
  with region 64_KB do
    limpas = map limpar_linha (dividir_linhas bruto)
    contar_validos limpas
```

1. **Quota garantida em hardware/runtime**: se dentro do bloco se tentar reservar nem que seja um único byte acima de `64_KB` (`65.536` bytes), o runtime aborta de forma limpa o bloco, liberta toda a arena temporária em tempo constante $O(1)$ e devolve `Err OutOfMemory` sem derrubar o processo.
2. **Libertação instantânea ao sair**: assim que termina o bloco `with region`, toda a memória temporária da arena desaparece de uma só vez sem deixar fragmentação.

---

## 8.3. Tensores Nativos, Contração de Einstein (`@`) e Dimensões Simbólicas

Se alguma vez programou em Python com NumPy ou PyTorch, de certeza que já sofreu o clássico erro ao minuto 41 de execução:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

Em Ridgun, os **`Tensor`** são cidadãos nativos de primeira classe e as suas dimensões fazem parte da assinatura de tipos:

```ridgun
-- Se entra (N × K) e (K × M), obrigatoriamente sai (N × M)!
multiplicar_matrizes Tensor[N, K] Tensor[K, M] => Tensor[N, M]
multiplicar_matrizes a            b            =  a_ik @ b_kj
```

Repare em dois detalhes espetaculares:
1. **Verificação estática de dimensões (`Tensor[N, K]`)**: o eixo interno `K` da primeira matriz tem de coincidir com o primeiro eixo `K` da segunda. Se tentar passar dimensões incompatíveis, o `ridgunc check` detém-no antes de executar o que quer que seja.
2. **Notação de subscritos de Einstein (`a_ik @ b_kj`) e Hadamard (`a_ij * b_j`)**:
   - Com **`@`**, os subscritos repetidos em todos os operandos (`k`) contraem-se (somam-se) e os únicos (`i`, `j`) sobrevivem no tensor resultado.
   - Com **`+`, `-`, `*`, `/`**, os subscritos alinham dimensões e fazem *broadcasting* automático (`a_ij * b_j` multiplica cada linha `i` de `a` pelo vetor `b_j` sem necessidade de escrever `unsqueeze` nem `reshape`).
3. **Mutação *in-place* para algoritmos numéricos**:
   ```ridgun
   criar_matriz_identidade => Tensor
   criar_matriz_identidade =
     m = Tensor [[1.0, 0.0], [0.0, 1.0]]
     m[0, 1] = 0.5
     m
   ```

---

## 8.4. Variáveis de Contexto (`context ::`) e Estado Partilhado Atómico (`shared ::`)

Em 99% do seu código passará dados por parâmetro. Mas para esse 1% onde precisa de configuração de ambiente ou de um contador global entre threads sem contaminar 40 assinaturas intermédias, o Ridgun oferece dois mecanismos explícitos e seguros:

### 1. `context ::` — Âmbito dinâmico isolado por tarefa (`with ... = ... do`)
```ridgun
context :: caminho_log : String = "/var/log/app.log"

registar_evento String => ()
registar_evento msg    =  echo "[{caminho_log}] {msg}"

main => ()
main =
  registar_evento "Arranque normal"
  with caminho_log = "/tmp/test.log" do
    registar_evento "Dentro do teste isolado"
```

### 2. `shared ::` e `atomic` — Estado concorrente com bloqueio atómico por linha
```ridgun
shared :: pedidos_totais : Int = 0

contabilizar_visita => Int
contabilizar_visita =
  atomic pedidos_totais = pedidos_totais + 1
  pedidos_totais
```

---

## 8.5. Acesso a Hardware (`hardware ::`) e Primitivas POSIX de Sistemas

O próprio compilador `ridgunc`, o gestor `stable` e utilitários de sistemas Unix estão escritos em Ridgun. Para tal, a linguagem inclui blocos de registos mapeados em memória (`hardware ::`) e primitivas POSIX diretas:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

E para trabalhar com o sistema operativo:

| Primitiva | Assinatura | O que faz |
|---|---|---|
| `cli_args` | `=> [String]` | Argumentos de linha de comandos (`argv`). |
| `read_file` / `write_file` | `String => String` / `String String => ()` | Leitura e escrita integral de ficheiros em disco. |
| `read_bytes` / `write_bytes` | `String => [Int]` / `String [Int] => ()` | Leitura e escrita binária exata byte a byte (`0..255`). |
| `list_dir` / `file_lstat` | `String => [String]` / `String => ...` | Listagem de diretórios e inspeção de metadados POSIX (`lstat`). |
| `sha256_file` / `sha256_str` | `String => String` | Hash criptográfico SHA-256 nativo. |
| `sys_exec` / `shell_exec` | `... => Int` | Execução de processos do sistema operativo. |
| `sys_getcwd` / `sys_chdir` | `=> String` / `String => Int` | Consultar ou alterar o diretório de trabalho. |
| `sys_getenv` / `sys_setenv` | `String => String` / `String String => Int` | Variáveis de ambiente do processo. |
| `sys_getuid` / `sys_getgid` | `=> Int` | UID e GID reais do processo (`doas`, ferramentas de segurança). |
| `sys_exit` | `Int => ()` | Terminar o processo com código de saída. |

---

## 8.6. Caso de Estudo Real: Construindo `rg-wc`, um utilitário Unix paralelo

Vamos unir tudo o que aprendemos desde o Capítulo 01 até aqui num programa real de sistemas: uma versão paralela da ferramenta Unix `wc` (contador de linhas e bytes para múltiplos ficheiros) escrita em Ridgun puro:

```ridgun
-- 1. Modelamos as métricas de um ficheiro com um registo ADT (Capítulo 06)
type Metricas = ficheiro: String, linhas: Int, bytes: Int

-- 2. Contamos quebras de linha (código ASCII 10) com recursão de cauda TCO (Capítulo 04)
fn :: contar_quebras String Int Int Int  => Int
      contar_quebras texto  pos fim acum =
        | pos >= fim                    = acum
        | (str_char_at texto pos) == 10 = contar_quebras texto (pos + 1) fim (acum + 1)
        | otherwise                     = contar_quebras texto (pos + 1) fim acum

fn :: numero_de_linhas String => Int
      numero_de_linhas texto  =  contar_quebras texto 0 (str_len texto) 0

-- 3. Analisamos um ficheiro e devolvemos a sua estrutura Metricas
fn :: analisar_ficheiro String   => Metricas
      analisar_ficheiro caminho  =
        conteudo = read_file caminho
        || numero_de_linhas conteudo -> n_linhas
        || str_len conteudo          -> n_bytes ||.
        Metricas caminho n_linhas n_bytes

-- 4. Formatamos cada linha e somamos totais com `fold` e `||` (Capítulo 07)
fn :: formatar_metrica Metricas => String
      formatar_metrica m        =  "{linhas m}\t{bytes m}\t{ficheiro m}"

fn :: somar_linhas Int Metricas => Int
      somar_linhas acc m        =  acc + (linhas m)

fn :: somar_bytes Int Metricas => Int
      somar_bytes acc m        =  acc + (bytes m)

fn :: gerar_relatorio [String] => String
      gerar_relatorio caminhos =
        metricas = map analisar_ficheiro caminhos
        || map formatar_metrica metricas -> linhas_fmt
        || fold somar_linhas 0 metricas  -> total_l
        || fold somar_bytes 0 metricas   -> total_b ||.
        "{linhas_fmt}\nTotal: {total_l} linhas, {total_b} bytes"

fn :: main => ()
      main =
        echo (gerar_relatorio ["README.md", "AGENTS.md"])
```

Pare um segundo para olhar para essas ~40 linhas de código:
- Não há um único `null`, nem uma exceção descontrolada, nem um `Mutex`.
- `contar_quebras` é compilada para um `loop` nativo com 0 bytes de pilha graças ao TCO automático.
- `map analisar_ficheiro caminhos` processa os ficheiros em paralelo em todos os núcleos do seu CPU, e o bloco `||` calcula simultaneamente as linhas formatadas, o total de linhas e o total de bytes.
- A memória temporária é libertada de forma determinística mediante **`RMM1`/`RMM2`**.
- E quando executa `ridgunc build rg_wc.rg -o rg-wc`, obtém um binário nativo autónomo de ~350 KB pronto para copiar para `/usr/local/bin`.

---

## 8.7. Roteiro Final: As 10 Regras de Ouro do Programador Ridgun

1. **Escreva sempre primeiro o contrato (`=>`) e depois as equações (`=`):** pensar nos tipos primeiro faz com que o compilador trabalhe para si.
2. **Deixe que o `stable format` pagine as suas tabelas:** escreva com um espaço e deixe que a ferramenta alinhe colunas, `=>`, `=` e `->`.
3. **Lembre-se da regra universal do `=`:** atrás de qualquer `=` pode abrir um bloco sequencial, uma árvore de guardas `|` ou um grafo paralelo `||`.
4. **Use `|.` e `||.` apenas quando fechar um bloco aninhado para voltar a um nível superior:** mantenha as árvores de decisão profundas compactas e sem ambiguidade.
5. **Imutável por omissão (`x = ...`), mutável explícito (`mut x = ...`):** use `mut` unicamente quando um acumulador local o exigir de verdade.
6. **Use operadores booleanos claros em minúsculas (`and`, `or`, `xor`, `not`) e feche sempre as suas guardas com `| otherwise =`.**
7. **Modele o seu domínio com ADTs (`type`):** use registos com `with campo: valor` e tipos soma (`Option`, `Result`) em vez de `null`.
8. **Paralelize declarando dependências com `|| expr -> var` e `map` / `filter`:** deixe que o compilador verifique que não há ciclos e distribua o trabalho pelos núcleos.
9. **Ponha dimensões simbólicas nos seus Tensores (`Tensor[N, K]`) e subscritos nas suas contrações (`a_ik @ b_kj`).**
10. **Confie no `RMM` (`RMM1`/`RMM2`), limite entradas externas com `with region` e verifique sempre com `stable check` e `stable test`.**

Boa viagem a programar em Ridgun!
