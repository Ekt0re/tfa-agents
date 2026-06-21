extends CharacterBody2D
class_name PlayerPrototype

signal height_level_changed(new_level: int)
signal health_changed(current: float, max_val: float)
signal ammo_changed(current: int, total: int)
signal reload_started(duration: float)

const PROJECTILE_VISUAL_SCENE := preload("res://Scenes/projectile_visual.tscn")

@export var speed: float = 400.0
@export var current_height_level: int = 0
@export var total_levels: int = 3
@export var team_id: int = 1
@export var skin_index: int = 0
@export var fire_cooldown: float = 0.12
@export var shot_range: float = 1600.0
@export var touch_auto_fire_range: float = 900.0
@export var projectile_visual_speed: float = 2200.0
@export var vita_max: float = 100.0
var vita: float = 100.0

@export var colpi_correnti: int = 30
@export var colpi_totali: int = 90
@export var capacita_caricatore: int = 30
@export var nome_arma: String = "ASSAULT_RIFLE_M4"

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var joystick: VirtualJoystickPlus = $InputManager/left_stick
@onready var right_stick: VirtualJoystickPlus = $InputManager/right_stick
@onready var muzzle_marker: Marker2D = $Muzzle if has_node("Muzzle") else null
@onready var shot_raycast: RayCast2D = $ShotRayCast2D if has_node("ShotRayCast2D") else null
@onready var camera_2d: Camera2D = $Camera2D if has_node("Camera2D") else null
@onready var global_settings: Node = get_node_or_null("/root/GlobalSettings")

@export var projectile_damage: float = 25.0
@export var reload_duration: float = 1.2

var level_shader := preload("res://Shaders/level_transition.gdshader")
var _using_touch := false
var _is_reloading: bool = false
var _reload_tween: Tween = null
var _last_shot_time: float = -1000.0
var _last_touch_aim_direction: Vector2 = Vector2.RIGHT
var _touch_aim_active: bool = false
var _camera_base_offset := Vector2.ZERO
var _shake_time_left := 0.0
var _shake_strength := 0.0

# Sync multiplayer
var _sync_tick: int = 0
const _SYNC_EVERY: int = 2  # invia ogni N physics frame (60Hz → ~30 update/s)


func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("players")
	add_to_group("damageable")
	
	if camera_2d:
		if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
			camera_2d.enabled = false
		else:
			camera_2d.make_current()
			_camera_base_offset = camera_2d.offset
	
	var input_mgr = get_node_or_null("InputManager")
	if input_mgr and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		input_mgr.queue_free() # Rimuove l'input manager remoto

	# Emetti i segnali iniziali per l'HUD
	health_changed.emit(vita, vita_max)
	ammo_changed.emit(colpi_correnti, colpi_totali)
	if shot_raycast:
		shot_raycast.enabled = true
		shot_raycast.add_exception(self)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		call_deferred("_sync_initial_state_to_peers")
	
	call_deferred("_initialize_level_system")


func _sync_initial_state_to_peers() -> void:
	_receive_initial_state.rpc(team_id, skin_index, nome_arma)

@rpc("any_peer", "call_local", "reliable")
func _receive_initial_state(p_team_id: int, p_skin_index: int, p_nome_arma: String) -> void:
	if multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return

	team_id = p_team_id
	skin_index = p_skin_index
	nome_arma = p_nome_arma
	print("Player %s: Ricevuto stato iniziale -> Team: %d, Skin: %d, Arma: %s" % [name, team_id, skin_index, nome_arma])
	
	# Mappa nome arma all'animazione
	var arama = get_node_or_null("Arama")
	if arama:
		var anim_name = "mitra" # fallback
		if arama.sprite_frames.has_animation(nome_arma):
			anim_name = nome_arma
		elif nome_arma == "ASSAULT_RIFLE_M4":
			anim_name = "mitra"
		arama.play(anim_name)

	
	var sprite = get_node_or_null("Sprite2D")
	if sprite and skin_index > 0:
		pass # In futuro aggiungi logica skin




