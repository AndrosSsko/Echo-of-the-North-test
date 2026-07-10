extends Camera3D

# --- CONFIGURATION PARAMETERS ---
@export_category("Target Tracking")
# Path to the node we want to track securely in space
@export var target_node_path: NodePath = "../Player"
# The exact relative offset distance we want to maintain from our target
@export var tracking_offset: Vector3 = Vector3(0.0, 12.0, 12.0)

@export_category("Dampening & Smoothing")
# Controls the weight behavior of the linear tracking interpolation
@export var follow_speed: float = 5.0

# --- PRIVATE STATE VARIABLES ---
var target_character: CharacterBody3D = null

func _ready() -> void:
	var players = get_tree().get_nodes_in_group("PlayerGroup")
	if players.size() > 0:
		target_character = players[0]
	else:
		push_error("Camera Error: No node with group 'PlayerGroup' found in scene tree.")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_character):
		return
		
	# Calculate target destination using your verified camera placement tracking offset
	var target_destination: Vector3 = target_character.global_position + tracking_offset
	
	# Smoothly glide the camera's current position toward the player's position context
	global_position = global_position.lerp(target_destination, follow_speed * delta)
