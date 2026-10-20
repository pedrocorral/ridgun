# Capítulo 00: Por que preciso Ridgun? Ah, si? Non o sabía... Cóntame máis!

Sexamos sinceros: cando alguén che di *"creamos unha nova linguaxe de programación"*, a túa primeira reacción natural —e moi sa— é erguer unha cella e pensar:

> *"Outra máis? Pero se xa teño Python para ir rápido, Rust ou C para cando preciso velocidade, e Bash para pegar cousas na terminal. Para que demo preciso eu aprender Ridgun?"*

É unha pregunta excelente. E a resposta curta é: **porque te acostumaches a sufrir catro dores diarias pensando que eran inevitables**.

Imos poñerlles nome.

---

## Dor n.º 1: "A síndrome dos dous mundos" (Prototipar nun, reescribir noutro)

Seguro que xa viviches esta película:

1. Comezas unha ferramenta ou un motor de cálculo en **Python**, **JavaScript** ou **Ruby** porque queres pensar no problema, non en punteiros nin no compilador.
2. O código queda curto e bonito... pero cando lle pasas un ficheiro de 500 MB ou intentas usar os 16 núcleos da túa máquina, arrástrase. E se queres distribuír o teu programa a un servidor limpo, tes que empaquetar medio xigabyte de contorno virtual, intérprete e bibliotecas dinámicas.
3. Resignado, decides reescribilo en **C**, **C++** ou **Rust**. Agora voa e ocupa uns poucos centos de kilobytes, pero o teu código de 40 liñas converteuse en 300 liñas cheas de `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, chaves `{}` e puntos e coma `;`.

**Que muda con Ridgun?**
En Ridgun escribes código **máis curto e limpo ca en Python**, pero cando executas `ridgunc build`, obtés **un único binario nativo ELF de ~350 KB** sen intérprete, sen máquina virtual externa e sen colector de lixo. Non hai fase de *"logo reescribímolo na linguaxe rápida"*: o código limpo onde pensas o problema **xa é** o binario nativo de produción.

---

## Dor n.º 2: "Ler código alleo (ou o teu de hai 6 meses) é xogar a ser detective"

Mira como escribimos lóxica condicional en case todas as linguaxes convencionais:

```text
if (estado == ACTIVO && (rol == ADMIN || (rol == EDITOR && tenPermiso))) {
    if (cota > 0) {
        return procesar(usuario);
    } else {
        return denegar("Sen cota");
    }
} else {
    return denegar("Non autorizado");
}
```

Os nosos ollos non evolucionaron para emparellar chaves aniñadas nin para desentrañar árbores de `if / else` graduadas. Cando os enxeñeiros, matemáticos ou físicos queren entender regras complexas sen trabucarse, non escriben parágrafos de `if / else`: **debuxan unha táboa**.

En Ridgun, **o código é esa táboa**:

```ridgun
autorizar String   String   Bool  Int  => String
autorizar "activo" "admin"  _     cota =
  | cota > 0  = "Procesando petición"
  | otherwise = "Denegado: sen cota"
autorizar "activo" "editor" True  cota =
  | cota > 0  = "Procesando petición"
  | otherwise = "Denegado: sen cota"
autorizar _        _        _     _    =  "Denegado: non autorizado"
```

Mira as columnas:
- Columna 1: o estado (`"activo"` ou `_`).
- Columna 2: o rol (`"admin"`, `"editor"` ou `_`).
- Columna 3: se ten permiso (`True` ou `_`).
- Columna 4: a `cota`.

Non tes que executar mentalmente o programa liña por liña para saber que pasa cando entra un `"editor"` con permiso `False`: os teus ollos baixan verticalmente pola táboa e veno en medio segundo.

---

## Dor n.º 3: "O meu ordenador ten 16 núcleos, pero o meu programa só usa 1 (porque me dá pánico tocar fíos)"

Hoxe ata o teléfono máis modesto ten 8 núcleos, e calquera servidor ou portátil de traballo ten entre 12 e 32. Porén, o 95% dos programas cotiáns seguen executándose nun só fío secuencial.

Por que? Porque nas linguaxes imperativas, paralelizar significa abrir a caixa de Pandora:
- E se dous fíos modifican o mesmo dicionario á vez? (*Data race*).
- E se bloqueo o `Mutex` A e logo o B nun fío, e o B e logo o A noutro? (*Deadlock*).
- E se contamino toda a miña base de código con `async` e `await` de arriba abaixo?

En Ridgun, **toda función é pura e todo dato é inmutable por defecto**. Iso ten unha consecuencia máxica: **dúas expresións que non dependen unha da outra xamais poden interferir entre si**.

Por iso, en Ridgun non tes que xestionar fíos para aproveitar a túa CPU. Só declaras **que depende de que** con barras paralelas `||` e frechas `->`:

```ridgun
informe_mensual Datos => Informe
informe_mensual d     =  combinar metricas_rede metricas_disco metricas_cpu
  || analizar_rede d  -> metricas_rede
  || analizar_disco d -> metricas_disco
  || analizar_cpu d   -> metricas_cpu
```

Ti só escribiches tres liñas limpas indicando de onde sae cada dato. O compilador ve que as tres ramas son independentes e sabe que pode lanzalas en paralelo sen que exista nin a máis mínima posibilidade dun *data race* ou dun *deadlock*.

---

## Dor n.º 4: "O colector de lixo decide pausar o mundo xusto no peor momento"

As linguaxes funcionais clásicas (Haskell, OCaml, Erlang, Clojure) son marabillosas para razoar sobre o código, pero case todas dependen dun **Colector de Lixo (*Garbage Collector*)** en tempo de execución. Iso descártaas cando precisas:
- Latencias predicibles ao microsegundo.
- Controlar exactamente canta memoria RAM pode consumir unha operación antes de abortala limpamente.
- Escribir utilidades do sistema operativo (`ls`, `find`, `sh`, `doas`, `make`) ou tocar rexistros de hardware (`MMIO`).

Ridgun dáche **toda a elegancia do mundo funcional puro, pero con Xestión de Memoria de Ridgun (`RMM`: `RMM1` estática e `RMM2` por conta de asignacións en fervenza) máis rexións léxicas con cota exacta (`with region`)**:

```ridgun
analizar_paquete String => Result
analizar_paquete cru    =
  with region 16_KB do
    decodificar_trama cru
```

Cada estrutura temporal é liberada de forma determinista polo compilador (`RMM1` / `RMM2`) no instante en que deixa de usarse, e se un atacante che envía un paquete malicioso deseñado para rebentar a memoria, ao superar o byte 16.384 a rexión córtase ao instante, libera a súa area en $O(1)$ e devólveche `Err OutOfMemory`. Sen caídas do proceso, sen pausas de GC e sen fugas de memoria.

---

## En resumo: Cando brilla Ridgun?

Ridgun está feito para ti se algunha vez quixeches:

1. **Escribir ferramentas de sistemas, compiladores, analizadores ou utilidades CLI** que arrinquen en microsegundos, pesen uns poucos centos de KB e non poidan romper por punteiros nulos nin efectos colaterais ocultos.
2. **Programar algoritmos, tubaxes de datos ou álxebra de tensores** onde o compilador verifique por ti ata as dimensións das matrices (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) antes de executar nada.
3. **Gozar lendo o teu propio código**: que cada ficheiro `.rg` pareza unha páxina dun libro ben maquetado grazas ao formatador tabular automático (`stable format`).

Pícache a curiosidade? Pasa ao **Capítulo 01** e escribamos o noso primeiro programa en menos de dous minutos.
