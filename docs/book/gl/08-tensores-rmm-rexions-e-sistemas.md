# Capítulo 08: Tensores, Memoria Compilada RMM (`RMM1`/`RMM2`), Rexións e Sistemas

Ata aquí vimos o lado máis amable, elegante e matemático de Ridgun: funcións puras, tipos alxébricos, *pattern matching*, árbores de decisión con `|` / `|.` e grafos paralelos `||` con `->` que aproveitan todos os núcleos do teu procesador sen pedirche nin un triste `Mutex`.

Chegados a este punto, o programador veterano de sistemas adoita erguer a man ao fondo da aula con medio sorriso e preguntar:

> *"Todo isto é precioso para calcular facturas ou compilar ASTs, pero que pasa cando preciso multiplicar matrices de millóns de flotantes a velocidade de vertixe? Que pasa coa memoria? Hai un colector de lixo (Garbage Collector) agochado debaixo da alfombra agardando o peor momento para conxelar o meu programa durante 200 milisegundos? E como falo co sistema operativo Unix de verdade?"*

Excelentes preguntas. Imos levantar o capó de Ridgun para ver como se las gasta cando toca baixar ao barro dos sistemas, o cálculo numérico e a memoria determinista.

---

## 8.1. O dilema da memoria: nin Garbage Collector nin pelexas co Borrow Checker (`RMM1` e `RMM2`)

No mundo das linguaxes modernas adoita haber dous bandos irreconciliables:

1. **O bando do Garbage Collector (Java, Go, Python, JS, Haskell, OCaml):** ti pides memoria alegremente e, de cando en vez, un camión do lixo invisible detén o tráfico do teu programa para rastrexar que obxectos seguen vivos e cales non. É comodísimo... ata que estás facendo unha ferramenta de sistema ultrarrápida ou un servidor con latencias estritas e o camión decide aparcar en dobre fila.
2. **O bando do control manual / Borrow Checker (C, C++, Rust):** non hai colector de lixo, pero a cambio tes que xestionar punteiros á man (xogándote un `Segmentation fault` ou un *use-after-free*) ou pasar media tarde negociando co *borrow checker* por que `'a` non vive tanto coma `'b`.

Ridgun resolve este dilema de raíz con **Ridgun Memory Management (`RMM`)**, un sistema determinista de dúas políticas complementarias (**`RMM1`** e **`RMM2`**) combinado con **rexións léxicas (`with region`)**:

### Política `RMM1` — Xestión de Memoria Compilada (CMM Lineal e Condicional)
Cando o compilador coñece estaticamente o fluxo das variables locais dentro dunha función:
- **CMM Lineal**: `ridgunc` calcula en tempo de compilación cal é a **última liña** na que se le cada variable local (`a`, `b`, ...) e insire xusto despois a súa liberación determinista (`rg_cmm_drop`), ou transfire a súa propiedade sen copias (`rg_cmm_move`) cando a variable se devolve como resultado.
- **CMM Condicional (`ptr(a) != ptr(c)`)**: e se unha función como `escoller cond a b` devolve `a` ou `b` segundo unha condición en tempo de execución? `ridgunc` constrúe a táboa de devanceiros e emite unha garda de identidade de punteiros de **1 ciclo de CPU**: se `b` deixa de usarse mentres `c` segue viva, comproba `if ptr(b) != ptr(c) { free(b) }`. A rama non escollida libérase ao instante e a escollida sobrevive intacta.

### Política `RMM2` — Conta por Asignación e Fervenza Estrutural
E que ocorre cando metes estruturas dentro doutras estruturas (`xs = [a, b]`), reasignas variables mutables (`mut x = ...`) ou encadeas chamadas complexas? Aí entra **`RMM2`**, que goberna todo o ciclo de vida con catro regras matemáticas sen fisuras:

1. **Os argumentos de entrada dunha función non se tocan (`+0` ao entrar, `-0` ao saír)**: pasar unha lista ou un rexistro a unha función xamais incrementa nin decrementa contadores en balde.
2. **Toda asignación a unha variable local interna ou cela de contedor suma `+1`**:
   - `a = [10, 20]` $\rightarrow$ o bloque `M1` nace con contador `1`.
   - `xs = [a, b]` $\rightarrow$ a lista `xs` nace con `1`, e como garda referencias a `a` e `b`, ambos soben a `2`.
   - Se reasignas unha variable mutable (`mut x = ...` e logo `x = novo`), `RMM2` aplica primeiro **`+1`** ao valor novo antes de aplicar **`-1`** ao antigo.
3. **Ao saír da función, as variables locais que NON se devolven reciben `-1`**: se o contador dunha estrutura chega a `0`, libérase a súa memoria no acto e **propaga `-1` en fervenza, un por un, a cada un dos seus fillos directos**.
4. **O valor devolto pola función exímese en tránsito**: recibe o seu `-1` de variable local pero non se destrúe ao cruzar o `return`, de xeito que cando quen chamou fai `c = mina_funcion ()`, ese `+1` da asignación déixao exactamente en `1`.

```ridgun
escoller Bool [Int] [Int] => [Int]
escoller cond a     b     =
  | cond      = a
  | otherwise = b

exemplo_rmm2 Bool => Int
exemplo_rmm2 cond =
  a = [10, 20, 30]           -- M1 (rc = 1)
  b = [40, 50, 60]           -- M2 (rc = 1)
  c = escoller cond a b      -- `c` recibe +1; o non escollido morre aquí mesmo (rc -> 0)
  (contar a) + (contar c)    -- Ao rematar, `a` e `c` reciben -1 e todo queda en 0 bloques vivos
```

---

## 8.2. Rexións Léxicas con Cota (`with region`): Devasas de memoria en $O(1)$

Ademais de `RMM1` e `RMM2`, cando estás procesando un paquete de rede externo, un ficheiro xigante ou un lote de datos non confiables e queres poñer un **teito estrito de memoria RAM**, envolves o cálculo nun bloque **`with region`**:

```ridgun
procesar_trama String => Result
procesar_trama cru    =
  with region 64_KB do
    limpas = map limpar_lina (dividir_linas cru)
    contar_validos limpas
```

1. **Cota garantida en hardware/runtime**: se dentro do bloque se intenta reservar nin un só byte por riba de `64_KB` (`65.536` bytes), o runtime aborta limpamente o bloque, libera toda a area temporal en tempo constante $O(1)$ e devolve `Err OutOfMemory` sen tombar o proceso.
2. **Liberación instantánea ao saír**: en canto remata o bloque `with region`, toda a memoria temporal da area desaparece de golpe sen deixar fragmentación.

---

## 8.3. Tensores Nativos, Contracción de Einstein (`@`) e Dimensións Simbólicas

Se algunha vez programaches en Python con NumPy ou PyTorch, seguro que sufriches o clásico erro no minuto 41 de execución:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

En Ridgun, os **`Tensor`** son cidadáns nativos de primeira clase e as súas dimensións forman parte da sinatura de tipos:

```ridgun
-- Se entra (N × K) e (K × M), por forza sae (N × M)!
multiplicar_matrices Tensor[N, K] Tensor[K, M] => Tensor[N, M]
multiplicar_matrices a            b            =  a_ik @ b_kj
```

Fíxate en dous detalles espectaculares:
1. **Verificación estática de dimensións (`Tensor[N, K]`)**: o eixe interno `K` da primeira matriz ten que coincidir co primeiro eixe `K` da segunda. Se intentas pasar dimensións incompatibles, `ridgunc check` deténte antes de executar nada.
2. **Notación de subíndices de Einstein (`a_ik @ b_kj`) e Hadamard (`a_ij * b_j`)**:
   - Con **`@`**, os subíndices repetidos en todos os operandos (`k`) contráense (súmanse) e os únicos (`i`, `j`) sobreviven no tensor resultado.
   - Con **`+`, `-`, `*`, `/`**, os subíndices aliñan dimensións e fan *broadcasting* automático (`a_ij * b_j` multiplica cada fila `i` de `a` polo vector `b_j` sen necesidade de escribir `unsqueeze` nin `reshape`).
