extends Area2D
class_name HeightTransitionArea

## Il livello di altezza di destinazione quando un player entra in questa area (0 per Terra, 1 per Elevato)
@export var target_level: int = 0

func _ready() -> void:
	# Collega il segnale body_entered a runtime se non è già collegato nell'editor
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# Controlla se il corpo ha il metodo change_height_level (tipicamente il Player o un Nemico)
	if body.has_method("change_height_level"):
		body.change_height_level(target_level)
