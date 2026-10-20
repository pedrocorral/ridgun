# Capítulo 00: Por que preciso do Ridgun? Ah, é? Não sabia... Conte-me mais!

Sejamos sinceros: quando alguém lhe diz *"criámos uma nova linguagem de programação"*, a sua primeira reação natural — e muito saudável — é arquear uma sobrancelha e pensar:

> *"Mais uma? Mas se eu já tenho Python para ir rápido, Rust ou C para quando preciso de velocidade, e Bash para colar coisas no terminal. Para que raio preciso eu de aprender Ridgun?"*

É uma excelente pergunta. E a resposta curta é: **porque se habituou a sofrer três dores diárias achando que eram inevitáveis**.

Vamos dar-lhes um nome.

---

## Dor n.º 1: "A síndrome dos dois mundos" (Prototipar num, reescrever noutro)

De certeza que já viveu este filme:

1. Começa uma ferramenta ou um motor de cálculo em **Python**, **JavaScript** ou **Ruby** porque quer pensar no problema, não em ponteiros nem no compilador.
2. O código fica curto e bonito... mas quando lhe passa um ficheiro de 500 MB ou tenta usar os 16 núcleos da sua máquina, arrasta-se. E se quiser distribuir o seu programa para um servidor limpo, tem de empacotar meio gigabyte de ambiente virtual, interpretador e bibliotecas dinâmicas.
3. Resignado, decide reescrevê-lo em **C**, **C++** ou **Rust**. Agora voa e ocupa apenas algumas centenas de kilobytes, mas o seu código de 40 linhas transformou-se em 300 linhas cheias de `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, chavetas `{}` e pontos e vírgulas `;`.

**O que muda com o Ridgun?**
Em Ridgun escreve código **mais curto e limpo do que em Python**, mas quando executa `ridgunc build`, obtém **um único binário nativo ELF de ~350 KB** sem interpretador, sem máquina virtual externa e sem coletor de lixo (*Garbage Collector*). Não há fase de *"depois reescrevemos na linguagem rápida"*: o código limpo onde pensa o problema **já é** o binário nativo de produção.

---

## Dor n.º 2: "Ler código alheio (ou o seu de há 6 meses) é brincar aos detetives"

Veja como escrevemos lógica condicional em quase todas as linguagens mainstream:

```text
if (estado == ATIVO && (papel == ADMIN || (papel == EDITOR && temPermissao))) {
    if (quota > 0) {
        return processar(utilizador);
    } else {
        return negar("Sem quota");
    }
} else {
    return negar("Não autorizado");
}
```

Os nossos olhos não evoluíram para emparelhar chavetas aninhadas nem para desemaranhar árvores de `if / else` em escada. Quando engenheiros, matemáticos ou físicos querem entender regras complexas sem se enganarem, não escrevem parágrafos de `if / else`: **desenham uma tabela**.

Em Ridgun, **o código é essa tabela**:

```ridgun
autorizar String  String   Bool  Int   => String
autorizar "ativo" "admin"  _     quota =
  | quota > 0 = "A processar pedido"
  | otherwise = "Negado: sem quota"
autorizar "ativo" "editor" True  quota =
  | quota > 0 = "A processar pedido"
  | otherwise = "Negado: sem quota"
