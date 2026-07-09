extends Node3D

@export var lerp_speed: float = 8.0
var target_character: CharacterBody3D = null

func _ready() -> void:
	# Use the PlayerGroup to find the target
	var players = get_tree().get_nodes_in_group("PlayerGroup")
	if players.size() > 0:
		target_character = players[0]
	else:
		push_warning("Camera Controller: No player found in 'PlayerGroup'.")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_character):
		# Try to find player if they weren't ready at startup
		var players = get_tree().get_nodes_in_group("PlayerGroup")
		if players.size() > 0:
			target_character = players[0]
		return

	# Smoothly follow the player position
	global_position = global_position.lerp(target_character.global_position, lerp_speed * delta)