func _initialize_level_system() -> void:
	_setup_shader_materials()
	_configure_shot_raycast_for_current_level()
	change_height_level(current_height_level, true)
	await get_tree().process_frame
	_check_and_restore_checkpoint()


func _check_and_restore_checkpoint() -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
		
	var flow_player = get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.get("last_checkpoint_id") != "":
		var last_cp_id = flow_player.get("last_checkpoint_id")
		var checkpoints = flow_player.get("_checkpoints")
		if checkpoints and checkpoints.has(last_cp_id):
			var cp_node = checkpoints[last_cp_id]
			if is_instance_valid(cp_node):
				global_position = cp_node.global_position
				print("PlayerPrototype: Ripristinato al checkpoint -> ", last_cp_id, " in pos: ", global_position)
				var level_idx = 0
				var p = cp_node.get_parent()
				while p:
					if p.name.begins_with("L") and p.name.substr(1).is_valid_int():
						level_idx = p.name.substr(1).to_int()
						break
					p = p.get_parent()
				change_height_level(level_idx, true)


func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
		
	if event.is_action_pressed("cambia_piano"):
		var next_level := (current_height_level + 1) % total_levels
		change_height_level(next_level)
		return

	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_R:
			_try_reload()
			return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_try_fire()


func _input(event: InputEvent) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
		
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_using_touch = true
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_touch = false


func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
		
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1

	var joy_dir := joystick.get_value()
	if joy_dir.length() > 0.0:
		direction += joy_dir

	var target_velocity := direction.normalized() * speed
	if direction.length() > 0.0:
		velocity = velocity.lerp(target_velocity, 15.0 * delta)
	else:
		velocity = velocity.lerp(Vector2.ZERO, 25.0 * delta)
		if velocity.length() < 5.0:
			velocity = Vector2.ZERO
	move_and_slide()

	if _using_touch:
		var look_dir := right_stick.get_value()
		_handle_touch_aim_and_fire(look_dir, delta)
	else:
		_touch_aim_active = false
		var mouse_pos := get_global_mouse_position()
		var dir_to_mouse := mouse_pos - global_position
		if dir_to_mouse.length() > 5.0:
			rotation = lerp_angle(rotation, dir_to_mouse.angle(), 20.0 * delta)
	
	# Invia stato ai peer remoti ogni _SYNC_EVERY frame
	if multiplayer.has_multiplayer_peer():
		_sync_tick += 1
		if _sync_tick >= _SYNC_EVERY:
			_sync_tick = 0
			_send_state_to_remotes.rpc(global_position, rotation, current_height_level)


## Riceve lo stato del giocatore remoto e lo applica (interpolato).
@rpc("any_peer", "unreliable")
func _send_state_to_remotes(remote_pos: Vector2, remote_rot: float, remote_level: int) -> void:
	# Ignora se siamo noi stessi (non dovrebbe arrivare, ma per sicurezza)
	if is_multiplayer_authority():
		return
	global_position = remote_pos
	rotation = remote_rot
	if remote_level != current_height_level:
		change_height_level(remote_level, true)


func _process(delta: float) -> void:
	_update_player_position_in_shaders()
	_update_entity_auras_in_shaders()
	_update_camera_shake(delta)


