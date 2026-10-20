# Capítulo 07: Funcións de Orde Superior e Paralelismo sen Suor (Nin `Mutex`, nin `Deadlocks`)

En case todas as linguaxes de programación hai un momento dramático na vida dun proxecto: o día en que alguén di nunha xuntanza:

> *"Isto vai lento. Hai que paralelizalo con fíos."*

Faise o silencio na sala. Todo o mundo sabe o que vén despois: semanas cazando *race conditions* pantasma que só ocorren os martes con lúa chea, bloqueos mutuos (*deadlocks*) e erros irreproducibles.

En Ridgun, cando alguén di *"hai que paralelizalo"*, abonda con antepoñer `||` ás túas operacións de lista (**`||map`** e **`||filter`**) ou poñer os teus cálculos nun bloque paralelo `||` con frechas `->` e vas tomar un café.

Por que? Porque **cando as túas funcións son puras e os teus datos son inmutables por defecto, dous núcleos de CPU traballando á vez xamais poden pisarse a mangueira**.

Imos velo paso a paso.

---

## 7.1. Funcións que reciben funcións: `map`, `||map`, `filter`, `||filter` e `fold`

En Ridgun unha función é un valor máis. Podes pasala por parámetro igual que pasas o número `7`.

A linguaxe trae de serie os combinadores de coleccións para transformar listas sen escribir nin unha soa recursión manual, tanto en modo secuencial (`map`, `filter`, `fold`) como en modo paralelo multicore co prefixo `||` (**`||map`**, **`||filter`**):

### 1. `map` (secuencial) e `||map` (paralelo multicore)
Supón que tes unha función `custoso Int => Int` e unha lista con números:

```ridgun
custoso Int => Int
custoso x   =  (x * x) + (x * 3)

main => ()
main =
  datos = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Secuencial estrito de esquerda a dereita:
  r1 = map custoso datos
  -- Paralelo multicore co prefixo `||`:
  r2 = ||map custoso datos
  echo r1
  echo r2
```

- Con **`map`**, Ridgun aplica a función elemento a elemento de esquerda a dereita no fío actual (ideal para listas pequenas ou funcións con efectos de entrada/saída ordenados).
- Con **`||map`**, o runtime de Ridgun reparte os elementos de `datos` entre os fíos traballadores do teu procesador e reconstrúe a lista final **exactamente na mesma orde**, garantindo que `||map f xs == map f xs`.

### 2. `filter` (secuencial) e `||filter` (paralelo): Quedar só cos que cumpran unha condición
Pásaslle unha función que devolva `Bool` (un *predicado*) e unha lista:

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

### 3. `fold`: Reducir toda unha lista a un só resultado
Pásaslle unha función combinadora de dous argumentos `(Acumulado Elemento => Acumulado)`, o valor inicial e a lista:

```ridgun
acumular_produto Int Int => Int
acumular_produto acc x   =  acc * x

main => ()
main =
  echo (fold acumular_produto 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### Como escribo eu a miña propia función que reciba outra función?
Moi doado: na sinatura de tipos pos a sinatura da función convidada entre parénteses `(Entrada => Saida)`:

```ridgun
executar_duas_veces (A => A) A => A
executar_duas_veces f        x =  f (f x)
```

---

## 7.2. A xoia da coroa: Bloques `||` con `->` como Grafos Paralelos (DAGs)

Aquí é onde Ridgun muda a túa forma de pensar.

Nunha linguaxe imperativa normal, cando escribes tres liñas seguidas:
1. Primeiro execútase a liña 1.
2. Logo a liña 2 (aínda que non teña nada que ver coa liña 1).
3. Logo a liña 3.

Iso é obrigar o ordenador a traballar con anteolleiras. En Ridgun, cando usas barras paralelas **`||`** con frechas **`->`** (sen necesidade de escribir ningunha palabra chave como `where`), non estás dando ordes secuenciais: estás debuxando un **Grafo Acíclico Dirixido (DAG)** que di que cálculo alimenta a que variable:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_calculo => Int
super_calculo =  rama_esquerda + rama_dereita
  || fib 10 -> rama_esquerda
  || fact 6 -> rama_dereita
```

Leo en voz alta:
- *"Quero calcular `rama_esquerda + rama_dereita`, mentres en paralelo (`||`) `fib 10` vai a `rama_esquerda` (`->`) e `fact 6` vai a `rama_dereita` (`->`)."*

