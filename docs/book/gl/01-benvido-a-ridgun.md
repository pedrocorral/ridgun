# Capítulo 01: O teu primeiro contacto con Ridgun (Sen cascos, sen chaves e sen puntos e coma)

Vale, xa te convencín no Capítulo 00 de que non estamos tolos por crear Ridgun. Agora seguramente esteas pensando:

> *"Moi bonito o discurso das táboas e os 16 núcleos, pero ensíname código de verdade. Canto tarda un en escribir algo que funcione sen pelexar co compilador?"*

Imos aló, mans á obra!

---

## 1.1. "Ola, mundo!", pero con substancia

Na maioría dos libros de programación ensínanche un `print("Ola mundo")` soso e pasan de páxina. Nós imos escribir directamente unha función con lóxica real para que vexas como respira Ridgun desde o minuto un.

Crea un ficheiro chamado `ola.rg` e escribe isto:

```ridgun
saudo String => String
saudo ""     =  "Ola, viaxeiro misterioso! (Non me dixeches o teu nome)"
saudo "Root" =  "Home, Root! Coidado co que borras hoxe."
saudo nome   =  "Ola, {nome}! Benvido a Ridgun."

main => ()
main =
  echo (saudo "Ada")
  echo (saudo "Root")
  echo (saudo "")
```

Para executalo agora mesmo:

```bash
ridgunc run ola.rg
```

E verás na túa terminal:

```text
Ola, Ada! Benvido a Ridgun.
Home, Root! Coidado co que borras hoxe.
Ola, viaxeiro misterioso! (Non me dixeches o teu nome)
```

Para un momento e mira o bloque de `saudo` arriba. Notas o que **NON** hai?
- **Non hai `function`, nin `def`, nin `pub fn`** (se queres poñer `fn ::` diante da sinatura podes facelo, pero é opcional).
- **Non hai parénteses `(String nome)` nin chaves `{ ... }`** lixando a pantalla.
- **Non hai `if (nome == "") ... else if (nome == "Root") ... else ...`**.
- **Non hai `return`**.

---

## 1.2. Como le o teu cerebro un ficheiro `.rg`

Imos destripar esas catro liñas de `saudo`, porque aquí xa está o 50% da filosofía de Ridgun:

```ridgun
saudo String => String
saudo ""     =  "Ola, viaxeiro misterioso! (Non me dixeches o teu nome)"
saudo "Root" =  "Home, Root! Coidado co que borras hoxe."
saudo nome   =  "Ola, {nome}! Benvido a Ridgun."
```

1. **A primeira liña é o contrato (`saudo String => String`)**:
   Di: *"Chámome `saudo`, recibo un `String` e devólvoche (`=>`) outro `String`"*. Punto. Se alguén intenta chamarme pasándome o número `42`, o compilador daralle un toque no ombreiro antes sequera de executar o programa.
2. **As liñas de abaixo son os casos (de arriba abaixo)**:
   - Pasáchesme a cadea baleira `""`? Devolvo a primeira frase.
   - Pasáchesme exactamente `"Root"`? Devolvo a segunda frase.
   - Pasáchesme calquera outra cousa? Gárdoa na variable `nome` e métoa dentro do texto usando `{nome}`.
3. **E que é `main => ()`?**:
   Como `main` non recibe argumentos, poñemos `=>` directamente despois do nome. E devolve `()` (o tipo baleiro ou *Unit*, para os amigos), porque o seu único traballo é sacar cousas por pantalla con `echo`.

---

## 1.3. "Agarda... teño que aliñar eses espazos á man coma un monxe copista?"

Nin de broma! Se tiveses que darlle á barra espazadora contando columnas a ollo, abandonarías Ridgun aos dez minutos (e con razón).

Ti escribes o código axiña, cun só espazo entre cada palabra:

```ridgun
saudo String => String
saudo "" = "Ola, viaxeiro misterioso!"
saudo nome = "Ola, {nome}!"
```