func change_height_level(new_level: int, force_update: bool = false) -> void:
	if new_level == current_height_level and not force_update:
		return

	var previous_level := current_height_level
	# Deve sempre rimuovere dal gruppo per evitare duplicazioni (es: quando si forza un aggiornamento RPC)
	remove_from_group("entities_level_" + str(previous_level))

	current_height_level = new_level
	add_to_group("entities_level_" + str(current_height_level))

	var layer_offset := current_height_level * 3
	collision_layer = 1 << (1 + layer_offset)

	var wall_bit := 1 << (0 + layer_offset)
	var character_bit := 1 << (1 + layer_offset)
	collision_mask = wall_bit | character_bit
	_configure_shot_raycast_for_current_level()

	z_index = current_height_level * 10

	if navigation_agent:
		navigation_agent.navigation_layers = 1 << current_height_level

	height_level_changed.emit(current_height_level)
	if _can_apply_local_feedback():
		_update_level_visibility_effects()
		_trigger_screen_shake(5.0, 0.18)
		if global_settings:
			global_settings.call("show_subtitle_key", "subtitle_level_changed", [current_height_level + 1], 1.8)
	else:
		# Se è un remote player, allinea istantaneamente la sua visibilità a quella del local player
		var local_player: Node2D = null
		var players = get_tree().get_nodes_in_group("players")
		for p in players:
			if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
				local_player = p
				break
		if not local_player and not players.is_empty():
			local_player = players[0]
			
		if local_player:
			self.visible = (self.current_height_level == local_player.current_height_level)

	print("Player cambia piano: " + str(new_level) + " da piano: " + str(previous_level))


func _try_fire() -> void:
	var fire_origin := _get_fire_origin()
	var aim_direction := _get_aim_direction(fire_origin)
	_try_fire_in_direction(aim_direction)


func _try_fire_in_direction(aim_direction: Vector2) -> void:
	if not _can_fire():
		# Auto-ricarica se il caricatore è vuoto ma ci sono munizioni di riserva
		if colpi_correnti <= 0 and colpi_totali > 0:
			_try_reload()
		return

	if aim_direction.length() <= 0.001:
		return

	var fire_origin := _get_fire_origin()
	var shot_data := _build_shot_data(fire_origin, aim_direction.normalized())
	_last_shot_time = _get_time_seconds()
	
	# Consuma colpo e aggiorna HUD
	colpi_correnti -= 1
	ammo_changed.emit(colpi_correnti, colpi_totali)

	if _can_apply_local_feedback():
		_trigger_screen_shake(3.5, 0.12)
		if global_settings:
			global_settings.call("show_subtitle_key", "subtitle_weapon_fired", [], 0.6)

	if multiplayer.has_multiplayer_peer():
		_replicate_fire.rpc(
			shot_data["origin"],
			shot_data["impact_position"],
			shot_data["target_path"],
			shot_data["height_level"],
			shot_data["visual_speed"]
		)
	else:
		_replicate_fire(
			shot_data["origin"],
			shot_data["impact_position"],
			shot_data["target_path"],
			shot_data["height_level"],
			shot_data["visual_speed"]
		)


@rpc("authority", "call_local", "reliable")
func _replicate_fire(origin: Vector2, impact_position: Vector2, target_path: NodePath, height_level: int, visual_speed: float) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return

	var projectile := PROJECTILE_VISUAL_SCENE.instantiate() as ProjectileVisual
	if not projectile:
		return

	current_scene.add_child(projectile)
	projectile.setup_projectile(origin, impact_position, visual_speed, height_level, target_path)

	if not target_path.is_empty() and _can_apply_projectile_impacts():
		projectile.impact_reached.connect(_on_projectile_impact, CONNECT_ONE_SHOT)


func _on_projectile_impact(target_path: NodePath) -> void:
	if target_path.is_empty():
		return

	var target := get_tree().root.get_node_or_null(target_path)
	if not target or not is_instance_valid(target):
		return

	if target.has_method("apply_damage"):
		target.call_deferred("apply_damage", projectile_damage)
	elif target.has_method("receive_damage"):
		var source_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		target.call_deferred("receive_damage", projectile_damage, source_id)

	elif target.has_method("destroy_from_projectile"):
		target.call_deferred("destroy_from_projectile")

	elif _is_enemy_target(target):
		target.call_deferred("queue_free")

	if _can_apply_local_feedback():
		_trigger_screen_shake(7.0, 0.16)

		if global_settings:
			global_settings.call(
				"show_subtitle_key",
				"subtitle_enemy_down",
				[],
				1.0
			)

