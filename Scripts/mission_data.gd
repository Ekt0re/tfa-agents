## mission_data.gd
## Resource dichiarativa che descrive una singola missione/obiettivo.
## Istanzia questa classe per definire ogni missione nel gioco.
class_name MissionData
extends Resource

## Tipi di missione supportati
enum Type {
	ELIMINATE,   ## Elimina tot nemici
	COLLECT,     ## Raccogli tot item di un tipo
	REACH,       ## Raggiungi una posizione/marker
	ACTIVATE,    ## Attiva un oggetto interattivo (portale, leva, ecc.)
	SURVIVE,     ## Sopravvivi per X secondi
	CUSTOM,      ## Testo libero, progresso gestito esternamente
}

## Tipo missione
@export var type: Type = Type.ELIMINATE

## Testo label breve mostrato nell'HUD (es. "NEUTRALIZZA", "RACCOGLI", "RAGGIUNGI")
@export var label: String = ""

## Descrizione estesa (opzionale, per tooltip o popup)
@export var description: String = ""

## Valore target (quanti nemici, quanti item, quanti secondi, ecc.)
## Per REACH/ACTIVATE ignorato (0 = completamento booleano)
@export var target: int = 0

## ID univoco stringa per identificare la missione nel codice
@export var mission_id: String = ""

## Colore accent della missione nel pannello HUD
@export var accent_color: Color = Color(0.988235, 0.380392, 0.156863, 1)

## Mostra una progress bar al posto del counter numerico
@export var show_progress_bar: bool = false

# ---------------------------------------------------------------------------
# Flow System — branching e comandi (usato dal Mission Flow Editor)
# ---------------------------------------------------------------------------

## ID della missione successiva da avviare in caso di successo (vuoto = nessuna)
@export var on_success_next: String = ""

## ID della missione successiva da avviare in caso di fallimento (vuoto = nessuna)
@export var on_fail_next: String = ""

## Comandi da eseguire al completamento (successo)
@export var on_complete_commands: Array[Resource] = []

## Comandi da eseguire al fallimento
@export var on_fail_commands: Array[Resource] = []

## Condizioni di fallimento opzionali (es. timer, vita player)
@export var fail_condition: String = ""

## Tempo limite in secondi per completare la missione (0 = nessun limite)
@export var time_limit: float = 0.0

## Posizione del nodo nel graph editor (salvata nel flusso)
@export var graph_position: Vector2 = Vector2.ZERO

## Gruppo / tag per categorizzare la missione (usato nel flow editor)
@export var tags: PackedStringArray = PackedStringArray()
