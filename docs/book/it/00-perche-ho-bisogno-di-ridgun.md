# Capitolo 00: Perché ho bisogno di Ridgun? Ah sì? Non lo sapevo... Raccontami di più!

Siamo sinceri: quando qualcuno ti dice *"abbiamo creato un nuovo linguaggio di programmazione"*, la tua prima reazione naturale — e sanissima — è inarcare un sopracciglio e pensare:

> *"Un altro? Ma se ho già Python per andare veloce, Rust o C per quando mi serve velocità pura, e Bash per incollare cose nel terminale. Perché diavolo dovrei imparare Ridgun?"*

È una domanda eccellente. E la risposta breve è: **perché ti sei abituato a soffrire quattro dolori quotidiani pensando che fossero inevitabili**.

Diamo loro un nome.

---

## Dolore n.º 1: "La sindrome dei due mondi" (Prototipare in uno, riscrivere nell'altro)

Sicuramente hai già vissuto questo film:

1. Inizi uno strumento o un motore di calcolo in **Python**, **JavaScript** o **Ruby** perché vuoi pensare al problema, non ai puntatori né al compilatore.
2. Il codice viene corto e bello... ma quando gli passi un file da 500 MB o provi a usare i 16 core della tua macchina, si trascina. E se vuoi distribuire il tuo programma su un server pulito, devi impacchettare mezzo gigabyte di ambiente virtuale, interprete e librerie dinamiche.
3. Rassegnato, decidi di riscriverlo in **C**, **C++** o **Rust**. Ora vola e occupa poche centinaia di kilobyte, ma il tuo codice di 40 righe si è trasformato in 300 righe piene di `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, parentesi graffe `{}` e punti e virgola `;`.

**Cosa cambia con Ridgun?**
In Ridgun scrivi codice **più corto e pulito che in Python**, ma quando esegui `ridgunc build`, ottieni **un unico binario nativo ELF da ~350 KB** senza interprete, senza macchina virtuale esterna e senza garbage collector. Non c'è la fase *"poi lo riscriviamo nel linguaggio veloce"*: il codice pulito in cui ragioni sul problema **è già** il binario nativo di produzione.

---

## Dolore n.º 2: "Leggere codice altrui (o il tuo di 6 mesi fa) è giocare al detective"

Guarda come scriviamo la logica condizionale in quasi tutti i linguaggi mainstream:

```text
if (stato == ATTIVO && (ruolo == ADMIN || (ruolo == EDITOR && haPermesso))) {
    if (quota > 0) {
        return elabora(utente);
    } else {
        return nega("Senza quota");
    }
} else {
    return nega("Non autorizzato");
}
```

I nostri occhi non si sono evoluti per accoppiare parentesi graffe annidate né per sbrogliare alberi di `if / else` a gradini. Quando gli ingegneri, i matematici o i fisici vogliono capire regole complesse senza sbagliare, non scrivono paragrafi di `if / else`: **disegnano una tabella**.

In Ridgun, **il codice è quella tabella**:

```ridgun
autorizzare String   String   Bool  Int   => String
autorizzare "attivo" "admin"  _     quota =
  | quota > 0 = "Elaborazione richiesta"
  | otherwise = "Negato: senza quota"
autorizzare "attivo" "editor" True  quota =
  | quota > 0 = "Elaborazione richiesta"
  | otherwise = "Negato: senza quota"
autorizzare _        _        _     _     =  "Negato: non autorizzato"
```

Guarda le colonne:
- Colonna 1: lo stato (`"attivo"` o `_`).
- Colonna 2: il ruolo (`"admin"`, `"editor"` o `_`).
- Colonna 3: se ha il permesso (`True` o `_`).
- Colonna 4: la `quota`.

Non devi eseguire mentalmente il programma riga per riga per sapere cosa succede quando entra un `"editor"` con permesso `False`: i tuoi occhi scendono verticalmente lungo la tabella e lo vedono in mezzo secondo.

---

## Dolore n.º 3: "Il mio computer ha 16 core, ma il mio programma ne usa solo 1 (perché ho il terrore di toccare i thread)"

Oggi persino il telefono più modesto ha 8 core, e qualsiasi server o portatile di lavoro ne ha tra 12 e 32. Eppure, il 95% dei programmi quotidiani continua a girare su un singolo thread sequenziale.

Perché? Perché nei linguaggi imperativi parallelizzare significa aprire il vaso di Pandora:
- E se due thread modificano lo stesso dizionario contemporaneamente? (*Data race*).
- E se blocco il `Mutex` A e poi il B in un thread, e il B e poi l'A in un altro? (*Deadlock*).
- E se contamino tutta la mia base di codice con `async` e `await` da cima a fondo?

In Ridgun, **ogni funzione è pura e ogni dato è immutabile per impostazione predefinita**. Questo ha una conseguenza magica: **due espressioni che non dipendono l'una dall'altra non possono mai interferire tra loro**.

Perciò, in Ridgun non devi gestire thread per sfruttare la tua CPU. Dichiari solo **cosa dipende da cosa** con barre parallele `||` e frecce `->`:

```ridgun
rapporto mensile Dati => Rapporto
rapporto mensile d    =  combina metriche_rete metriche_disco metriche_cpu
  || analizza rete d  -> metriche_rete
  || analizza disco d -> metriche_disco
  || analizza cpu d   -> metriche_cpu
