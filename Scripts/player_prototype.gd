extends CharacterBody2D
class_name PlayerPrototype

signal height_level_changed(new_level: int)

@export var speed: float = 400.0
@export var current_height_level: int = 0
@export var total_levels: int = 3

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

	z_index = current_height_level * 10

	if navigation_agent:
		navigation_agent.navigation_layers = 1 << current_height_level

	height_level_changed.emit(current_height_level)
	_update_level_visibility_effects()
	
	print("Player cambia piano: " + str(new_level) + " da piano: " + str(previous_level))



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
		if entity != self and entity is CanvasItem:
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
