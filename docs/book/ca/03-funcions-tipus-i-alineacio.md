# Capítol 03: Funcions, signatures de tipus i l'art d'escriure codi com una taula

Hi ha una pregunta que tot programador es fa la primera vegada que veu codi funcional:

> *"Si aquí no hi ha classes, ni objectes, ni variables que canvien de valor... aleshores on fico la meva lògica?"*

En **funcions**. Però no en aquelles funcions de 200 línies plenes de banderes booleanes que tots hem patit alguna vegada, sinó en funcions petites, directes i tan fàcils de llegir que semblen una taula en una pissarra.

Vegem com es construeixen.

---

## 3.1. Dues maneres de presentar una funció (Tu tries el vestit)

En Ridgun tota funció comença amb la seva **signatura de tipus** (què entra i què surt després de `=>`) i a sota hi van les seves **clàusules d'implementació** (amb `=`).

Pots escriure la capçalera de dues maneres:

### Opció A: Directa al gra (sense prefix)
```ridgun
aplicar_descompte Int  Int         => Int
aplicar_descompte preu percentatge =  preu - (preu * percentatge / 100)
```

### Opció B: Amb etiqueta explícita (`fn ::`)
```ridgun
fn :: aplicar_descompte Int  Int         => Int
      aplicar_descompte preu percentatge =  preu - (preu * percentatge / 100)
```

*"Escolta, i per què existeixen totes dues?"*
Perquè per a gustos, els colors:
- Hi ha qui prefereix que les funcions comencin enganxades al marge esquerre sense escriure `fn ::` cada vegada (al cap i a la fi, la fletxa `=>` ja crida als quatre vents que aquella línia és una signatura de tipus).
- I hi ha qui prefereix tenir una columna esquerra dedicada a les etiquetes (`fn ::`, `op ::`, `type`, `import`) per escanejar el fitxer visualment.

El compilador i `stable format` entenen totes dues a la perfecció.

---

## 3.2. La màgia de les columnes: per què els teus ulls descansen

Mira aquesta funció que calcula el cost d'un enviament segons el país i si és urgent:

```ridgun
cost_enviament String Bool  Int => Int
cost_enviament "ES"   False _   =  5
cost_enviament "ES"   True  _   =  12
cost_enviament _      False pes =  10 + (pes * 2)
cost_enviament _      True  pes =  25 + (pes * 4)
```

Fes la prova: tapa la meitat dreta de la pantalla i mira només les tres columnes d'entrada:
- Primera columna (`String`): `"ES"`, `"ES"`, `_`, `_`.
- Segona columna (`Bool`): `False`, `True`, `False`, `True`.
- Tercera columna (`Int`): `_`, `_`, `pes`, `pes`.

Hi veus cap forat lògic? Cap ni un: hi ha les 4 combinacions possibles davant dels teus nassos, alineades verticalment sota `String`, `Bool` i `Int`. En un bloc d'`if / else` tradicional hauries de llegir 18 línies per estar segur que no t'has deixat cap cas penjat.

---

## 3.3. Els tipus bàsics i un regal per no comptar zeros (`_KB`, `_MB`, `_GB`)

Els tipus escalars de Ridgun són directes i sense sorpreses:

