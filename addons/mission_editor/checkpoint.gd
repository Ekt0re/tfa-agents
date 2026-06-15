## checkpoint.gd
## Area2D Checkpoint — posizionabile nella scena.
## Quando il player (gruppo "players") entra nell'area, interagisce con
## MissionManager e MissionFlowPlayer per completare missioni REACH/ACTIVATE.
@tool
extends Area2D
class_name CheckPoint

## ID univoco del checkpoint (referenziato nei flussi di missione)
@export var checkpoint_id: String = ""

## Se true, il checkpoint si disattiva dopo il primo trigger
@export var one_shot: bool = true

## Raggio visivo dell'area (modifica il CollisionShape2D)
@export var radius: float = 64.0:
	set(value):
		radius = value
		_update_shape()

## Colore del checkpoint nell'editor e in-game
@export var checkpoint_color: Color = Color(0.0, 0.898039, 1.0, 0.6)

## Se true, completa automaticamente la missione REACH quando il player entra
@export var auto_complete_reach: bool = true

## Label mostrato quando il player è vicino (opzionale)
@export var display_label: String = ""

## Se true, il checkpoint è attivo (può essere toggolato da comandi)
@export var is_active: bool = true:
	set(value):
		is_active = value
		monitoring = is_active
		_update_visual()

# Nodi interni
var _collision_shape: CollisionShape2D = null
var _visual: Node2D = null
var _label_node: Label = null
var _triggered: bool = false


func _ready() -> void:
	# Configura nodi figli se non esistono
	_setup_collision_shape()
	if not Engine.is_editor_hint():
		_setup_runtime()
	else:
		_setup_editor_visual()


func _setup_collision_shape() -> void:
	_collision_shape = get_node_or_null("CollisionShape2D")
	if not _collision_shape:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		add_child(_collision_shape)
		_collision_shape.owner = self
	var shape := CircleShape2D.new()
	shape.radius = radius
	_collision_shape.shape = shape


func _update_shape() -> void:
	if _collision_shape and _collision_shape.shape is CircleShape2D:
		(_collision_shape.shape as CircleShape2D).radius = radius
	elif _collision_shape:
		var shape := CircleShape2D.new()
		shape.radius = radius
		_collision_shape.shape = shape


func _setup_editor_visual() -> void:
	# Nell'editor disegna un cerchio colorato
	_visual = get_node_or_null("Visual")
	if not _visual:
		_visual = Node2D.new()
		_visual.name = "Visual"
		add_child(_visual)
		_visual.owner = self
		_visual.set_script(_get_draw_script())
	_update_visual()


func _setup_runtime() -> void:
	# Registra con MissionFlowPlayer se esiste
	var flow_player := get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_method("register_checkpoint"):
		flow_player.register_checkpoint(checkpoint_id, self)

	# Connetti al segnale body_entered
	body_entered.connect(_on_body_entered)

	# Crea label opzionale
	if not display_label.is_empty():
		_label_node = Label.new()
		_label_node.text = display_label
		_label_node.position = Vector2(-50, -radius - 30)
		_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label_node.add_theme_color_override("font_color", checkpoint_color)
		add_child(_label_node)

	# Visualizzazione runtime: cerchio semi-trasparente
	_visual = get_node_or_null("Visual")
	if not _visual:
		_visual = Node2D.new()
		_visual.name = "Visual"
		add_child(_visual)
	_visual.set_script(_get_runtime_draw_script())
	_update_visual()


func _on_body_entered(body: Node2D) -> void:
	if Engine.is_editor_hint():
		return
	if not is_active or _triggered:
		return
	# Controlla se è il player
	if not body.is_in_group("players"):
		return

	_triggered = true

	# Notifica MissionFlowPlayer
	var flow_player := get_node_or_null("/root/MissionFlowPlayer")
	if flow_player and flow_player.has_signal("checkpoint_reached"):
		flow_player.checkpoint_reached.emit(checkpoint_id)

	# Auto-completa missioni REACH se la missione attiva ha questo target
	if auto_complete_reach:
		var active: Resource = MissionManager.active_mission
		if active and active is MissionData:
			var data := active as MissionData
			if data.type == MissionData.Type.REACH:
				# Verifica se il checkpoint_id è nel label o nel mission_id
				if data.mission_id.find(checkpoint_id) != -1 or \
				   data.label.to_upper().find(checkpoint_id.to_upper()) != -1:
					MissionManager.complete()
			elif data.type == MissionData.Type.ACTIVATE:
				if data.mission_id.find(checkpoint_id) != -1 or \
				   data.label.to_upper().find(checkpoint_id.to_upper()) != -1:
					MissionManager.complete()

	# Effetto visivo di attivazione
	_play_activation_effect()

	if one_shot:
		is_active = false


func _play_activation_effect() -> void:
	# Semplice effetto: lampeggia e riduci opacità
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0.3), 0.3)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0.0), 0.5)


func _update_visual() -> void:
	if _visual:
		_visual.queue_redraw()


## Resetta il checkpoint per riutilizzo
func reset() -> void:
	_triggered = false
	is_active = true
	modulate = Color(1, 1, 1, 1)


## Disegna il checkpoint nell'editor
func _draw() -> void:
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, checkpoint_color, 2.0)
		draw_circle(Vector2.ZERO, 8.0, checkpoint_color)
		if not checkpoint_id.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(-checkpoint_id.length() * 4, -radius - 8),
				checkpoint_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, checkpoint_color)


## Script dinamico per il disegno editor
func _get_draw_script() -> GDScript:
	var script_src := """extends Node2D
func _draw():
	get_parent()._draw_checkpoint_visual()
"""
	var script := GDScript.new()
	script.source_code = script_src
	script.reload()
	return script


## Script runtime per il disegno del checkpoint
func _get_runtime_draw_script() -> GDScript:
	var script_src := """extends Node2D
var _parent_ref: Area2D = null

func _ready():
	_parent_ref = get_parent()

func _draw():
	if _parent_ref and _parent_ref.is_active:
		var r: float = _parent_ref.radius
		var c: Color = _parent_ref.checkpoint_color
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, c, 2.0)
		draw_circle(Vector2.ZERO, 6.0, c)
"""
	var script := GDScript.new()
	script.source_code = script_src
	script.reload()
	return script


## Chiamato dal Visual node per disegnare
func _draw_checkpoint_visual() -> void:
	if _visual:
		_visual.draw_arc(Vector2.ZERO, radius, 0, TAU, 64, checkpoint_color, 2.0)
		_visual.draw_circle(Vector2.ZERO, 8.0, checkpoint_color)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if checkpoint_id.is_empty():
		warnings.append("CheckPoint requires a checkpoint_id to function properly.")
	return warnings