E cando executas **`stable format`** (ou premes `TAB` / gardas o ficheiro en Emacs con `ridgun-mode`), o formatador canónico coloca cada parámetro debaixo do seu tipo e aliña todos os `=` con precisión milimétrica. Ti escribes rápido; a máquina maqueta a táboa.

---

## 1.4. De script rápido a binario de combate nun comando

Cando fas `ridgunc run ola.rg`, estás compilando e lanzando o programa ao voo. Pero imaxina que xa remataches a túa ferramenta e queres levala a un servidor de produción ou compartila cun compañeiro que non ten instalado Ridgun.

Executas:

```bash
ridgunc build ola.rg -o ola
```

E xa tes `./ola`: un **executable nativo ELF de Linux x86_64**, limpo, sen código morto (*Tree-Shaking*), con optimización de ligazón completa (*LTO*) e sen depender de ningún intérprete externo.

---

## 1.5. A chuleta honesta: De onde vén cada idea de Ridgun?

Ridgun non pretende reinventar a roda cadrada; toma prestado sen complexos o mellor de catro tradicións:

| De quen | Que toma Ridgun | Que deixa fóra (pola túa saúde mental) |
|---|---|---|
| **Haskell / ML** | Funcións puras, *pattern matching* por casos, tipos alxébricos (`Option`, `Result`) e polimorfismo (`A`..`Z`). | As mónadas abstractas, os 40 `LANGUAGE pragmas` e o colector de lixo. |
| **J / APL** | A obsesión pola forma tabular do código, tensores nativos e máscaras de secuencias (`s["-+-"]`). | Os símbolos xeroglíficos imposibles de escribir nun teclado normal. |
| **Rust / C** | Binarios ELF nativos pequenos, cero GC, control de memoria (`with region`) e chamadas ao sistema POSIX. | A pelexa constante co *borrow checker*, os *lifetimes* `'a` e a verbosidade sintáctica. |
| **Erlang / Go** | Axentes illados (`agent`, `send ... to`, `receive from`) e concorrencia por canles (`new bounded channel`). | Os punteiros `nil` e as mutacións compartidas por descoido. |

---

## 1.6. E o máis importante: Que fai Ridgun que NON ten ninguén máis?

Recoñecer os clásicos é de boa educación, pero se Ridgun fose só un "compilatorio de grandes éxitos" doutras linguaxes, non estarías lendo este libro.

Hai **sete cousas** que deseñamos e integramos en Ridgun que non vas atopar xuntas —e moitas delas, nin sequera por separado— en ningunha outra linguaxe actual:

### 1. Bloques paralelos `||` con `->` que son grafos paralelos reais, non simple azucre sintáctico
Noutras linguaxes funcionais un bloque de variables locais só ordena expresións que logo se avalían nun único fío.
En Ridgun, **un bloque `||` con frechas `->` é un Grafo Acíclico Dirixido (DAG) de execución paralela** sen sequera precisar escribir palabras chave extra como `where`:
```ridgun
informe_anual Int => Int
informe_anual id  =  ingresos - gastos
  || calcular_vendas id -> ingresos
  || calcular_custos id -> gastos
```
Ti debuxas as frechas de fluxo (`->`). O compilador analiza quen depende de quen, **verifica estaticamente que non crearas ningún ciclo infinito**, e lanza as ramas independentes en paralelo sen que escribas nin un só `async`, `await`, `Future` nin `Mutex`.

### 2. O código como táboa bidimensional onde a sinatura é a cabeceira das columnas
En calquera outra linguaxe, a sinatura de tipos vai por libre nunha liña e o corpo da función vai debaixo como un parágrafo de texto normal.
En Ridgun, **a sinatura de tipos é literalmente a cabeceira dunha táboa**, e cada caso debaixo aliña cada patrón xusto na vertical do seu tipo e cada `=` baixo o `=>`:
```ridgun
dividir Int Int => Option
dividir _   0   =  None
dividir a   b   =  Some (a / b)
```
Ninguén máis trata a sinatura e as ecuacións como unha única matriz visual verificada polo compilador e maquetada automaticamente por `stable format`.

