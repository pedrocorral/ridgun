# Capítol 08: Tensors, Memòria Compilada RMM (`RMM1`/`RMM2`), Regions i Sistemes

Fins aquí hem vist el costat més amable, elegant i matemàtic de Ridgun: funcions pures, tipus algebraics, *pattern matching*, arbres de decisió amb `|` / `|.` i grafs paral·lels `||` amb `->` que aprofiten tots els nuclis del teu processador sense demanar-te ni un trist `Mutex`.

Arribats a aquest punt, el programador veterà de sistemes sol aixecar la mà al fons de l'aula amb mig somriure i preguntar:

> *"Tot això és preciós per calcular factures o compilar ASTs, però què passa quan necessito multiplicar matrius de milions de flotants a velocitat de vertigen? Què passa amb la memòria? Hi ha un recol·lector de brossa (Garbage Collector) amagat sota la catifa esperant el pitjor moment per congelar el meu programa durant 200 mil·lisegons? I com parlo amb el sistema operatiu Unix de debò?"*

Excel·lents preguntes. Aixequem el capó de Ridgun per veure com se les gasta quan toca baixar al fang dels sistemes, el càlcul numèric i la memòria determinista.

---

## 8.1. El dilema de la memòria: ni Garbage Collector ni baralles amb el Borrow Checker (`RMM1` i `RMM2`)

Al món dels llenguatges moderns sol haver-hi dos bàndols irreconciliables:

1. **El bàndol del Garbage Collector (Java, Go, Python, JS, Haskell, OCaml):** tu demanes memòria alegrement i, de tant en tant, un camió de la brossa invisible atura el trànsit del teu programa per rastrejar quins objectes continuen vius i quins no. És comodíssim... fins que estàs fent una eina de sistema ultraràpida o un servidor amb latències estrictes i el camió decideix aparcar en doble fila.
2. **El bàndol del control manual / Borrow Checker (C, C++, Rust):** no hi ha recol·lector de brossa, però a canvi has de gestionar punters a mà (jugant-te un `Segmentation fault` o un *use-after-free*) o passar-te mitja tarda negociant amb el *borrow checker* per què `'a` no viu tant com `'b`.

Ridgun resol aquest dilema de soca-rel amb **Ridgun Memory Management (`RMM`)**, un sistema determinista de dues polítiques complementàries (**`RMM1`** i **`RMM2`**) combinat amb **regions lèxiques (`with region`)**:

### Política `RMM1` — Gestió de Memòria Compilada (CMM Lineal i Condicional)
Quan el compilador coneix estàticament el flux de les variables locals dins d'una funció:
- **CMM Lineal**: `ridgunc` calcula en temps de compilació quina és l'**última línia** en què es llegeix cada variable local (`a`, `b`, ...) i insereix just després el seu alliberament determinista (`rg_cmm_drop`), o transfereix la seva propietat sense còpies (`rg_cmm_move`) quan la variable es retorna com a resultat.
- **CMM Condicional (`ptr(a) != ptr(c)`)**: i si una funció com `triar cond a b` retorna `a` o `b` segons una condició en temps d'execució? `ridgunc` construeix la taula d'ancestres i emet una guarda d'identitat de punters d'**1 cicle de CPU**: si `b` deixa de fer-se servir mentre `c` continua viva, comprova `if ptr(b) != ptr(c) { free(b) }`. La branca no triada s'allibera a l'instant i la triada sobreviu intacta.

### Política `RMM2` — Recompte per Assignació i Cascada Estructural
I què passa quan fiques estructures dins d'altres estructures (`xs = [a, b]`), reassignes variables mutables (`mut x = ...`) o encadenes crides complexes? Aquí entra **`RMM2`**, que governa tot el cicle de vida amb quatre regles matemàtiques sense fissures:

1. **Els arguments d'entrada d'una funció no es toquen (`+0` en entrar, `-0` en sortir)**: passar una llista o un registre a una funció mai no incrementa ni decrementa comptadors en va.
2. **Tota assignació a una variable local interna o cel·la de contenidor suma `+1`**:
   - `a = [10, 20]` $\rightarrow$ el bloc `M1` neix amb comptador `1`.
   - `xs = [a, b]` $\rightarrow$ la llista `xs` neix amb `1`, i com que desa referències a `a` i `b`, tots dos pugen a `2`.
   - Si reassignes una variable mutable (`mut x = ...` i després `x = nou`), `RMM2` aplica primer **`+1`** al valor nou abans d'aplicar **`-1`** a l'antic.
3. **En sortir de la funció, les variables locals que NO es retornen reben `-1`**: si el comptador d'una estructura arriba a `0`, s'allibera la seva memòria a l'instant i **propaga `-1` en cascada, un per un, a cadascun dels seus fills directes**.
4. **El valor retornat per la funció s'eximeix en trànsit**: rep el seu `-1` de variable local però no es destrueix en creuar el `return`, de manera que quan qui ha cridat fa `c = la_meva_funcio ()`, aquell `+1` de l'assignació el deixa exactament en `1`.

```ridgun
triar Bool [Int] [Int] => [Int]
triar cond a     b     =
  | cond      = a
  | otherwise = b

exemple_rmm2 Bool => Int
exemple_rmm2 cond =
  a = [10, 20, 30]           -- M1 (rc = 1)
  b = [40, 50, 60]           -- M2 (rc = 1)
  c = triar cond a b         -- `c` rep +1; el no triat mor aquí mateix (rc -> 0)
  (comptar a) + (comptar c)  -- En acabar, `a` i `c` reben -1 i tot queda en 0 blocs vius
```

---

## 8.2. Regions Lèxiques amb Quota (`with region`): Tallafocs de memòria en $O(1)$

A més d'`RMM1` i `RMM2`, quan estàs processant un paquet de xarxa extern, un fitxer gegant o un lot de dades no confiables i vols posar un **sostre estricte de memòria RAM**, envoltes el càlcul en un bloc **`with region`**:

```ridgun
processar_trama String => Result
processar_trama cru    =
  with region 64_KB do
    netes = map netejar_linia (dividir_linies cru)
    comptar_valids netes
```

1. **Quota garantida en maquinari/runtime**: si dins del bloc s'intenta reservar ni un sol byte per sobre de `64_KB` (`65.536` bytes), el runtime avorta netament el bloc, allibera tota l'arena temporal en temps constant $O(1)$ i retorna `Err OutOfMemory` sense tombar el procés.
2. **Alliberament instantani en sortir**: tan bon punt acaba el bloc `with region`, tota la memòria temporal de l'arena desapareix de cop sense deixar fragmentació.

---

## 8.3. Tensors Natius, Contracció d'Einstein (`@`) i Dimensions Simbòliques

Si alguna vegada has programat en Python amb NumPy o PyTorch, segur que has patit el clàssic error al minut 41 d'execució:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

En Ridgun, els **`Tensor`** són ciutadans natius de primera classe i les seves dimensions formen part de la signatura de tipus:

```ridgun
-- Si entra (N × K) i (K × M), per nassos surt (N × M)!
multiplicar_matrius Tensor[N, K] Tensor[K, M] => Tensor[N, M]
multiplicar_matrius a            b            =  a_ik @ b_kj
```

Fixa't en tres detalls espectaculars:
1. **Verificació estàtica de dimensions (`Tensor[N, K]`)**: l'eix intern `K` de la primera matriu ha de coincidir amb el primer eix `K` de la segona. Si intentes passar dimensions incompatibles, `ridgunc check` t'atura abans d'executar res.
2. **Notació de subíndexs d'Einstein (`a_ik @ b_kj`) i Hadamard (`a_ij * b_j`)**:
   - Amb **`@`**, els subíndexs repetits en tots els operands (`k`) es contrauen (es sumen) i els únics (`i`, `j`) sobreviuen al tensor resultat.
   - Amb **`+`, `-`, `*`, `/`**, els subíndexs alineen dimensions i fan *broadcasting* automàtic (`a_ij * b_j` multiplica cada fila `i` d'`a` pel vector `b_j` sense necessitat d'escriure `unsqueeze` ni `reshape`).