| Tipus | Què és en realitat | Exemples |
|---|---|---|
| `Int` | Enter de 64 bits amb signe (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `Real` | Decimal de doble precisió (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Cadena de text immutable | `"Hola"`, `'ruta\crua'` |
| `Char` | Codi de caràcter | Retornat per `str_char_at` |
| `Bool` | Booleà de tota la vida | `True`, `False` |
| `()` | Buit (*Unit*, quan només imprimeixes o fas I/O) | `()` |

### Cansat d'escriure `65536` o `1048576` i resar per no haver-te menjat un dígit?
En Ridgun els literals numèrics accepten directament els sufixos **`_KB`**, **`_MB`** i **`_GB`**, a més de guions baixos `_` per separar grups de xifres:

```ridgun
mida_buffer => Int
mida_buffer =  64_KB        -- El compilador ho tradueix a 65536

limit_fitxer => Int
limit_fitxer =  16_MB       -- El compilador ho tradueix a 16777216

mascara_octet => Int
mascara_octet =  0xFF_00    -- Hexadecimal net i llegible
```

---

## 3.4. Cometes dobles (`"..."`) vs. Cometes simples (`'...'`)

En molts llenguatges les cometes simples i dobles fan exactament el mateix (un malbaratament). En Ridgun cadascuna té una missió claríssima:

### 1. Cometes dobles (`"..."`): Intel·ligents i interpolades
Interpreten escapaments (`\n`, `\t`, `\"`, `\\`) i **avaluen qualsevol variable o expressió que posis entre claus `{...}`**:

```ridgun
resum_comanda String Int Int  => String
resum_comanda item   uts preu =
  "Has demanat {uts}x {item}. Total a pagar: {uts * preu} euros."
```

*(Truc: si necessites escriure una clau literal dins de cometes dobles —per exemple en generar un script de shell `"$\{VAR:-default\}"` o un JSON—, pots escapar-la amb barra invertida `\{` i `\}` o duplicar-la `{{` i `}}`).*

### 2. Cometes simples (`'...'`): Crues i literals (*Raw Strings*)
El que escrius entre cometes simples surt **tal qual**, sense tocar ni una barra invertida `\`, ni una clau `{}`. Perfecte per a quan generes codi en un altre llenguatge, escrius ordres de shell o treballes amb rutes plenes de barres:

```ridgun
ordre_sed => String
ordre_sed =  's/\([0-9]+\)/[\1]/g'
```

### La teva caixa d'eines per a cadenes (`String`)
Unir cadenes és tan simple com sumar-les amb `+`: `"Hola, " + nom`. I quan necessites fer cirurgia fina sobre un text, tens aquestes funcions natives a punt sense importar res:

- `str_len s` $\rightarrow$ longitud de `s`.
- `str_char_at s i` $\rightarrow$ codi numèric (`Int`) del caràcter a la posició `i` (`-1` si et passes).
- `str_slice s inici fi` $\rightarrow$ retalla des d'`inici` fins a `fi` (sense incloure `fi`).
- `char_from_code c` $\rightarrow$ converteix un codi numèric (`Int`, p. ex. `10` per a `\n` o `34` per a `"`) en un `String` d'1 caràcter.
- `str_contains s agulla` i `str_starts_with s prefix` $\rightarrow$ retornen `True` o `False`.
- `int_to_str n` i `str_to_int s` $\rightarrow$ converteixen de número a text i viceversa (`str_to_int` entén fins i tot `"0xFF"`!).

---

## 3.5. Blocs de diverses línies, la regla universal de l'`=` i variables `mut`

Quan una funció no cap en una sola línia, fas un salt de línia després de l'`=` i sagnes el bloc.

Mira com es llegeix un bloc pas a pas:

```ridgun
calcular_factura Int  Int     => Int
calcular_factura base iva_pct =
  impostos = base * iva_pct / 100
  despeses_gestio = 5
  echo "Desglossament -> Base:" base "Impostos:" impostos
  base + impostos + despeses_gestio
```

Quatre regles d'or que fan que els blocs en Ridgun siguin nets i uniformes:
1. **Immutable per defecte sense `let` ni `const`**: escrius `impostos = ...` i ja tens la teva constant local immutable. Si per descuit intentes sobreescriure `impostos = 99` més avall en el mateix bloc, el compilador et frena en sec.
2. **Variables mutables explícites amb `mut`**: quan de debò vols anar actualitzant un acumulador local pas a pas dins d'una funció, el declares amb **`mut`** i després el reassignes lliurement amb `=`:
   ```ridgun
   aplicar_recarrecs Int  => Int
   aplicar_recarrecs preu =
     mut total = preu
     total = total + 10
     total = total * 2
     total
   ```
   *(I si `total` desa una llista o estructura en memòria, la política **`RMM2`** de Ridgun suma `+1` al nou valor abans de descomptar `-1` a l'antic, alliberant-lo a l'instant si ningú més el fa servir).*
3. **La regla universal de l'`=`**: darrere de **qualsevol `=`** (en una funció, en un operador, en una variable local `x =` o en una branca condicional) pots posar sempre qualsevol de les tres formes de bloc de Ridgun:
   - **`(res)`**: línies seqüencials sagnades (com a dalt).
   - **`|`**: un arbre de guardes condicionals.
   - **`||`**: un graf de càlculs en paral·lel amb `->`.
4. **L'última expressió és sempre el resultat**: `base + impostos + despeses_gestio` és el que retorna `calcular_factura`. Sense `return`.

Al **Capítol 04** veurem com prendre decisions complexes —incloent-hi arbres de decisió de diversos nivells amb `|.`— sense escriure mai un `if/else` ni un bucle `while`: benvingut al món de les **guardes booleanes** i la **recursió de cua de cost zero**.
