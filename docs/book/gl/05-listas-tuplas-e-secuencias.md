# Capítulo 05: Listas, Tuplas e o truco ninja das Secuencias

Un programa que só move un número ou un texto á vez serve de pouco. Na vida real manexas listas de ficheiros, filas dunha base de datos, paquetes de rede ou coordenadas.

Para iso, Ridgun dáche tres envases distintos, cada un pensado para un traballo moi concreto:
1. **Listas (`[T]`)**: *"Teño moitos elementos do mesmo tipo (ou ningún) e quero percorrelos"*.
2. **Tuplas (`(A, B)`)**: *"Quero devolver un par ou un trío de cousas distintas xuntas sen crear un tipo novo"*.
3. **Secuencias e máscaras (`s["-+-"]`)**: *"Quero filtrar ou reordenar argumentos ao voo coma se tivese un coador matemático"*.

Imos unha por unha.

---

## 5.1. Listas (`[T]`): O pan de cada día

En Ridgun, se pos corchetes arredor dun tipo, tes unha lista dese tipo:
- `[Int]` é unha lista de enteiros: `[10, 20, 30]`.
- `[String]` é unha lista de textos: `["maza", "pera"]`.
- `[]` é a lista baleira (o comodín que encaixa con calquera `[T]`).

> *"Ouve, podo meter un número e un texto xuntos na mesma lista tipo `[1, "dous"]`?"*
> Tal cal, **non** (e dálle as grazas ao compilador por impedircho, porque así nunca che rebentará unha suma en produción ao atoparse un texto sorpresa). No Capítulo 06 veremos como resolver o caso de `[1, "dous"]` con elegancia total usando un Tipo Alxébrico (igual que fai Haskell).

### Como se anaquea unha lista sen usar índices `i`, `j`, `k`: `[]` e `(x:xs)`
Nas linguaxes imperativas, percorrer unha lista adoita implicar `for (int i = 0; i < lista.size(); i++)`, co clásico risco de pasarte por un (*off-by-one*).

En Ridgun non contas índices; **desmontas a lista pola cabeza**:
- `[]`: encaixa se a lista está baleira.
- `(x:xs)`: encaixa se a lista ten polo menos un elemento. Mete o primeiro elemento en `x` (a **cabeza**) e o resto da lista en `xs` (a **cola**).

Mira que gusto dá sumar unha lista ou contar cantos elementos ten:

```ridgun
sumar_lista [Int]  => Int
sumar_lista []     =  0
sumar_lista (x:xs) =  x + (sumar_lista xs)

contar_elementos [A]    => Int
contar_elementos []     =  0
contar_elementos (_:xs) =  1 + (contar_elementos xs)
```

E un detalle técnico que che alegrará o día: en Ridgun, sacar a cola `xs` en `(x:xs)` **non copia o resto da lista en memoria**. Internamente é unha vista sobre o mesmo vector que só avanza o punteiro de inicio en `1` ($O(1)$ instantáneo).

### Podes destapar varios elementos de golpe
O patrón `:` dá moitísimo xogo cando estás analizando comandos ou protocolos:

```ridgun
interpretar_comando [String]                 => String
interpretar_comando []                       =  "Non escribiches nada"
interpretar_comando ("axuda":_)              =  "Mostrando a axuda..."
interpretar_comando ("copiar":orixe:dest:[]) =  "Copiando de {orixe} a {dest}"
interpretar_comando (cmd:_)                  =  "Comando descoñecido: {cmd}"
```

Mira a terceira fila: `("copiar":orixe:dest:[])` comproba dun só golpe que a lista teña **exactamente 3 elementos**, que o primeiro sexa `"copiar"`, e déixache o segundo e o terceiro servidos en bandexa en `orixe` e `dest`. Intenta escribir iso en C ou Java e verás cantas liñas de `args.length == 3 && args[0].equals("copiar")` che saen.

### Unir listas con dobres dous puntos (`::`)
Cando estás no lado dereito do `=` (nunha expresión) e queres pegar dúas listas, usas **`::`**:

```ridgun
pegar_listas [Int] [Int] => [Int]
pegar_listas a     b     =  a :: b

engadir_detras [Int] Int => [Int]
engadir_detras xs    x   =  xs :: [x]
```

*(Regra mnemotécnica rápida: un só `:` nos patróns desmonta a lista; dous `::` nas expresións pegan dúas listas).*