3. **Mutació *in-place* per a algorismes numèrics**:
   ```ridgun
   crear_matriu_identitat => Tensor
   crear_matriu_identitat =
     m = Tensor [[1.0, 0.0], [0.0, 1.0]]
     m[0, 1] = 0.5
     m
   ```

---

## 8.4. Variables de Context (`context ::`) i Estat Compartit Atòmic (`shared ::`)

En el 99% del teu codi passaràs dades per paràmetre. Però per a aquell 1% on necessites configuració d'entorn o un comptador global entre fils sense contaminar 40 signatures intermèdies, Ridgun ofereix dos mecanismes explícits i segurs:

### 1. `context ::` — Àmbit dinàmic aïllat per tasca (`with ... = ... do`)
```ridgun
context :: ruta_log : String = "/var/log/app.log"

registrar_esdeveniment String => ()
registrar_esdeveniment msg    =  echo "[{ruta_log}] {msg}"

main => ()
main =
  registrar_esdeveniment "Arrencada normal"
  with ruta_log = "/tmp/test.log" do
    registrar_esdeveniment "Dins del test aïllat"
```

### 2. `shared ::` i `atomic` — Estat concurrent amb bloqueig atòmic per línia
```ridgun
shared :: peticions_totals : Int = 0

comptabilitzar_visita => Int
comptabilitzar_visita =
  atomic peticions_totals = peticions_totals + 1
  peticions_totals
```

---

## 8.5. Accés a Maquinari (`hardware ::`) i Primitives POSIX de Sistemes

El mateix compilador `ridgunc`, el gestor `stable` i utilitats de sistemes Unix estan escrits en Ridgun. Per a això, el llenguatge inclou blocs de registres mapejats en memòria (`hardware ::`) i primitives POSIX directes:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

I per treballar amb el sistema operatiu:

| Primitiva | Signatura | Què fa |
|---|---|---|
| `cli_args` | `=> [String]` | Arguments de línia d'ordres (`argv`). |
| `read_file` / `write_file` | `String => String` / `String String => ()` | Lectura i escriptura íntegra de fitxers en disc. |
| `read_bytes` / `write_bytes` | `String => [Int]` / `String [Int] => ()` | Lectura i escriptura binària exacta byte a byte (`0..255`). |
| `list_dir` / `file_lstat` | `String => [String]` / `String => ...` | Llistat de directoris i inspecció de metadades POSIX (`lstat`). |
| `sha256_file` / `sha256_str` | `String => String` | Resum criptogràfic SHA-256 natiu. |
| `sys_exec` / `shell_exec` | `... => Int` | Execució de processos del sistema operatiu. |
| `sys_getcwd` / `sys_chdir` | `=> String` / `String => Int` | Consultar o canviar el directori de treball. |
| `sys_getenv` / `sys_setenv` | `String => String` / `String String => Int` | Variables d'entorn del procés. |
| `sys_getuid` / `sys_getgid` | `=> Int` | UID i GID reals del procés (`doas`, eines de seguretat). |
| `sys_exit` | `Int => ()` | Acabar el procés amb codi de sortida. |

---

## 8.6. Cas d'Estudi Real: Construint `rg-wc`, una utilitat Unix paral·lela

Unirem tot el que hem après des del Capítol 01 fins aquí en un programa real de sistemes: una versió paral·lela de l'eina Unix `wc` (comptador de línies i bytes per a múltiples fitxers) escrita en Ridgun pur:

```ridgun
-- 1. Modelem les mètriques d'un fitxer amb un registre ADT (Capítol 06)
type Metriques = fitxer: String, linies: Int, bytes: Int

-- 2. Comptem salts de línia (codi ASCII 10) amb recursió de cua TCO (Capítol 04)
fn :: comptar_salts String Int Int Int  => Int
      comptar_salts text   pos fi  acum =
        | pos >= fi                    = acum
        | (str_char_at text pos) == 10 = comptar_salts text (pos + 1) fi (acum + 1)
        | otherwise                    = comptar_salts text (pos + 1) fi acum

fn :: nombre_de_linies String => Int
      nombre_de_linies text   =  comptar_salts text 0 (str_len text) 0

-- 3. Analitzem un fitxer i retornem la seva estructura Metriques
fn :: analitzar_fitxer String => Metriques
      analitzar_fitxer ruta   =
        contingut = read_file ruta
        || nombre_de_linies contingut -> n_linies
        || str_len contingut          -> n_bytes ||.
        Metriques ruta n_linies n_bytes

-- 4. Formatem cada fila i sumem totals amb `fold` i `||` (Capítol 07)
fn :: formatar_metrica Metriques => String
      formatar_metrica m         =  "{linies m}\t{bytes m}\t{fitxer m}"

fn :: sumar_linies Int Metriques => Int
      sumar_linies acc m         =  acc + (linies m)

fn :: sumar_bytes Int Metriques => Int
      sumar_bytes acc m         =  acc + (bytes m)

fn :: generar_informe [String] => String
      generar_informe rutes    =
        metriques = map analitzar_fitxer rutes
        || map formatar_metrica metriques -> files
        || fold sumar_linies 0 metriques  -> total_l
        || fold sumar_bytes 0 metriques   -> total_b ||.
        "{files}\nTotal: {total_l} línies, {total_b} bytes"

fn :: main => ()
      main =
        echo (generar_informe ["README.md", "AGENTS.md"])
```

Atura't un segon a mirar aquestes ~40 línies de codi:
- No hi ha ni un sol `null`, ni una excepció descontrolada, ni un `Mutex`.
- `comptar_salts` es compila a un `loop` natiu amb 0 bytes de pila gràcies al TCO automàtic.
- `map analitzar_fitxer rutes` processa els fitxers en paral·lel en tots els nuclis de la teva CPU, i el bloc `||` calcula simultàniament les files formatades, el total de línies i el total de bytes.
- La memòria temporal s'allibera determinísticament mitjançant **`RMM1`/`RMM2`**.
- I quan executes `ridgunc build rg_wc.rg -o rg-wc`, obtens un binari natiu autònom de ~350 KB a punt per copiar a `/usr/local/bin`.

---

## 8.7. Full de Ruta Final: Les 10 Regles d'Or del Programador Ridgun

1. **Escriu sempre primer el contracte (`=>`) i després les equacions (`=`):** pensar en els tipus primer fa que el compilador treballi per a tu.
2. **Deixa que `stable format` maqueti les teves taules:** escriu amb un espai i deixa que l'eina alineï columnes, `=>`, `=` i `->`.
3. **Recorda la regla universal de l'`=`:** darrere de qualsevol `=` pots obrir un bloc seqüencial, un arbre de guardes `|` o un graf paral·lel `||`.
4. **Fes servir `|.` i `||.` només quan tanquis un bloc imbricat per tornar a un nivell superior:** mantén els arbres de decisió profunds compactes i sense ambigüitat.
5. **Immutable per defecte (`x = ...`), mutable explícit (`mut x = ...`):** fes servir `mut` únicament quan un acumulador local ho demani de debò.
6. **Fes servir operadors booleans clars en minúscules (`and`, `or`, `xor`, `not`) i tanca sempre les teves guardes amb `| otherwise =`.**
7. **Modela el teu domini amb ADTs (`type`):** fes servir registres amb `with camp: valor` i tipus suma (`Option`, `Result`) en lloc de `null`.
8. **Paral·lelitza declarant dependències amb `|| expr -> var` i `map` / `filter`:** deixa que el compilador verifiqui que no hi ha cicles i reparteixi la feina entre els nuclis.
9. **Posa dimensions simbòliques als teus Tensors (`Tensor[N, K]`) i subíndexs a les teves contraccions (`a_ik @ b_kj`).**
10. **Confia en `RMM` (`RMM1`/`RMM2`), afita entrades externes amb `with region` i verifica sempre amb `stable check` i `stable test`.**

Bon viatge programant en Ridgun!
