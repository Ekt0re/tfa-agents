## SoldatoState_Chase.gd
## Stato CHASE: il bot insegue attivamente il nemico via NavigationAgent2D.
## Mantiene l'inseguimento per `chase_time` secondi dopo aver perso il LoS.
## Il Cecchino NON si avvicina al nemico (rimane fermo ad aspettare il range).
##
## Transizioni:
##   → Attack:      se il nemico entra nel range d'attacco
##   → Investigate: se perde il contatto per chase_time secondi

extends LimboState

var _bot: SoldatoBot
var _los_lost_timer: float = 0.0
var _has_los: bool = true
var _nav_update_counter: int = 0

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_los_lost_timer = 0.0
	_has_los = true
	_nav_update_counter = 0

func _update(delta: float) -> void:
	var target: Node2D = _bot.get_current_target()

	# Target non valido → investigare l'ultima posizione nota
	if target == null or not is_instance_valid(target):
		_bot.clear_target()
		dispatch(&"target_lost")
		return

	# Aggiorna posizione target nella blackboard
	_bot.ai_blackboard["last_known_pos"] = target.global_position

	# Orienta il bot verso il target
	var dir: Vector2 = _bot.global_position.direction_to(target.global_position)
	_bot.global_rotation = lerp_angle(_bot.global_rotation, dir.angle(), 12.0 * delta)

	# Cecchino: rimane fermo, aspetta il range
	if _bot.classe == 2:
		_bot.navigate_to(_bot.global_position)
	else:
		# Aggiorna percorso ogni N frame (ottimizzazione)
		_nav_update_counter += 1
		if _nav_update_counter >= _bot.nav_update_every_frames:
			_nav_update_counter = 0
			_bot.navigate_to(target.global_position)

	# Controlla LoS
	if _bot.is_in_fov(target):
		_has_los = true
		_los_lost_timer = 0.0
	else:
		_has_los = false
		_los_lost_timer += delta
		if _los_lost_timer >= _bot.chase_time:
			_bot.clear_target()
			dispatch(&"target_lost")
			return

	# Controlla range d'attacco
	var dist: float = _bot.global_position.distance_to(target.global_position)
	if dist <= _bot.attack_range:
		dispatch(&"in_attack_range")

func _exit() -> void:
	_los_lost_timer = 0.0
	_nav_update_counter = 0
