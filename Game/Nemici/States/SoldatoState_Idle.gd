## SoldatoState_Idle.gd
## Stato IDLE: il bot è fermo e sorveglia ruotando lentamente.
## Transizioni:
##   → Patrol:      se patrol_path è assegnato
##   → Chase:       se un nemico entra nel FOV
##   → Investigate: se riceve un segnale d'allarme
##   → Heal:        se è un Medico e trova un alleato ferito

extends LimboState

var _bot: SoldatoBot
var _idle_time: float = 0.0
var _rotation_dir: float = 1.0
const IDLE_ROT_SPEED: float = 0.6  # rad/s — velocità rotazione sorveglianza

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_idle_time = 0.0
	# Direzione di rotazione casuale per varietà visiva
	_rotation_dir = 1.0 if randf() > 0.5 else -1.0
	# Ferma il bot impostando la destinazione sulla posizione attuale
	_bot.navigate_to(_bot.global_position)

func _update(delta: float) -> void:
	_idle_time += delta

	# Rotazione "sorveglianza" sinusoidale — simula guardia che guarda intorno
	_bot.global_rotation += sin(_idle_time * 0.8) * IDLE_ROT_SPEED * _rotation_dir * delta

	# Controlla transizioni in uscita
	if _bot.get_current_target() != null:
		dispatch(&"enemy_spotted")
		return

	if _bot.ai_blackboard.get("has_alert", false):
		dispatch(&"go_investigate")
		return

	if _bot.patrol_path != null:
		dispatch(&"go_patrol")
		return

	# Solo Medico: controlla alleati feriti
	if _bot.classe == 1 and _bot.find_wounded_ally() != null:
		dispatch(&"go_heal")
		return

func _exit() -> void:
	_idle_time = 0.0
