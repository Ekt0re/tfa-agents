extends Node

## Segnale globale emesso quando un'entità attraversa una rampa e cambia livello.
## - entity: il nodo che ha attraversato la rampa (es. PlayerPrototype, nemico)
## - new_level: il livello di altezza raggiunto dopo la transizione
## - ramp: il nodo della rampa attraversata
signal ramp_traversed(entity: Node2D, new_level: int, ramp: Node2D)