func _can_fire() -> bool:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false

	if _is_reloading:
		return false

	if colpi_correnti <= 0:
		return false

	return _get_time_seconds() - _last_shot_time >= fire_cooldown


func _get_fire_origin() -> Vector2:
	if muzzle_marker:
		return muzzle_marker.global_position
	return global_position


func _get_aim_direction(_fire_origin: Vector2) -> Vector2:
	if _using_touch:
		var touch_direction := right_stick.get_value()
		if touch_direction.length() > 0.1:
			return touch_direction.normalized()
		if _last_touch_aim_direction.length() > 0.1:
			return _last_touch_aim_direction.normalized()

	var mouse_direction := get_global_mouse_position() - global_position
	if mouse_direction.length() > 0.001:
		return mouse_direction.normalized()

	return Vector2.RIGHT.rotated(global_rotation)


func _handle_touch_aim_and_fire(look_dir: Vector2, delta: float) -> void:
	var has_active_aim := look_dir.length() > 0.1
	if has_active_aim:
		_last_touch_aim_direction = look_dir.normalized()
		_touch_aim_active = true
		rotation = lerp_angle(rotation, _last_touch_aim_direction.angle(), 20.0 * delta)
		_try_touch_auto_fire()
		return

	if _touch_aim_active and _last_touch_aim_direction.length() > 0.1:
		_touch_aim_active = false
		_try_fire_in_direction(_last_touch_aim_direction)


func _try_touch_auto_fire() -> void:
	if not _using_touch or not _touch_aim_active or not _can_fire():
		return

	var look_direction := Vector2.RIGHT.rotated(global_rotation)
	if look_direction.length() <= 0.001:
		return

	var fire_origin := _get_fire_origin()
	if not _has_enemy_target_in_direction(fire_origin, look_direction.normalized(), touch_auto_fire_range):
		return

	_try_fire_in_direction(look_direction)


func _has_enemy_target_in_direction(fire_origin: Vector2, aim_direction: Vector2, detection_range: float) -> bool:
	if not shot_raycast:
		return false

	shot_raycast.global_position = fire_origin
	shot_raycast.global_rotation = aim_direction.angle()
	shot_raycast.target_position = Vector2(minf(detection_range, shot_range), 0.0)
	shot_raycast.force_raycast_update()

	if not shot_raycast.is_colliding():
		return false

	var collider := shot_raycast.get_collider()
	return collider is Node and _is_enemy_target(collider)


func _is_enemy_target(target: Variant) -> bool:
	if not (target is Node):
		return false

	var node := target as Node
	
	if node is PlayerPrototype:
		var other_team = node.team_id
		if other_team == self.team_id:
			return false # No friendly fire
		return true

	return (
		node.is_in_group("enemy")
		or node.is_in_group("bots")
		or node.is_in_group("damageable")
	)

func _build_shot_data(fire_origin: Vector2, aim_direction: Vector2) -> Dictionary:
	var impact_position := fire_origin + aim_direction * shot_range
	var target_path := NodePath()

	if shot_raycast:
		shot_raycast.global_position = fire_origin
		shot_raycast.global_rotation = aim_direction.angle()
		shot_raycast.target_position = Vector2(shot_range, 0.0)
		shot_raycast.force_raycast_update()

		if shot_raycast.is_colliding():
			impact_position = shot_raycast.get_collision_point()

			var collider := shot_raycast.get_collider()

			if collider is Node:
				var node := collider as Node

				if (
					node.is_in_group("enemy")
					or node.is_in_group("bots")
					or node.is_in_group("damageable")
				):
					target_path = node.get_path()

	return {
		"origin": fire_origin,
		"impact_position": impact_position,
		"target_path": target_path,
		"height_level": current_height_level,
		"visual_speed": projectile_visual_speed
	}


func _configure_shot_raycast_for_current_level() -> void:
	if not shot_raycast:
		return

	var layer_offset := current_height_level * 3
	var wall_bit := 1 << (0 + layer_offset)
	var character_bit := 1 << (1 + layer_offset)
	shot_raycast.collision_mask = wall_bit | character_bit


