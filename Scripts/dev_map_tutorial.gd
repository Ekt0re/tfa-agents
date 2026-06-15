## dev_map_tutorial.gd
## Script tutorial sequenziale per dev_map.tscn.
## Gestisce 6 missioni concatenate che introducono i controlli di gioco.
##
## Missione 1: Muovi con WASD
## Missione 2: Mira con il mouse
## Missione 3: Spara con il tasto sinistro
## Missione 4: Elimina tutti i nemici (gruppo "bots")
## Missione 5: Raccogli tutti gli item (gruppo "powerup")
## Missione 6: Distruggi tutti i barili (gruppo "Barile")
extends Node

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------
enum TutorialStep { MOVE, AIM, FIRE, ELIMINATE, COLLECT, DESTROY, DONE }

var _current_step: int = TutorialStep.MOVE
var _player: CharacterBody2D = null
var _player_start_pos: Vector2 = Vector2.ZERO
var _mouse_moved := false
var _initial_ammo: int = -1
var _group_initial_count: int = 0
var _poll_timer: float = 0.0
var _completing: bool = false  # Guard contro doppio completamento

# Distanza minima (px) per considerare il movimento valido
const MOVE_THRESHOLD: float = 32.0
# Movimento mouse minimo (px cumulativi) per considerare la mira valida
const MOUSE_THRESHOLD: float = 50.0
var _mouse_accumulator: float = 0.0

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Connetti al segnale di completamento per avanzare allo step successivo
	if not MissionManager.mission_completed.is_connected(_on_mission_completed_advance):
		MissionManager.mission_completed.connect(_on_mission_completed_advance)

	# Attendi un frame per assicurarti che il player sia nella scena
	await get_tree().process_frame
	_find_player()
	# Avvia la prima missione dopo un breve delay per lasciare il tempo all'HUD di inizializzarsi
	await get_tree().create_timer(0.5).timeout
	_start_step(TutorialStep.MOVE)


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_player = players[0] as CharacterBody2D
		_player_start_pos = _player.global_position


func _input(event: InputEvent) -> void:
	# Traccia il movimento del mouse per la missione AIM
	if _current_step == TutorialStep.AIM and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse_accumulator += motion.relative.length()
		if _mouse_accumulator >= MOUSE_THRESHOLD:
			_mouse_moved = true


func _process(delta: float) -> void:
	if _current_step == TutorialStep.DONE:
		return

	match _current_step:
		TutorialStep.MOVE:
			_check_movement()
		TutorialStep.AIM:
			if _mouse_moved:
				_complete_current()
		TutorialStep.FIRE:
			pass  # Gestito dal segnale ammo_changed
		TutorialStep.ELIMINATE, TutorialStep.COLLECT, TutorialStep.DESTROY:
			# Polling periodico per evitare check ogni frame
			_poll_timer += delta
			if _poll_timer >= 0.3:
				_poll_timer = 0.0
				_check_group_clear()


