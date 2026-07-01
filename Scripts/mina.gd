## mina.gd
## Oggetto Mina Esplosiva.
## Esplode se calpestata da un nemico o colpita da un proiettile nemico.

@tool
extends Area2D
class_name Mina

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------

signal exploded(pos: Vector2, noise_radius: float)
signal hacking_started()
signal hacking_completed(new_team_id: int)

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

@export var explosion_damage: float = 100.0
@export var explosion_radius: float = 1200.0

@export_group("Hacking")
@export var hackable: bool = true
@export var hack_duration: float = 3.0
@export var hack_bar_vertical_offset: float = 60.0
@export var hack_bar_size: Vector2 = Vector2(160.0, 34.0)

@export_group("Difficoltà")
## 0=Facile 1=Normale 2=Difficile 3=Agente Caduto
@export_range(0, 3, 1) var difficulty_level: int = 1
## Se true, legge la difficoltà da GlobalSettings automaticamente.
@export var use_global_difficulty: bool = true

## Moltiplicatori difficoltà — [Facile, Normale, Difficile, Agente Caduto]
const DIFFICULTY_MULTIPLIERS: Array[Dictionary] = [
	{ "danno": 0.65, "vita": 0.65, "hack_duration": 0.8 },
	{ "danno": 1.00, "vita": 1.00, "hack_duration": 1.0 },
	{ "danno": 1.35, "vita": 1.35, "hack_duration": 1.2 },
	{ "danno": 1.80, "vita": 1.80, "hack_duration": 1.5 },
]

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

var _is_hacking: bool = false
var _hack_progress: float = 0.0
var _hack_bar_progress: float = 0.0
var _hack_bar_pivot: Node2D = null
var _hack_target_team: int = 1  ## Team a cui passa dopo l'hack (gestito dinamicamente)
var _entities_in_hacking_range: Array[Node2D] = []

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

	# Risolvi e applica difficoltà
	_resolve_difficulty()
	_apply_difficulty()
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
	if _col_explosion:
		_col_explosion.disabled = false

	add_to_group("objects")
	add_to_group("damageable")
	add_to_group("team_" + str(team_id))
	add_to_group("explodable")
	
	_refresh_level_membership()
	_apply_collision_layers()
	_connect_to_player()
	_setup_global_settings()
	
	# Usa i segnali "shape-aware" per distinguere quale CollisionShape2D
	# ha generato l'evento (CollisionMina vs CollisionExplosione), dato che
	# entrambe appartengono allo stesso Area2D.
	body_shape_entered.connect(_on_body_shape_entered)
	body_shape_exited.connect(_on_body_shape_exited)

	# Inizializza hack bar
	if not Engine.is_editor_hint():
		_crea_hack_bar()
		if _hack_bar_pivot:
			_hack_bar_pivot.visible = false

# ---------------------------------------------------------------------------
# Sistema Difficoltà
# ---------------------------------------------------------------------------

func _resolve_difficulty() -> void:
	if use_global_difficulty:
		var global_settings = get_node_or_null("/root/GlobalSettings")
		if global_settings:
			difficulty_level = global_settings.call("get_setting", "difficulty", 1)
	# In multiplayer, forza sempre difficoltà normale (1)
	if multiplayer.has_multiplayer_peer():
		difficulty_level = 1

func _apply_difficulty() -> void:
	var mults = DIFFICULTY_MULTIPLIERS[clampi(difficulty_level, 0, DIFFICULTY_MULTIPLIERS.size() - 1)]
	explosion_damage *= mults["danno"]
	vita_max *= mults["vita"]
	hack_duration *= mults["hack_duration"]

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if _exploded:
		if _danger_indicator and _danger_indicator.visible:
			_danger_indicator.visible = false
		if _point_light and _point_light.visible:
			_point_light.visible = false
		return

	# Hacking progress
	if _is_hacking:
		_hack_progress += delta
		_hack_bar_progress = clampf(_hack_progress / hack_duration, 0.0, 1.0)
		_update_hack_bar()
		if _hack_progress >= hack_duration:
			_complete_hack()
		return

	# Gestione hacking da parte del player (tiene premuto il tasto hack nel raggio)
	if hackable and not _is_hacking:
		for body in _entities_in_hacking_range:
			if not is_instance_valid(body):
				continue
			if not body.is_in_group("players"):
				continue
			var player_team := _get_team_id(body)
			if player_team == team_id:
				continue  # Ormai alleato (es. mina appena hackerata): niente barra
			if Input.is_action_pressed("hack"):
				print("[MINE] Player (team %d) inizia hack mina (team %d)" % [player_team, team_id])
				start_hack(player_team)
				break
		
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

func _on_body_shape_entered(_body_rid: RID, body: Node2D, _body_shape_index: int, local_shape_index: int) -> void:
	var shape_node := _shape_node_from_local_index(local_shape_index)

	if shape_node == _col_mina:
		_handle_mina_entered(body)
	elif shape_node == _col_explosion:
		_handle_hack_range_entered(body)

func _on_body_shape_exited(_body_rid: RID, body: Node2D, _body_shape_index: int, local_shape_index: int) -> void:
	var shape_node := _shape_node_from_local_index(local_shape_index)

	if shape_node == _col_explosion:
		_handle_hack_range_exited(body)

func _shape_node_from_local_index(local_shape_index: int) -> CollisionShape2D:
	var owner_id := shape_find_owner(local_shape_index)
	return shape_owner_get_owner(owner_id) as CollisionShape2D

