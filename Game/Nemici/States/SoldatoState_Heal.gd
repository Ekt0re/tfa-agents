## SoldatoState_Heal.gd
## Stato HEAL — Solo classe Medico (classe == 1).
## Il Medico cerca l'alleato più vicino con vita < heal_threshold,
## si avvicina e lo cura a intervalli di HEAL_INTERVAL secondi.
##
## Transizioni:
##   → Chase:    se avvista un nemico (priorità combattimento)
##   → Idle:     se non ci sono più alleati da curare

extends LimboState

var _bot: SoldatoBot
var _heal_target: Node2D = null
var _heal_timer: float = 0.0
var _nav_update_counter: int = 0

const HEAL_INTERVAL: float = 1.0  # Cura ogni N secondi
const HEAL_ARRIVAL_DISTANCE: float = 0.8  # Fraction of heal_range

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_heal_timer = 0.0
	_nav_update_counter = 0
	_heal_target = _bot.find_wounded_ally()
	if _heal_target == null:
		dispatch(&"heal_done")

func _update(delta: float) -> void:
	# Priorità assoluta: nemico visibile → smette di curare
	if _bot.get_current_target() != null:
		dispatch(&"enemy_spotted")
		return

	# Verifica che il target di cura sia ancora valido
	if _heal_target == null or not is_instance_valid(_heal_target):
		_heal_target = _bot.find_wounded_ally()
		if _heal_target == null:
			dispatch(&"heal_done")
			return

	# Naviga verso l'alleato se troppo lontano
	var dist: float = _bot.global_position.distance_to(_heal_target.global_position)
	var arrival_range: float = _bot.heal_range * HEAL_ARRIVAL_DISTANCE

	if dist > arrival_range:
		# Aggiorna navigazione ogni N frame
		_nav_update_counter += 1
		if _nav_update_counter >= _bot.nav_update_every_frames:
			_nav_update_counter = 0
			_bot.navigate_to(_heal_target.global_position)
		return
	else:
		# Arrivato: fermati e cura
		_bot.navigate_to(_bot.global_position)

	# Orienta verso l'alleato
	var look_dir: Vector2 = _bot.global_position.direction_to(_heal_target.global_position)
	if look_dir.length() > 0.05:
		_bot.global_rotation = lerp_angle(_bot.global_rotation, look_dir.angle(), 8.0 * delta)

	# Tick di cura a intervalli
	_heal_timer += delta
	if _heal_timer >= HEAL_INTERVAL:
		_heal_timer = 0.0
		_do_heal()

func _exit() -> void:
	_heal_target = null
	_heal_timer = 0.0
	_nav_update_counter = 0

func _do_heal() -> void:
	if _heal_target == null or not is_instance_valid(_heal_target):
		return

	# Applica cura
	if _heal_target.has_method("heal"):
		_heal_target.heal(_bot.heal_amount)

	# Controlla se l'alleato è ora guarito — cerca il prossimo
	if "vita" in _heal_target and "vita_max" in _heal_target:
		var ratio: float = float(_heal_target.get("vita")) / float(_heal_target.get("vita_max"))
		if ratio >= _bot.heal_threshold:
			_heal_target = _bot.find_wounded_ally()
			if _heal_target == null:
				dispatch(&"heal_done")
