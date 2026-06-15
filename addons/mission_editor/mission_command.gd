## mission_command.gd
## Resource per definire comandi eseguibili al completamento/fallimento di una missione.
## Usato dal Mission Flow Editor per triggerare azioni personalizzate.
@tool
class_name MissionCommand
extends Resource

## Tipi di comando disponibili
enum CommandType {
	PLAY_SOUND,        ## Riproduce un suono/audio
	CHANGE_SCENE,      ## Cambia scena
	SPAWN_ENEMIES,     ## Spawn nemici
	PLAY_ANIMATION,    ## Riproduce animazione su un nodo
	SET_VARIABLE,      ## Imposta variabile globale
	CALL_METHOD,       ## Chiama metodo su un nodo
	SHOW_DIALOG,       ## Mostra messaggio dialog
	ENABLE_CHECKPOINT, ## Abilita un checkpoint
	DISABLE_CHECKPOINT,## Disabilita un checkpoint
	DELAY,             ## Pausa tra comandi
}

## Tipo di comando
@export var command_type: CommandType = CommandType.PLAY_SOUND

## Parametri del comando (dipende dal tipo)
## PLAY_SOUND:        { "path": "res://...", "volume_db": 0.0, "loop": false }
## CHANGE_SCENE:      { "scene_path": "res://..." }
## SPAWN_ENEMIES:     { "scene_path": "res://...", "count": 3, "position": "checkpoint" }
## PLAY_ANIMATION:    { "node_path": "/root/...", "anim_name": "..." }
## SET_VARIABLE:      { "autoload": "GlobalSettings", "property": "...", "value": ... }
## CALL_METHOD:       { "node_path": "/root/...", "method": "...", "args": [] }
## SHOW_DIALOG:       { "text": "...", "duration": 3.0 }
## ENABLE_CHECKPOINT: { "checkpoint_id": "..." }
## DISABLE_CHECKPOINT:{ "checkpoint_id": "..." }
## DELAY:             { "seconds": 1.0 }
@export var parameters: Dictionary = {}

## Ritardo prima di eseguire il comando (secondi)
@export var delay: float = 0.0

## Se false il comando viene saltato
@export var enabled: bool = true

## Nome descrittivo per l'editor
@export var description: String = ""


## Ritorna un nome leggibile per l'editor
func get_display_name() -> String:
	if not description.is_empty():
		return description
	match command_type:
		CommandType.PLAY_SOUND:
			return "Play Sound: %s" % parameters.get("path", "?")
		CommandType.CHANGE_SCENE:
			return "Change Scene: %s" % parameters.get("scene_path", "?")
		CommandType.SPAWN_ENEMIES:
			return "Spawn %d Enemies" % parameters.get("count", 1)
		CommandType.PLAY_ANIMATION:
			return "Play Anim: %s" % parameters.get("anim_name", "?")
		CommandType.SET_VARIABLE:
			return "Set %s.%s" % [parameters.get("autoload", "?"), parameters.get("property", "?")]
		CommandType.CALL_METHOD:
			return "Call %s.%s()" % [parameters.get("node_path", "?"), parameters.get("method", "?")]
		CommandType.SHOW_DIALOG:
			return "Dialog: %s" % parameters.get("text", "?").left(20)
		CommandType.ENABLE_CHECKPOINT:
			return "Enable Checkpoint: %s" % parameters.get("checkpoint_id", "?")
		CommandType.DISABLE_CHECKPOINT:
			return "Disable Checkpoint: %s" % parameters.get("checkpoint_id", "?")
		CommandType.DELAY:
			return "Delay: %.1fs" % parameters.get("seconds", 1.0)
	return "Unknown"


## Ritorna il colore icona per l'editor
func get_type_color() -> Color:
	match command_type:
		CommandType.PLAY_SOUND:
			return Color(0.3, 0.8, 1.0)
		CommandType.CHANGE_SCENE:
			return Color(1.0, 0.6, 0.2)
		CommandType.SPAWN_ENEMIES:
			return Color(1.0, 0.3, 0.3)
		CommandType.PLAY_ANIMATION:
			return Color(0.9, 0.5, 1.0)
		CommandType.SET_VARIABLE:
			return Color(0.5, 0.9, 0.5)
		CommandType.CALL_METHOD:
			return Color(1.0, 1.0, 0.3)
		CommandType.SHOW_DIALOG:
			return Color(0.7, 0.7, 1.0)
		CommandType.ENABLE_CHECKPOINT, CommandType.DISABLE_CHECKPOINT:
			return Color(0.9, 0.9, 0.4)
		CommandType.DELAY:
			return Color(0.5, 0.5, 0.5)
	return Color.WHITE
