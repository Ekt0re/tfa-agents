## LevelManager — Node2D
##
## Applica ad ogni nodo Node2D che rappresenta un livello (L0, L1, …).
## Configura automaticamente i TileMapLayer figli (Ground e Walls) con
## physics layer, collision mask e navigation layer isolati per livello.
##
## ─────────────────────────────────────────────────────────────────────
## LEGENDA BIT (1-indexed come nell'editor Godot, 0-indexed nel codice)
## ─────────────────────────────────────────────────────────────────────
##
## PHYSICS / COLLISION LAYERS
##   Bit  1  (1 << 0)  — L0_Ground  : superficie calpestabile livello 0
##   Bit  2  (1 << 1)  — L0_Walls   : muri/ostacoli livello 0
##   Bit  3  (1 << 2)  — L1_Ground  : superficie calpestabile livello 1
##   Bit  4  (1 << 3)  — L1_Walls   : muri/ostacoli livello 1
##   …  pattern: livello N → bit (N*2)+1 per Ground, bit (N*2)+2 per Walls
##
## NAVIGATION LAYERS
##   Bit  1  (1 << 0)  — navigazione livello 0
##   Bit  2  (1 << 1)  — navigazione livello 1
##   …  pattern: livello N → bit N
##
## CONVENZIONE COLLISION MASK
##   Ground di un livello collide SOLO con i Walls dello stesso livello,
##   così entità su livelli diversi non si ostruiscono a vicenda.
##   I Walls non hanno mask (non si muovono, non devono "rilevare" nulla).
##
## ─────────────────────────────────────────────────────────────────────

class_name LevelManager
extends Node2D


# ── Proprietà esportate ────────────────────────────────────────────────

## Indice del livello (0 = primo piano, 1 = secondo piano, …).
## Modifica questo valore nell'Inspector: la configurazione viene
## ricalcolata automaticamente in editor e a runtime.
@export var level_index: int = 0 :
	set(value):
		level_index = clampi(value, 0, MAX_LEVELS - 1)
		_apply_level_config()

## Se true, la configurazione viene ricalcolata ogni volta che
## la scena entra nell'albero (utile durante lo sviluppo).
@export var auto_configure_on_ready: bool = true


# ── Costanti ────────────────────────────────────────────────────────────

## Numero massimo di livelli supportati prima di esaurire i bit a 32-bit.
## 16 livelli × 2 layer ciascuno = 32 bit Physics; 32 Navigation layer.
const MAX_LEVELS: int = 16

## Suffissi attesi per i TileMapLayer figli.
const SUFFIX_GROUND: String = "_Ground"
const SUFFIX_WALLS:  String = "_Walls"


# ── Ciclo di vita ────────────────────────────────────────────────────────

func _ready() -> void:
	if auto_configure_on_ready:
		_apply_level_config()


# ── API pubblica ────────────────────────────────────────────────────────

## Ricalcola e applica la configurazione a tutti i TileMapLayer figli.
## Chiamabile manualmente se la scena viene modificata a runtime.
func apply_config() -> void:
	_apply_level_config()


# ── Logica interna ───────────────────────────────────────────────────────

func _apply_level_config() -> void:
	# Calcola i bit per questo livello.
	var ground_physics_layer: int = _ground_physics_layer(level_index)
	var walls_physics_layer:  int = _walls_physics_layer(level_index)
	var nav_layer:            int = _navigation_layer(level_index)

	# Ground collide con i Walls dello stesso livello.
	var ground_mask: int = walls_physics_layer

	# Walls non rilevare collisioni (mask = 0); sono statici.
	var walls_mask: int = 0

	for child: Node in get_children():
		if child is TileMapLayer:
			var tile_layer := child as TileMapLayer
			if _is_ground(tile_layer.name):
				_configure_tile_layer(tile_layer, ground_physics_layer, ground_mask, nav_layer)
			elif _is_walls(tile_layer.name):
				_configure_tile_layer(tile_layer, walls_physics_layer, walls_mask, nav_layer)


func _configure_tile_layer(
		layer:          TileMapLayer,
		physics_layer:  int,
		collision_mask: int,
		nav_layer:      int) -> void:

	# Physics layer 0 corrisponde al primo physics layer del TileSet.
	layer.set_physics_layer_collision_layer(0, physics_layer)
	layer.set_physics_layer_collision_mask(0, collision_mask)
	layer.set_navigation_layer_layers(0, nav_layer)


# ── Calcolo bit mask ────────────────────────────────────────────────────

## Restituisce il bit (come maschera) assegnato al Ground del livello N.
## Esempio: N=0 → 0b0001, N=1 → 0b0100, N=2 → 0b010000
static func _ground_physics_layer(index: int) -> int:
	return 1 << (index * 2)


## Restituisce il bit (come maschera) assegnato ai Walls del livello N.
## Esempio: N=0 → 0b0010, N=1 → 0b1000, N=2 → 0b100000
static func _walls_physics_layer(index: int) -> int:
	return 1 << (index * 2 + 1)


## Restituisce il bit (come maschera) assegnato alla navigation del livello N.
## Esempio: N=0 → 0b01, N=1 → 0b10, N=2 → 0b100
static func _navigation_layer(index: int) -> int:
	return 1 << index


# ── Identificazione figli ───────────────────────────────────────────────

static func _is_ground(node_name: StringName) -> bool:
	return (node_name as String).ends_with(SUFFIX_GROUND)


static func _is_walls(node_name: StringName) -> bool:
	return (node_name as String).ends_with(SUFFIX_WALLS)
