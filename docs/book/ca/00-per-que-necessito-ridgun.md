# Capítol 00: Per què necessito Ridgun? Ah, sí? No ho sabia... Explica-m'ho!

Siguem sincers: quan algú et diu *"hem creat un nou llenguatge de programació"*, la teva primera reacció natural —i molt sana— és arquejar una cella i pensar:

> *"Un altre? Però si ja tinc Python per anar ràpid, Rust o C per a quan necessito velocitat, i Bash per enganxar coses al terminal. Per a què dimonis necessito jo aprendre Ridgun?"*

És una pregunta excel·lent. I la resposta curta és: **perquè t'has acostumat a patir quatre mals de cap diaris pensant que eren inevitables**.

Posem-los nom.

---

## Mal de cap núm. 1: "La síndrome dels dos mons" (Prototipar en un, reescriure en un altre)

Segur que has viscut aquesta pel·lícula:

1. Comences una eina o un motor de càlcul en **Python**, **JavaScript** o **Ruby** perquè vols pensar en el problema, no en punters ni en el compilador.
2. El codi queda curt i bonic... però quan li passes un fitxer de 500 MB o intentes fer servir els 16 nuclis de la teva màquina, s'arrossega. I si vols distribuir el teu programa a un servidor net, has d'empaquetar mig gigabyte d'entorn virtual, intèrpret i llibreries dinàmiques.
3. Resignat, decideixes reescriure'l en **C**, **C++** o **Rust**. Ara vola i ocupa uns pocs centenars de kilobytes, però el teu codi de 40 línies s'ha convertit en 300 línies plenes d'`unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, claus `{}` i punts i coma `;`.

**Què canvia amb Ridgun?**
En Ridgun escrius codi **més curt i net que en Python**, però quan executes `ridgunc build`, obtens **un únic binari natiu ELF de ~350 KB** sense intèrpret, sense màquina virtual externa i sense recol·lector de brossa. No hi ha fase de *"després ho reescrivim en el llenguatge ràpid"*: el codi net on penses el problema **ja és** el binari natiu de producció.

---

## Mal de cap núm. 2: "Llegir codi aliè (o el teu de fa 6 mesos) és jugar a fer de detectiu"

Mira com escrivim lògica condicional en gairebé tots els llenguatges convencionals:

```text
if (estat == ACTIU && (rol == ADMIN || (rol == EDITOR && tePermis))) {
    if (quota > 0) {
        return processar(usuari);
    } else {
        return denegar("Sense quota");
    }
} else {
    return denegar("No autoritzat");
}
```

Els nostres ulls no van evolucionar per aparellar claus imbricades ni per desentranyar arbres d'`if / else` esglaonats. Quan els enginyers, matemàtics o físics volen entendre regles complexes sense equivocar-se, no escriuen paràgrafs d'`if / else`: **dibuixen una taula**.

En Ridgun, **el codi és aquesta taula**:

```ridgun
autoritzar String  String   Bool  Int   => String
autoritzar "actiu" "admin"  _     quota =
  | quota > 0 = "Processant petició"
  | otherwise = "Denegat: sense quota"
autoritzar "actiu" "editor" True  quota =
  | quota > 0 = "Processant petició"
  | otherwise = "Denegat: sense quota"
autoritzar _       _        _     _     =  "Denegat: no autoritzat"
```

Mira les columnes:
- Columna 1: l'estat (`"actiu"` o `_`).
- Columna 2: el rol (`"admin"`, `"editor"` o `_`).
- Columna 3: si té permís (`True` o `_`).
- Columna 4: la `quota`.

No has d'executar mentalment el programa línia per línia per saber què passa quan entra un `"editor"` amb permís `False`: els teus ulls baixen verticalment per la taula i ho veuen en mig segon.

---

## Mal de cap núm. 3: "El meu ordinador té 16 nuclis, però el meu programa només en fa servir 1 (perquè em fa pànic tocar fils)"

Avui fins i tot el telèfon més modest té 8 nuclis, i qualsevol servidor o portàtil de feina en té entre 12 i 32. Tot i això, el 95% dels programes quotidians continuen executant-se en un sol fil seqüencial.

Per què? Perquè en els llenguatges imperatius, paral·lelitzar significa obrir la caixa de Pandora:
- I si dos fils modifiquen el mateix diccionari alhora? (*Data race*).
- I si bloquejo el `Mutex` A i després el B en un fil, i el B i després l'A en un altre? (*Deadlock*).
- I si contamino tota la meva base de codi amb `async` i `await` de dalt a baix?

