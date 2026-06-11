extends Node2D
class_name ProjectileVisual

signal impact_reached(target_path: NodePath)

@export var speed: float = 1800.0
@export var trail_length: float = 36.0

@onready var trail: Line2D = $Trail if has_node("Trail") else null

var _impact_position: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.RIGHT
var _remaining_distance: float = 0.0
var _hit_target_path: NodePath = NodePath()
var _completed: bool = false
var _initialized: bool = false


func setup_projectile(start_position: Vector2, end_position: Vector2, projectile_speed: float, height_level: int, hit_target_path: NodePath = NodePath()) -> void:
	global_position = start_position
	_impact_position = end_position
	_hit_target_path = hit_target_path
	speed = maxf(projectile_speed, 1.0)
	z_index = height_level * 10 + 9
	add_to_group("entities_level_" + str(height_level))

	var travel_vector := end_position - start_position
	_remaining_distance = travel_vector.length()
	if _remaining_distance <= 0.001:
		_complete_travel()
		return

	_direction = travel_vector / _remaining_distance
	rotation = _direction.angle()
	_initialized = true
	_update_trail()


func _physics_process(delta: float) -> void:
	if not _initialized or _completed:
		return

	var step_distance: float = speed * delta
	if step_distance >= _remaining_distance:
		global_position = _impact_position
		_remaining_distance = 0.0
		_complete_travel()
		return

	global_position += _direction * step_distance
	_remaining_distance -= step_distance


func _update_trail() -> void:
	if not trail:
		return
	trail.points = PackedVector2Array([
		Vector2(-trail_length, 0.0),
		Vector2.ZERO
	])


func _complete_travel() -> void:
	if _completed:
		return

	_completed = true
	impact_reached.emit(_hit_target_path)
	queue_free()
