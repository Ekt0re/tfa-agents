# Guida al Sistema Missioni

Questo documento spiega come creare, gestire e concatenare missioni nel gioco TFA-Agents utilizzando il sistema basato su `MissionManager`, `MissionData` e `MissionPanel`.

## Architettura

Il sistema è composto da tre componenti principali:

| Componente | File | Ruolo |
|---|---|---|
| **MissionManager** | `Scripts/mission_manager.gd` | Autoload singleton. API pubblica per avviare, aggiornare e terminare missioni. |
| **MissionData** | `Scripts/mission_data.gd` | Resource che descrive una singola missione (tipo, label, target, colori). |
| **MissionPanel** | `Scripts/mission_panel.gd` | Script attaccato al nodo `TopCenter` nell'HUD. Ascolta i segnali di `MissionManager` e aggiorna la UI. |

### Flusso dei segnali

```
MissionManager ──► mission_started(data)         ──► MissionPanel
                 ──► mission_progress_changed(c,t) ──► MissionPanel
                 ──► mission_completed(data)       ──► MissionPanel
                 ──► mission_failed(data)          ──► MissionPanel
                 ──► mission_cleared()             ──► MissionPanel
```

## Tipi di Missione

Definiti in `MissionData.Type`:

| Tipo | Descrizione | Target |
|---|---|---|
| `ELIMINATE` | Elimina N nemici | Numero nemici |
| `COLLECT` | Raccogli N item | Numero item |
| `REACH` | Raggiungi un punto | 0 (booleano) |
| `ACTIVATE` | Attiva un oggetto | 0 (booleano) |
| `SURVIVE` | Sopravvivi N secondi | Secondi (con progress bar) |
| `CUSTOM` | Testo libero | Variabile |

## API MissionManager

### Avviare una missione

```gdscript
# Metodo diretto con MissionData personalizzato
var data := MissionData.new()
data.type = MissionData.Type.ELIMINATE
data.label = "NEUTRALIZZA"
data.target = 5
data.mission_id = "eliminate_5"
data.accent_color = Color(0.988, 0.380, 0.157, 1.0)
MissionManager.start(data)

# Factory helper (più veloce)
MissionManager.start(MissionManager.make_eliminate(5))
MissionManager.start(MissionManager.make_collect(3, "CRISTALLO"))
MissionManager.start(MissionManager.make_reach("PORTALE"))
MissionManager.start(MissionManager.make_activate("LEV_ALPHA"))
MissionManager.start(MissionManager.make_survive(30))
MissionManager.start(MissionManager.make_custom("OBIETTIVO SPECIALE", 10, Color.CYAN))
```

### Aggiornare il progresso

```gdscript
# Incrementa di 1 (default)
MissionManager.update_progress()

# Incrementa di N
MissionManager.update_progress(3)

# Imposta valore assoluto
MissionManager.set_progress(7)
```

> Quando `progress >= target`, la missione si completa automaticamente.

### Forzare completamento / fallimento

```gdscript
MissionManager.complete()  # Forza completamento
MissionManager.fail()      # Forza fallimento
MissionManager.clear()     # Rimuove la missione dall'HUD
```

### Leggere lo stato

```gdscript
var missione_attiva: MissionData = MissionManager.active_mission
var progresso: int = MissionManager.progress
```

## Factory Helper Disponibili

| Metodo | Tipo | Colore default |
|---|---|---|
| `make_eliminate(count, label)` | ELIMINATE | Arancio |
| `make_collect(count, item_name)` | COLLECT | Verde |
| `make_reach(point_name)` | REACH | Ciano |
| `make_activate(object_name)` | ACTIVATE | Giallo |
| `make_survive(seconds)` | SURVIVE | Viola |
| `make_custom(label, target, color)` | CUSTOM | Bianco |

## Concatenare Missioni

Il pattern per concatenare missioni in sequenza è basato sul segnale `mission_completed`:

### Pattern Base

```gdscript
extends Node

enum Step { MISSIONE_1, MISSIONE_2, MISSIONE_3, DONE }
var current_step: Step = Step.MISSIONE_1

func _ready() -> void:
    MissionManager.mission_completed.connect(_on_mission_completed)
    _start_missione_1()

func _start_missione_1() -> void:
    current_step = Step.MISSIONE_1
    MissionManager.start(MissionManager.make_eliminate(3, "ELIMINA SCOUT"))

func _start_missione_2() -> void:
    current_step = Step.MISSIONE_2
    MissionManager.start(MissionManager.make_reach("BASE NEMICA"))

func _start_missione_3() -> void:
    current_step = Step.MISSIONE_3
    MissionManager.start(MissionManager.make_activate("TRASMETTITORE"))

func _on_mission_completed(data: MissionData) -> void:
    # Attendi che il pannello HUD mostri "COMPLETATA" e si nasconda
    await get_tree().create_timer(2.8).timeout

    match current_step:
        Step.MISSIONE_1:
            _start_missione_2()
        Step.MISSIONE_2:
            _start_missione_3()
        Step.MISSIONE_3:
            _on_tutte_completate()

func _on_tutte_completate() -> void:
    print("Tutte le missioni completate!")
    MissionManager.clear()
```

### Pattern con Avanzamento Automatico

Se vuoi che le missioni avanzino automaticamente al completamento della precedente (come nel tutorial di `dev_map.tscn`):

