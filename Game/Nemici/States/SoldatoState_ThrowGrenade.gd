## SoldatoState_ThrowGrenade.gd
## Stato LANCIO GRANATA — Solo classe Granatiere (classe == 5).
##
## TODO: Implementare quando la scena granata sarà disponibile.
## Per ora: placeholder che torna immediatamente allo stato Attack.
##
## Future transizioni pianificate:
##   → Attack:      dopo aver lanciato la granata (cooldown completato)
##   → Chase:       se il nemico esce dal range mentre si prepara

extends LimboState

var _bot: SoldatoBot

func _setup() -> void:
	_bot = agent as SoldatoBot

func _enter() -> void:
	# Placeholder: torna immediatamente ad attaccare
	# Quando la granata sarà implementata, qui si animerà il lancio
	push_warning("[SoldatoBot] ThrowGrenade state: granata non ancora implementata.")
	dispatch(&"out_of_range")

func _update(_delta: float) -> void:
	dispatch(&"out_of_range")

func _exit() -> void:
	pass
