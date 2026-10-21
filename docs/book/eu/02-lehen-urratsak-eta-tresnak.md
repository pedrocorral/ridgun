# 02. kapitulua: Zure bi lagunik onenak: `ridgunc` eta `stable` (Zero YAML fitxategi, hitza emanda)

Badira konpiladore zoragarria duten lengoaiak, baina haien proiektu-sistema zure etsai amorratuenak diseinatua dirudiena: tabuladore ikusezinak dituen 400 lerroko `Makefile` bat dela, `pom.xml` amaigabe bat dela, finko begiratzen badiozu funtzionatzeari uzten dion `webpack.config.js` bat dela...

Ridgunen promesa oso sinple bat egin genion geure buruari lehen egunetik:

> *"Bi exekutagarri baino ez dira egongo ekosistema osoan (`ridgunc` eta `stable`), biak Ridgunen bertan idatzita egongo dira, eta proiektuaren konfigurazio-fitxategia (`build.rg`) Ridgun kode arrunta izango da. Ez JSON, ez YAML, ez TOML, ez asmakizun arrarorik."*

Ikus dezagun nola erabiltzen diren.

---

## 2.1. `ridgunc`: Fitxategi solteetarako frankotiratzailea

Esku artean `.rg` fitxategi bakar bat duzunean eta ideia azkar bat probatu, bere motak aztertu edo exekutagarri bat konpilatu nahi duzunean, zuzenean **`ridgunc`**-ekin hitz egiten duzu.

Benetan gogoratu behar dituzun 4 komando baino ez ditu:

```bash
# 1. "Honek konpilatzen du ala hanka sartu dut motaren batekin?"
ridgunc check esperimentua.rg

# 2. "Exekutatu oraintxe!" (Konpilatu eta exekutatu kolpe batean)
ridgunc run esperimentua.rg

# 3. "Egidazu eramateko prest dagoen ELF bitar natibo bat"
ridgunc build esperimentua.rg -o nire_programa

# 4. "Atera iezadazu tarteko bytecode artefaktua (.rgc)"
ridgunc compile esperimentua.rg -o esperimentua.rgc
```

### `ridgunc check`-en superbotere ezkutua
`ridgunc check` abiarazten duzunean, ez dizu *"0 errore"* bakarrik esaten. Analizatzaile estatikoak zure funtzio bakoitzerako zein estrategia aukeratu duen ere xuxurlatzen dizu:
- **`InlineSequential`**: *"Funtzio hau txikia eta zuzena da; lerroan exekutatuko dut planifikazio-gainkosturik sartu gabe"*.
- **`LazyStealableTask`**: *"Hemen errekurtsioa edo `||` grafo paralelo bat dago; prestatu egingo dut beste PUZ nukleo batzuek lana lapurtu ahal izan dezaten behar izanez gero"*.

### `ridgunc build`-en bisturia (Zergatik zure bitarrek ez duten 20 MB pisatzen)
`ridgunc build` exekutatzen duzunean, konpiladorea ez da mugatzen inportatu dituzun liburutegietako kode guztia botatzera:
1. Zure `main` funtzioan hasten da eta dei-grafoa zeharkatzen du **zein funtzio erabiltzen dituzun benetan** ikusteko. 80 funtzioko liburutegi erraldoi bat inportatu baduzu baina 2ri baino ez badiezu deitzen, beste 78ak baztertu egiten dira mihiztatzailea ukitu aurretik ere (*Tree-Shaking*).
2. Isats-errekurtsiboak diren funtzio guztiak bilatzen ditu eta **0 pila-byte** kontsumitzen dituzten `loop` begizta natibo bihurtzen ditu.
3. Azken esteka optimizazio globalarekin (*fat LTO*) pasatzen du eta DWARF arazketa-zaborra garbitzen du, bitar trinko eta zorrotz bat (~350 KB) uzteko.

---

## 2.2. `stable`: Zure proiektua hazten denean eta ordena nahi duzunean

Fitxategi solte bat bikaina da script baterako, baina hainbat modulu, liburutegi partekatu eta test dituzun bezain laster, orkestra-zuzendari bat behar duzu. Hori **`stable`** da.

Ridgun proiektu baten karpeta-egiturak ez du misteriorik:

```text
nire-super-tresna/
├── build.rg                  # Proiektuaren manifestua (Ridgun kodea da!)
├── src/
│   ├── main/
│   │   └── ridgun/
│   │       ├── lib/          # Zure modulu berrerabilgarriak (`import tresnak`)
│   │       └── app/
│   │           └── main.rg   # Sarrera-puntua (`main => ()`)
│   └── test/
│       └── ridgun/           # Zure test-bateriak (`test *.rg`)
│           └── test dena.rg
└── target/                   # Konpilatutako bitarrak agertzen diren lekua
```

---

## 2.3. `build.rg`: Inoiz gezurrik esango ez dizun konfigurazio-fitxategia

Zergatik uko egiten diogu YAML edo TOML erabiltzeari Ridgun proiektu bat konfiguratzeko?
YAMLen koskako bi zuriunetan huts egiten duzulako eta ez zarelako konturatzen hedapenak huts egiten duen arte. Aldiz, **`build.rg` Ridgun fitxategi bat denez**, mota estatikoak ditu, `stable check`-etik pasatzen da eta bakarrik lerrokatzen da `stable format`-ekin:

```ridgun
type ProjectInfo =
  name: String
  version: String
  edition: String

project => ProjectInfo
project =  ProjectInfo "nire-super-tresna" "0.1.0" "2026"

source dir => String
source dir =  "src/main/ridgun"

test dir => String
test dir =  "src/test/ridgun"

target dir => String
target dir =  "target"
```

Eremu bat idaztean huts egiten baduzu, konpiladoreak berak abisatzen dizu. Ezustekorik gabe.

---

## 2.4. Zure eguneroko errutina `stable`-rekin (4 fantastikoak)

Zure proiektuaren barruan lanean ari zarenean, zure egunerokoa lau komandotara murrizten da:

### 1. `stable format` — Taldeko estilo-eztabaiden amaiera
```bash
stable format
```
Zure lankideak `=>` aurretik hiru zuriune jartzen dituela eta zuk bat? Berdin dio. `stable format` exekutatzen duzu eta segundo bat baino gutxiagoan biltegiko `.rg` fitxategi **guztiak** Suitzako taula bat bezala lerrokatuta uzten ditu.

### 2. `stable check` — Berehalako radarra
```bash
stable check
```
`src/main/ridgun/` barruko modulu guztiak zeharkatzen ditu, motak, eraikitzaileak, aritateak eta tentsore-dimentsioak egiaztatzen ditu, eta epaia ematen dizu moduluz modulu.

### 3. `stable test` — Gauez lasai lo egitea
```bash
stable test
```
`src/test/ridgun/test *.rg` suite guztiak bilatzen ditu, exekutatzen ditu eta `assert equals` zein `assert true` bakoitza egiaztatzen du.

```ridgun
-- src/test/ridgun/test matematika.rg adibidea
import test

bikoitza Int => Int
bikoitza x   =  x * 2

main => ()
main =
  assert equals (bikoitza 21) 42
  assert true ((bikoitza 5) > 0)
```

### 4. `stable built` (eta `stable clean`) — Ekoizpenera
```bash
stable built
```
Helburu natibo guztiak `target/` karpetan konpilatzen ditu. Eta egunen batean `target/` ezabatu eta garbi hasi nahi baduzu: `stable clean`.

---

## 2.5. Nola inportatzen dut fitxategi bat beste batetik? (`import`)

`../../../lib/gauzak.rg` moduko bide erlatibo infernuzkorik gabe. `src/main/ridgun/lib/kateak.rg` fitxategi bat baduzu, beste edozein fitxategitan goi-goian hau idazten duzu:

```ridgun
import kateak
```

Eta kitto: `kateak.rg`-ko funtzio eta mota guztiak eskuragarri daude zure fitxategian bertan baleude bezala. Eta zer gertatzen da `A` moduluak `import kateak` egiten badu, `B` moduluak ere `import kateak` egiten badu, eta zure `main.rg`-k `A` eta `B` inportatzen baditu? Lasai: Ridgunen kargatzaileak gogoratzen du zein fitxategi kanoniko irakurri dituen dagoeneko eta **behin bakarrik sartzen du**.

Orain tresna-kutxa kontrolpean duzula, pasa gaitezen **03. kapitulura** funtzioak, motak, blokeak eta testu-kateekin egiteko trikimailuak menderatzeko.
