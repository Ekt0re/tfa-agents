## example_tutorial_flow.gd
## @tool
## Esempio di flusso tutorial creato via codice.
## Usalo come riferimento per creare i tuoi flussi.
##
## Per usare questo flusso nel tuo gioco:
##   var flow = preload("res://addons/mission_editor/examples/example_tutorial_flow.gd").create_flow()
##   MissionFlowPlayer.start_flow(flow)
@tool
extends RefCounted


## Crea e ritorna un MissionFlow tutorial completo
static func create_flow() -> Resource:
	var MissionDataScript: GDScript = load("res://Scripts/mission_data.gd") as GDScript
	var MissionCmdScript: GDScript = load("res://addons/mission_editor/mission_command.gd") as GDScript
	var MissionFlowScript: GDScript = load("res://addons/mission_editor/mission_flow.gd") as GDScript

	var flow: Resource = MissionFlowScript.new()
	flow.set("flow_id", "tutorial_flow")
	flow.set("flow_name", "Tutorial Flow")
	flow.set("description", "Tutorial sequence: move, aim, fire, eliminate, collect, destroy")

	# ── Missione 1: Muovi con WASD ──
	var m1: Resource = MissionDataScript.new()
	m1.set("mission_id", "tutorial_move")
	m1.set("label", "mission_tutorial_move")
	m1.set("type", 5)  # CUSTOM
	m1.set("target", 0)
	m1.set("accent_color", Color(0.0, 0.898, 1.0, 1.0))
	m1.set("on_success_next", "tutorial_aim")
	m1.set("graph_position", Vector2(50, 50))
	flow.get("missions").append(m1)

	# ── Missione 2: Mira con il mouse ──
	var m2: Resource = MissionDataScript.new()
	m2.set("mission_id", "tutorial_aim")
	m2.set("label", "mission_tutorial_aim")
	m2.set("type", 5)  # CUSTOM
	m2.set("target", 0)
	m2.set("accent_color", Color(0.0, 0.898, 1.0, 1.0))
	m2.set("on_success_next", "tutorial_fire")
	m2.set("graph_position", Vector2(350, 50))
	flow.get("missions").append(m2)

	# ── Missione 3: Spara ──
	var m3: Resource = MissionDataScript.new()
	m3.set("mission_id", "tutorial_fire")
	m3.set("label", "mission_tutorial_fire")
	m3.set("type", 5)  # CUSTOM
	m3.set("target", 0)
	m3.set("accent_color", Color(0.988, 0.38, 0.157, 1.0))
	m3.set("on_success_next", "tutorial_eliminate")
	m3.set("graph_position", Vector2(650, 50))
	flow.get("missions").append(m3)

	# ── Missione 4: Elimina nemici ──
	var m4: Resource = MissionDataScript.new()
	m4.set("mission_id", "tutorial_eliminate")
	m4.set("label", "mission_tutorial_eliminate")
	m4.set("type", 0)  # ELIMINATE
	m4.set("target", 5)
	m4.set("show_progress_bar", true)
	m4.set("accent_color", Color(0.988, 0.38, 0.157, 1.0))
	m4.set("on_success_next", "tutorial_collect")
	m4.set("on_fail_next", "tutorial_retry_combat")
	m4.set("time_limit", 120.0)  # 2 minuti per eliminare
	m4.set("graph_position", Vector2(950, 50))
	# Comando al completamento: suona effetto vittoria
	var cmd_sound: Resource = MissionCmdScript.new()
	cmd_sound.set("command_type", 0)  # PLAY_SOUND
	cmd_sound.set("parameters", {"path": "res://Assets/Audio/Music/Drinking.mp3", "volume_db": -6.0})
	cmd_sound.set("description", "Play victory jingle")
	m4.get("on_complete_commands").append(cmd_sound)
	flow.get("missions").append(m4)

	# ── Missione 4b: Retry (fallback se fallisce) ──
	var m4b: Resource = MissionDataScript.new()
	m4b.set("mission_id", "tutorial_retry_combat")
	m4b.set("label", "RETRY COMBAT")
	m4b.set("type", 5)  # CUSTOM
	m4b.set("target", 0)
	m4b.set("accent_color", Color(1.0, 0.3, 0.3, 1.0))
	m4b.set("on_success_next", "tutorial_eliminate")  # Ritorna al combattimento
	m4b.set("graph_position", Vector2(950, 250))
	flow.get("missions").append(m4b)

	# ── Missione 5: Raccogli item ──
	var m5: Resource = MissionDataScript.new()
	m5.set("mission_id", "tutorial_collect")
	m5.set("label", "mission_tutorial_collect")
	m5.set("type", 1)  # COLLECT
	m5.set("target", 3)
	m5.set("show_progress_bar", true)
	m5.set("accent_color", Color(0.2, 0.9, 0.4, 1.0))
	m5.set("on_success_next", "tutorial_destroy")
	m5.set("graph_position", Vector2(1250, 50))
	flow.get("missions").append(m5)

	# ── Missione 6: Distruggi barili ──
	var m6: Resource = MissionDataScript.new()
	m6.set("mission_id", "tutorial_destroy")
	m6.set("label", "mission_tutorial_destroy")
	m6.set("type", 0)  # ELIMINATE (barili)
	m6.set("target", 4)
	m6.set("show_progress_bar", true)
	m6.set("accent_color", Color(1.0, 0.5, 0.0, 1.0))
	m6.set("on_success_next", "tutorial_done")
	m6.set("graph_position", Vector2(1550, 50))
	# Comando: cambia scena dopo il completamento
	var cmd_scene: Resource = MissionCmdScript.new()
	cmd_scene.set("command_type", 1)  # CHANGE_SCENE
	cmd_scene.set("parameters", {"scene_path": "res://Maps/dev_map.tscn"})
	cmd_scene.set("delay", 2.0)
	cmd_scene.set("description", "Go to main map after tutorial")
	m6.get("on_complete_commands").append(cmd_scene)
	flow.get("missions").append(m6)

	# ── Missione 7: Tutorial completato ──
	var m7: Resource = MissionDataScript.new()
	m7.set("mission_id", "tutorial_done")
	m7.set("label", "mission_tutorial_done")
	m7.set("type", 5)  # CUSTOM
	m7.set("target", 0)
	m7.set("accent_color", Color(0.3, 1.0, 0.3, 1.0))
	m7.set("graph_position", Vector2(1850, 50))
	flow.get("missions").append(m7)

	flow.set("start_mission_id", "tutorial_move")
	return flow