func _handle_mina_entered(body: Node2D) -> void:
	if _exploded:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

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
	if body_team == team_id:
		return  # Alleato: ignora

	# Qualsiasi entità di team diverso → esplode immediatamente
	print("[MINE] Entità '%s' (team %d) calpesta la mina (team %d) - ESPLOSIONE" % [body.name, body_team, team_id])
	if multiplayer.has_multiplayer_peer():
		_trigger_explosion_rpc.rpc()
	else:
		_trigger_explosion_rpc()

func _handle_hack_range_entered(body: Node2D) -> void:
	if not hackable or _exploded:
		return
	if not body.is_in_group("players"):
		return

	# Verifica il livello di altezza del target rispetto a questa mina
	var target_level: int = livello
	if "livello" in body:
		target_level = body.get("livello")
	elif "current_height_level" in body:
		target_level = body.get("current_height_level")

	if target_level != livello:
		return

	# Solo un player di un team avversario può hackerare la mina
	var body_team := _get_team_id(body)
	if body_team == team_id:
		return  # Alleato: non hackerabile dal proprio team

	if not _entities_in_hacking_range.has(body):
		_entities_in_hacking_range.append(body)
		print("[MINE] Player '%s' (team %d) entrato nel raggio di hacking della mina (team %d)" % [body.name, body_team, team_id])

func _handle_hack_range_exited(body: Node2D) -> void:
	_entities_in_hacking_range.erase(body)
	if _entities_in_hacking_range.is_empty() and _is_hacking:
		print("[MINE] Entità uscita dal raggio, hack annullato")
		cancel_hack()

# ---------------------------------------------------------------------------
# Danno e distruzione
# ---------------------------------------------------------------------------

func apply_damage(amount: float, _source: Node = null) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _exploded or vita <= 0.0:
		return

	vita = maxf(vita - amount, 0.0)
	if vita <= 0.0:
		if multiplayer.has_multiplayer_peer():
			_trigger_explosion_rpc.rpc()
		else:
			_trigger_explosion_rpc()

@rpc("authority", "call_local", "reliable")
func _trigger_explosion_rpc() -> void:
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
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
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
			body.call("apply_damage", explosion_damage * falloff, self)
	
	# Disabilita collisioni fisiche
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	
	exploded.emit(global_position, radius * 1.5)
		
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
		var local_player: Node2D = null
		for p in players:
			if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
				local_player = p
				break
		if not local_player:
			local_player = players[0]
		_setup_player_connection(local_player)
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

# ---------------------------------------------------------------------------
# Hacking
# ---------------------------------------------------------------------------

func start_hack(new_team: int = -1) -> void:
	if not hackable or _exploded or _is_hacking:
		return
	if new_team >= 0:
		_hack_target_team = new_team
	_is_hacking = true
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = true
		_update_hack_bar()
	hacking_started.emit()

func cancel_hack() -> void:
	if not _is_hacking:
		return
	_is_hacking = false
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false

func _complete_hack() -> void:
	_is_hacking = false
	_hack_progress = 0.0
	_hack_bar_progress = 0.0
	if _hack_bar_pivot:
		_hack_bar_pivot.visible = false
	
	# Cambia team
	team_id = _hack_target_team
	
	# Aggiorna gruppi
	for group in get_groups():
		if group.begins_with("team_"):
			remove_from_group(group)
	add_to_group("team_" + str(team_id))
	
	_apply_collision_layers()
	
	# Rimuove dal raggio di hacking chi ora è diventato alleato,
	# così non può ri-hackerare (o mostrare la barra su) una mina già sua
	for i in range(_entities_in_hacking_range.size() - 1, -1, -1):
		var body := _entities_in_hacking_range[i]
		if not is_instance_valid(body) or _get_team_id(body) == team_id:
			_entities_in_hacking_range.remove_at(i)
	
	hacking_completed.emit(team_id)

func _crea_hack_bar() -> void:
	var pivot := Node2D.new()
	pivot.name = "HackBarPivot"
	pivot.z_index = 1000
	pivot.z_as_relative = false
	add_child(pivot)
	pivot.global_position = global_position + Vector2(0, -hack_bar_vertical_offset)
	pivot.global_rotation = 0.0

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.06, 0.06, 0.08, 0.92)
	bg.size = hack_bar_size + Vector2(6, 6)
	bg.position = -(hack_bar_size + Vector2(6, 6)) * 0.5
	pivot.add_child(bg)

	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBG"
	bar_bg.color = Color(0.15, 0.15, 0.18, 1.0)
	bar_bg.size = hack_bar_size
	bar_bg.position = -hack_bar_size * 0.5
	pivot.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.name = "BarFill"
	bar_fill.color = Color(0.0, 0.85, 1.0, 1.0)
	bar_fill.size = Vector2(0.0, hack_bar_size.y)
	bar_fill.position = -hack_bar_size * 0.5
	pivot.add_child(bar_fill)

	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.0, 0.9, 1.0, 0.7)
	border.size = hack_bar_size + Vector2(4, 4)
	border.position = -(hack_bar_size + Vector2(4, 4)) * 0.5
	pivot.add_child(border)
	border.z_index = 1

	var label := Label.new()
	label.name = "Label"
	label.size = hack_bar_size
	label.position = -hack_bar_size * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 2
	pivot.add_child(label)

	_hack_bar_pivot = pivot

func _update_hack_bar() -> void:
	if not _hack_bar_pivot or not is_node_ready():
		return

	var fill := _hack_bar_pivot.get_node_or_null("BarFill") as ColorRect
	if fill:
		fill.size.x = hack_bar_size.x * _hack_bar_progress
		fill.color = Color(0.0, 0.85, 1.0).lerp(Color(0.1, 1.0, 0.4), _hack_bar_progress)

	var label := _hack_bar_pivot.get_node_or_null("Label") as Label
	if label:
		label.text = "HACK %d%%" % int(_hack_bar_progress * 100.0)