### 3. Operadores frase (*Mixfix* N-arios) tipados e aliñados (`op ::`)
Na maioría das linguaxes, ou te aguantas con `+`, `-`, `*` ou como moito defines un operador binario críptico como `<|>` que ninguén sabe que significa.
En Ridgun podes crear **operadores que son frases lexibles con tantos ocos tipados como queiras** (incluíndo palabras contextuais como `type` ou `with`):
```ridgun
op :: Int limitado_entre Int e Int => Int
      x   limitado_entre min e max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
E logo no teu código escribes `velocidade limitado_entre 0 e 120`. Lese coma galego (ou inglés), pero está 100% tipado e compilado a código nativo.

### 4. Máscaras visuais sobre secuencias (`s(+ _)` e `s["-+-"]`)
Algunha vez tiveches que escribir unha ensalada de índices `filter(\(i, x) -> i % 2 == 0)` só para quedar cos elementos pares ou extraer un patrón rítmico dunha lista?
En Ridgun pásaslle directamente unha **máscara visual**:
- `datos["-+-"]`: descarta o primeiro (`-`), queda co segundo (`+`), descarta o terceiro (`-`).
- `datos["+-~"]`: o símbolo `~` repite o patrón `+-` en bucle ata o final da lista (todos os índices pares dun golpe).
Cero aritmética de índices, cero erros *off-by-one*.

### 5. Polimorfismo de "cero ruído" (`A`..`Z`) gobernado polo teu dominio
En Rust, TypeScript ou Java, cando unha función é xenérica tes que encher a liña de parénteses angulares: `fn intercambiar<A, B>(par: (A, B)) -> (B, A)`.
En Ridgun simplemente usas unha letra maiúscula solta:
```ridgun
intercambiar (A, B) => (B, A)
intercambiar (x, y) =  (y, x)
```
*"E se no meu programa quero ter un tipo real que se chame `type A`?"* — Ningún problema: en Ridgun **as túas declaracións `type` mandan**. Se non existe `type A`, `A` é xenérico; no instante en que defines `type A = ...`, pasa a ser o teu tipo concreto en todo o módulo.

### 6. Cero ficheiros de configuración estraños: `build.rg` é Ridgun puro
Esquece aprender TOML para Cargo, JSON para npm, XML para Maven ou a sintaxe arcana de `Makefile` con tabuladores invisibles. En Ridgun, a receita que constrúe o teu proxecto (`build.rg`) **é un ficheiro `.rg` máis**, coas mesmas funcións puras e o mesmo *pattern matching* có resto do teu código.

### 7. A "Santísima Trindade" que parecía imposible: Nivel Haskell + Memoria RMM sen GC nin Lifetimes + Binarios de ~350 KB
Ata hoxe tiñas que escoller:
- Se querías expresividade funcional pura (Haskell, OCaml, Elixir), pagabas cun colector de lixo e un runtime pesado.
- Se querías binarios diminutos de sistema sen colector de lixo (C, Rust, Zig), pagabas xestionando punteiros ou pelexando co *borrow checker* e escribindo código imperativo cheo de `let mut`.

Ridgun rompe ese dilema combinando **Ridgun Memory Management (`RMM`: `RMM1` estática e `RMM2` por conta de asignacións en fervenza)**, **rexións léxicas (`with region`)** que liberan areas enteiras en $O(1)$, **recursión de cola transformada en bucles nativos (`loop`)**, e **poda de grafo de chamadas (*Tree-Shaking*)** desde `main`. O resultado: escribes código declarativo de altísimo nivel e obtés un executable ELF autónomo de **~350 KB** capaz de competir de ti a ti con ferramentas escritas en C.

Agora si: coas cartas sobre a mesa, imos ao **Capítulo 02** para poñer a traballar a **`ridgunc`** e **`stable`**.
