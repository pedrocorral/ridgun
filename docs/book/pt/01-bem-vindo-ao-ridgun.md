# Capítulo 01: O seu primeiro contacto com o Ridgun (Sem capacetes, sem chavetas e sem pontos e vírgulas)

Muito bem, já o convenci no Capítulo 00 de que não estamos loucos por criar o Ridgun. Agora provavelmente está a pensar:

> *"Muito bonito o discurso das tabelas e dos 16 núcleos, mas mostre-me código de verdade. Quanto tempo demora alguém a escrever algo que funcione sem andar à pancada com o compilador?"*

Vamos lá, mãos à obra!

---

## 1.1. "Olá, mundo!", mas com substância

Na maioria dos livros de programação ensinam-lhe um `print("Olá mundo")` insosso e viram a página. Nós vamos escrever diretamente uma função com lógica real para que veja como o Ridgun respira desde o primeiro minuto.

Crie um ficheiro chamado `ola.rg` e escreva isto:

```ridgun
saudacao String => String
saudacao ""     =  "Olá, viajante misterioso! (Não me disseste o teu nome)"
saudacao "Root" =  "Ora viva, Root! Cuidado com o que apagas hoje."
saudacao nome   =  "Olá, {nome}! Bem-vindo ao Ridgun."

main => ()
main =
  echo (saudacao "Ada")
  echo (saudacao "Root")
  echo (saudacao "")
```

Para o executar agora mesmo:

```bash
ridgunc run ola.rg
```

E verá no seu terminal:

```text
Olá, Ada! Bem-vindo ao Ridgun.
Ora viva, Root! Cuidado com o que apagas hoje.
Olá, viajante misterioso! (Não me disseste o teu nome)
```

Pare um momento e olhe para o bloco de `saudacao` acima. Nota o que **NÃO** há?
- **Não há `function`, nem `def`, nem `pub fn`** (se quiser pôr `fn ::` antes da assinatura pode fazê-lo, mas é opcional).
- **Não há parênteses `(String nome)` nem chavetas `{ ... }`** a sujar o ecrã.
- **Não há `if (nome == "") ... else if (nome == "Root") ... else ...`**.
- **Não há `return`**.

---

## 1.2. Como o seu cérebro lê um ficheiro `.rg`

Vamos dissecar essas quatro linhas de `saudacao`, porque aqui já está 50% da filosofia do Ridgun:

```ridgun
saudacao String => String
saudacao ""     =  "Olá, viajante misterioso! (Não me disseste o teu nome)"
saudacao "Root" =  "Ora viva, Root! Cuidado com o que apagas hoje."
saudacao nome   =  "Olá, {nome}! Bem-vindo ao Ridgun."
```

1. **A primeira linha é o contrato (`saudacao String => String`)**:
   Diz: *"Chamo-me `saudacao`, recebo uma `String` e devolvo-lhe (`=>`) outra `String`"*. Ponto final. Se alguém tentar chamar-me passando o número `42`, o compilador dar-lhe-á um toque no ombro antes sequer de executar o programa.
2. **As linhas abaixo são os casos (de cima para baixo)**:
   - Passou-me a cadeia vazia `""`? Devolvo a primeira frase.
   - Passou-me exatamente `"Root"`? Devolvo a segunda frase.
   - Passou-me qualquer outra coisa? Guardo-a na variável `nome` e coloco-a dentro do texto usando `{nome}`.
3. **E o que é `main => ()`?**:
   Como `main` não recebe argumentos, pomos `=>` diretamente depois do nome. E devolve `()` (o tipo vazio ou *Unit*, para os amigos), porque o seu único trabalho é mostrar coisas no ecrã com `echo`.

---

## 1.3. "Espere... tenho de alinhar esses espaços à mão como um monge copista?"

Nem pensar! Se tivesse de carregar na barra de espaços a contar colunas a olho, abandonaria o Ridgun ao fim de dez minutos (e com razão).

Escreve o código depressa, com um único espaço entre cada palavra:

```ridgun
saudacao String => String
saudacao "" = "Olá, viajante misterioso!"
saudacao nome = "Olá, {nome}!"
```

E quando executa **`stable format`** (ou prime `TAB` / guarda o ficheiro no Emacs com `ridgun-mode`), o formatador canónico coloca cada parâmetro debaixo do seu tipo e alinha todos os `=` com precisão milimétrica. Você escreve rápido; a máquina pagina a tabela.