E se de verdade queres sacar o elemento número 5 directamente sen percorrer nada? Usa corchetes pegados ao nome: `mina_lista[5]`.

---

## 5.2. Funcións variádicas (`T...`): "Pásame todos os que queiras!"

Ás veces queres que quen chame á túa función poida escribir `maximo_de 4 19 2 88 7` comodamente, sen obrigalo a envolver os números entre corchetes `[4, 19, 2, 88, 7]`.

Pon tres puntos **`...`** detrás do último tipo da túa sinatura, e dentro da túa función recibirálo automaticamente empaquetado coma unha lista:

```ridgun
sumar_varios Int... => Int
sumar_varios nums   =  sumar_lista nums

main => ()
main =
  echo (sumar_varios 10 20 30)       -- Imprime 60
  echo (sumar_varios 1 2 3 4 5 6 7)  -- Imprime 28
```

---

## 5.3. Tuplas: Cando unha función quere devolver máis dunha cousa

En moitas linguaxes devolver dúas cousas desde unha función é unha dor: ou creas unha clase auxiliar parva `ResultadoConPosicion`, ou pasas punteiros de saída por referencia.

En Ridgun devolves unha **tupla** `(A, B)`:

```ridgun
dividir_e_resto Int Int => (Int, Int)
dividir_e_resto a   b   =  (a / b, a % b)
```

Mesmo podes aforrar os parénteses na liña da sinatura se che resulta máis limpo:
`dividir_e_resto Int Int => Int Int`.

### Como abrir unha tupla
Igual que a creas con `(a, b)`, ábrela nos argumentos de calquera función con `(cociente, resto)`:

```ridgun
explicar_division (Int, Int)        => String
explicar_division (cociente, resto) =  "Cabe a {cociente} e sobran {resto}"
```

### O detalle estrela: Desempaquetado automático entre funcións
Supón que tes `dividir_e_resto` (que devolve unha tupla de 2 enteiros) e outra función `sumar_par Int Int => Int` (que agarda 2 enteiros soltos). En Ridgun non tes que abrir a tupla á man nunha variable intermedia; podes enchufar unha función dentro da outra directamente:

```ridgun
sumar_par Int Int => Int
sumar_par x   y   =  x + y

main => ()
main =
  -- dividir_e_resto 17 5 devolve (3, 2), e sumar_par recibe 3 e 2 directamente:
  echo (sumar_par (dividir_e_resto 17 5))  -- Imprime 5
```

---

## 5.4. O truco ninja: Secuencias e Máscaras Posicionais (`s["-+-"]`)

Aquí vén unha das xoias máis orixinais de Ridgun, herdada directamente das linguaxes vectoriais como J e APL.

Imaxina que recibes unha restra de argumentos co patrón de secuencia **`(s)`** e queres quedar só con algúns e tirar outros sen declarar cinco variables con nomes inventados (`_a`, `b`, `_c`, `d`...).

Aplícaslle a `s` unha **máscara de signos `+` (queda con el) e `-` (tírao)**:

- **`s["-+-"]`**: de 3 elementos, tira o primeiro (`-`), queda co segundo (`+`) e tira o terceiro (`-`).
- **`s["+-+"]`**: queda co primeiro e o terceiro; devolve a secuencia con eses dous.
- **`s["-- +"]`** (ollo ao espazo antes do último `+`): tira os dous primeiros (`--`) e aplica `+` **a todos os demais que veñan detrás**, sexan cantos sexan.

Mírao funcionando:

```ridgun
o_do_medio Int Int Int => Int
o_do_medio (s)         =  s["-+-"]

descartar_dous_primeiros Int... => [Int]
descartar_dous_primeiros (s)    =  s["-- +"]

main => ()
main =
  echo (o_do_medio 100 42 999)                -- Imprime 42
  echo (descartar_dous_primeiros 1 2 10 20 30)  -- Imprime [10, 20, 30]
```

Ademais, se usas o operador coma `,` fóra de parénteses (`lista1 , lista2`), Ridgun aplana ambas coleccións nunha única secuencia continua.

No **Capítulo 06** imos dar o paso que converte a un programador funcional nun arquitecto de primeira: **crear os teus propios Tipos de Datos Alxébricos (ADTs), escribir funcións polimórficas con `A`..`Z` e fabricar os teus propios operadores á medida**.