```

Tu hai scritto solo tre righe pulite indicando da dove esce ogni dato. Il compilatore vede che i tre rami sono indipendenti e sa che può lanciarli in parallelo senza che esista nemmeno la minima possibilità di un *data race* o di un *deadlock*.

E se hai bisogno di agenti persistenti con casella di posta e stato isolato (ad esempio per mantenere migliaia di sessioni client, worker in background o connessioni di rete)? In Ridgun non devi definire classi `Actor` né usare `Mutex`: **qualsiasi funzione normale si trasforma in un agente autonomo in una sola riga con `agent`**:

```ridgun
contatore = agent (somma visita) 0
send 1 to contatore
send 5 to contatore
totale = receive from contatore
stop contatore
```

Inoltre, il compilatore effettua una **scelta intelligente a tempo di compilazione**: analizza staticamente la profondità e il costo di ogni funzione in `||`, `||map`, `||filter` e `agent` per eseguire le funzioni leggere come passi *green-thread* a sovraccarico zero (senza pagare il costo di riscaldare thread del sistema operativo) e smistare automaticamente i calcoli pesanti o ricorsivi su thread reali del kernel su più core (`SYS_clone`).

---

## Dolore n.º 4: "Il garbage collector decide di mettere in pausa il mondo proprio nel momento peggiore"

I linguaggi funzionali classici (Haskell, OCaml, Erlang, Clojure) sono meravigliosi per ragionare sul codice, ma quasi tutti dipendono da un **Garbage Collector** a tempo di esecuzione. Questo li esclude quando hai bisogno di:
- Latenze prevedibili al microsecondo.
- Controllare esattamente quanta memoria RAM può consumare un'operazione prima di interromperla in modo pulito.
- Scrivere utilità di sistema operativo (`ls`, `find`, `sh`, `doas`, `make`) o toccare registri hardware (`MMIO`).

Ridgun ti dà **tutta l'eleganza del mondo funzionale puro, ma con la Gestione della Memoria di Ridgun (`RMM`: `RMM1` statica e `RMM2` per conteggio di assegnazioni a cascata) più regioni lessicali con quota esatta (`with region`)**:

```ridgun
analizza pacchetto String => Result
analizza pacchetto grezzo =
  with region 16_KB do
    decodifica trama grezzo
```

Ogni struttura temporanea viene liberata in modo deterministico dal compilatore (`RMM1` / `RMM2`) nell'istante in cui smette di essere usata, e se un attaccante ti invia un pacchetto malevolo progettato per far esplodere la memoria, superato il byte 16.384 la regione viene tagliata all'istante, libera la sua arena in $O(1)$ e ti restituisce `Err OutOfMemory`. Senza crolli del processo, senza pause del GC e senza perdite di memoria.

---

## In sintesi: Quando brilla Ridgun?

Ridgun è fatto per te se hai mai voluto:

1. **Scrivere strumenti di sistema, compilatori, analizzatori o utilità CLI** che si avviino in microsecondi, pesino poche centinaia di KB e non possano rompersi per puntatori nulli né effetti collaterali nascosti.
2. **Costruire sistemi concorrenti e server basati sul Modello Nativo di Agenti (`agent`, `send ... to`, `receive from`, `stop`)**, dove qualsiasi funzione pura diventa un agente con o senza stato isolato e il compilatore sceglie in modo intelligente tra esecuzione *green-thread* ultraleggera e thread nativi multicore.
3. **Programmare algoritmi, pipeline di dati o algebra dei tensori** in cui il compilatore verifichi per te persino le dimensioni delle matrici (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) prima di eseguire alcunché.
4. **Divertirti leggendo il tuo stesso codice**: che ogni file `.rg` sembri la pagina di un libro ben impaginato grazie al formattatore tabellare automatico (`stable format`).

Ti pizzica la curiosità? Passa al **Capitolo 01** e scriviamo il nostro primo programma in meno di due minuti.
