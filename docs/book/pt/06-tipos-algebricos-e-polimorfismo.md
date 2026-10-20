# Capítulo 06: Tipos de Dados Algébricos (ADTs), Polimorfismo e porque é que aqui não queremos `null` nem `Any`

Em 1965, Tony Hoare inventou a referência nula (`null` / `nil`). Quarenta anos depois pediu desculpa publicamente e chamou-lhe *"o meu erro de mil milhões de dólares"*.

Porquê? Porque nas linguagens com `null`, uma função promete-lhe na assinatura que lhe vai devolver um `Utilizador`... e quando menos espera devolve-lhe `null` e deita abaixo o servidor às três da manhã.

E o mesmo acontece com a herança de objetos e o tipo `Any` (ou `Object`): coloca um número e um texto numa lista `[1, "dois"]`, a linguagem encolhe os ombros e diz *"está bem, então agora isto é uma `List[Any]`, boa sorte a adivinhar o que está lá dentro quando a percorrer"*.

Em Ridgun cortamos esses dois problemas pela raiz com **Tipos de Dados Algébricos (ADTs)** e **Polimorfismo Paramétrico**. Soa a nome de cadeira difícil da faculdade, mas em cinco minutos vai ver que é a forma mais natural do mundo de modelar dados.

---

## 6.1. Tipos Produto (Registos): Os seus `struct` de toda a vida, mas com superpoderes

Quando quer agrupar vários dados que pertencem a uma mesma entidade (por exemplo, um servidor com o seu nome, o seu IP e a sua porta), define um **`type`** com os seus campos:

```ridgun
type Servidor = host: String, porta: Int, tls_ativo: Bool
```

Só por escrever essa linha, o Ridgun oferece-lhe **quatro coisas** automaticamente:

### 1. O construtor `Servidor`
```ridgun
meu_no => Servidor
meu_no =  Servidor "api.exemplo.com" 443 True
```

### 2. Uma função *getter* pura para cada campo (`host`, `porta`, `tls_ativo`)
Não precisa de escrever `s.getHost()` nem nada parecido; cada nome de campo é diretamente uma função que extrai esse dado:

```ridgun
url_ligacao Servidor => String
url_ligacao srv      =  "Ligar a " + (host srv) + " na porta {porta srv}"
```

### 3. Atualização funcional de registos (`with campo: valor`)
Imagine um registo de configuração com 12 ou 15 campos (como as opções de um comando `ls` ou de um servidor web) e quer mudar apenas um ou dois campos sem tocar no resto. Em vez de reconstruir o registo passando os 15 campos à mão, usa **`with`** e dois pontos **`:`** (exatamente igual à definição do `type`):

```ridgun
ativar_modo_dev Servidor => Servidor
ativar_modo_dev srv      =  srv with porta: 8080, tls_ativo: False
```

O melhor dos dois mundos:
- No seu código é **100% imutável e seguro** (o compilador verifica que `porta` e `tls_ativo` existem em `Servidor` e têm o tipo correto).
- Por baixo, se `srv` não estiver partilhado com mais ninguém, o executável nativo reutiliza a sua memória *in-place* (`Arc::try_unwrap`) sem copiar os restantes campos.

### 4. *Pattern matching* completo caso queira abrir o registo de ponta a ponta
```ridgun
e_porta_segura Servidor                => Bool
e_porta_segura (Servidor _ 443 True)   =  True
e_porta_segura _                       =  False
```

---

## 6.2. Tipos Soma (Variantes com `|`): Como reformar o `null`, as exceções e a herança

Agora vem a melhor parte.
Um registo normal tem `host` **E** `porta` **E** `tls_ativo`.
Mas no mundo real muitas vezes precisa de dizer: *"Um método de pagamento é **OU** um cartão com o seu número, **OU** uma transferência com o seu IBAN, **OU** dinheiro vivo (que não leva nenhum dado extra)"*.

Em orientação a objetos teria de criar uma interface `MetodoPagamento`, três subclasses em três ficheiros diferentes, construtores, `instanceof`... Em Ridgun é **uma linha**:

```ridgun
type MetodoPagamento = Cartao String Int | Transferencia String | Dinheiro
```

E veja o que acontece quando processa um `MetodoPagamento` numa função:

```ridgun
descrever_pagamento MetodoPagamento      => String
descrever_pagamento (Cartao num _)       =  "Pagamento com cartão terminado em {num}"
descrever_pagamento (Transferencia iban) =  "Transferência da conta {iban}"
descrever_pagamento Dinheiro             =  "Pagamento em numerário no balcão"
```

Cada variante (`Cartao`, `Transferencia`, `Dinheiro`) traz colados unicamente os dados que fazem sentido para ela. É **impossível** construir um pagamento em `Dinheiro` que tenha um `iban` pendurado por erro.

---

## 6.3. "E como meto `[1, "dois"]` numa lista sem usar `Any`?"

Voltemos à pergunta de um milhão de dólares. Imagine que está a ler um ficheiro CSV ou JSON onde uma célula pode ser um número inteiro, um texto ou estar vazia.

Se tivesse um tipo `Any`, meteria `[1, "dois"]` e perderia toda a ajuda do compilador: a partir desse momento qualquer operação sobre a lista seria caminhar de olhos vendados.

Em Ridgun (tal como em Haskell ou Rust), cria em dois segundos um tipo soma que explica exatamente que coisas podem viver dentro dessa lista:

