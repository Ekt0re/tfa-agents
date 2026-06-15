## dev_map_tutorial.gd
## Script tutorial per dev_map.tscn — integrato con MissionFlowPlayer.
## Il flusso di missioni è definito in example_tutorial_flow.gd e modificabile
## dall'editor visuale (Mission Flow Editor dock).
##
## Questo script rileva le condizioni di gioco per ogni step e chiama
## MissionManager.complete() quando soddisfatte. MissionFlowPlayer gestisce
## il sequencing automatico, branching e comandi di completamento.
##
## Flusso: MOVE → AIM → FIRE → ELIMINATE → COLLECT → DESTROY →
##          DONE → REACH_PORTAL → TUTORIAL_COMPLETE → (main menu)
extends Node

# ---------------------------------------------------------------------------
# ID delle missioni nel flusso (devono corrispondere a example_tutorial_flow.gd)
# ---------------------------------------------------------------------------
const MISSION_MOVE := "tutorial_move"
const MISSION_AIM := "tutorial_aim"
const MISSION_FIRE := "tutorial_fire"
const MISSION_ELIMINATE := "tutorial_eliminate"
const MISSION_COLLECT := "tutorial_collect"
const MISSION_DESTROY := "tutorial_destroy"
const MISSION_DONE := "tutorial_done"
const MISSION_REACH_PORTAL := "tutorial_reach_portal"
const MISSION_COMPLETE := "tutorial_complete"

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------
var _player: CharacterBody2D = null
var _player_start_pos: Vector2 = Vector2.ZERO
var _mouse_moved := false
var _initial_ammo: int = -1
var _group_initial_count: int = 0
var _poll_timer: float = 0.0
var _completing: bool = false
var _ammo_connected: bool = false
var _checkpoint: Area2D = null

# Distanza minima (px) per considerare il movimento valido
const MOVE_THRESHOLD: float = 32.0
# Movimento mouse minimo (px cumulativi) per considerare la mira valida
const MOUSE_THRESHOLD: float = 50.0
var _mouse_accumulator: float = 0.0


# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Attendi un frame per assicurarti che il player sia nella scena
	await get_tree().process_frame
	_find_player()

	# Trova il checkpoint e nascondilo fino allo step REACH
	_checkpoint = _find_checkpoint()
	if _checkpoint:
		_checkpoint.visible = false

	# Connetti al segnale di start missione per setup specifico per step
	MissionManager.mission_started.connect(_on_flow_mission_started)

	# Carica e avvia il flusso tutorial tramite MissionFlowPlayer
	var ExampleFlow = preload("res://addons/mission_editor/examples/example_tutorial_flow.gd")
	var flow: Resource = ExampleFlow.create_flow()
	await get_tree().create_timer(0.5).timeout
	MissionFlowPlayer.start_flow(flow)


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_player = players[0] as CharacterBody2D
		if _player:
			_player_start_pos = _player.global_position


func _find_checkpoint() -> Area2D:
	# Cerca per unique name, poi per gruppo/nodo figlio
	var cp := get_node_or_null("%CheckPoint")
	if cp:
		return cp as Area2D
	# Fallback: cerca tra i figli
	return find_child("CheckPoint", true, false) as Area2D


func _input(event: InputEvent) -> void:
	# Traccia il movimento del mouse per la missione AIM
	if _current_mission_id() == MISSION_AIM and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse_accumulator += motion.relative.length()
		if _mouse_accumulator >= MOUSE_THRESHOLD:
			_mouse_moved = true


func _process(delta: float) -> void:
	var mid := _current_mission_id()
	if mid.is_empty() or mid == MISSION_COMPLETE:
		return

	match mid:
		MISSION_MOVE:
			_check_movement()
		MISSION_AIM:
			if _mouse_moved:
				_complete_current()
		MISSION_FIRE:
			_ensure_ammo_connected()
		MISSION_ELIMINATE, MISSION_COLLECT, MISSION_DESTROY:
			# Polling periodico per evitare check ogni frame
			_poll_timer += delta
			if _poll_timer >= 0.3:
				_poll_timer = 0.0
				_check_group_clear(mid)
		MISSION_DONE, MISSION_REACH_PORTAL:
			pass  # DONE auto-completata dal timer in _on_flow_mission_started, REACH dal CheckPoint


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Ritorna l'ID della missione corrente dal MissionFlowPlayer
func _current_mission_id() -> String:
	if MissionFlowPlayer and MissionFlowPlayer.is_playing:
		return MissionFlowPlayer.current_mission_id
	return ""


