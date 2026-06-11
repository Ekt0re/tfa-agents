extends CharacterBody2D
class_name PlayerPrototype

signal height_level_changed(new_level: int)

const PROJECTILE_VISUAL_SCENE := preload("res://Scenes/projectile_visual.tscn")

@export var speed: float = 400.0
@export var current_height_level: int = 0
@export var total_levels: int = 3
@export var fire_cooldown: float = 0.12
@export var shot_range: float = 1600.0
@export var touch_auto_fire_range: float = 900.0
@export var projectile_visual_speed: float = 2200.0

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var joystick: VirtualJoystickPlus = $InputManager/left_stick
@onready var right_stick: VirtualJoystickPlus = $InputManager/right_stick
@onready var muzzle_marker: Marker2D = $Muzzle if has_node("Muzzle") else null
@onready var shot_raycast: RayCast2D = $ShotRayCast2D if has_node("ShotRayCast2D") else null

var level_shader := preload("res://Shaders/level_transition.gdshader")
var _using_touch := false
var _last_shot_time: float = -1000.0
var _last_touch_aim_direction: Vector2 = Vector2.RIGHT
var _touch_aim_active: bool = false


func _ready() -> void:
	add_to_group("players")
	if shot_raycast:
		shot_raycast.enabled = true
		shot_raycast.add_exception(self)
	call_deferred("_initialize_level_system")


func _initialize_level_system() -> void:
	_setup_shader_materials()
	_configure_shot_raycast_for_current_level()
	change_height_level(current_height_level, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cambia_piano"):
		var next_level := (current_height_level + 1) % total_levels
		change_height_level(next_level)
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_try_fire()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_using_touch = true
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_touch = false


func _physics_process(delta: float) -> void:
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


func _process(_delta: float) -> void:
	_update_player_position_in_shaders()
	_update_entity_auras_in_shaders()


func change_height_level(new_level: int, force_update: bool = false) -> void:
	if new_level == current_height_level and not force_update:
		return

	var previous_level := current_height_level
	if not force_update:
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
	_update_level_visibility_effects()

	print("Player cambia piano: " + str(new_level) + " da piano: " + str(previous_level))


func _try_fire() -> void:
	var fire_origin := _get_fire_origin()
	var aim_direction := _get_aim_direction(fire_origin)
	_try_fire_in_direction(aim_direction)


func _try_fire_in_direction(aim_direction: Vector2) -> void:
	if not _can_fire():
		return

	if aim_direction.length() <= 0.001:
		return

	var fire_origin := _get_fire_origin()
	var shot_data := _build_shot_data(fire_origin, aim_direction.normalized())
	_last_shot_time = _get_time_seconds()

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

	if not _is_enemy_target(target):
		return

	if target.has_method("destroy_from_projectile"):
		target.call_deferred("destroy_from_projectile")
	else:
		target.call_deferred("queue_free")


func _can_fire() -> bool:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false

	return _get_time_seconds() - _last_shot_time >= fire_cooldown


func _get_fire_origin() -> Vector2:
	if muzzle_marker:
		return muzzle_marker.global_position
	return global_position


func _get_aim_direction(fire_origin: Vector2) -> Vector2:
	if _using_touch:
		var touch_direction := right_stick.get_value()
		if touch_direction.length() > 0.1:
			return touch_direction.normalized()
		if _last_touch_aim_direction.length() > 0.1:
			return _last_touch_aim_direction.normalized()

	var mouse_direction := get_global_mouse_position() - fire_origin
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
	return target is Node and ((target as Node).is_in_group("enemy") or (target as Node).is_in_group("bots"))


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
			if collider is Node and _is_enemy_target(collider):
				target_path = (collider as Node).get_path()

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


func _setup_shader_materials() -> void:
	for level_index in range(total_levels):
		for canvas_item in _get_level_canvas_items(level_index):
			var shader_material := canvas_item.material as ShaderMaterial
			if not shader_material or shader_material.shader != level_shader:
				shader_material = ShaderMaterial.new()
				shader_material.shader = level_shader
				canvas_item.material = shader_material


func _update_player_position_in_shaders() -> void:
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