# ---------------------------------------------------------------------------
# Gestione step
# ---------------------------------------------------------------------------
func _start_step(step: int) -> void:
	_current_step = step
	_poll_timer = 0.0
	_completing = false

	match step:
		TutorialStep.MOVE:
			var data: MissionData = MissionManager.make_custom(tr("mission_tutorial_move"), 0, Color(0.0, 0.898039, 1.0, 1.0))
			MissionManager.start(data)

		TutorialStep.AIM:
			_mouse_accumulator = 0.0
			_mouse_moved = false
			var data: MissionData = MissionManager.make_custom(tr("mission_tutorial_aim"), 0, Color(0.0, 0.898039, 1.0, 1.0))
			MissionManager.start(data)

		TutorialStep.FIRE:
			_connect_ammo_signal()
			var data: MissionData = MissionManager.make_custom(tr("mission_tutorial_fire"), 0, Color(0.988235, 0.380392, 0.156863, 1.0))
			MissionManager.start(data)

		TutorialStep.ELIMINATE:
			_group_initial_count = get_tree().get_nodes_in_group("bots").size()
			if _group_initial_count == 0:
				# Nessun nemico, skip
				_complete_current()
				return
			var data: MissionData = MissionManager.make_eliminate(_group_initial_count, tr("mission_tutorial_eliminate"))
			MissionManager.start(data)
			MissionManager.set_progress(0)

		TutorialStep.COLLECT:
			_group_initial_count = get_tree().get_nodes_in_group("powerup").size()
			if _group_initial_count == 0:
				_complete_current()
				return
			var data: MissionData = MissionManager.make_collect(_group_initial_count, "powerup")
			MissionManager.start(data)
			MissionManager.set_progress(0)

		TutorialStep.DESTROY:
			_group_initial_count = get_tree().get_nodes_in_group("Barile").size()
			if _group_initial_count == 0:
				_complete_current()
				return
			var data: MissionData = MissionManager.make_eliminate(_group_initial_count, tr("mission_tutorial_destroy"))
			data.accent_color = Color(1.0, 0.5, 0.0, 1.0)
			MissionManager.start(data)
			MissionManager.set_progress(0)

		TutorialStep.DONE:
			var data: MissionData = MissionManager.make_custom(tr("mission_tutorial_done"), 0, Color(0.3, 1.0, 0.3, 1.0))
			MissionManager.start(data)


func _complete_current() -> void:
	if _completing:
		return
	_completing = true
	MissionManager.complete()


func _advance_to_next_step() -> void:
	var next_step: int = int(_current_step) + 1
	if next_step > TutorialStep.DONE:
		next_step = TutorialStep.DONE
	# Aspetta che il pannello "COMPLETATA" scompaia prima di mostrare la prossima
	await get_tree().create_timer(2.8).timeout
	_start_step(next_step)


# ---------------------------------------------------------------------------
# Check conditions
# ---------------------------------------------------------------------------
func _check_movement() -> void:
	if not _player or not is_instance_valid(_player):
		return
	# WASD premuto oppure il player si è spostato dalla posizione iniziale
	var moved := false
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or \
	   Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D):
		moved = true
	elif _player.global_position.distance_to(_player_start_pos) > MOVE_THRESHOLD:
		moved = true

	if moved:
		_complete_current()


func _check_group_clear() -> void:
	match _current_step:
		TutorialStep.ELIMINATE:
			var remaining := get_tree().get_nodes_in_group("bots").size()
			var eliminated := _group_initial_count - remaining
			MissionManager.set_progress(eliminated)
			if remaining == 0:
				_complete_current()

		TutorialStep.COLLECT:
			var remaining := get_tree().get_nodes_in_group("powerup").size()
			var collected := _group_initial_count - remaining
			MissionManager.set_progress(collected)
			if remaining == 0:
				_complete_current()

		TutorialStep.DESTROY:
			var remaining := get_tree().get_nodes_in_group("Barile").size()
			var destroyed := _group_initial_count - remaining
			MissionManager.set_progress(destroyed)
			if remaining == 0:
				_complete_current()


# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
func _connect_ammo_signal() -> void:
	if not _player or not is_instance_valid(_player):
		_find_player()
	if _player and _player.has_signal("ammo_changed"):
		if not _player.ammo_changed.is_connected(_on_player_ammo_changed):
			_player.ammo_changed.connect(_on_player_ammo_changed)
	_initial_ammo = _player.colpi_correnti if _player and "colpi_correnti" in _player else -1


func _on_player_ammo_changed(current: int, _total: int) -> void:
	if _current_step != TutorialStep.FIRE:
		return
	# Se le munizioni sono diminuite, il player ha sparato
	if _initial_ammo >= 0 and current < _initial_ammo:
		_complete_current()
	elif current >= 0 and _initial_ammo < 0:
		# Fallback: qualsiasi cambio di ammo dopo la connessione
		_complete_current()


# ---------------------------------------------------------------------------
# Connessione al segnale mission_completed per avanzare automaticamente
# ---------------------------------------------------------------------------
func _on_mission_completed_advance(_data: MissionData) -> void:
	if _current_step == TutorialStep.DONE:
		return  # Tutorial finito, non avanzare oltre
	_advance_to_next_step()
