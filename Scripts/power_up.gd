@tool
extends Area2D
class_name PowerUp

enum PowerUpType {
	HEAL,
	AMMO,
	MONEY,
	CHEST,
	STAR,
	MYSTERY
}

@export var type: PowerUpType = PowerUpType.HEAL:
	set(value):
		type = value
		update_animation()
		
@export_range(0, 15, 1) var livello: int = 0:
	set(value):
		livello = maxi(value, 0)
		_apply_collision_layers()
		_update_editor_preview()

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var point_light: PointLight2D = $PointLight2D

var _time_passed: float = 0.0
var _quality: int = 3
var _glow_material: ShaderMaterial
var _player_node: Node2D

func _ready() -> void:
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		if GlobalSettings.has_signal("settings_changed"):
			GlobalSettings.settings_changed.connect(_on_settings_changed)
		_quality = int(GlobalSettings.get_setting("graphics_preset", 3))
	else:
		_quality = 3
		_update_editor_preview()

	_setup_shader()
	update_animation()
	_apply_quality()
	
	_apply_collision_layers()
	_connect_to_player()
	
	add_to_group(str(type))
	add_to_group("item")

func _setup_shader() -> void:
	_glow_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 5.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = c + c * intensity * c.a;
}
"""
	_glow_material.shader = shader
	if animated_sprite:
		animated_sprite.material = _glow_material

func _on_settings_changed(settings: Dictionary) -> void:
	_quality = int(settings.get("graphics_preset", 3))
	_apply_quality()

func _apply_quality() -> void:
	if point_light:
		point_light.visible = _quality > 0
		point_light.shadow_enabled = (_quality >= 2)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		pass # Le animazioni funzionano anche nell'editor
		
	if _quality == 0:
		if animated_sprite:
			animated_sprite.scale = Vector2(1, 1)
		if _glow_material:
			_glow_material.set_shader_parameter("intensity", 0.0)
		if point_light:
			point_light.energy = 0.6
		return

	_time_passed += delta
	var breath_intensity: float = float(_quality) / 3.0
	var breath = sin(_time_passed * 3.0) * breath_intensity
	
	if animated_sprite:
		var scale_val = 1.0 + breath * 0.05
		animated_sprite.scale = Vector2(scale_val, scale_val)
		
	if _glow_material:
		var shader_intensity = max(0.0, breath * 1.5) if _quality >= 2 else 0.0
		_glow_material.set_shader_parameter("intensity", shader_intensity)
		
	if point_light:
		point_light.energy = 0.8 + breath * 0.3

func update_animation() -> void:
	if not is_inside_tree() or animated_sprite == null:
		return
		
	match type:
		PowerUpType.HEAL:
			animated_sprite.play("Cura")
		PowerUpType.AMMO:
			animated_sprite.play("Munizioni")
		PowerUpType.MONEY:
			animated_sprite.play("Crediti")
		PowerUpType.CHEST:
			animated_sprite.play("Armi")
		PowerUpType.STAR:
			animated_sprite.play("Collezionabile")
		PowerUpType.MYSTERY:
			animated_sprite.play("Mistero")

func _on_body_entered(body: Node2D) -> void:
	if Engine.is_editor_hint():
		return
		
	# Verifica il livello di altezza del target rispetto a questo item
	var target_level: int = livello
	if "livello" in body:
		target_level = body.get("livello")
	elif "current_height_level" in body:
		target_level = body.get("current_height_level")
		
	if target_level != livello:
		return
		
	if body.is_in_group("players") or body.name == "Player":
		# Solo il server gestisce la scomparsa logica del power up
		# Oppure se l'oggetto locale distrugge se stesso
		
		# Emetti il segnale globale solo per l'authority
		if _is_local_authority(body):
			GameEvents.powerup_collected.emit(type, livello)
			
		# Applica gli effetti al player specifico che ha raccolto il power up
		apply_effect(body)
			
		# Distruggi il powerup localmente e per tutti (via spawner se previsto)
		queue_free()

func _is_local_authority(body: Node2D) -> bool:
	if not multiplayer.has_multiplayer_peer(): return true
	if body.has_method("is_multiplayer_authority") and body.is_multiplayer_authority():
		return true
	return false

func apply_effect(player: Node2D) -> void:
	match type:
		PowerUpType.HEAL:
			if multiplayer.has_multiplayer_peer():
				if player.has_method("rpc_heal"):
					player.rpc_heal(10)
			else:
				if player.has_method("heal"):
					player.heal(10)
			_show_subtitle_if_local(player, "POWERUP_COLLECTED_HEAL")
		PowerUpType.AMMO:
			if multiplayer.has_multiplayer_peer():
				if player.has_method("rpc_add_ammo"):
					player.rpc_add_ammo(5)
			else:
				if player.has_method("add_ammo"):
					player.add_ammo(5)
			_show_subtitle_if_local(player, "POWERUP_COLLECTED_AMMO")
		PowerUpType.MONEY:
			if multiplayer.has_multiplayer_peer():
				if player.has_method("rpc_add_money"):
					player.rpc_add_money(10)
			else:
				if player.has_method("add_money"):
					player.add_money(10)
			_show_subtitle_if_local(player, "POWERUP_COLLECTED_MONEY")
		PowerUpType.CHEST:
			_show_subtitle_if_local(player, "POWERUP_COLLECTED_CHEST")
		PowerUpType.STAR:
			_show_subtitle_if_local(player, "POWERUP_COLLECTED_STAR")
		PowerUpType.MYSTERY:
			_show_subtitle_if_local(player, "POWERUP_COLLECTED_MYSTERY")

func _show_subtitle_if_local(player: Node2D, text_key: String) -> void:
	if _is_local_authority(player):
		if GlobalSettings.has_method("show_subtitle"):
			GlobalSettings.show_subtitle(tr(text_key))

# ---------------------------------------------------------------------------
# Gestione Piani (Ispirata a mina.gd)
# ---------------------------------------------------------------------------

func _apply_collision_layers() -> void:
	var base_layer := livello * 3 + 1
	var wall_bit := 1 << (base_layer - 1)
	var character_bit := 1 << base_layer
	
	# Configura l'Area2D per rilevare i player del livello corretto
	collision_layer = wall_bit
	collision_mask = character_bit

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

func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	visible = true
	z_index = livello * 10 + 1
