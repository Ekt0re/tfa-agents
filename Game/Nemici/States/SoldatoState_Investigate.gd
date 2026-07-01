## SoldatoState_Investigate.gd
## Stato INVESTIGATE: il bot si sposta verso l'ultima posizione nota del nemico
## (o verso la posizione d'allarme ricevuta), poi guarda intorno.
## Uscirà dallo stato dopo `investigate_time` secondi.
##
## Innescato da:
##   - Perdita del nemico durante Chase/Attack
##   - Segnale d'allarme da altri bot (receive_alert)
##   - Esplosione di mina vicina (_on_explosion_nearby)
##
## Transizioni:
##   → Chase:       se avvista un nemico durante l'indagine
##   → Patrol:      se ha un patrol_path al termine dell'indagine
##   → Idle:        se non ha patrol_path al termine dell'indagine

extends LimboState

var _bot: SoldatoBot
var _investigate_timer: float = 0.0
var _arrived_at_target: bool = false
var _look_around_timer: float = 0.0
var _target_position: Vector2 = Vector2.ZERO
var _look_dir: float = 1.0

const LOOK_AROUND_SPEED: float = 1.8  # rad/s — velocità rotazione investigazione

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_investigate_timer = 0.0
	_arrived_at_target = false
	_look_around_timer = 0.0
	_look_dir = 1.0 if randf() > 0.5 else -1.0

	# Priorità posizione: allarme > ultima posizione nota > spawn
	if _bot.ai_blackboard.get("has_alert", false):
		_target_position = _bot.ai_blackboard.get("alert_position", _bot.ai_blackboard.get("last_known_pos", _bot.global_position))
		_bot.ai_blackboard["has_alert"] = false
	else:
		_target_position = _bot.ai_blackboard.get("last_known_pos", _bot.global_position)

	_bot.navigate_to(_target_position)

func _update(delta: float) -> void:
	# Se vede un nemico → passa subito all'inseguimento
	if _bot.get_current_target() != null:
		dispatch(&"enemy_spotted")
		return

	_investigate_timer += delta

	if not _arrived_at_target:
		if _bot.is_at_destination():
			_arrived_at_target = true
			# Inizia a guardarsi intorno
	else:
		# Rotazione "investigazione" rapida
		_look_around_timer += delta
		_bot.global_rotation += sin(_look_around_timer * 2.0) * LOOK_AROUND_SPEED * _look_dir * delta

	# Controlla se arriva un nuovo allarme durante l'investigazione
	if _bot.ai_blackboard.get("has_alert", false):
		# Aggiorna la posizione da investigare
		_target_position = _bot.ai_blackboard.get("alert_position", _target_position)
		_bot.ai_blackboard["has_alert"] = false
		_bot.navigate_to(_target_position)
		_arrived_at_target = false
		# NON resettare il timer — l'investigazione continua ma verso il nuovo punto

	# Timer investigazione scaduto → torna alla normalità
	if _investigate_timer >= _bot.investigate_time:
		_end_investigation()

func _exit() -> void:
	_investigate_timer = 0.0
	_arrived_at_target = false
	_bot.ai_blackboard["has_alert"] = false

func _end_investigation() -> void:
	if _bot.patrol_path != null:
		dispatch(&"go_patrol")
	else:
		dispatch(&"investigation_done")