```ridgun
type ValorCelula = Inteiro Int | Texto String | Vazio

formatar_celula ValorCelula => String
formatar_celula (Inteiro n) =  "Número: {n}"
formatar_celula (Texto s)   =  "Texto: {s}"
formatar_celula Vazio       =  "(vazio)"

minha_linha => [ValorCelula]
minha_linha =  [Inteiro 1, Texto "dois", Vazio]
```

Vê a diferença?
- Com `Any`, o compilador não sabe se na lista há inteiros, cadeias ou uma cafeteira ligada por USB.
- Com `[ValorCelula]`, pode misturar números e textos na mesma lista, **mas o compilador sabe a 100% que só existem essas três possibilidades** e obriga-o a desempacotar cada caso (`Inteiro n`, `Texto s`, `Vazio`) antes de o usar. Segurança total sem perder nem um pingo de flexibilidade.

---

## 6.4. `Option` e `Result`: Quando algo pode não estar presente ou pode falhar

Como em Ridgun não existe `null` nem existem exceções que expludam pelos ares (`throw new Exception()`), a linguagem traz integrados dois tipos soma universais:

1. **`Option`**: ou tem **`Some valor`**, ou tem **`None`** (nada).
2. **`Result`**: ou a operação correu bem (**`Ok valor`**), ou falhou por um motivo concreto (**`Err erro`**).

```ridgun
procurar_divisao Int Int => Result
procurar_divisao _   0   =  Err "Ei! Não se pode dividir por zero"
procurar_divisao a   b   =  Ok (a / b)

imprimir_res Result    => ()
imprimir_res (Ok n)    =  echo "O resultado é {n}"
imprimir_res (Err msg) =  echo "Falha controlada: {msg}"
```

Ninguém pode ignorar um erro por descuido porque o próprio tipo `Result` o obriga a verificar se lá dentro há um `Ok` ou um `Err`.

---

## 6.5. Polimorfismo Paramétrico: Funções genéricas com `A`, `B`, `T`...

Suponha que escreve uma função que inverte um par `(x, y)` ou que extrai o primeiro elemento de uma lista. Importa mesmo se a lista é de `Int`, de `String` ou de `Servidor`? De maneira nenhuma! O algoritmo é idêntico.

Em Ridgun, **qualquer letra maiúscula individual (`A` a `Z`)** numa assinatura de tipos funciona automaticamente como um **tipo curinga polimórfico (variável de tipo)**:

```ridgun
cabeca_segura [A]   A           => A
cabeca_segura []    por_omissao =  por_omissao
cabeca_segura (x:_) _           =  x

rodar_par (A, B) => (B, A)
rodar_par (x, y) =  (y, x)
```

Repare na magia de `cabeca_segura [A] A => A`:
- Não é um `Any` descontrolado: diz que **o tipo da lista `[A]`, o tipo do valor `por_omissao` (`A`) e o tipo devolvido (`A`) têm de ser o mesmo**.
- Se chamar `cabeca_segura [10, 20] 0`, o compilador junta as pontas (`A = Int`) e devolve-lhe um `Int`.
- Se chamar `cabeca_segura ["a", "b"] "nenhum"`, junta as pontas (`A = String`) e devolve-lhe uma `String`.
- Mas se tentar fazer batota e chamar `cabeca_segura [10, 20] "nenhum"`, zás! O compilador trava-o a fundo porque o primeiro argumento diz que `A` é `Int` e o segundo diz que `A` é `String`.

---

## 6.6. Crie os seus próprios operadores (`op ::`): Desde vetores até frases por medida

Porque é que só os números nativos haveriam de ter direito a usar `+` ou `*`? E porquê conformar-se com os operadores do costume quando pode inventar a sintaxe perfeita para o seu problema?

Com **`op ::`** (ou diretamente sem prefixo se usar padrões de operador) pode fazer duas proezas:

### 1. Ensinar `+`, `-`, `*`, `/`, `%` a operar com os seus próprios tipos
```ridgun
type Complexo = real: Int, imag: Int

op :: Complexo + Complexo => Complexo
      a        + b        =  Complexo ((real a) + (real b)) ((imag a) + (imag b))
```

### 2. Criar operadores *Mixfix* (que se leem como frases naturais, incluindo `type` e `with`)
Numa assinatura de operador, **as palavras com maiúscula inicial (`Int`, `String`, `A`..`Z`) ou entre parênteses retos/curvos (`[Int]`, `(A, B)`) são os espaços para os argumentos**, e **as palavras em minúsculas fazem parte da frase do operador** (mesmo palavras tão habituais como `type` ou `with`, que em Ridgun são contextuais e nunca o bloqueiam):

```ridgun
op :: se Bool entao A senao A => A
      se True entao v senao _ =  v
      se False entao _ senao f = f

op :: format String type String with Int => String
      format label  type kind   with w   =  "{label} ({kind}, width={w})"

main => ()
main =
  mensagem = se (10 > 5) entao "O dez ganha!" senao "Impossível"
  echo mensagem
  echo (format "painel" type "com_borda" with 80)
```

Acabou de fabricar o seu próprio operador ternário polimórfico e um DSL de formatação em **3 linhas** de Ridgun.

No **Capítulo 07** vamos pôr todos os núcleos do seu processador a trabalhar ao mesmo tempo sem derramar uma gota de suor: **funções de ordem superior (`map`, `||map`, `filter`, `||filter`, `fold`), grafos paralelos `||` com `->` e canais concorrentes**.
