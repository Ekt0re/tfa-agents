extends CharacterBody2D
class_name PlayerPrototype

signal height_level_changed(new_level: int)

@export var speed: float = 400.0
@export var current_height_level: int = 0
@export var total_levels: int = 3 # Numero totale di piani (0, 1, 2)

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var joystick: VirtualJoystickPlus = $InputManager/left_stick
@onready var right_stick: VirtualJoystickPlus = $InputManager/right_stick

var level_shader := preload("res://Shaders/level_transition.gdshader")
var _using_touch := false


func _ready() -> void:
	add_to_group("players")
	call_deferred("_initialize_level_system")


func _initialize_level_system() -> void:
	_setup_shader_materials()
	change_height_level(current_height_level, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_Q:
			# Passa al piano successivo ciclicamente (0 -> 1 -> 2 -> 0)
			var next_level := (current_height_level + 1) % total_levels
			change_height_level(next_level)


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
		if look_dir.length() > 0.1:
			rotation = lerp_angle(rotation, look_dir.angle(), 20.0 * delta)
	else:
		var mouse_pos := get_global_mouse_position()
		var dir_to_mouse := mouse_pos - global_position
		if dir_to_mouse.length() > 5.0:
			rotation = lerp_angle(rotation, dir_to_mouse.angle(), 20.0 * delta)


func _process(_delta: float) -> void:
	if current_height_level == 0:
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

	# === CALCOLO AUTOMATICO DEI LAYER SULLO SCHEMA A 9 LIVELLI ===
	var layer_offset := current_height_level * 3
	
	# Il Player si posiziona sui Personaggi (Layer 2, 5, 8 -> indici di bit 1, 4, 7)
	collision_layer = 1 << (1 + layer_offset)
	
	# Il Player rileva i Muri (indice 0) e i Personaggi (indice 1) dello stesso piano
	var wall_bit := 1 << (0 + layer_offset)
	var character_bit := 1 << (1 + layer_offset)
	collision_mask = wall_bit | character_bit

	# Imposta l'ordine visivo (Piano 0 = Z 0, Piano 1 = Z 10, Piano 2 = Z 20)
	z_index = current_height_level * 10

	# Aggiorna l'agente di navigazione (Mappa i quadratini 1, 2, 3 della tua TileMap)
	if navigation_agent:
		navigation_agent.navigation_layers = 1 << current_height_level

	height_level_changed.emit(current_height_level)
	_update_level_visibility_effects()


func _setup_shader_materials() -> void:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	# Cerca i nodi L0, L1, L2 direttamente sotto la mappa di sviluppo
	for i in range(total_levels):
		var layer_node = current_scene.find_child("L" + str(i), true, false)
		if layer_node and layer_node is CanvasItem:
			var mat := ShaderMaterial.new()
			mat.shader = level_shader
			layer_node.material = mat


func _update_player_position_in_shaders() -> void:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	var screen_pos = get_global_transform_with_canvas().origin
	var camera = get_viewport().get_camera_2d()
	var zoom_factor = camera.zoom.x if camera else 1.0
	var scaled_radius = 980.0 * zoom_factor
	var scaled_softness = 200.0 * zoom_factor

	for i in range(current_height_level + 1, total_levels):
		var layer_node = current_scene.find_child("L" + str(i), true, false)
		if layer_node and layer_node is CanvasItem and layer_node.material is ShaderMaterial:
			layer_node.material.set_shader_parameter("player_screen_position", screen_pos)
			layer_node.material.set_shader_parameter("mask_radius", scaled_radius)
			layer_node.material.set_shader_parameter("mask_softness", scaled_softness)


func _update_level_visibility_effects() -> void:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	for level_index in range(total_levels):
		var is_current := level_index == current_height_level
		var is_above := level_index > current_height_level
		
		var layer_node = current_scene.find_child("L" + str(level_index), true, false)
		if layer_node and layer_node is CanvasItem and layer_node.material is ShaderMaterial:
			layer_node.material.set_shader_parameter("use_mask", is_above)
			layer_node.material.set_shader_parameter("fog_amount", 0.5 if is_above else (0.75 if not is_current else 0.0))
		
		_set_entities_visibility_for_level(level_index, is_current)


func _update_entity_auras_in_shaders() -> void:
	if current_height_level != 0:
		return

	var positions: Array[Vector2] = []
	for entity in get_tree().get_nodes_in_group("entities_level_0"):
		if entity != self and entity is Node2D:
			positions.append(get_viewport().get_canvas_transform() * entity.global_position)
			if positions.size() >= 24:
				break

	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	for level_index in range(1, total_levels):
		var layer_node = current_scene.find_child("L" + str(level_index), true, false)
		if layer_node and layer_node is CanvasItem and layer_node.material is ShaderMaterial:
			var pos_array: Array[Vector2] = []
			for i in range(24):
				# Riga corretta ripristinata con l'operatore 'else' completo
				pos_array.append(positions[i] if i < positions.size() else Vector2(-9999.0, -9999.0))
			layer_node.material.set_shader_parameter("entity_screen_positions", pos_array)
			layer_node.material.set_shader_parameter("entity_count", positions.size())

func _set_entities_visibility_for_level(level: int, should_be_visible: bool) -> void:
	for entity in get_tree().get_nodes_in_group("entities_level_" + str(level)):
		if entity != self and entity is CanvasItem:
			entity.visible = should_be_visible