func _complete_current() -> void:
	if _completing:
		return
	_completing = true
	MissionManager.complete()
	# Reset guard dopo un frame per la prossima missione
	await get_tree().process_frame
	_completing = false


# ---------------------------------------------------------------------------
# Hook di setup quando la missione cambia
# ---------------------------------------------------------------------------
func _on_flow_mission_started(data: MissionData) -> void:
	# Reset stato per la nuova missione
	_poll_timer = 0.0
	_completing = false

	# Gestisci visibilità checkpoint — mostra solo allo step REACH
	if _checkpoint:
		_checkpoint.visible = (data.mission_id == MISSION_REACH_PORTAL)

	match data.mission_id:
		MISSION_AIM:
			_mouse_accumulator = 0.0
			_mouse_moved = false
		MISSION_FIRE:
			_ensure_ammo_connected()
		MISSION_ELIMINATE:
			_group_initial_count = get_tree().get_nodes_in_group("bots").size()
			if _group_initial_count > 0:
				# Counter contestuale: target = numero reale di nemici nella scena
				data.target = _group_initial_count
				MissionManager.emit_signal("mission_progress_changed", 0, data.target)
			else:
				# Nessun nemico → obiettivo già completato
				_complete_current()
		MISSION_COLLECT:
			_group_initial_count = get_tree().get_nodes_in_group("powerup").size()
			if _group_initial_count > 0:
				data.target = _group_initial_count
				MissionManager.emit_signal("mission_progress_changed", 0, data.target)
			else:
				_complete_current()
		MISSION_DESTROY:
			_group_initial_count = get_tree().get_nodes_in_group("Barile").size()
			if _group_initial_count > 0:
				data.target = _group_initial_count
				MissionManager.emit_signal("mission_progress_changed", 0, data.target)
			else:
				_complete_current()
		MISSION_DONE:
			# Messaggio "VAI AL PORTALE" → auto-completa dopo 1.5s per avanzare
			await get_tree().create_timer(1.5).timeout
			_complete_current()
		MISSION_COMPLETE:
			# Tutorial finito → auto-completa così il comando CHANGE_SCENE riporta al menu
			await get_tree().create_timer(1.0).timeout
			_complete_current()


# ---------------------------------------------------------------------------
# Check conditions
# ---------------------------------------------------------------------------
func _check_movement() -> void:
	if not _player or not is_instance_valid(_player):
		return
	var moved := false
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or \
	   Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D):
		moved = true
	elif _player.global_position.distance_to(_player_start_pos) > MOVE_THRESHOLD:
		moved = true

	if moved:
		_complete_current()


func _check_group_clear(mid: String) -> void:
	match mid:
		MISSION_ELIMINATE:
			var remaining := get_tree().get_nodes_in_group("bots").size()
			var eliminated := _group_initial_count - remaining
			MissionManager.set_progress(eliminated)
			if remaining == 0:
				_complete_current()

		MISSION_COLLECT:
			var remaining := get_tree().get_nodes_in_group("powerup").size()
			var collected := _group_initial_count - remaining
			MissionManager.set_progress(collected)
			if remaining == 0:
				_complete_current()

		MISSION_DESTROY:
			var remaining := get_tree().get_nodes_in_group("Barile").size()
			var destroyed := _group_initial_count - remaining
			MissionManager.set_progress(destroyed)
			if remaining == 0:
				_complete_current()


# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
func _ensure_ammo_connected() -> void:
	if _ammo_connected:
		return
	if not _player or not is_instance_valid(_player):
		_find_player()
	if not _player or not is_instance_valid(_player):
		return
	if _player.has_signal("ammo_changed"):
		if not _player.ammo_changed.is_connected(_on_player_ammo_changed):
			_player.ammo_changed.connect(_on_player_ammo_changed)
		_ammo_connected = true
	_initial_ammo = int(_player.get("colpi_correnti")) if _player.get("colpi_correnti") != null else -1


func _on_player_ammo_changed(current: int, _total: int) -> void:
	if _current_mission_id() != MISSION_FIRE:
		return
	if _initial_ammo >= 0 and current < _initial_ammo:
		_complete_current()
	elif current >= 0 and _initial_ammo < 0:
		_complete_current()
