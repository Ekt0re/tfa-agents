# Mission Flow Editor — Guida Utente

> Plugin Godot 4.4+ per la creazione visuale di flussi di missioni in giochi top-down.  
> Stile Dialogic: graph editor, inspector, branching e comandi personalizzati.

---

## Indice

1. [Installazione e Attivazione](#1-installazione-e-attivazione)
2. [Panoramica dell'Interfaccia](#2-panoramica-dellinterfaccia)
3. [Creare un Nuovo Flusso](#3-creare-un-nuovo-flusso)
4. [Aggiungere e Configurare Missioni](#4-aggiungere-e-configurare-missioni)
5. [Collegare le Missioni (Branching)](#5-collegare-le-missioni-branching)
6. [Comandi Personalizzati](#6-comandi-personalizzati)
7. [CheckPoint (Area2D)](#7-checkpoint-area2d)
8. [Salvare e Caricare Flussi](#8-salvare-e-caricare-flussi)
9. [Usare i Flussi nel Gioco](#9-usare-i-flussi-nel-gioco)
10. [Esempio Completo: Tutorial](#10-esempio-completo-tutorial)
11. [Riferimento Rapido](#11-riferimento-rapido)

---

## 1. Installazione e Attivazione

Il plugin si trova in `addons/mission_editor/`.

**Per attivarlo:**
1. Apri **Project → Project Settings → Plugins**
2. Trova **Mission Flow Editor** nella lista
3. Imposta lo stato su **Enabled**

Il plugin aggiunge automaticamente:
- Il dock **MissionFlowEditor** nel pannello laterale destro
- L'autoload `MissionFlowPlayer` (runtime)
- Il nodo custom `CheckPoint` (Area2D)

---

## 2. Panoramica dell'Interfaccia

```
┌─────────────────────────────────────────────────────────┐
│  [New] [Open] [Save] │ [+ Mission] [- Del]             │  ← Toolbar
├──────────────────────────────┬──────────────────────────┤
│                              │  Mission Inspector       │
│    FLOW GRAPH                │  ┌────────────────────┐  │
│    (GraphEdit)               │  │ ID: mission_001    │  │
│                              │  │ Label: ...         │  │
│    ┌──────┐    ┌──────┐     │  │ Type: CUSTOM       │  │
│    │ MISS1├───►│ MISS2│     │  │ Target: 0          │  │
│    │ START│    │      │     │  │ Color: [■]         │  │
│    └──────┘    └──────┘     │  │ On Success → ...   │  │
│                              │  │ On Fail → ...      │  │
│    [Tab: Flow Graph]         │  │ Time Limit: 0s     │  │
│    [Tab: Mission List]       │  └────────────────────┘  │
│                              │  Commands                │
│                              │  [On Complete] [On Fail]  │
│                              │  [+ Add Cmd] [- Remove]  │
├──────────────────────────────┴──────────────────────────┤
│  Status: Flow: My Flow (3 missions)                    │  ← Status bar
└─────────────────────────────────────────────────────────┘
```

### Tab disponibili

| Tab | Funzione |
|-----|----------|
| **Flow Graph** | Editor visuale con nodi trascinabili e connessioni |
| **Mission List** | Lista testuale di tutte le missioni (click per selezionare) |

---

## 3. Creare un Nuovo Flusso

1. Clicca **[New]** nella toolbar
2. Viene creato un flusso con una missione iniziale "First Mission"
3. Il nodo appare nel graph editor con l'etichetta **▶ START**

> **Suggerimento:** Il flusso è una Resource salvabile come `.tres`. Ogni flusso può contenere quante missioni vuoi.

---

## 4. Aggiungere e Configurare Missioni

### Aggiungere una missione

1. Clicca **[+ Mission]** nella toolbar
2. Un nuovo nodo "New Mission" appare nel graph
3. Trascinalo per posizionarlo dove vuoi

### Selezionare una missione

- **Nel Graph:** clicca sul nodo
- **Nella Mission List:** clicca sull'elemento nella lista

### Inspector (pannello destro)

Una volta selezionata una missione, l'inspector mostra tutti i campi modificabili:

| Campo | Descrizione |
|-------|-------------|
| **ID** | Identificativo univoco (es. `mission_001`). Deve essere unico nel flusso. |
| **Label** | Testo mostrato nell'HUD. Può essere una chiave di traduzione (es. `mission_tutorial_move`). |
| **Type** | Tipo di missione: `ELIMINATE`, `COLLECT`, `REACH`, `ACTIVATE`, `SURVIVE`, `CUSTOM` |
| **Target** | Numero obiettivo (es. 5 nemici, 3 item). `0` per missioni booleane. |
| **Color** | Colore accent nel pannello HUD. |
| **Progress Bar** | Se attivo, mostra una barra di progresso invece del counter numerico. |
| **Time Limit** | Tempo massimo in secondi. `0` = nessun limite. Se scade → fallimento. |
| **On Success →** | Missione successiva in caso di completamento. |
| **On Fail →** | Missione successiva in caso di fallimento (branching). |
| **Description** | Testo esteso (tooltip o note interne). |
| **Tags** | Etichette separate da virgola per categorizzare. |
| **Fail Cond** | Condizione di fallimento personalizzata (testo libero). |

### Tipi di Missione

| Tipo | Uso | Target |
|------|-----|--------|
| **ELIMINATE** | Elimina N nemici/oggetti | Numero di nemici |
| **COLLECT** | Raccogli N item | Numero di item |
| **REACH** | Raggiungi un checkpoint | 0 (completato dal CheckPoint) |
| **ACTIVATE** | Attiva un oggetto | 0 (completato dal CheckPoint) |
| **SURVIVE** | Sopravvivi N secondi | Secondi |
| **CUSTOM** | Logica personalizzata | Gestito dal tuo codice |

### Eliminare una missione

1. Seleziona il nodo nel graph
2. Clicca **[- Del]** nella toolbar
3. Il nodo e tutte le sue connessioni vengono rimossi

---

## 5. Collegare le Missioni (Branching)

### Metodo 1: Drag nel Graph

1. **Trascina** dal lato destro (output verde) di un nodo al lato sinistro (input grigio) di un altro
2. La connessione verde = percorso di **successo**
3. Se il nodo ha già un fail branch, apparirà una seconda porta rossa per il **fallimento**

### Metodo 2: Inspector

1. Seleziona la missione
2. Nel campo **On Success →**, scegli la missione successiva dal dropdown
3. Nel campo **On Fail →**, scegli la missione alternativa (branching di fallimento)

### Esempio di Branching

```
  ┌─────────────┐     successo     ┌──────────────┐
  │ ELIMINA 5   ├────────────────►│ RACCOGLI 3   │
  │ nemici      │                  │ powerup      │
  │ (2 min)     │     fallimento   │              │
  │             ├────────────────►│ RETRY        │
  └─────────────┘                  └──────┬───────┘
                                          │ successo
                                          ▼
                                   ┌──────────────┐
                                   │ ELIMINA 5    │
                                   │ (ritenta)    │
                                   └──────────────┘
```

In questo esempio:
- Se il giocatore elimina i nemici entro 2 minuti → avanza
- Se fallisce (tempo scaduto o `MissionManager.fail()`) → va al retry
- Dal retry può ritentare la missione originale

---

## 6. Comandi Personalizzati

I comandi si eseguono automaticamente al completamento o fallimento di una missione.

### Aggiungere un comando

1. Seleziona la missione nel graph
2. Nella sezione **Commands**, scegli **On Complete** o **On Fail**
3. Clicca **[+ Add Cmd]**
4. Configura il comando nell'inspector comandi:

| Campo | Descrizione |
|-------|-------------|
| **Type** | Tipo di comando (vedi tabella sotto) |
| **Params** | Parametri in formato JSON |
| **Delay** | Ritardo in secondi prima dell'esecuzione |
| **Active** | Se disattivato, il comando viene saltato |
| **Desc** | Nome descrittivo per l'editor |

### Tipi di Comando

#### PLAY_SOUND — Riproduci un suono
```json
{ "path": "res://Assets/Audio/Music/Drinking.mp3", "volume_db": -6.0 }
```

#### CHANGE_SCENE — Cambia scena
```json
{ "scene_path": "res://Maps/dev_map.tscn" }
```

#### SPAWN_ENEMIES — Genera nemici
```json
{ "scene_path": "res://bot_simple.tscn", "count": 3, "position": "checkpoint", "checkpoint_id": "spawn_point" }
```

#### PLAY_ANIMATION — Riproduci animazione
```json
{ "node_path": "/root/MyScene/AnimPlayer", "anim_name": "victory" }
```

#### SET_VARIABLE — Imposta variabile globale
```json
{ "autoload": "GlobalSettings", "property": "difficulty", "value": 2 }
```

#### CALL_METHOD — Chiama metodo su un nodo
```json
{ "node_path": "/root/MyScene/Spawner", "method": "spawn_wave", "args": [3] }
```

#### SHOW_DIALOG — Mostra messaggio
```json
{ "text": "Missione completata! Avanti al prossimo obiettivo.", "duration": 3.0 }
```

#### ENABLE_CHECKPOINT / DISABLE_CHECKPOINT — Attiva/disattiva checkpoint
```json
{ "checkpoint_id": "secret_room" }
```

#### DELAY — Pausa tra comandi
```json
{ "seconds": 1.5 }
```

### Esempio: Suono + Cambio Scena al completamento

```
On Complete:
  1. PLAY_SOUND  { "path": "res://Assets/Audio/victory.mp3" }  delay: 0s
  2. SHOW_DIALOG { "text": "Area completata!", "duration": 2.0 } delay: 0.5s
  3. CHANGE_SCENE { "scene_path": "res://Maps/level2.tscn" }    delay: 2.5s
```

---

## 7. CheckPoint (Area2D)

I CheckPoint sono nodi Area2D posizionabili nelle scene che interagiscono con il sistema di missioni.

### Aggiungere un CheckPoint

1. Nella scena, clicca **Add Child Node** (Ctrl+A)
2. Cerca **CheckPoint** (sotto Area2D)
3. Posizionalo nella scena

### Proprietà del CheckPoint

| Proprietà | Descrizione |
|-----------|-------------|
| **Checkpoint ID** | ID univoco (es. `exit_door`, `boss_room`). Referenziato nei comandi. |
| **One Shot** | Se attivo, si disattiva dopo il primo trigger. |
| **Radius** | Raggio dell'area di rilevamento (pixel). |
| **Color** | Colore del cerchio visivo (editor e runtime). |
| **Auto Complete Reach** | Completa automaticamente missioni `REACH`/`ACTIVATE` con ID corrispondente. |
| **Display Label** | Testo mostrato sopra il checkpoint (opzionale). |
| **Is Active** | Se disattivato, il checkpoint non risponde al player. |

### Come funziona

1. Quando il player (gruppo `"players"`) entra nell'area:
2. Il checkpoint notifica `MissionFlowPlayer.checkpoint_reached`
3. Se la missione attiva è `REACH` o `ACTIVATE` e l'ID corrisponde → `MissionManager.complete()`
4. Se `one_shot` è attivo → il checkpoint si disattiva

### Usare i CheckPoint nei Flussi

- Crea una missione `REACH` con `mission_id` che contiene il checkpoint_id
- Oppure usa i comandi `ENABLE_CHECKPOINT` / `DISABLE_CHECKPOINT` per controllarli

---

## 8. Salvare e Caricare Flussi

### Salvare

1. Clicca **[Save]** nella toolbar
2. Se è il primo salvataggio, si apre il FileDialog
3. Scegli un percorso (es. `res://Flows/chapter1.tres`)
4. Il flusso viene salvato come risorsa Godot

### Caricare

1. Clicca **[Open]** nella toolbar
2. Seleziona il file `.tres` dal FileDialog
3. Il flusso viene caricato nel editor

> **Nota:** I flussi `.tres` sono risorse standard Godot — puoi anche caricarli dall'Inspector di qualsiasi nodo.

---

## 9. Usare i Flussi nel Gioco

### Via codice

```gdscript
# Carica e avvia un flusso
var flow: Resource = load("res://Flows/chapter1.tres")
MissionFlowPlayer.start_flow(flow)

# Ferma il flusso corrente
MissionFlowPlayer.stop_flow()

# Salta a una missione specifica
MissionFlowPlayer.jump_to_mission("mission_003")

# Forza l'avanzamento
MissionFlowPlayer.force_advance()
```

### Segnali disponibili

```gdscript
MissionFlowPlayer.flow_started.connect(func(flow): print("Flusso iniziato"))
MissionFlowPlayer.flow_ended.connect(func(flow): print("Flusso terminato"))
MissionFlowPlayer.mission_branch_taken.connect(func(id, next_id, is_fail):
    if is_fail:
        print("Branch fallimento: %s → %s" % [id, next_id])
)
MissionFlowPlayer.command_executed.connect(func(cmd): print("Comando eseguito"))
MissionFlowPlayer.checkpoint_reached.connect(func(cp_id): print("Checkpoint: %s" % cp_id))
```

### Proprietà runtime

```gdscript
MissionFlowPlayer.is_playing        # bool — flusso in corso?
MissionFlowPlayer.current_flow      # Resource — flusso attivo
MissionFlowPlayer.current_mission_id # String — ID missione corrente
```

---

## 10. Esempio Completo: Tutorial

Un flusso tutorial che guida il giocatore attraverso i controlli:

```
[MOVE] ──► [AIM] ──► [FIRE] ──► [ELIMINATE] ──► [COLLECT] ──► [DESTROY] ──► [DONE]
                                    │
                                    │ fail
                                    ▼
                               [RETRY]──► [ELIMINATE]
```

### Creazione via codice

```gdscript
# Nel tuo script (es. dev_map_tutorial.gd):
func _ready():
    var ExampleFlow = preload("res://addons/mission_editor/examples/example_tutorial_flow.gd")
    var flow = ExampleFlow.create_flow()
    MissionFlowPlayer.start_flow(flow)
```

### Creazione dall'Editor

1. Clicca **[New]**
2. Aggiungi 7 missioni con **[+ Mission]**
3. Configura ogni missione nell'inspector:
   - MOVE → type: CUSTOM, target: 0, on_success: aim
   - AIM → type: CUSTOM, target: 0, on_success: fire
   - FIRE → type: CUSTOM, target: 0, on_success: eliminate
   - ELIMINATE → type: ELIMINATE, target: 5, time_limit: 120, on_success: collect, on_fail: retry
   - RETRY → type: CUSTOM, target: 0, on_success: eliminate
   - COLLECT → type: COLLECT, target: 3, on_success: destroy
   - DESTROY → type: ELIMINATE, target: 4, on_success: done
4. Collega i nodi trascinando nel graph
5. Salva come `res://Flows/tutorial.tres`

---

## 11. Riferimento Rapido

### Toolbar

| Pulsante | Azione |
|----------|--------|
| **New** | Crea nuovo flusso vuoto con 1 missione |
| **Open** | Apri flusso `.tres` esistente |
| **Save** | Salva flusso corrente |
| **+ Mission** | Aggiungi nodo missione |
| **- Del** | Elimina missione selezionata |

### Colori nel Graph

| Colore | Significato |
|--------|-------------|
| Verde (connessione) | Percorso di successo |
| Rosso (connessione) | Percorso di fallimento |
| Grigio (input) | Porta di input del nodo |
| ▶ START (verde) | Missione iniziale del flusso |
| ⏱ (rosso) | Missione con time_limit |

### Integrazione con MissionManager

Il plugin si integra con il sistema esistente:
- `MissionManager.start()` — avvia la missione
- `MissionManager.complete()` — completa (trigger branching successo)
- `MissionManager.fail()` — fallisce (trigger branching fallimento)
- `MissionManager.set_progress()` — aggiorna progresso
- Il `MissionPanel` HUD continua a funzionare normalmente

### File del Plugin

```
addons/mission_editor/
├── plugin.cfg              # Registrazione plugin
├── plugin.gd               # Entry point
├── mission_flow.gd         # Resource: contenitore flusso
├── mission_command.gd      # Resource: comando
├── mission_flow_player.gd  # Autoload runtime
├── checkpoint.gd           # Script CheckPoint
├── checkpoint.tscn         # Scena CheckPoint
├── editor/
│   └── editor_main.gd      # Dock editor visuale
└── examples/
    └── example_tutorial_flow.gd
```
