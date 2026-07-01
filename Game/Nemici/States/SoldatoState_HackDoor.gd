## SoldatoState_HackDoor.gd
## Stato HACK_DOOR: il bot attende che una porta MANUAL si apra.
##
## La porta avvia l'hack in automatico quando il bot entra nell'area
## di attivazione (_try_open_door). Questo stato gestisce solo:
##   - L'attesa del segnale door_opened
##   - L'interruzione prioritaria se compare un nemico o arriva un allarme
##
## Transizioni:
##   → enemy_spotted: il bot vede un nemico (priorità massima)
##   → go_investigate: allarme ricevuto mentre aspetta
##   → door_hacked:    la porta si è aperta (via segnale door_opened)

extends LimboState

var _bot: SoldatoBot
var _door: Door = null
var _destination_before_door: Vector2 = Vector2.ZERO
var _wait_timer: float = 0.0
const MAX_WAIT_TIME: float = 8.0  ## Abbandona se la porta non si apre entro N secondi

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_door = _bot.ai_blackboard.get("door_to_hack", null)
	_destination_before_door = _bot.ai_blackboard.get("last_known_pos", _bot.global_position)
	_wait_timer = 0.0

	if not _door or not is_instance_valid(_door):
		dispatch(&"door_hacked")
		return

	# Rimane in prossimità della porta (la porta gestisce l'hack da sola)
	_bot.navigate_to(_door.global_position)

	# Connetti door_opened (CONNECT_ONE_SHOT: auto-disconnect dopo il trigger)
	if not _door.door_opened.is_connected(_on_door_opened):
		_door.door_opened.connect(_on_door_opened, CONNECT_ONE_SHOT)

func _update(delta: float) -> void:
	# Priorità assoluta: nemico avvistato → interrompe l'attesa
	if _bot.get_current_target() != null:
		_disconnect_door()
		dispatch(&"enemy_spotted")
		return

	# Allarme ricevuto → investigare
	if _bot.ai_blackboard.get("has_alert", false):
		_disconnect_door()
		dispatch(&"go_investigate")
		return

	# Porta non più valida o già aperta
	if not _door or not is_instance_valid(_door) or _door.is_door_open():
		dispatch(&"door_hacked")
		return

	# Timeout: la porta non si è aperta in tempo
	_wait_timer += delta
	if _wait_timer >= MAX_WAIT_TIME:
		_disconnect_door()
		dispatch(&"door_hacked")

func _exit() -> void:
	_disconnect_door()
	_bot.ai_blackboard["door_to_hack"] = null

func _disconnect_door() -> void:
	if _door and is_instance_valid(_door) and _door.door_opened.is_connected(_on_door_opened):
		_door.door_opened.disconnect(_on_door_opened)

func _on_door_opened() -> void:
	## La porta si è aperta: riprende la navigazione verso la destinazione originale.
	_bot.navigate_to(_destination_before_door)
	dispatch(&"door_hacked")
