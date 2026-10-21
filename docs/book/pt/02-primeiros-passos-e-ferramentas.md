# Capítulo 02: Os seus dois melhores amigos: `ridgunc` e `stable` (Zero ficheiros YAML, prometido)

Há linguagens cujo compilador é maravilhoso, mas cujo sistema de projetos parece desenhado pelo seu pior inimigo: ora um `Makefile` de 400 linhas com tabulações invisíveis, ora um `pom.xml` infinito, ora um `webpack.config.js` que deixa de funcionar se olhar fixamente para ele...

Em Ridgun fizemos uma promessa muito simples desde o primeiro dia:

> *"Só haverá dois executáveis em todo o ecossistema (`ridgunc` e `stable`), ambos serão escritos no próprio Ridgun, e o ficheiro de configuração do projeto (`build.rg`) será código Ridgun normal e corrente. Nem JSON, nem YAML, nem TOML, nem invenções estranhas."*

Vamos ver como se usam.

---

## 2.1. `ridgunc`: O atirador furtivo para ficheiros soltos

Quando tem um único ficheiro `.rg` em mãos e quer testar uma ideia rápida, analisar os seus tipos ou compilar um executável, fala diretamente com o **`ridgunc`**.

Só tem 4 comandos que realmente precisa de recordar:

```bash
# 1. "Isto compila ou meti água com algum tipo?"
ridgunc check experiencia.rg

# 2. "Executa já!" (Compila e corre de uma só vez)
ridgunc run experiencia.rg

# 3. "Faz-me um binário nativo ELF pronto a levar"
ridgunc build experiencia.rg -o meu_programa

# 4. "Gera-me o artefacto intermédio de bytecode (.rgc)"
ridgunc compile experiencia.rg -o experiencia.rgc
```

### O superpoder oculto de `ridgunc check`
Quando lança `ridgunc check`, não lhe diz apenas *"0 erros"*. Também lhe revela que estratégia o analisador estático escolheu para cada uma das suas funções:
- **`InlineSequential`**: *"Esta função é pequenina e direta; vou executá-la em linha sem introduzir sobrecarga de escalonamento"*.
- **`LazyStealableTask`**: *"Aqui há recursão ou um grafo paralelo `||`; preparo-a para que outros núcleos de CPU possam roubar trabalho se for preciso"*.

### O bisturi de `ridgunc build` (Porque é que os seus binários não pesam 20 MB)
Quando executa `ridgunc build`, o compilador não se limita a despejar todo o código das bibliotecas que tenha importado:
1. Começa na sua função `main` e percorre o grafo de chamadas para ver **que funções usa de verdade**. Se importou uma biblioteca enorme de 80 funções mas só chama 2, as outras 78 são descartadas antes sequer de tocar no assembly (*Tree-Shaking*).
2. Procura todas as funções recursivas de cauda e converte-as em ciclos `loop` nativos que consomem **0 bytes de pilha**.
3. Passa a ligação final com otimização global (*fat LTO*) e limpa o lixo de depuração DWARF para lhe deixar um binário compacto e afiado (~350 KB).

---

## 2.2. `stable`: Quando o seu projeto cresce e quer ordem

Um ficheiro solto é ótimo para um script, mas assim que tem vários módulos, bibliotecas partilhadas e testes, precisa de um maestro de orquestra. Esse é o **`stable`**.

A estrutura de pastas de um projeto Ridgun não tem mistério:

```text
minha-super-ferramenta/
├── build.rg                  # O manifesto do projeto (é código Ridgun!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Os seus módulos reutilizáveis (`import utilitarios`)
│   │       └── app/
│   │           └── main.rg   # Ponto de entrada (`main => ()`)
│   └── test/
│       └── ridgun/           # As suas baterias de testes (`test *.rg`)
│           └── test tudo.rg
└── target/                   # Onde aparecem os binários compilados
```

---

## 2.3. `build.rg`: Um ficheiro de configuração que nunca lhe mentirá

Porque nos recusamos a usar YAML ou TOML para configurar um projeto Ridgun?
Porque em YAML engana-se em dois espaços de indentação e só descobre quando falha a implementação. Em contrapartida, como **`build.rg` é um ficheiro Ridgun**, tem tipos estáticos, passa pelo `stable check` e alinha-se sozinho com `stable format`:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "minha-super-ferramenta" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"
```

Se cometer um erro ao escrever um campo, o próprio compilador avisa-o. Sem surpresas.

---

## 2.4. A sua rotina diária com `stable` (Os 4 fantásticos)

Quando está a trabalhar dentro do seu projeto, o seu dia a dia resume-se a quatro comandos:

### 1. `stable format` — O fim das discussões de estilo na equipa
```bash
stable format
```
O seu colega põe três espaços antes do `=>` e você põe um? Tanto faz. Executa `stable format` e em menos de um segundo deixa **todos** os ficheiros `.rg` do repositório alinhados como um relógio suíço.

### 2. `stable check` — O radar instantâneo
```bash
stable check
```
Percorre todos os módulos de `src/main/ridgun/`, verifica tipos, construtores, aridades e dimensões de tensores, e dá-lhe o veredito módulo a módulo.

### 3. `stable test` — Dormir descansado à noite
```bash
stable test
```
Procura todas as suites `src/test/ridgun/test *.rg`, executa-as e comprova cada `assert equals` e `assert true`.

```ridgun
-- Exemplo de src/test/ridgun/test matematica.rg
import test

dobro Int => Int
dobro x   =  x * 2

main => ()
main =
  assert equals (dobro 21) 42
  assert true ((dobro 5) > 0)
```

### 4. `stable built` (e `stable clean`) — Para produção
```bash
stable built
```
Compila todos os alvos nativos em `target/`. E se algum dia quiser apagar `target/` e começar limpo: `stable clean`.

---

## 2.5. Como importo um ficheiro a partir de outro? (`import`)

Sem caminhos relativos infernais do tipo `../../../lib/coisas.rg`. Se tiver um ficheiro `src/main/ridgun/lib/cadeias.rg`, em qualquer outro ficheiro escreve mesmo no topo:

```ridgun
import cadeias
```

E pronto: todas as funções e tipos de `cadeias.rg` ficam disponíveis como se estivessem no seu próprio ficheiro. E o que acontece se o módulo `A` fizer `import cadeias`, o módulo `B` também fizer `import cadeias`, e o seu `main.rg` importar `A` e `B`? Fique descansado: o carregador do Ridgun lembra-se de que ficheiros canónicos já leu e **só o inclui uma vez**.

Agora que tem a caixa de ferramentas controlada, passemos ao **Capítulo 03** para dominar as funções, os tipos, os blocos e os truques com cadeias de texto.