func _can_apply_projectile_impacts() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _can_apply_local_feedback() -> bool:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false
	return true


func _trigger_screen_shake(strength: float, duration: float) -> void:
	if not camera_2d:
		return
	if global_settings and not bool(global_settings.call("get_setting", "screen_shake", true)):
		camera_2d.offset = _camera_base_offset
		return
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time_left = maxf(_shake_time_left, duration)


func _update_camera_shake(delta: float) -> void:
	if not camera_2d:
		return
	if global_settings and not bool(global_settings.call("get_setting", "screen_shake", true)):
		camera_2d.offset = camera_2d.offset.lerp(_camera_base_offset, minf(1.0, delta * 20.0))
		_shake_time_left = 0.0
		_shake_strength = 0.0
		return
	if _shake_time_left <= 0.0:
		camera_2d.offset = camera_2d.offset.lerp(_camera_base_offset, minf(1.0, delta * 18.0))
		return
	_shake_time_left = maxf(0.0, _shake_time_left - delta)
	var shake_offset := Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))
	camera_2d.offset = _camera_base_offset + shake_offset
	_shake_strength = lerpf(_shake_strength, 0.0, minf(1.0, delta * 12.0))


func _setup_shader_materials() -> void:
	for level_index in range(total_levels):
		for canvas_item in _get_level_canvas_items(level_index):
			var shader_material := canvas_item.material as ShaderMaterial
			if not shader_material or shader_material.shader != level_shader:
				shader_material = ShaderMaterial.new()
				shader_material.shader = level_shader
				canvas_item.material = shader_material


func _update_player_position_in_shaders() -> void:
	if not _can_apply_local_feedback():
		return
	var screen_pos = get_viewport().get_canvas_transform() * global_position

	var camera = get_viewport().get_camera_2d()
	var zoom_factor = camera.zoom.x if camera else 1.0
	var scaled_radius = 850.0 * zoom_factor
	var scaled_softness = 200.0 * zoom_factor

	for level_index in range(total_levels):
		for shader_material in _get_level_shader_materials(level_index):
			shader_material.set_shader_parameter("player_screen_position", screen_pos)
			shader_material.set_shader_parameter("mask_radius", scaled_radius)
			shader_material.set_shader_parameter("mask_softness", scaled_softness)


func _update_level_visibility_effects() -> void:
	if not _can_apply_local_feedback():
		return
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	for level_index in range(total_levels):
		var is_current: bool = (level_index == current_height_level)

		# Logica sicura senza simboli di "minore di" per evitare interruzioni di testo
		var is_above: bool = (level_index > current_height_level)
		var is_below: bool = (current_height_level > level_index)

		var target_fog: float = 0.0
		if is_below:
			target_fog = 0.75
		elif is_above:
			target_fog = 0.40

		for shader_material in _get_level_shader_materials(level_index):
			shader_material.set_shader_parameter("use_mask", is_above)
			shader_material.set_shader_parameter("fog_amount", target_fog)

		_set_entities_visibility_for_level(level_index, is_current)


func _update_entity_auras_in_shaders() -> void:
	if not _can_apply_local_feedback():
		return
	var positions: Array[Vector2] = []
	for entity in get_tree().get_nodes_in_group("entities_level_" + str(current_height_level)):
		if entity != self and entity is Node2D:
			positions.append(get_viewport().get_canvas_transform() * entity.global_position)
			if positions.size() >= 24:
				break

	var pos_array := PackedVector2Array()
	for i in range(24):
		if i >= positions.size():
			pos_array.append(Vector2(-9999.0, -9999.0))
		else:
			pos_array.append(positions[i])

	for level_index in range(total_levels):
		for shader_material in _get_level_shader_materials(level_index):
			shader_material.set_shader_parameter("entity_screen_positions", pos_array)
			shader_material.set_shader_parameter("entity_count", positions.size())