```gdscript
extends Node

var mission_queue: Array[MissionData] = []
var _current_index: int = -1

func _ready() -> void:
    MissionManager.mission_completed.connect(_on_completed)

    # Definisci la coda di missioni
    mission_queue.append(MissionManager.make_eliminate(3, "ELIMINA SCOUT"))
    mission_queue.append(MissionManager.make_reach("PUNTO_ALPHA"))
    mission_queue.append(MissionManager.make_collect(5, "RISORSE"))

    # Avvia la prima
    _start_next()

func _start_next() -> void:
    _current_index += 1
    if _current_index < mission_queue.size():
        MissionManager.start(mission_queue[_current_index])

func _on_completed(_data: MissionData) -> void:
    await get_tree().create_timer(2.8).timeout
    _start_next()
```

### Pattern con Condizioni Dinamiche

Per missioni che avanzano solo quando una condizione è soddisfatta (es. tutti i nemici eliminati):

```gdscript
extends Node

var _initial_bot_count: int = 0

func _ready() -> void:
    MissionManager.mission_completed.connect(_on_completed)
    _start_eliminate_mission()

func _start_eliminate_mission() -> void:
    _initial_bot_count = get_tree().get_nodes_in_group("bots").size()
    var data := MissionManager.make_eliminate(_initial_bot_count, "ELIMINA TUTTI")
    MissionManager.start(data)
    MissionManager.set_progress(0)

func _process(delta: float) -> void:
    if MissionManager.active_mission == null:
        return
    # Polling: aggiorna il progresso in base ai bot rimasti
    var remaining := get_tree().get_nodes_in_group("bots").size()
    var eliminated := _initial_bot_count - remaining
    MissionManager.set_progress(eliminated)
    # Il completamento avviene automaticamente quando progress >= target

func _on_completed(data: MissionData) -> void:
    print("Missione completata: ", data.label)
    # Avvia la prossima missione...
```

## HUD Mission Panel

### Struttura Nodi Richiesta

Il `MissionPanel` (script su `TopCenter` nell'HUD) cerca questi nodi con unique name (`%`):

| Nodo | Tipo | Descrizione |
|---|---|---|
| `%MissionPanelInner` | PanelContainer | Pannello interno con lo stile |
| `%MissionLabel` | Label | Testo label della missione |
| `%MissionCounter` | Label | Counter numerico (es. "3 / 5") |
| `%MissionProgressBar` | ProgressBar | Barra di progresso (per SURVIVE) |
| `%MissionStatus` | Label | Stato "✔ COMPLETATA" / "✖ FALLITA" |
| `%MissionAnim` | AnimationPlayer | Animazioni opzionali (slide_in, slide_out, complete_flash) |

### Animazioni Opzionali

L'`AnimationPlayer` `%MissionAnim` può contenere:

- **`slide_in`** — riprodotta quando la missione inizia
- **`slide_out`** — riprodotta quando la missione viene rimossa (clear)
- **`complete_flash`** — riprodotta quando la missione è completata

Se un'animazione non esiste, il sistema continua senza errori.

### Stili per Stato

Il `MissionPanel` supporta tre `StyleBoxFlat` esportati:

- `style_active` — stile quando la missione è in corso
- `style_completed` — stile quando la missione è completata
- `style_failed` — stile quando la missione è fallita

Se non assegnati, il pannello usa lo stile di default definito nella scena.

## Esempio Completo: Missione con Timer di Sopravvivenza

```gdscript
func _start_survive_mission() -> void:
    var data := MissionManager.make_survive(30)  # 30 secondi
    MissionManager.start(data)

    # Timer che decrementa il progresso (countdown)
    var elapsed := 0
    while elapsed < 30:
        await get_tree().create_timer(1.0).timeout
        elapsed += 1
        MissionManager.set_progress(elapsed)
        # Se il player muore durante la missione:
        # MissionManager.fail()
        # return
```

## Note Importanti

1. **Auto-completamento**: Quando `progress >= target`, `MissionManager` chiama automaticamente `complete()`. Non serve chiamarlo manualmente per missioni con counter.

2. **Clear automatico**: Dopo il completamento, il `MissionPanel` attende 2.5 secondi mostrando "COMPLETATA", poi chiama `MissionManager.clear()` automaticamente.

3. **Una missione alla volta**: `MissionManager` supporta una sola missione attiva. Chiamare `start()` sostituisce la missione corrente.

4. **Segnali globali**: Tutti i segnali di `MissionManager` sono globali (singleton), quindi qualsiasi nodo può ascoltarli.

5. **Gruppi Godot per il tracking**: Per missioni di tipo ELIMINATE o COLLECT, usa i gruppi Godot per contare gli elementi:
   - `"bots"` — nemici bot
   - `"item"` — oggetti raccoglibili (Casse, Barili, PowerUp)
   - `"Barile"` — solo barili esplosivi
   - `"Cassa"` — solo casse

## Tutorial dev_map.tscn

Nella scena `Maps/dev_map.tscn` è presente un tutorial sequenziale (`Scripts/dev_map_tutorial.gd`) che guida il player attraverso 6 missioni:

1. **Muovi con WASD** — si completa quando il player si sposta
2. **Mira con il mouse** — si completa quando il mouse viene mosso
3. **Spara con tasto sinistro** — si completa quando il player spara (munizioni diminuiscono)
4. **Elimina tutti i nemici** — tracking del gruppo `"bots"`
5. **Raccogli tutti gli item** — tracking del gruppo `"item"`
6. **Distruggi tutti i barili** — tracking del gruppo `"Barile"`

Ogni missione avanza automaticamente alla successiva dopo il completamento.
