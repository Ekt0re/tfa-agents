## SoldatoState_Patrol.gd
## Stato PATROL: il bot segue i waypoint di una Path2D (se assegnata),
## altrimenti esegue un wander casuale intorno alla posizione di spawn.
##
## Transizioni:
##   → Chase:       se un nemico entra nel FOV
##   → Investigate: se riceve un segnale d'allarme
##   → Heal:        se è un Medico e trova un alleato ferito

extends LimboState

var _bot: SoldatoBot

var _patrol_points: PackedVector2Array = PackedVector2Array()
var _current_index: int = 0
var _wait_timer: float = 0.0
var _is_waiting: bool = false
var _wander_generated: bool = false

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	_wait_timer = 0.0
	_is_waiting = false
	_wander_generated = false
	_build_patrol_points()
	_go_to_current_point()

func _update(delta: float) -> void:
	# Priorità: nemico > allarme > medico > pattuglia
	if _bot.get_current_target() != null:
		dispatch(&"enemy_spotted")
		return

	if _bot.ai_blackboard.get("has_alert", false):
		dispatch(&"go_investigate")
		return

	if _bot.classe == 1 and _bot.find_wounded_ally() != null:
		dispatch(&"go_heal")
		return

	if _is_waiting:
		_wait_timer += delta
		if _wait_timer >= _bot.patrol_wait_time:
			_is_waiting = false
			_advance_patrol_index()
			_go_to_current_point()
		return

	# Raggiunto il waypoint corrente
	if _bot.is_at_destination():
		_is_waiting = true
		_wait_timer = 0.0

func _exit() -> void:
	_is_waiting = false
	_wait_timer = 0.0

# ─── Costruzione waypoint ──────────────────────────────────────────────────

func _build_patrol_points() -> void:
	_patrol_points.clear()
	_current_index = 0

	if _bot.patrol_path != null:
		_build_from_path2d()
	else:
		_generate_random_wander()

func _build_from_path2d() -> void:
	var curve: Curve2D = _bot.patrol_path.curve
	if not curve or curve.point_count == 0:
		_generate_random_wander()
		return
	for i in range(curve.point_count):
		_patrol_points.append(_bot.patrol_path.to_global(curve.get_point_position(i)))

## Genera punti di wander casuali attorno allo spawn. Ogni bot usa un seed diverso
## per evitare che tutti vadano nella stessa direzione.
func _generate_random_wander() -> void:
	if _wander_generated:
		return
	_wander_generated = true
	_patrol_points.clear()

	var rng := RandomNumberGenerator.new()
	# Seed basato sull'ID istanza → ogni bot ha un pattern unico
	rng.seed = hash(_bot.get_instance_id())

	var count: int = rng.randi_range(4, 8)
	for i in range(count):
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float  = rng.randf_range(60.0, _bot.wander_radius)
		_patrol_points.append(_bot.spawn_position + Vector2.RIGHT.rotated(angle) * dist)

func _advance_patrol_index() -> void:
	_current_index = (_current_index + 1) % max(_patrol_points.size(), 1)
	# Se il wander è finito, rigenera nuovi punti casuali
	if _bot.patrol_path == null and _current_index == 0:
		_wander_generated = false
		_generate_random_wander()

func _go_to_current_point() -> void:
	if _patrol_points.is_empty():
		return
	var dest: Vector2 = _patrol_points[_current_index]
	_bot.navigate_to(dest)