### O que fai `ridgunc` entre bastidores coas túas liñas `||`:
1. Mira as frechas `->` e arma a árbore de dependencias (DAG).
2. **Caza ciclos estaticamente**: se por erro escribes `|| a + 1 -> b` e `|| b + 1 -> a`, o compilador diche no acto *"Quietos! Hai unha dependencia circular"* e non che deixa compilar un colgue infinito.
3. Ve que `fib 10` e `fact 6` non dependen o un do outro, así que teñen luz verde para correr en paralelo antes de sumarse en `rama_esquerda + rama_dereita`.

Mesmo podes montar unha tubaxe de varias plantas dentro do mesmo bloque `||` —xa sexa ao pé da expresión ou xusto despois do `=`— e o compilador deducirá el só que plantas poden ir á vez e cales teñen que agardar:

```ridgun
balance_trimestral Int  => Int
balance_trimestral base =
  || base * 100                   -> vendas_brutas
  || base * 40                    -> custos_fixos
  || vendas_brutas - custos_fixos -> beneficio_bruto ||.
  beneficio_bruto * 80 / 100
```

Fíxate no detalle **`||.`** ao final da última liña `||`: igual que `|.` pecha unha árbore de gardas aniñada, **`||.`** pecha o bloque paralelo `||` cando debaixo seguen sentenzas secuenciais normais. Aquí `vendas_brutas` e `custos_fixos` arrincan en paralelo; cando ambos están listos calcúlase `beneficio_bruto`, e finalmente devólvese `beneficio_bruto * 80 / 100`. Todo sen un só `async`, `Future`, `Promise` nin `Mutex`.

---

## 7.3. O atallo `||` sen nomes: Tubaxes paralelas que devolven unha tupla

E se só queres lanzar dous ou tres cálculos en paralelo e recollelos xuntos nunha tupla sen sequera inventar nomes de variables con `->`?

Usas `||` directamente:

```ridgun
par_paralelo Int => (Int, Int)
par_paralelo n   =
  || fib n
  || fact n
```

Directo, visual e devolve a tupla `(fib n, fact n)`.

---

## 7.4. Cando queres o volante manual: `spawn`, `join` e Canles CSP

O paralelismo automático de `||` e `map` cobre o 90% dos casos. Pero ás veces estás programando un sistema de actores, unha fila de traballos ou unha tubaxe produtor-consumidor e queres controlar ti mesmo as tarefas e as mensaxes.

Para iso tes dúas ferramentas limpas:

### 1. Lanzar tarefas con `spawn` e recoller o resultado con `join`
```ridgun
procesar_lote Int => Int
procesar_lote id  =  id * 100

main => ()
main =
  tarefa1 = spawn procesar_lote 1
  tarefa2 = spawn procesar_lote 2
  -- Mentres tanto poderías facer outras cousas aquí...
  res1 = join tarefa1
  res2 = join tarefa2
  echo "Remataron con:" res1 "e" res2
```

### 2. Pasar mensaxes por canles acoutadas (`new_bounded_channel`)
Igual ca en Go ou Erlang, en lugar de compartir memoria entre fíos, envías valores inmutables a través dun tubo seguro:

- `new_bounded_channel capacidade`: crea unha canle con espazo para `capacidade` mensaxes.
- `chan_send valor canle` (ou `send_through valor canle`): mete unha mensaxe no tubo.
- `chan_recv canle` (ou `receive_from canle`): saca a seguinte mensaxe do tubo.
- `chan_try_recv canle`: mira se hai mensaxe sen quedar agardando; devolve `Some valor` ou `None`.
- `receive_from_timeout canle ticks`: agarda un límite de tempo e devolve `Ok valor` ou `Err Timeout`.

```ridgun
main => ()
main =
  tubo = new_bounded_channel 4
  _ = chan_send "Tarefa A completada" tubo
  _ = chan_send "Tarefa B completada" tubo
  primeiro = chan_recv tubo
  segundo = chan_recv tubo
  echo primeiro "|" segundo
```

E agora, abrocha o cinto para o **Capítulo 08**, o gran final: **tensores con dimensións verificadas en compilación, variables de ámbito (`context`/`shared`), rexións de memoria deterministas, acceso directo a hardware MMIO e programación de sistemas UNIX/POSIX**.
