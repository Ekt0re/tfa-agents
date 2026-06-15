## mission_flow_player.gd
## Autoload runtime per eseguire flussi di missioni.
## Aggiungilo in Project > Autoload come "MissionFlowPlayer".
##
## Si integra con MissionManager esistente e aggiunge:
## - Branching automatico (successo → missione X, fallimento → missione Y)
## - Esecuzione comandi personalizzati al completamento/fallimento
## - Gestione checkpoint per missioni REACH
## - Timer di fallimento (time_limit)
extends Node

const MissionFlowType = preload("res://addons/mission_editor/mission_flow.gd")
const MissionCommandType = preload("res://addons/mission_editor/mission_command.gd")

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------
signal flow_started(flow: Resource)
signal flow_ended(flow: Resource)
signal mission_branch_taken(mission_id: String, next_id: String, is_fail: bool)
signal command_executed(command: Resource)
signal checkpoint_reached(checkpoint_id: String)

# ---------------------------------------------------------------------------
# Stato
# ---------------------------------------------------------------------------
var _current_flow: Resource = null
var _current_mission_id: String = ""
var _is_playing: bool = false
var _time_remaining: float = 0.0
var _checkpoints: Dictionary = {}  # id -> Area2D node reference
var _audio_players: Array[AudioStreamPlayer] = []

# ---------------------------------------------------------------------------
# Proprietà
# ---------------------------------------------------------------------------
var current_flow: Resource:
	get: return _current_flow

var is_playing: bool:
	get: return _is_playing

var current_mission_id: String:
	get: return _current_mission_id


# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Connetti ai segnali di MissionManager
	if MissionManager.mission_completed.is_connected(_on_mission_completed):
		return
	MissionManager.mission_completed.connect(_on_mission_completed)
	MissionManager.mission_failed.connect(_on_mission_failed)


func _process(delta: float) -> void:
	if not _is_playing or _current_flow == null:
		return
	# Gestisci time_limit
	if _time_remaining > 0.0:
		_time_remaining -= delta
		if _time_remaining <= 0.0:
			_handle_time_expired()


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

## Avvia un flusso di missioni
func start_flow(flow: Resource) -> void:
	if flow == null or flow.missions.is_empty():
		push_warning("MissionFlowPlayer: Flow is null or empty")
		return
	stop_flow()
	_current_flow = flow
	_is_playing = true
	flow_started.emit(flow)
	# Avvia la prima missione
	var start_mission: Resource = flow.get_start_mission()
	if start_mission and start_mission is MissionData:
		_start_mission(start_mission as MissionData)


## Ferma il flusso corrente
func stop_flow() -> void:
	if _current_flow:
		flow_ended.emit(_current_flow)
	_current_flow = null
	_current_mission_id = ""
	_is_playing = false
	_time_remaining = 0.0
	# Pulisci audio
	for player: AudioStreamPlayer in _audio_players:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_audio_players.clear()


## Registra un checkpoint per ID (chiamato dai CheckPoint._ready())
func register_checkpoint(checkpoint_id: String, node: Area2D) -> void:
	_checkpoints[checkpoint_id] = node


## Deregistra un checkpoint
func unregister_checkpoint(checkpoint_id: String) -> void:
	_checkpoints.erase(checkpoint_id)


## Forza il completamento della missione corrente e avanza
func force_advance() -> void:
	if not _is_playing:
		return
	MissionManager.complete()


## Salta alla missione con ID specifico
func jump_to_mission(mission_id: String) -> void:
	if _current_flow == null:
		return
	var mission: Resource = _current_flow.get_mission_by_id(mission_id)
	if mission and mission is MissionData:
		MissionManager.clear()
		_start_mission(mission as MissionData)


# ---------------------------------------------------------------------------
# Gestione interna
# ---------------------------------------------------------------------------

func _start_mission(data: MissionData) -> void:
	_current_mission_id = data.mission_id
	# Imposta timer se presente
	if data.time_limit > 0.0:
		_time_remaining = data.time_limit
	else:
		_time_remaining = 0.0
	# Avvia tramite MissionManager
	MissionManager.start(data)


func _on_mission_completed(data: MissionData) -> void:
	if not _is_playing or _current_flow == null:
		return
	if data.mission_id != _current_mission_id:
		return
	_time_remaining = 0.0
	# Esegui comandi di completamento
	await _execute_commands(data.on_complete_commands)
	# Branching: vai alla prossima missione (successo)
	if not data.on_success_next.is_empty():
		var next_mission: Resource = _current_flow.get_mission_by_id(data.on_success_next)
		if next_mission and next_mission is MissionData:
			mission_branch_taken.emit(data.mission_id, data.on_success_next, false)
			# Aspetta che il pannello HUD scompaia
			await get_tree().create_timer(2.8).timeout
			_start_mission(next_mission as MissionData)
			return
	# Nessuna missione successiva → fine flusso
	await get_tree().create_timer(2.8).timeout
	stop_flow()


func _on_mission_failed(data: MissionData) -> void:
	if not _is_playing or _current_flow == null:
		return
	if data.mission_id != _current_mission_id:
		return
	_time_remaining = 0.0
	# Esegui comandi di fallimento
	await _execute_commands(data.on_fail_commands)
	# Branching: vai alla missione di fallimento
	if not data.on_fail_next.is_empty():
		var next_mission: Resource = _current_flow.get_mission_by_id(data.on_fail_next)
		if next_mission and next_mission is MissionData:
			mission_branch_taken.emit(data.mission_id, data.on_fail_next, true)
			await get_tree().create_timer(2.8).timeout
			_start_mission(next_mission as MissionData)
			return
	# Nessuna missione di fallback → fine flusso
	await get_tree().create_timer(2.8).timeout
	stop_flow()