autorizar _       _        _     _     =  "Negado: não autorizado"
```

Repare nas colunas:
- Coluna 1: o estado (`"ativo"` ou `_`).
- Coluna 2: o papel (`"admin"`, `"editor"` ou `_`).
- Coluna 3: se tem permissão (`True` ou `_`).
- Coluna 4: a `quota`.

Não precisa de executar mentalmente o programa linha por linha para saber o que acontece quando entra um `"editor"` com permissão `False`: os seus olhos descem verticalmente pela tabela e veem-no em meio segundo.

---

## Dor n.º 3: "O meu computador tem 16 núcleos, mas o meu programa só usa 1 (porque tenho pânico de mexer em threads)"

Hoje até o telemóvel mais modesto tem 8 núcleos, e qualquer servidor ou portátil de trabalho tem entre 12 e 32. No entanto, 95% dos programas do dia a dia continuam a ser executados numa única thread sequencial.

Porquê? Porque nas linguagens imperativas, paralelizar significa abrir a caixa de Pandora:
- E se duas threads modificarem o mesmo dicionário ao mesmo tempo? (*Data race*).
- E se eu bloquear o `Mutex` A e depois o B numa thread, e o B e depois o A noutra? (*Deadlock*).
- E se eu contaminar toda a minha base de código com `async` e `await` de cima a baixo?

Em Ridgun, **toda a função é pura e todo o dado é imutável por omissão**. Isso tem uma consequência mágica: **duas expressões que não dependem uma da outra jamais podem interferir entre si**.

Por isso, em Ridgun não precisa de gerir threads para aproveitar o seu CPU. Só declara **o que depende do quê** com barras paralelas `||` e setas `->`:

```ridgun
relatorio_mensal Dados => Relatorio
relatorio_mensal d     =  combinar metricas_rede metricas_disco metricas_cpu
  || analisar_rede d  -> metricas_rede
  || analisar_disco d -> metricas_disco
  || analisar_cpu d   -> metricas_cpu
```

Só escreveu três linhas limpas indicando de onde sai cada dado. O compilador vê que os três ramos são independentes e sabe que pode lançá-los em paralelo sem que exista a mais mínima possibilidade de um *data race* ou de um *deadlock*.

---

## Dor n.º 4: "O coletor de lixo decide pausar o mundo mesmo no pior momento"

As linguagens funcionais clássicas (Haskell, OCaml, Erlang, Clojure) são maravilhosas para raciocinar sobre o código, mas quase todas dependem de um **Coletor de Lixo (*Garbage Collector*)** em tempo de execução. Isso descarta-as quando precisa de:
- Latências previsíveis ao microssegundo.
- Controlar exatamente quanta memória RAM uma operação pode consumir antes de a abortar de forma limpa.
- Escrever utilitários do sistema operativo (`ls`, `find`, `sh`, `doas`, `make`) ou tocar em registos de hardware (`MMIO`).

O Ridgun dá-lhe **toda a elegância do mundo funcional puro, mas com Gestão de Memória do Ridgun (`RMM`: `RMM1` estática e `RMM2` por contagem de atribuições em cascata) mais regiões léxicas com quota exata (`with region`)**:

```ridgun
analisar_pacote String => Result
analisar_pacote bruto  =
  with region 16_KB do
    descodificar_trama bruto
```

Cada estrutura temporária é libertada de forma determinística pelo compilador (`RMM1` / `RMM2`) no instante em que deixa de ser usada, e se um atacante lhe enviar um pacote malicioso desenhado para rebentar a memória, ao ultrapassar o byte 16.384 a região é cortada no instante, liberta a sua arena em $O(1)$ e devolve `Err OutOfMemory`. Sem quedas do processo, sem pausas de GC e sem fugas de memória.

---

## Em resumo: Quando é que o Ridgun brilha?

O Ridgun foi feito para si se alguma vez quis:

1. **Escrever ferramentas de sistemas, compiladores, analisadores ou utilitários CLI** que arranquem em microssegundos, pesem apenas algumas centenas de KB e não possam quebrar por ponteiros nulos nem efeitos colaterais ocultos.
2. **Programar algoritmos, pipelines de dados ou álgebra de tensores** onde o compilador verifique por si até as dimensões das matrizes (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) antes de executar o que quer que seja.
3. **Desfrutar a ler o seu próprio código**: que cada ficheiro `.rg` pareça uma página de um livro bem paginado graças ao formatador tabular automático (`stable format`).

Ficou com curiosidade? Passe ao **Capítulo 01** e vamos escrever o nosso primeiro programa em menos de dois minutos.
