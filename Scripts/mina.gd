## mina.gd
## Oggetto Mina Esplosiva.
## Esplode se calpestata da un nemico o colpita da un proiettile nemico.

@tool
extends Area2D
class_name Mina

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

@export_group("Mina")

@export var team_id: int = 2:
	set(value):
		team_id = value
		_update_editor_preview()

@export var vita_max: float = 1.0

@export_group("Livello")

@export_range(0, 15, 1) var livello: int = 0:
	set(value):
		livello = maxi(value, 0)
		_refresh_level_membership()
		_apply_collision_layers()
		_update_editor_preview()

@export_group("Esplosione")

@export var explosion_damage: float = 100.0
@export var explosion_radius: float = 1200.0

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

var vita: float = 0.0
var _registered_levels: Array[int] = []
var _exploded: bool = false
var _player_node: Node2D
var _danger_indicator: ColorRect
var _shader_material: ShaderMaterial
var _point_light: PointLight2D

@onready var _sprite: AnimatedSprite2D     = $AnimatedSprite2D
@onready var _col_explosion: CollisionShape2D = $CollisionExplosione
@onready var _particles: CPUParticles2D = $ExplosionParticles
@onready var _col_mina: CollisionShape2D = $CollisionMina

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return

	vita = vita_max

	var anims = ["MinaViola", "MinaVerde"]
	if _sprite:
		_sprite.play(anims[randi() % anims.size()])

	if not Engine.is_editor_hint():
		var explosion_rad = get_explosion_radius()
		var rect_size = explosion_rad * 2.5
		_danger_indicator = ColorRect.new()
		_danger_indicator.size = Vector2(rect_size, rect_size)
		_danger_indicator.position = -_danger_indicator.size / 2.0
		_danger_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var shader = load("res://Shaders/dashed_circle.gdshader")
		if shader:
			_shader_material = ShaderMaterial.new()
			_shader_material.shader = shader
			_shader_material.set_shader_parameter("quality", 1.0)
			_danger_indicator.material = _shader_material
			
		add_child(_danger_indicator)
		move_child(_danger_indicator, 0)
		
		# Setup PointLight2D
		_point_light = PointLight2D.new()
		var tex = GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		var grad = Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		tex.gradient = grad
		tex.width = int(explosion_rad * 2.5)
		tex.height = int(explosion_rad * 2.5)
		_point_light.texture = tex
		_point_light.blend_mode = Light2D.BLEND_MODE_ADD
		_point_light.energy = 0.5
		add_child(_point_light)
		
	if _col_mina:
		_col_mina.disabled = false

	add_to_group("objects")
	add_to_group("damageable")
	add_to_group("team_" + str(team_id))
	
	_refresh_level_membership()
	_apply_collision_layers()
	_connect_to_player()
	_setup_global_settings()
	
	# Connect the Area2D's body_entered signal for collision detection
	body_entered.connect(_on_body_entered)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if _exploded:
		if _danger_indicator and _danger_indicator.visible:
			_danger_indicator.visible = false
		if _point_light and _point_light.visible:
			_point_light.visible = false
		return
		
	if _player_node and is_instance_valid(_player_node):
		var dist = global_position.distance_to(_player_node.global_position)
		var trigger_rad = get_explosion_radius() * 1.5
		
		# Determine team colors
		var is_friendly = false
		var player_team = _get_team_id(_player_node)
		if player_team != -1 and player_team == team_id:
			is_friendly = true
			
		var target_color = Color(0.0, 1.0, 0.0) if is_friendly else Color(1.0, 0.0, 0.0)
		var base_safe_color = Color(1.0, 1.0, 1.0) # Bianco
		var deep_safe_color = Color(0.0, 0.6, 1.0) # Blu
		
		if dist < trigger_rad:
			var danger = 1.0 - (dist / trigger_rad)
			if _point_light:
				_point_light.color = target_color
				_point_light.energy = lerp(0.8, 1.2, clamp(danger, 0.0, 1.0))
			if _danger_indicator:
				_danger_indicator.color = target_color
		else:
			var breathe_val = (sin(Time.get_ticks_msec() * 0.003) * 0.5) + 0.5
			var breathed_color = base_safe_color.lerp(deep_safe_color, breathe_val)
			if _point_light:
				_point_light.color = breathed_color
				var breathe = (sin(Time.get_ticks_msec() * 0.003) * 0.15) + 0.35
				_point_light.energy = breathe
			if _danger_indicator:
				_danger_indicator.color = breathed_color