En Ridgun, **tota funció és pura i tota dada és immutable per defecte**. Això té una conseqüència màgica: **dues expressions que no depenen l'una de l'altra mai no poden interferir entre si**.

Per això, en Ridgun no has de gestionar fils per aprofitar la teva CPU. Només declares **què depèn de què** amb barres paral·leles `||` i fletxes `->`:

```ridgun
informe_mensual Dades => Informe
informe_mensual d     =  combinar metriques_xarxa metriques_disc metriques_cpu
  || analitzar_xarxa d -> metriques_xarxa
  || analitzar_disc d  -> metriques_disc
  || analitzar_cpu d   -> metriques_cpu
```

Tu només has escrit tres línies netes indicant d'on surt cada dada. El compilador veu que les tres branques són independents i sap que pot llançar-les en paral·lel sense que hi hagi ni la més mínima possibilitat d'un *data race* o un *deadlock*.

I si necessites agents persistents amb bústia de missatges i estat aïllat (per exemple, per mantenir milers de sessions de clients, treballadors en segon pla o connexions de xarxa)? En Ridgun no cal definir classes `Actor` ni usar `Mutex`: **qualsevol funció normal es converteix en un agent autònom en una sola línia amb `agent`**:

```ridgun
comptador = agent (sumar visita) 0
send 1 to comptador
send 5 to comptador
total = receive from comptador
stop comptador
```

A més, el compilador realitza una **elecció intel·ligent en temps de compilació**: analitza estàticament la profunditat i el cost de cada funció a `||`, `||map`, `||filter` i `agent` per executar les funcions lleugeres com a passos *green-thread* de sobrecàrrega zero i despatxar automàticament els càlculs pesats o recursius a fils reals del nucli en múltiples nuclis (`SYS_clone`).

---

## Mal de cap núm. 4: "El recol·lector de brossa decideix pausar el món just en el pitjor moment"

Els llenguatges funcionals clàssics (Haskell, OCaml, Erlang, Clojure) són meravellosos per raonar sobre el codi, però gairebé tots depenen d'un **Recol·lector de Brossa (*Garbage Collector*)** en temps d'execució. Això els descarta quan necessites:
- Latències predicibles al microsegon.
- Controlar exactament quanta memòria RAM pot consumir una operació abans d'avortar-la netament.
- Escriure utilitats del sistema operatiu (`ls`, `find`, `sh`, `doas`, `make`) o tocar registres de maquinari (`MMIO`).

Ridgun et dóna **tota l'elegància del món funcional pur, però amb Gestió de Memòria de Ridgun (`RMM`: `RMM1` estàtica i `RMM2` per recompte d'assignacions en cascada) més regions lèxiques amb quota exacta (`with region`)**:

```ridgun
analitzar_paquet String => Result
analitzar_paquet cru    =
  with region 16_KB do
    descodificar_trama cru
```

Cada estructura temporal és alliberada de manera determinista pel compilador (`RMM1` / `RMM2`) en l'instant en què deixa d'utilitzar-se, i si un atacant t'envia un paquet maliciós dissenyat per rebentar la memòria, en superar el byte 16.384 la regió es talla a l'instant, allibera la seva arena en $O(1)$ i et retorna `Err OutOfMemory`. Sense caigudes del procés, sense pauses de GC i sense fuites de memòria.

---

## En resum: Quan brilla Ridgun?

Ridgun està fet per a tu si alguna vegada has volgut:

1. **Escriure eines de sistemes, compiladors, analitzadors o utilitats CLI** que arrenquin en microsegons, pesin uns pocs centenars de KB i no es puguin trencar per punters nuls ni efectes col·laterals ocults.
2. **Construir sistemes concurrents i servidors basats en el Model Natiu d'Agents (`agent`, `send ... to`, `receive from`, `stop`)**, on qualsevol funció pura es converteix en un agent amb o sense estat aïllat i el compilador tria intel·ligentment entre execució *green-thread* ultralleugera i fils natius multinucli.
3. **Programar algorismes, canonades de dades o àlgebra de tensors** on el compilador verifiqui per tu fins i tot les dimensions de les matrius (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) abans d'executar res.
4. **Gaudir llegint el teu propi codi**: que cada fitxer `.rg` sembli una pàgina d'un llibre ben maquetat gràcies al formatador tabular automàtic (`stable format`).

Et pica la curiositat? Passa al **Capítol 01** i escrivim el nostre primer programa en menys de dos minuts.