func _set_entities_visibility_for_level(level: int, should_be_visible: bool) -> void:
	for entity in get_tree().get_nodes_in_group("entities_level_" + str(level)):
		if entity == self or entity is Ramp:
			continue
		if entity is CanvasItem:
			entity.visible = should_be_visible


func _get_level_shader_materials(level_index: int) -> Array[ShaderMaterial]:
	var shader_materials: Array[ShaderMaterial] = []
	for canvas_item in _get_level_canvas_items(level_index):
		if canvas_item.material is ShaderMaterial:
			shader_materials.append(canvas_item.material)
	return shader_materials


func _get_level_canvas_items(level_index: int) -> Array[CanvasItem]:
	var current_scene = get_tree().current_scene
	var canvas_items: Array[CanvasItem] = []
	if not current_scene:
		return canvas_items

	var level_node = current_scene.find_child("L" + str(level_index), true, false)
	if level_node:
		_collect_canvas_items(level_node, canvas_items)
	return canvas_items


func _collect_canvas_items(node: Node, canvas_items: Array[CanvasItem]) -> void:
	if node is CanvasItem:
		canvas_items.append(node)

	for child in node.get_children():
		_collect_canvas_items(child, canvas_items)


func apply_damage(amount: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_apply_damage_internal(amount, 0)
	elif not multiplayer.has_multiplayer_peer():
		_apply_damage_internal(amount, 0)

@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: float, source_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var source_player = null
	var current_scene = get_tree().current_scene
	if current_scene.has_node("Players"):
		source_player = current_scene.get_node("Players").get_node_or_null(str(source_peer_id))
	elif current_scene.has_node(str(source_peer_id)):
		source_player = current_scene.get_node(str(source_peer_id))
		
	if source_player and source_player is PlayerPrototype:
		if source_player.team_id == self.team_id:
			return # No friendly fire
	
	_apply_damage_internal(amount, source_peer_id)

func _apply_damage_internal(amount: float, source_peer_id: int) -> void:
	if vita <= 0.0:
		return
	vita = maxf(vita - amount, 0.0)
	print("Player ", name, " subisce ", amount, " danni da ", source_peer_id, ". Vita rimanente: ", vita)
	_broadcast_health_update.rpc(vita, vita_max)
	
	if vita <= 0.0:
		print("Player ", name, " è morto!")
		if multiplayer.has_multiplayer_peer():
			var map = get_tree().current_scene
			if map.has_method("_on_player_killed"):
				map._on_player_killed(source_peer_id, int(str(name)))
		_die.rpc()

@rpc("any_peer", "call_local", "reliable")
func _broadcast_health_update(new_vita: float, new_vita_max: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return
	vita = new_vita
	vita_max = new_vita_max
	health_changed.emit(vita, vita_max)

@rpc("any_peer", "call_local", "reliable")
func _die() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return
	# Disattiva controlli e movimento del player locale
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		set_physics_process(false)
		set_process(false)
		set_process_unhandled_input(false)
		set_process_input(false)
		
		# Disattiva collisioni
		collision_layer = 0
		collision_mask = 0
		
		# Nascondi elementi visivi (sprites) ma mantieni camera attiva per spectating
		for child in get_children():
			if child is CanvasItem and child != camera_2d and child.name != "InputManager":
				child.visible = false
				
		var input_mgr = get_node_or_null("InputManager")
		if input_mgr:
			input_mgr.visible = false
			
		# In PvP siamo in gruppo pvp_all_players → aspetta respawn, non game over
		if is_in_group("pvp_all_players"):
			print("In attesa di respawn...")
		else:
			_show_game_over()

@rpc("any_peer", "call_local", "reliable")
func respawn(spawn_pos: Vector2, spawn_level: int) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return
	vita = vita_max
	colpi_correnti = capacita_caricatore
	colpi_totali = 90
	global_position = spawn_pos
	
	health_changed.emit(vita, vita_max)
	ammo_changed.emit(colpi_correnti, colpi_totali)
	
	change_height_level(spawn_level, true)
	
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		set_physics_process(true)
		set_process(true)
		set_process_unhandled_input(true)
		set_process_input(true)
		
		var layer_offset := current_height_level * 3
		collision_layer = 1 << (1 + layer_offset)
		var wall_bit := 1 << (0 + layer_offset)
		var character_bit := 1 << (1 + layer_offset)
		collision_mask = wall_bit | character_bit
		
		for child in get_children():
			if child is CanvasItem and child != camera_2d and child.name != "InputManager":
				child.visible = true
				
		var input_mgr = get_node_or_null("InputManager")
		if input_mgr:
			input_mgr.visible = true
	
	print("Player ", name, " respawnato a ", spawn_pos)


func _show_game_over() -> void:
	if get_tree().current_scene.has_node("GameOverMenu"):
		return
		
	var game_over_scene = load("res://Menu/game_over_menu.tscn")
	if game_over_scene:
		var game_over_instance = game_over_scene.instantiate()
		get_tree().current_scene.add_child(game_over_instance)
		if game_over_instance.has_method("setup"):
			game_over_instance.setup(self)


func _try_reload() -> void:
	if _is_reloading:
		return
	if colpi_correnti == capacita_caricatore or colpi_totali <= 0:
		return

	_is_reloading = true
	reload_started.emit(reload_duration)
	_play_reload_animation()

	if _reload_tween and _reload_tween.is_valid():
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.tween_interval(reload_duration)
	_reload_tween.tween_callback(_finish_reload)


func _finish_reload() -> void:
	var da_ricaricare: int = capacita_caricatore - colpi_correnti
	var effettivi: int = min(da_ricaricare, colpi_totali)
	colpi_correnti += effettivi
	colpi_totali -= effettivi
	_is_reloading = false
	ammo_changed.emit(colpi_correnti, colpi_totali)
	if global_settings:
		global_settings.call("show_subtitle_key", "subtitle_reloading", [], 1.0)


func _play_reload_animation() -> void:
	var weapon_sprite: AnimatedSprite2D = get_node_or_null("Arama") as AnimatedSprite2D
	if not weapon_sprite:
		return
	var tw: Tween = create_tween()
	var original_rotation: float = weapon_sprite.rotation
	var original_scale: Vector2 = weapon_sprite.scale
	tw.set_parallel(true)
	tw.tween_property(weapon_sprite, "rotation", original_rotation + 0.5, reload_duration * 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(weapon_sprite, "scale", original_scale * 0.85, reload_duration * 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(weapon_sprite, "rotation", original_rotation - 0.3, reload_duration * 0.25).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(weapon_sprite, "rotation", original_rotation, reload_duration * 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(weapon_sprite, "scale", original_scale, reload_duration * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC).set_delay(reload_duration * 0.15)


func heal(amount: float) -> void:
	vita = minf(vita + amount, vita_max)
	print("Player si cura di ", amount, ". Vita corrente: ", vita)
	health_changed.emit(vita, vita_max)


func add_ammo(amount: int) -> void:
	colpi_totali += amount
	print("Player aggiunge ", amount, " munizioni. Colpi totali: ", colpi_totali)
	ammo_changed.emit(colpi_correnti, colpi_totali)


#Organizzazione collisioni fisiche, layer, maschere e navigation.
# Piano 0
# - layer 1: muri
# - layer 2: player, nemici ecc
# - - mask: layer 1, 2
# - layer 3: proiettili Piano 0
# - - mask: layer 1, 2
# - Navigation: layer 0
# Piano 1
# - layer 4: muri
# - layer 5: player, nemici ecc
# - - mask: layer 4, 5
# - layer 6: proiettili Piano 1
# - - mask: layer 4, 5
# - Navigation: layer 1
# Piano 2
# - layer 7: muri
# - layer 8: player, nemici ecc
# - - mask: layer 7, 8
# - layer 9: proiettili Piano 2
# - - mask: layer 7, 8
# - Navigation: layer 2