func _on_body_entered(body: Node2D) -> void:
	if _exploded:
		return
		
	# Rileva se il corpo è un player o bot su cui disabilitare la collisione fisica
		
	# Verifica il livello di altezza del target rispetto a questa mina
	var target_level: int = livello
	if "livello" in body:
		target_level = body.get("livello")
	elif "current_height_level" in body:
		target_level = body.get("current_height_level")
		
	if target_level != livello:
		return
		
	# Calcola il team del corpo
	var body_team := _get_team_id(body)
	if body_team != team_id:
		# Nemico o entità non allineata calpesta la mina -> Esplosione!
		_explode()

# ---------------------------------------------------------------------------
# Danno e distruzione
# ---------------------------------------------------------------------------

func apply_damage(amount: float, source: Node = null) -> void:
	if _exploded or vita <= 0.0:
		return

	vita = maxf(vita - amount, 0.0)
	if vita <= 0.0:
		_explode()

func get_explosion_radius() -> float:
	if _col_explosion and _col_explosion.shape is CircleShape2D:
		return _col_explosion.shape.radius
	return explosion_radius

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	
	var radius := get_explosion_radius()
	for body: Node in get_tree().get_nodes_in_group("damageable"):
		if body == self:
			continue
		if not body.has_method("apply_damage"):
			continue
		
		# Verifica il livello di altezza del target rispetto a questa mina
		var target_level: int = livello
		if "livello" in body:
			target_level = body.get("livello")
		elif "current_height_level" in body:
			target_level = body.get("current_height_level")
		
		if target_level != livello:
			continue
			
		var target := body as Node2D
		if target == null:
			continue
		var dist: float = global_position.distance_to(target.global_position)
		if dist > radius:
			continue
		var falloff: float = 1.0 - (dist / radius)
		body.call("apply_damage", explosion_damage * falloff)
	
	# Disabilita collisioni fisiche
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
		
	# Nasconde immediatamente indicatori e luci
	if _danger_indicator:
		_danger_indicator.visible = false
	if _point_light:
		_point_light.visible = false
	
	# Rimuove il materiale shader per riprodurre l'esplosione senza effetti
	if _sprite:
		_sprite.material = null
	
	# Avvia l'animazione di esplosione
	if _sprite.sprite_frames.has_animation(&"Esplosione"):
		_sprite.animation = &"Esplosione"
		
		# Sincronizza visivamente lo sprite dell'esplosione con il raggio reale,
		# rendendola un po' più grande (moltiplicata per 1.4).
		var target_scale := (radius * 2.0 * 1.4) / 256.0
		_sprite.scale = Vector2(target_scale, target_scale)
		
		_sprite.play()
		_sprite.animation_finished.connect(func(): _sprite.visible = false, CONNECT_ONE_SHOT)

	# Avvia le particelle dell'esplosione regolate in base al raggio (se la qualità non è bassa)
	var global_settings = get_node_or_null("/root/GlobalSettings")
	var preset := 2
	if global_settings:
		preset = global_settings.call("get_setting", "graphics_preset", 2)

	if _particles and preset > 0:
		_particles.emission_sphere_radius = radius
		_particles.initial_velocity_min = radius * 0.4
		_particles.initial_velocity_max = radius * 1.2
		_particles.scale_amount_min = maxf(4.0, radius * 0.015)
		_particles.scale_amount_max = maxf(12.0, radius * 0.045)
		_particles.emitting = true

	# Attende il completamento delle particelle prima di distruggere l'oggetto
	await get_tree().create_timer(0.8).timeout
	queue_free()

