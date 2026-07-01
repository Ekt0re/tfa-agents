## oggetto.gd
## Oggetto distruttibile (Cassa / Barile Esplosivo).
## Scena unica: il tipo configura animazione, collision e comportamento di distruzione.

@tool
extends StaticBody2D
class_name Oggetto

# ---------------------------------------------------------------------------
# Segnali
# ---------------------------------------------------------------------------

signal exploded(pos: Vector2, noise_radius: float)

# ---------------------------------------------------------------------------
# Tipi
# ---------------------------------------------------------------------------

enum Tipo { CASSA, BARILE_ESPLOSIVO }

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

@export_group("Oggetto")

@export var tipo: Tipo = Tipo.CASSA:
	set(value):
		tipo = value
		_apply_tipo()

@export var vita_max: float = 100.0

@export_group("Livello")

@export_range(0, 15, 1) var livello: int = 0:
	set(value):
		livello = maxi(value, 0)
		_refresh_level_membership()
		_apply_collision_layers()
		_update_editor_preview()

@export_group("Esplosione")

@export var explosion_damage: float = 100.0
@export var explosion_radius: float = 2000.0

@export_group("Difficoltà")
## 0=Facile 1=Normale 2=Difficile 3=Agente Caduto
@export_range(0, 3, 1) var difficulty_level: int = 1
## Se true, legge la difficoltà da GlobalSettings automaticamente.
@export var use_global_difficulty: bool = true

## Moltiplicatori difficoltà — [Facile, Normale, Difficile, Agente Caduto]
const DIFFICULTY_MULTIPLIERS: Array[Dictionary] = [
	{ "danno": 0.65, "vita": 0.65 },
	{ "danno": 1.00, "vita": 1.00 },
	{ "danno": 1.35, "vita": 1.35 },
	{ "danno": 1.80, "vita": 1.80 },
]

# ---------------------------------------------------------------------------
# Stato interno
# ---------------------------------------------------------------------------

var vita: float = 0.0
var _crack_material: ShaderMaterial
var _registered_levels: Array[int] = []

@onready var _sprite: AnimatedSprite2D     = $AnimatedSprite2D
@onready var _col_cassa: CollisionShape2D  = $CollisionCassa
@onready var _col_barile: CollisionShape2D = $CollisionBarile
@onready var _col_explosion: CollisionShape2D = $CollisionExplosione
@onready var _particles: CPUParticles2D = $ExplosionParticles

# ---------------------------------------------------------------------------
# Ciclo di vita
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_tipo()
		_update_editor_preview()
		return

	# Risolvi e applica difficoltà
	_resolve_difficulty()
	_apply_difficulty()
	vita = vita_max

	add_to_group("objects")
	add_to_group("damageable")
	add_to_group("item")
	add_to_group("explodable")
	
	
	_apply_tipo()
	_setup_crack_shader()
	_refresh_level_membership()
	_apply_collision_layers()
	_connect_to_player()
	_setup_global_settings()

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

# ---------------------------------------------------------------------------
# Tipo → animazione + collision
# ---------------------------------------------------------------------------

func _apply_tipo() -> void:
	if not is_node_ready():
		return

	match tipo:
		Tipo.CASSA:
			_sprite.animation = &"Cassa"
			_col_cassa.disabled  = false
			_col_barile.disabled = true
			add_to_group("Cassa")

		Tipo.BARILE_ESPLOSIVO:
			_sprite.animation = &"Barile"
			_col_barile.disabled = false
			_col_cassa.disabled  = true
			add_to_group("Barile")

	if not Engine.is_editor_hint():
		_sprite.play()

# ---------------------------------------------------------------------------
# Shader crepe
# ---------------------------------------------------------------------------

func _setup_crack_shader() -> void:
	var shader := load("res://Shaders/crack_shader.gdshader") as Shader
	if shader == null:
		push_warning("Oggetto: crack_shader.gdshader non trovato in res://Shaders/")
		return

	_crack_material = ShaderMaterial.new()
	_crack_material.shader = shader
	_sprite.material = _crack_material

	match tipo:
		Tipo.CASSA:
			_crack_material.set_shader_parameter("crack_scale", 8.0)
			_crack_material.set_shader_parameter("crack_width", 0.015)
		Tipo.BARILE_ESPLOSIVO:
			_crack_material.set_shader_parameter("crack_scale", 12.0)
			_crack_material.set_shader_parameter("crack_width", 0.01)
			
func _update_crack_shader() -> void:
	if _crack_material == null:
		return
	var damage_ratio: float = 1.0 - clampf(vita / vita_max, 0.0, 1.0)
	_crack_material.set_shader_parameter("damage_ratio", damage_ratio)

# ---------------------------------------------------------------------------
# Danno e distruzione
# ---------------------------------------------------------------------------

func apply_damage(amount: float, _source: Node = null) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if vita <= 0.0:
		return
	vita = maxf(vita - amount, 0.0)
	if multiplayer.has_multiplayer_peer():
		_sync_vita.rpc(vita)
	else:
		_sync_vita(vita)
	
	if vita <= 0.0:
		destroy()

@rpc("authority", "call_local", "reliable")
func _sync_vita(new_vita: float) -> void:
	vita = new_vita
	_update_crack_shader()

func destroy() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if multiplayer.has_multiplayer_peer():
		_replicate_destroy.rpc()
	else:
		_replicate_destroy()

@rpc("authority", "call_local", "reliable")
func _replicate_destroy() -> void:
	match tipo:
		Tipo.CASSA:
			_destroy_cassa()
		Tipo.BARILE_ESPLOSIVO:
			_explode()


func _destroy_cassa() -> void:
	# TODO: particelle legno, suono
	queue_free()

func get_explosion_radius() -> float:
	if _col_explosion and _col_explosion.shape is CircleShape2D:
		return _col_explosion.shape.radius
	return explosion_radius

func _explode() -> void:
	var radius := get_explosion_radius()
	
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		for body: Node in get_tree().get_nodes_in_group("damageable"):
			if body == self:
				continue
			if not body.has_method("apply_damage"):
				continue
			
			# Verifica il livello di altezza del target rispetto a questo barile
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

	
	# Disabilita collisioni fisiche per evitare ulteriori interazioni
	collision_layer = 0
	collision_mask = 0
	_col_barile.disabled = true
	_col_cassa.disabled = true
	
	exploded.emit(global_position, radius * 1.5)
	
	# Rimuove il materiale shader per riprodurre l'esplosione senza crepe
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
# Collision layer/mask — sincronizzate con livello
# ---------------------------------------------------------------------------

func _apply_collision_layers() -> void:
	
	var base_layer := livello * 3 + 1
	collision_layer = 1 << (base_layer - 1)
	collision_mask = 0
	collision_mask |= 1 << base_layer      # layer successivo
	collision_mask |= 1 << (base_layer + 1) # layer ancora successivo

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
	if preset == 0:
		_sprite.material = null
	else:
		_sprite.material = _crack_material
		_update_crack_shader()

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