---

## 1.4. De script rápido a binário de combate num só comando

Quando faz `ridgunc run ola.rg`, está a compilar e a lançar o programa na hora. Mas imagine que já terminou a sua ferramenta e quer levá-la para um servidor de produção ou partilhá-la com um colega que não tem o Ridgun instalado.

Executa:

```bash
ridgunc build ola.rg -o ola
```

E já tem `./ola`: um **executável nativo ELF de Linux x86_64**, limpo, sem código morto (*Tree-Shaking*), com otimização de ligação completa (*LTO*) e sem depender de nenhum interpretador externo.

---

## 1.5. A cábula honesta: De onde vem cada ideia do Ridgun?

O Ridgun não pretende reinventar a roda quadrada; pede emprestado sem complexos o melhor de quatro tradições:

| De quem | O que o Ridgun aproveita | O que deixa de fora (pela sua saúde mental) |
|---|---|---|
| **Haskell / ML** | Funções puras, *pattern matching* por casos, tipos algébricos (`Option`, `Result`) e polimorfismo (`A`..`Z`). | As mónadas abstratas, os 40 `LANGUAGE pragmas` e o coletor de lixo. |
| **J / APL** | A obsessão pela forma tabular do código, tensores nativos e máscaras de sequências (`s(_ + _)`). | Os símbolos hieroglíficos impossíveis de escrever num teclado normal. |
| **Rust / C** | Binários ELF nativos pequenos, zero GC, controlo de memória (`with region`) e chamadas ao sistema POSIX. | A luta constante com o *borrow checker*, os *lifetimes* `'a` e a verbosidade sintática. |
| **Erlang / Go** | Agentes isolados (`agent`, `send ... to`, `receive from`) e concorrência por canais (`new bounded channel`). | Os ponteiros `nil` e as mutações partilhadas por descuido. |

---

## 1.6. E o mais importante: O que faz o Ridgun que NINGUÉM mais tem?

Reconhecer os clássicos é sinal de boa educação, mas se o Ridgun fosse apenas uma "coletânea de grandes êxitos" de outras linguagens, não estaria a ler este livro.

Há **oito coisas** que desenhámos e integrámos no Ridgun que não vai encontrar juntas — e muitas delas, nem sequer em separado — em nenhuma outra linguagem atual:

### 1. Blocos paralelos `||` com `->` que são grafos paralelos reais, não simples açúcar sintático
Noutras linguagens funcionais, um bloco de variáveis locais apenas ordena expressões que depois são avaliadas numa única thread.
Em Ridgun, **um bloco `||` com setas `->` é um Grafo Acíclico Dirigido (DAG) de execução paralela** sem sequer precisar de escrever palavras-chave extra como `where`:
```ridgun
relatorio_anual Int => Int
relatorio_anual id  =  receitas - despesas
  || calcular_vendas id -> receitas
  || calcular_custos id -> despesas
```
Você desenha as setas de fluxo (`->`). O compilador analisa quem depende de quem, **verifica estaticamente que não criou nenhum ciclo infinito**, e lança os ramos independentes em paralelo sem que escreva um único `async`, `await`, `Future` nem `Mutex`.

### 2. Modelo Nativo de Agentes (`agent`) de zero fricção com escolha inteligente em compilação
Noutras linguagens, programar com atores ou agentes obriga-o a criar classes especiais, implementar *traits*, gerir *locks* ou infetar as suas funções com `async`.
Em Ridgun, **qualquer função pura normal (`fn ::` ou `op ::`) converte-se diretamente num agente autónomo — com ou sem estado isolado — usando `agent`**:
```ridgun
atender_http (Sessao, String) => (Sessao, String)
...
servidor = agent atender_http sessao_inicial
send "GET /perfil" to servidor
resposta = receive from servidor
stop servidor
```
Melhor ainda: o compilador **analisa em tempo de compilação a profundidade e o custo computacional da função** tanto em `agent` como em `||` e `||map`. Se a função for leve, executa-a como uma *green thread* instantânea sem pagar o custo de aquecer threads do sistema operativo; se for um cálculo pesado ou recursivo profundo, despacha-a automaticamente em paralelo sobre threads reais do kernel (`SYS_clone`) distribuídas pelos núcleos do seu CPU.

