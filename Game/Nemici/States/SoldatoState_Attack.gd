## SoldatoState_Attack.gd
## Stato ATTACK: il bot ha il nemico nel range e spara.
## Il comportamento di movimento dipende dalla classe:
##   Soldato/MiniBoss: si avvicina leggermente mentre spara
##   Cecchino:         rimane FERMO, usa shot_range molto lungo
##   Pesante:          avanza sempre verso il nemico
##   Ninja:            si avvicina rapidamente per il corpo a corpo
##   Medico/Granatiere/Altro: mantiene distanza media
##
## Transizioni:
##   → Chase:       se il nemico esce dal range (isteresi 1.2x)
##   → Investigate: se perde il LoS per chase_time secondi

extends LimboState

var _bot: SoldatoBot
var _los_lost_timer: float = 0.0
var _nav_update_counter: int = 0

## Isteresi: torna in Chase solo se la distanza supera il 120% del range d'attacco.
const RANGE_HYSTERESIS: float = 1.2

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_los_lost_timer = 0.0
	_nav_update_counter = 0

func _update(delta: float) -> void:
	var target: Node2D = _bot.get_current_target()

	if target == null or not is_instance_valid(target):
		_bot.clear_target()
		dispatch(&"target_lost")
		return

	# Orienta il bot verso il target
	var dir: Vector2 = _bot.global_position.direction_to(target.global_position)
	_bot.global_rotation = lerp_angle(_bot.global_rotation, dir.angle(), 16.0 * delta)

	var dist: float = _bot.global_position.distance_to(target.global_position)

	# Controlla LoS e spara
	if _bot.has_line_of_sight(target):
		_los_lost_timer = 0.0
		_bot.try_shoot(target)
		_update_movement_for_class(target, dist, delta)
	else:
		# Nessun LoS: conta il tempo e poi torna ad investigare
		_los_lost_timer += delta
		if _los_lost_timer >= _bot.chase_time:
			_bot.clear_target()
			dispatch(&"target_lost")
			return
		# Anche senza LoS, il Pesante continua ad avanzare
		if _bot.classe == 3:
			_update_nav_throttled(target)

	# Il nemico è uscito dal range d'attacco → torna a inseguire
	if dist > _bot.attack_range * RANGE_HYSTERESIS:
		dispatch(&"out_of_range")

func _exit() -> void:
	_los_lost_timer = 0.0
	_nav_update_counter = 0

# ─── Movimenti per classe ──────────────────────────────────────────────────

func _update_movement_for_class(target: Node2D, dist: float, _delta: float) -> void:
	match _bot.classe:
		0, 6:  # Soldato, MiniBoss — si avvicina alla metà del range
			if dist > _bot.attack_range * 0.55:
				_update_nav_throttled(target)
			else:
				_bot.navigate_to(_bot.global_position)  # Fermo
		1:  # Medico — mantiene distanza media
			if dist > _bot.attack_range * 0.70:
				_update_nav_throttled(target)
			elif dist < _bot.attack_range * 0.40:
				# Troppo vicino: arretra
				var away: Vector2 = _bot.global_position + (_bot.global_position - target.global_position).normalized() * 60.0
				_bot.navigate_to(away)
			else:
				_bot.navigate_to(_bot.global_position)
		2:  # Cecchino — assolutamente fermo
			_bot.navigate_to(_bot.global_position)
		3:  # Pesante — avanza sempre
			_update_nav_throttled(target)
		4:  # Ninja — si avvicina al massimo per corpo a corpo
			_update_nav_throttled(target)
		5, 7:  # Granatiere, Altro — normale
			if dist > _bot.attack_range * 0.60:
				_update_nav_throttled(target)
			else:
				_bot.navigate_to(_bot.global_position)

func _update_nav_throttled(target: Node2D) -> void:
	_nav_update_counter += 1
	if _nav_update_counter >= _bot.nav_update_every_frames:
		_nav_update_counter = 0
		_bot.navigate_to(target.global_position)