func _handle_time_expired() -> void:
	if not _is_playing:
		return
	MissionManager.fail()


# ---------------------------------------------------------------------------
# Esecuzione comandi
# ---------------------------------------------------------------------------

func _execute_commands(commands: Array[Resource]) -> void:
	for cmd_res: Resource in commands:
		if cmd_res == null:
			continue
		var cmd: Resource = cmd_res
		if not cmd.enabled:
			continue
		if cmd.delay > 0.0:
			await get_tree().create_timer(cmd.delay).timeout
		await _execute_single_command(cmd)
		command_executed.emit(cmd)


func _execute_single_command(cmd: Resource) -> void:
	var CT := MissionCommandType.CommandType
	match cmd.command_type:
		CT.PLAY_SOUND:
			_cmd_play_sound(cmd.parameters)
		CT.CHANGE_SCENE:
			_cmd_change_scene(cmd.parameters)
		CT.SPAWN_ENEMIES:
			_cmd_spawn_enemies(cmd.parameters)
		CT.PLAY_ANIMATION:
			_cmd_play_animation(cmd.parameters)
		CT.SET_VARIABLE:
			_cmd_set_variable(cmd.parameters)
		CT.CALL_METHOD:
			_cmd_call_method(cmd.parameters)
		CT.SHOW_DIALOG:
			await _cmd_show_dialog(cmd.parameters)
		CT.ENABLE_CHECKPOINT:
			_cmd_toggle_checkpoint(cmd.parameters.get("checkpoint_id", ""), true)
		CT.DISABLE_CHECKPOINT:
			_cmd_toggle_checkpoint(cmd.parameters.get("checkpoint_id", ""), false)
		CT.DELAY:
			await get_tree().create_timer(cmd.parameters.get("seconds", 1.0)).timeout


func _cmd_play_sound(params: Dictionary) -> void:
	var path: String = params.get("path", "")
	if path.is_empty():
		return
	if not ResourceLoader.exists(path):
		push_warning("MissionFlowPlayer: Sound not found: %s" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = float(params.get("volume_db", 0.0))
	player.bus = params.get("bus", "Master")
	add_child(player)
	_audio_players.append(player)
	player.play()
	player.finished.connect(func(): player.queue_free(); _audio_players.erase(player))


func _cmd_change_scene(params: Dictionary) -> void:
	var scene_path: String = params.get("scene_path", "")
	if scene_path.is_empty():
		return
	get_tree().change_scene_to_file(scene_path)


func _cmd_spawn_enemies(params: Dictionary) -> void:
	var scene_path: String = params.get("scene_path", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var scene: PackedScene = load(scene_path) as PackedScene
	if not scene:
		return
	var count: int = int(params.get("count", 1))
	var pos_type: String = params.get("position", "origin")
	var base_pos := Vector2.ZERO
	if pos_type == "checkpoint":
		var cp_id: String = params.get("checkpoint_id", "")
		if _checkpoints.has(cp_id):
			var cp_node: Area2D = _checkpoints[cp_id]
			if is_instance_valid(cp_node):
				base_pos = cp_node.global_position
	for i in range(count):
		var instance: Node = scene.instantiate()
		if instance is Node2D:
			(instance as Node2D).global_position = base_pos + Vector2(i * 64, 0)
		get_tree().current_scene.add_child(instance)


func _cmd_play_animation(params: Dictionary) -> void:
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("anim_name", "")
	if node_path.is_empty() or anim_name.is_empty():
		return
	var node := get_node_or_null(NodePath(node_path))
	if node and node.has_node("AnimationPlayer"):
		var anim_player: AnimationPlayer = node.get_node("AnimationPlayer")
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name)


func _cmd_set_variable(params: Dictionary) -> void:
	var autoload_name: String = params.get("autoload", "")
	var property: String = params.get("property", "")
	if autoload_name.is_empty() or property.is_empty():
		return
	var autoload := get_node_or_null("/root/" + autoload_name)
	if autoload:
		autoload.set(property, params.get("value", null))


func _cmd_call_method(params: Dictionary) -> void:
	var node_path: String = params.get("node_path", "")
	var method: String = params.get("method", "")
	if node_path.is_empty() or method.is_empty():
		return
	var node := get_node_or_null(NodePath(node_path))
	if node and node.has_method(method):
		var args: Array = params.get("args", [])
		node.callv(method, args)


func _cmd_show_dialog(params: Dictionary) -> void:
	var text: String = params.get("text", "")
	var duration: float = float(params.get("duration", 3.0))
	if text.is_empty():
		return
	# Usa MissionManager per mostrare il testo come missione custom temporanea
	var data := MissionManager.make_custom(text, 0, Color(0.7, 0.7, 1.0))
	MissionManager.start(data)
	await get_tree().create_timer(duration).timeout
	MissionManager.complete()


func _cmd_toggle_checkpoint(checkpoint_id: String, enable: bool) -> void:
	if _checkpoints.has(checkpoint_id):
		var cp: Area2D = _checkpoints[checkpoint_id]
		if is_instance_valid(cp):
			cp.monitoring = enable
			cp.visible = enable
