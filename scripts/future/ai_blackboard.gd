extends Node
class_name AIBlackboard

## A pure data dictionary attached to the enemy carcass.
var data: Dictionary = {
	"is_slipped": false,
	"is_dizzy": false,
	"suspicion_level": 0.0,
	"patrol_targets": [],
	"current_target_pos": Vector3.ZERO,
}

func set_value(key: String, val) -> void:
	data[key] = val

func get_value(key: String, fallback = null):
	return data.get(key, fallback)