3. **Mutación *in-place* para algoritmos numéricos**:
   ```ridgun
   crear_matriz_identidade => Tensor
   crear_matriz_identidade =
     m = Tensor [[1.0, 0.0], [0.0, 1.0]]
     m[0, 1] = 0.5
     m
   ```

---

## 8.4. Variables de Contexto (`context ::`) e Estado Compartido Atómico (`shared ::`)

No 99% do teu código pasarás datos por parámetro. Pero para ese 1% onde precisas configuración de contorno ou un contador global entre fíos sen contaminar 40 sinaturas intermedias, Ridgun ofrece dous mecanismos explícitos e seguros:

### 1. `context ::` — Ámbito dinámico illado por tarefa (`with ... = ... do`)
```ridgun
context :: ruta_log : String = "/var/log/app.log"

rexistrar_evento String => ()
rexistrar_evento msg    =  echo "[{ruta_log}] {msg}"

main => ()
main =
  rexistrar_evento "Arrinque normal"
  with ruta_log = "/tmp/test.log" do
    rexistrar_evento "Dentro da proba illada"
```

### 2. `shared ::` e `atomic` — Estado concorrente con bloqueo atómico por liña
```ridgun
shared :: peticions_totais : Int = 0

contabilizar_visita => Int
contabilizar_visita =
  atomic peticions_totais = peticions_totais + 1
  peticions_totais
```

---

## 8.5. Acceso a Hardware (`hardware ::`) e Primitivas POSIX de Sistemas

O propio compilador `ridgunc`, o xestor `stable` e utilidades de sistemas Unix están escritos en Ridgun. Para iso, a linguaxe inclúe bloques de rexistros mapeados en memoria (`hardware ::`) e primitivas POSIX directas:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

E para traballar co sistema operativo:

| Primitiva | Sinatura | Que fai |
|---|---|---|
| `cli_args` | `=> [String]` | Argumentos de liña de comandos (`argv`). |
| `read_file` / `write_file` | `String => String` / `String String => ()` | Lectura e escritura íntegra de ficheiros en disco. |
| `read_bytes` / `write_bytes` | `String => [Int]` / `String [Int] => ()` | Lectura e escritura binaria exacta byte a byte (`0..255`). |
| `list_dir` / `file_lstat` | `String => [String]` / `String => ...` | Listaxe de directorios e inspección de metadatos POSIX (`lstat`). |
| `sha256_file` / `sha256_str` | `String => String` | Hash criptográfico SHA-256 nativo. |
| `sys_exec` / `shell_exec` | `... => Int` | Execución de procesos do sistema operativo. |
| `sys_getcwd` / `sys_chdir` | `=> String` / `String => Int` | Consultar ou mudar o directorio de traballo. |
| `sys_getenv` / `sys_setenv` | `String => String` / `String String => Int` | Variables de contorno do proceso. |
| `sys_getuid` / `sys_getgid` | `=> Int` | UID e GID reais do proceso (`doas`, ferramentas de seguridade). |
| `sys_exit` | `Int => ()` | Rematar o proceso con código de saída. |

---

## 8.6. Caso de Estudo Real: Construíndo `rg-wc`, unha utilidade Unix paralela

Imos unir todo o aprendido desde o Capítulo 01 ata aquí nun programa real de sistemas: unha versión paralela da ferramenta Unix `wc` (contador de liñas e bytes para múltiples ficheiros) escrita en Ridgun puro:

```ridgun
-- 1. Modelamos as métricas dun ficheiro cun rexistro ADT (Capítulo 06)
type Metricas = ficheiro: String, linas: Int, bytes: Int

-- 2. Contamos saltos de liña (código ASCII 10) con recursión de cola TCO (Capítulo 04)
fn :: contar_saltos String Int Int Int => Int
      contar_saltos texto  pos fin acum =
        | pos >= fin                    = acum
        | (str_char_at texto pos) == 10 = contar_saltos texto (pos + 1) fin (acum + 1)
        | otherwise                     = contar_saltos texto (pos + 1) fin acum

fn :: numero_de_linas String => Int
      numero_de_linas texto  =  contar_saltos texto 0 (str_len texto) 0

-- 3. Analizamos un ficheiro e devolvemos a súa estrutura Metricas
fn :: analizar_ficheiro String => Metricas
      analizar_ficheiro ruta   =
        contido = read_file ruta
        || numero_de_linas contido -> n_linas
        || str_len contido         -> n_bytes ||.
        Metricas ruta n_linas n_bytes

-- 4. Formatamos cada fila e sumamos totais con `fold` e `||` (Capítulo 07)
fn :: formatar_metrica Metricas => String
      formatar_metrica m        =  "{linas m}\t{bytes m}\t{ficheiro m}"

fn :: sumar_linas Int Metricas => Int
      sumar_linas acc m        =  acc + (linas m)

fn :: sumar_bytes Int Metricas => Int
      sumar_bytes acc m        =  acc + (bytes m)

fn :: xerar_informe [String] => String
      xerar_informe rutas    =
        metricas = map analizar_ficheiro rutas
        || map formatar_metrica metricas -> filas
        || fold sumar_linas 0 metricas   -> total_l
        || fold sumar_bytes 0 metricas   -> total_b ||.
        "{filas}\nTotal: {total_l} liñas, {total_b} bytes"

fn :: main => ()
      main =
        echo (xerar_informe ["README.md", "AGENTS.md"])
```

Párate un segundo a mirar esas ~40 liñas de código:
- Non hai nin un só `null`, nin unha excepción descontrolada, nin un `Mutex`.
- `contar_saltos` compílase a un `loop` nativo con 0 bytes de pila grazas ao TCO automático.
- `map analizar_ficheiro rutas` procesa os ficheiros en paralelo en todos os núcleos da túa CPU, e o bloque `||` calcula simultaneamente as filas formatadas, o total de liñas e o total de bytes.
- A memoria temporal libérase deterministicamente mediante **`RMM1`/`RMM2`**.
- E cando executas `ridgunc build rg_wc.rg -o rg-wc`, obtés un binario nativo autónomo de ~350 KB listo para copiar a `/usr/local/bin`.

---

## 8.7. Folla de Ruta Final: As 10 Regras de Ouro do Programador Ridgun

1. **Escribe sempre primeiro o contrato (`=>`) e despois as ecuacións (`=`):** pensar nos tipos primeiro fai que o compilador traballe para ti.
2. **Deixa que `stable format` maquete as túas táboas:** escribe cun espazo e deixa que a ferramenta aliñe columnas, `=>`, `=` e `->`.
3. **Lembra a regra universal do `=`:** detrás de calquera `=` podes abrir un bloque secuencial, unha árbore de gardas `|` ou un grafo paralelo `||`.
4. **Usa `|.` e `||.` só cando peches un bloque aniñado para volver a un nivel superior:** mantén as árbores de decisión profundas compactas e sen ambigüidade.
5. **Inmutable por defecto (`x = ...`), mutable explícito (`mut x = ...`):** usa `mut` unicamente cando un acumulador local o pida de verdade.
6. **Usa operadores booleanos claros en minúsculas (`and`, `or`, `xor`, `not`) e pecha sempre as túas gardas con `| otherwise =`.**
7. **Modela o teu dominio con ADTs (`type`):** usa rexistros con `with campo: valor` e tipos suma (`Option`, `Result`) en lugar de `null`.
8. **Paraleliza declarando dependencias con `|| expr -> var` e `map` / `filter`:** deixa que o compilador verifique que non hai ciclos e reparta o traballo entre os núcleos.
9. **Ponlle dimensións simbólicas aos teus Tensores (`Tensor[N, K]`) e subíndices ás túas contraccións (`a_ik @ b_kj`).**
10. **Confía en `RMM` (`RMM1`/`RMM2`), acouta entradas externas con `with region` e verifica sempre con `stable check` e `stable test`.**

Feliz viaxe programando en Ridgun!