# ---------------------------------------------------------------------------
# Utility Team
# ---------------------------------------------------------------------------

func _get_team_id(node: Node) -> int:
	for group in node.get_groups():
		if group.begins_with("team_"):
			return int(group.get_slice("_", 1))
	return -1

# ---------------------------------------------------------------------------
# Collision layer/mask — sincronizzate con livello
# ---------------------------------------------------------------------------

func _apply_collision_layers() -> void:
	var base_layer := livello * 3 + 1
	var wall_bit := 1 << (base_layer - 1)
	var character_bit := 1 << base_layer
	
	# Configura l'Area2D per rilevare nemici, bot e proiettili dello stesso livello
	# L'Area2D non ha collisioni fisiche, solo rilevamento
	collision_layer = wall_bit
	collision_mask = character_bit

# ---------------------------------------------------------------------------
# Gruppi livello
# ---------------------------------------------------------------------------

func _refresh_level_membership() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	for lv: int in _registered_levels:
		remove_from_group("entities_level_" + str(lv))
	_registered_levels.clear()
	add_to_group("entities_level_" + str(livello))
	_registered_levels.append(livello)

# ---------------------------------------------------------------------------
# Visibilità player
# ---------------------------------------------------------------------------

func is_visible_from_level(player_level: int) -> bool:
	return player_level == livello

func _connect_to_player() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_setup_player_connection(players[0] as Node2D)
	else:
		get_tree().process_frame.connect(_connect_to_player, CONNECT_ONE_SHOT)

func _setup_player_connection(player: Node2D) -> void:
	_player_node = player
	if player.has_signal("height_level_changed"):
		if not player.height_level_changed.is_connected(_on_player_height_level_changed):
			player.height_level_changed.connect(_on_player_height_level_changed)
	if "current_height_level" in player:
		_apply_for_player_level(player.current_height_level)

func _on_player_height_level_changed(player_level: int) -> void:
	_apply_for_player_level(player_level)

func _apply_for_player_level(player_level: int) -> void:
	visible = is_visible_from_level(player_level)
	z_index = (player_level if is_visible_from_level(player_level) else livello) * 10 + 1

# ---------------------------------------------------------------------------
# Impostazioni grafiche globali
# ---------------------------------------------------------------------------

func _setup_global_settings() -> void:
	var global_settings = get_node_or_null("/root/GlobalSettings")
	if global_settings:
		if global_settings.has_signal("settings_changed"):
			if not global_settings.settings_changed.is_connected(_on_settings_changed):
				global_settings.settings_changed.connect(_on_settings_changed)
		var preset: int = global_settings.call("get_setting", "graphics_preset", 2)
		_apply_graphics_settings(preset)

func _on_settings_changed(new_settings: Dictionary) -> void:
	var preset: int = new_settings.get("graphics_preset", 2)
	_apply_graphics_settings(preset)

func _apply_graphics_settings(preset: int) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("quality", 0.0 if preset == 0 else 1.0)
		
	if _point_light:
		_point_light.shadow_enabled = (preset >= 3) # Attiva ombre solo su preset Ultra (3)

	if _sprite and _sprite.sprite_frames.has_animation(&"Esplosione"):
		match preset:
			0:
				_sprite.sprite_frames.set_animation_speed(&"Esplosione", 6.0)
			1:
				_sprite.sprite_frames.set_animation_speed(&"Esplosione", 9.0)
			_:
				_sprite.sprite_frames.set_animation_speed(&"Esplosione", 12.0)

	if _particles:
		match preset:
			0:
				_particles.amount = 1
			1:
				_particles.amount = 40
			_:
				_particles.amount = 120

# ---------------------------------------------------------------------------
# Editor
# ---------------------------------------------------------------------------

func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	visible = true
	z_index = livello * 10 + 1
	update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if vita_max <= 0.0:
		w.append("vita_max deve essere > 0.")
	return w
