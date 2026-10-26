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

### 4. Clausuras léxicas e funcións anónimas (`(x => expr)`, `(acc x => expr)`)
Cando queres pasar unha función curta ao voo ou capturar variables locais do teu ámbito actual (como un desprazamento, un prefixo ou unha sesión activa) sen declarar unha función global auxiliar, usas unha **clausura léxica** entre parénteses con **`=>`**:

```ridgun
fn :: procesar con sesion => [Int]
      procesar con sesion =
        base      = 10
        bono      = 3
        sumados   = map (x => x + base) [1, 2, 3]
        filtrados = filter (x => x >= bono) [1, 2, 3, 4]
        total     = fold (acc x => acc + x + bono) 0 [1, 2, 3]
        pares     = map ((a b) => a + b + base) [(1, 2), (3, 4)]
        sumados :: filtrados :: [total] :: pares
```

Cinco regras manteñen as lambdas limpas e sen ambigüidade:
- **Parénteses obrigatorias**: toda lambda vai sempre entre parénteses `(... => ...)`.
- **Lambda sen parámetros (`(=> expr)`)**: igual que `fn :: main => ()` non leva `()` antes de `=>`, unha lambda sen parámetros escríbese `(=> expr)` (e o seu tipo é `(=> Tipo)`), nunca `(() => expr)`.
- **Varios parámetros fronte a tupla (`(a b => ...)` vs. `((a b) => ...)`)**: `(acc x => ...)` recibe dous parámetros separados; `((a b) => ...)` recibe unha soa tupla e desestrutúraa.
- **Corpo de varias liñas**: se pos un salto de liña tras `=>`, podes escribir un bloque sangrado de varios pasos antes do `)` de peche:
  ```ridgun
  dobres = map (x =>
    paso = x * 2
    paso + base
  ) [1, 2, 3]
  ```
- **Maiúsculas fronte a minúsculas**: `(Conn => Conn)` é un tipo de función (inicial maiúscula) e `(conn => conn)` é un valor lambda (inicial minúscula).

As variables capturadas (`base`, `bono`) empaquétanse automaticamente con xestión determinista de memoria (`RMM1`/`RMM2`), sen fugas e sen pausas de colector de lixo.

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

## 7.4. Cando queres o volante manual: o Modelo Nativo de Axentes (`agent`, `send ... to`, `receive from`) e Canles CSP

O paralelismo automático de `||` e `||map` cobre o 90% dos casos. Pero cando programas un servidor persistente, sesións de usuario con estado illado, filas de traballos ou unha tubaxe produtor-consumidor, queres **axentes concorrentes con memoria illada e paso de mensaxes tipado**.

En Ridgun non fai falta inventar unha sintaxe estraña como `actor ::`: **calquera función normal (`fn ::` ou `op ::`) convértese nun axente concorrente nunha liña con `agent`**:

### 1. Axentes sen estado e con estado illado (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (miña funcion)`: converte unha función `M => R` nun axente sen estado de tipo `Agent M R`.
- `ag = agent (funcion con estado) estado_inicial`: converte unha función `S M => S` (ou `S M => S R`) nun axente con estado illado que lembra o seu estado mensaxe tras mensaxe sen un só `Mutex`.
- `send msg to ag` (ou con varios argumentos: `send a b to ag`): envía unha mensaxe tipada á caixa de correo do axente.
- `res = receive from ag` (ou `try receive from ag` sen bloquear): recolle a seguinte resposta da caixa de saída do axente.
- `stop ag`: detén o axente e libera o seu estado automaticamente mediante `RMM1`/`RMM2`.

```ridgun
fn :: sumar visita Int Int => Int
      sumar visita acum n  =  acum + n

fn :: procesar lote Int Int => Int
      procesar lote id  t   =  (id * 100) + t

fn :: main => ()
      main =
        contador = agent (sumar visita) 10
        send 5 to contador
        send 7 to contador
        v1 = receive from contador
        v2 = receive from contador
        stop contador

        traballador = agent (procesar lote)
        send 3 25 to traballador
        lote = receive from traballador
        stop traballador
        echo "Visitas:" v1 "->" v2 "| Lote:" lote
```

### 2. Elección intelixente en tempo de compilación (*Green Threads* vs. Fíos Reais do Kernel)
Unha pregunta habitual é: *"Os bloques `||`, `||map` e os axentes `agent` crean sempre fíos do sistema operativo ou corren como tarefas lixeiras?"*

En Ridgun, **o compilador toma esa decisión por ti analizando estaticamente cada función**:
- **Funcións lixeiras (`TierTrivial` / `StratInlineSequential`)**: Se a función que pasas a `||`, `||map`, `||filter` ou `agent` ten pouca profundidade (aritmética, formatado de cadeas, transición de estado rápida dunha sesión HTTP), quentar fíos do sistema operativo custaría máis có propio cálculo. O compilador execútaa como un paso *green-thread* ultralixeiro sen sobrecarga de `SYS_clone`.
- **Cálculos pesados ou recursivos profundos (`TierDynamicRecursive` / `TierHeavyCPU`)**: Se a función ten recursión profunda (como `fib` ou `fact`) ou álxebra de tensores (`einsum`, `hadamard`, `@`), o compilador xera automaticamente o despacho multinúcleo sobre **fíos reais do kernel (`SYS_clone`)**, procesando as ramas `||` ou a cola de mensaxes do `agent` en paralelo real sobre todos os teus núcleos de CPU.

### 3. Pasar mensaxes por canles acoutadas (`new bounded channel`)
Igual ca en Go ou Erlang, ademais de axentes tamén podes crear tubos explícitos para comunicar etapas:

- `new bounded channel capacidade`: crea unha canle con espazo para `capacidade` mensaxes.
- `send through valor canle` (ou `chan send valor canle`): mete unha mensaxe no tubo.
- `receive from canle` (ou `chan recv canle`): saca a seguinte mensaxe do tubo.
- `try receive from canle`: mira se hai mensaxe sen quedar agardando; devolve `Some valor` ou `None`.
- `receive from timeout canle ticks`: agarda un límite de tempo e devolve `Ok valor` ou `Err Timeout`.

```ridgun
fn :: main => ()
      main =
        tubo = new bounded channel 4
        _ = send through "Tarefa A completada" tubo
        _ = send through "Tarefa B completada" tubo
        primeiro = receive from tubo
        segundo = receive from tubo
        echo primeiro "|" segundo
```

E agora, abrocha o cinto para o **Capítulo 08**, o gran final: **tensores con dimensións verificadas en compilación, variables de ámbito (`context`/`shared`), rexións de memoria deterministas, acceso directo a hardware MMIO e programación de sistemas UNIX/POSIX**.
