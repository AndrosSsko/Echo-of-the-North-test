extends Node

## EventBus (Autoload Singleton)
## Global broadcast channel for non-lethal gadget communications.

# Convenience enum to satisfy the signal parameters without magic numbers
enum GadgetType { GENERIC, BOLA, SLIME, PEBBLE, BOMB }

## Fired when any non-lethal gadget strikes something in the world.
signal gadget_impact(gadget_type: int, position: Vector3, radius: float)

## Fired when a distraction sound is emitted into the world (e.g. a pebble clattering).
signal distraction_sound_emitted(position: Vector3, volume_intensity: float)

func _ready() -> void:
	print("📡 EVENT BUS: Core communication singleton successfully initialized.")
