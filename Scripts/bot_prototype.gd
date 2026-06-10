extends CharacterBody2D
class_name BotPrototype

## Segnale emesso quando il livello di altezza del bot cambia.
signal height_level_changed(new_level: int)

@export var speed: float = 370.0

## Il livello di altezza iniziale (0 = Terra, 1 = Elevato)
@export var current_height_level: int = 0

## Riferimento opzionale al NavigationAgent2D (se usato per il pathfinding dei bot o click-to-move)
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null


func _ready() -> void:
	call_deferred("change_height_level", current_height_level, true)


## Funzione per cambiare dinamicamente il livello di altezza.
## Se force_update è true, forza l'aggiornamento anche se il livello è lo stesso (es. all'avvio).
func change_height_level(new_level: int, force_update: bool = false) -> void:
	if new_level == current_height_level and not force_update:
		return

	var previous_level := current_height_level
	if not force_update:
		remove_from_group("entities_level_" + str(previous_level))

	current_height_level = new_level
	add_to_group("entities_level_" + str(current_height_level))

	# Configurazione dei layer fisici:
	# Layer 1: players_l0 (Valore 1)
	# Layer 2: players_l1 (Valore 2)
	# Layer 3: world_l0 (Valore 4)
	# Layer 4: world_l1 (Valore 8)
	# Layer 7: ramps (Valore 64)

	if current_height_level == 0:
		# Giocatore a Terra (L0)
		collision_layer = 1          # appartiene al Layer 1 (players_l0)
		collision_mask = 1 + 4 + 64  # collide con: players_l0, world_l0, ramps
		z_index = 1                  # Disegnato sopra il terreno e le decorazioni di base (z_index 1)

		# Aggiorna il pathfinding per navigare solo sul Livello 0
		if navigation_agent:
			navigation_agent.navigation_layers = 1 # Usa il Navigation Layer 1 (bit 1)

	else:
		# Bot Elevato (L1)
		collision_layer = 2          # appartiene al Layer 2 (players_l1)
		collision_mask = 2 + 8 + 64  # collide con: players_l1, world_l1, ramps
		z_index = 3                  # Disegnato sopra il terreno e le decorazioni del Livello 1 (z_index 3)

		# Aggiorna il pathfinding per navigare solo sul Livello 1
		if navigation_agent:
			navigation_agent.navigation_layers = 2 # Usa il Navigation Layer 2 (bit 2)

	# Emette il segnale per gli script della mappa o dell'interfaccia
	height_level_changed.emit(current_height_level)
