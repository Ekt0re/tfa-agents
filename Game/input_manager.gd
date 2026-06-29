extends CanvasLayer

@onready var right_stick: VirtualJoystickPlus = $right_stick
@onready var action_button: Button = $action_button

## Distanza del button dal centro del joystick (in pixel)
@export var button_offset: Vector2 = Vector2(150, -50)


func _ready() -> void:
	# Collega il segnale del button
	action_button.pressed.connect(_on_action_button_pressed)
	
	# Aggiorna il posizionamento quando la scena è pronta
	_update_button_position()


func _process(_delta: float) -> void:
	# Aggiorna continuamente la posizione del button per seguire il joystick
	_update_button_position()


func _update_button_position() -> void:
	if not is_instance_valid(right_stick) or not is_instance_valid(action_button):
		return
	
	# Calcola la posizione globale del centro del joystick destro
	var joystick_global_pos = right_stick.global_position + right_stick.size / 2.0
	
	# Posiziona il button relativo al joystick + offset
	action_button.global_position = joystick_global_pos + button_offset - action_button.size / 2.0


func _on_action_button_pressed() -> void:
	# Qui gestisci l'azione del button
	print("Action button pressed!")
	# Esempio: emetti un segnale, chiama una funzione del player, ecc.
	# GameEvents.action_pressed.emit()
