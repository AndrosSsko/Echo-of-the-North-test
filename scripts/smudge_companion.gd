extends CharacterBody3D

# --- EMBERBOND CONFIGURATION MATRIX ---
@export_category("Emberbond Tracking")
@export var target_player_path: NodePath = "../Player"
@export var ideal_follow_distance: float = 3.5
@export var maximum_leash_distance: float = 25.0

@export_category("Locomotion Matrix")
@export var tracking_speed: float = 6.5
@export var wall_catchup_speed: float = 12.0 # High speed burst when cutting corners
@export var acceleration: float = 10.0
@export var visual_rotation_speed: float = 8.0

# --- NARRATIVE PROGRESSION STATES ---
var current_bond_stage: String = "Cinder" 

# --- PRIVATE COMPANION SYSTEM VARIABLES ---
var player_character: CharacterBody3D = null

func _ready() -> void:
	var players = get_tree().get_nodes_in_group("PlayerGroup")
	if players.size() > 0:
		player_character = players[0]
	else:
		print("COMPANION: Smudge initialized. Waiting for player to spawn into level.")
		
		

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player_character):
		var players = get_tree().get_nodes_in_group("PlayerGroup")
		if players.size() > 0:
			player_character = players[0] as CharacterBody3D
			print("COMPANION: Smudge successfully locked tracking coordinates onto Eira!")
		return # Wait for the next frame if the player isn't ready yet
		
	# The rest of your existing companion movement and command logic continues perfectly below...
	if Input.is_action_just_pressed("companion_command"):
		execute_contextual_command()

	# 1. SAMPLE COORDINATES & VECTOR DISTANCE
	var vector_to_player: Vector3 = player_character.global_position - global_position
	var distance_to_player: float = vector_to_player.length()
	
	var flat_direction: Vector3 = vector_to_player
	flat_direction.y = 0.0
	flat_direction = flat_direction.normalized()

	# 2. RUN ARCHITECTURAL LINE-OF-SIGHT CHECK
	# Check if a solid CSG wall or ruin barrier sits directly between Smudge and Eira
	var is_wall_blocking: bool = check_if_blocked_by_wall()

	# 3. ADVANCED STEERING MACHINE
	if distance_to_player > maximum_leash_distance or (is_wall_blocking and distance_to_player > 7.0):
		# SHADOW BLINK: If a wall completely strands him far away, he vanishes through the floor
		# and instantly snaps safely to Eira's side out of hunter sight lines!
		global_position = player_character.global_position - (flat_direction * ideal_follow_distance)
		velocity = Vector3.ZERO
		print("SMUDGE: Shadow-slips through the ruin walls to reach Eira.")
		
	elif distance_to_player > ideal_follow_distance:
		# KINDLE CATCHUP STATE: Dynamically boost speed if a wall is dragging against his collision mesh
		var current_speed: float = wall_catchup_speed if is_wall_blocking else tracking_speed
		
		# If sliding against a corner, project velocity along the wall surface to slide around cleanly
		var movement_vector: Vector3 = flat_direction
		if is_on_wall():
			movement_vector = movement_vector.slide(get_wall_normal()).normalized()
			
		var target_velocity: Vector3 = movement_vector * current_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		
		var target_angle: float = atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, visual_rotation_speed * delta)
		
	else:
		# IDLE STANCE
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
		
		var look_target: Vector3 = player_character.global_position
		look_target.y = global_position.y
		var target_angle: float = atan2(-(look_target.x - global_position.x), -(look_target.z - global_position.z))
		rotation.y = lerp_angle(rotation.y, target_angle, visual_rotation_speed * delta)

	# Gravity Snap
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

	move_and_slide()

# --- OPTIMIZED SENSORY RAYCAST LOGIC ---

func check_if_blocked_by_wall() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.4, 0.0), # Origin: Smudge center height
		player_character.global_position + Vector3(0.0, 0.5, 0.0) # Target: Eira center height
	)
	
	var ray_result: Dictionary = space_state.intersect_ray(ray_query)
	if not ray_result.is_empty():
		var hit_object: Node = ray_result["collider"]
		# If the raycast lens strikes a static arena wall instead of Eira, line of sight is broken!
		if hit_object.name != "Player":
			return true
			
	return false

# --- NARRATIVE COMMAND HOOKS ---
func execute_contextual_command() -> void:
	match current_bond_stage:
		"Cinder":
			print("Smudge tries to help, but trips over his own oversized wings and chirps nervously.")
		"Kindle":
			deploy_ash_cloud_ability()
		"Flame":
			deploy_wing_shadow_ability()
		"Inferno":
			trigger_thermal_echo_vision()

func deploy_ash_cloud_ability() -> void:
	print("COMMAND: Smudge executes an Ash Puff, creating a soot screen to blind guards!")

func deploy_wing_shadow_ability() -> void:
	print("COMMAND: Smudge spreads his wings, casting a shadow silhouette to hide Eira!")

func trigger_thermal_echo_vision() -> void:
	print("COMMAND: Smudge lets out an echolocation click, illuminating hunter bones through the stone ruins!")