### 3. O código como tabela bidimensional onde a assinatura é o cabeçalho das colunas
Em qualquer outra linguagem, a assinatura de tipos anda solta numa linha e o corpo da função vai por baixo como um parágrafo de texto normal.
Em Ridgun, **a assinatura de tipos é literalmente o cabeçalho de uma tabela**, e cada caso abaixo alinha cada padrão exatamente na vertical do seu tipo e cada `=` debaixo do `=>`:
```ridgun
dividir Int Int => Option
dividir _   0   =  None
dividir a   b   =  Some (a / b)
```
Mais ninguém trata a assinatura e as equações como uma única matriz visual verificada pelo compilador e paginada automaticamente pelo `stable format`.

### 4. Operadores frase (*Mixfix* N-ários) tipados e alinhados (`op ::`)
Na maioria das linguagens, ou se aguenta com `+`, `-`, `*` ou no máximo define um operador binário críptico como `<|>` que ninguém sabe o que significa.
Em Ridgun pode criar **operadores que são frases legíveis com tantos espaços tipados quantos quiser** (incluindo palavras contextuais como `type` ou `with`):
```ridgun
op :: Int limitado_entre Int e Int => Int
      x   limitado_entre min e max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
E depois no seu código escreve `velocidade limitado_entre 0 e 120`. Lê-se como português (ou inglês), mas está 100% tipado e compilado para código nativo.

### 5. Máscaras visuais sobre sequências (`s(_ + _)` e `-> (+ _ _ +) ->`)
Alguma vez teve de escrever uma salada de índices ou abrir uma tupla com variáveis mudas só para ficar com duas posições concretas?
Em Ridgun passa-lhe diretamente uma **máscara visual**:
- `dados(_ + _)`: descarta o primeiro (`_`), fica com o segundo (`+`), descarta o terceiro (`_`).
- `analisar pacote "v0.9.9" -> (+ _ _ +) -> combinar codigo -> resumo`: filtra uma tupla de 4 elementos em plena tubagem e passa o 1.º e o 4.º diretamente como argumentos da função seguinte.
Zero aritmética de índices, zero erros *off-by-one*.

### 6. Polimorfismo de "zero ruído" (`A`..`Z`) governado pelo seu domínio
Em Rust, TypeScript ou Java, quando uma função é genérica tem de encher a linha de parênteses angulares: `fn trocar<A, B>(par: (A, B)) -> (B, A)`.
Em Ridgun usa simplesmente uma letra maiúscula solta:
```ridgun
trocar (A, B) => (B, A)
trocar (x, y) =  (y, x)
```
*"E se no meu programa eu quiser ter um tipo real que se chame `type A`?"* — Sem problema: em Ridgun **as suas declarações `type` mandam**. Se não existir `type A`, `A` é genérico; no instante em que define `type A = ...`, passa a ser o seu tipo concreto em todo o módulo.

### 7. Zero ficheiros de configuração estranhos: `build.rg` é Ridgun puro
Esqueça aprender TOML para o Cargo, JSON para o npm, XML para o Maven ou a sintaxe arcana de `Makefile` com tabulações invisíveis. Em Ridgun, a receita que constrói o seu projeto (`build.rg`) **é mais um ficheiro `.rg`**, com as mesmas funções puras e o mesmo *pattern matching* que o resto do seu código.

### 8. A "Santíssima Trindade" que parecia impossível: Nível Haskell + Memória RMM sem GC nem Lifetimes + Binários de ~350 KB
Até hoje tinha de escolher:
- Se queria expressividade funcional pura (Haskell, OCaml, Elixir), pagava com um coletor de lixo e um runtime pesado.
- Se queria binários diminutos de sistema sem coletor de lixo (C, Rust, Zig), pagava gerindo ponteiros ou lutando com o *borrow checker* e escrevendo código imperativo cheio de `let mut`.

O Ridgun rompe esse dilema combinando **Ridgun Memory Management (`RMM`: `RMM1` estática e `RMM2` por contagem de atribuições em cascata)**, **regiões léxicas (`with region`)** que libertam arenas inteiras em $O(1)$, **recursão de cauda transformada em ciclos nativos (`loop`)**, e **poda de grafo de chamadas (*Tree-Shaking*)** a partir de `main`. O resultado: escreve código declarativo de altíssimo nível e obtém um executável ELF autónomo de **~350 KB** capaz de competir de igual para igual com ferramentas escritas em C.

Agora sim: com as cartas na mesa, vamos ao **Capítulo 02** para pôr a trabalhar o **`ridgunc`** e o **`stable`**.
