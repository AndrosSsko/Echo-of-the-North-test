extends CharacterBody3D

enum CompanionStealthState { IDLE_FOLLOW, POINT_SAFE, COWER_DANGER }
var current_stealth_mood: CompanionStealthState = CompanionStealthState.IDLE_FOLLOW
var tactical_scan_cooldown: float = 0.0

# --- EMBERBOND CONFIGURATION MATRIX [PDF: 0.1.2] ---
@export_category("Emberbond Tracking")
@export var target_player_path: NodePath = "../Player"
@export var ideal_follow_distance: float = 3.5
@export var maximum_leash_distance: float = 25.0

@export_category("Locomotion Matrix")
@export var tracking_speed: float = 6.5
@export var wall_catchup_speed: float = 12.0 # High speed burst when cutting corners [PDF: 0.1.2]
@export var acceleration: float = 10.0
@export var visual_rotation_speed: float = 8.0

# --- NARRATIVE PROGRESSION STATES [PDF: 0.1.2] ---
var current_bond_stage: String = "Cinder"

# --- PRIVATE COMPANION SYSTEM VARIABLES [PDF: 0.1.2] ---
var player_character: CharacterBody3D = null

# Scene tree node caching references [PDF: 0.1.13, 0.1.14]
@onready var main_capsule_collision: CollisionShape3D = $CollisionShape3D
@onready var primitive_visual_mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("PetGroup") # Ensures Eira's single-click tripwire query passes straight through his body!
	var players = get_tree().get_nodes_in_group("PlayerGroup")
	if players.size() > 0:
		player_character = players[0]
	else:
		print("COMPANION: Smudge initialized. Waiting for player to spawn into level.")

func _physics_process(delta: float) -> void:
	process_takedown_safety_analyzer(delta)
	
	if not is_instance_valid(player_character):
		var players = get_tree().get_nodes_in_group("PlayerGroup")
		if players.size() > 0:
			player_character = players[0] as CharacterBody3D
			print("COMPANION: Smudge successfully locked tracking coordinates onto Eira!")
		return # Wait for the next frame if the player isn't ready yet [PDF: 0.1.3]

	if Input.is_action_just_pressed("companion_command"):
		execute_contextual_command()

	# 1. SAMPLE COORDINATES & VECTOR DISTANCE [PDF: 0.1.3]
	var vector_to_player: Vector3 = player_character.global_position - global_position
	var distance_to_player: float = vector_to_player.length()
	var flat_direction: Vector3 = vector_to_player
	flat_direction.y = 0.0
	flat_direction = flat_direction.normalized()

	# 2. RUN ARCHITECTURAL LINE-OF-SIGHT CHECK [PDF: 0.1.3]
	var is_wall_blocking: bool = check_if_blocked_by_wall()

	# 3. ADVANCED STEERING MACHINE [PDF: 0.1.4]
	if distance_to_player > maximum_leash_distance or (is_wall_blocking and distance_to_player > 7.0):
		# SHADOW BLINK: If a wall traps him far away, he instantly snaps safely back to Eira [PDF: 0.1.4]
		global_position = player_character.global_position - (flat_direction * ideal_follow_distance)
		velocity = Vector3.ZERO
		print("SMUDGE: Shadow-slips through the ruin walls to reach Eira.")
		
	elif distance_to_player > ideal_follow_distance:
		# KINDLE CATCHUP STATE: Dynamically boost speed if a wall drags against his collision [PDF: 0.1.4]
		var current_speed: float = wall_catchup_speed if is_wall_blocking else tracking_speed
		var movement_vector: Vector3 = flat_direction
		
		if is_on_wall():
			movement_vector = movement_vector.slide(get_wall_normal()).normalized()
			
		var target_velocity: Vector3 = movement_vector * current_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		
		# Turn to face his active movement vector path cleanly during locomotion sweeps
		if Vector2(velocity.x, velocity.z).length_squared() > 0.01:
			var target_angle: float = atan2(-velocity.x, -velocity.z)
			rotation.y = lerp_angle(rotation.y, target_angle, visual_rotation_speed * delta)
	else:
		# IDLE STANCE LOOK GATES: Turn head smoothly to monitor his player master when sitting [PDF: 0.1.4, 0.1.5]
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
		
		var look_target: Vector3 = player_character.global_position
		look_target.y = global_position.y
		var target_angle: float = atan2(-(look_target.x - global_position.x), -(look_target.z - global_position.z))
		rotation.y = lerp_angle(rotation.y, target_angle, visual_rotation_speed * delta)

	# Gravity Snap [PDF: 0.1.5]
	if not is_on_floor():
		var default_engine_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= default_engine_gravity * delta
	else:
		velocity.y = -0.1
		
	move_and_slide()

# --- OPTIMIZED SENSORY RAYCAST LOGIC [PDF: 0.1.5] ---
func check_if_blocked_by_wall() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.4, 0.0), # Origin: Smudge center height
		player_character.global_position + Vector3(0.0, 0.5, 0.0) # Target: Eira center height
	)
	ray_query.exclude = [self.get_rid()]
	var ray_result: Dictionary = space_state.intersect_ray(ray_query)
	
	if not ray_result.is_empty():
		var hit_object: Node = ray_result["collider"]
		if hit_object.name != "Player" and not hit_object.is_in_group("PlayerGroup"):
			return true
	return false

# --- NARRATIVE COMMAND HOOKS [PDF: 0.1.6] ---
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
	print("COMMAND: Smudge lets out an echolocation click, illuminating hunter bones through ruins!")

# --- STEALTH ANALYZER & TAKEDOWN MONITOR [PDF: 0.1.6, 0.1.7] ---
func process_takedown_safety_analyzer(delta: float) -> void:
	tactical_scan_cooldown -= delta
	if tactical_scan_cooldown > 0.0: return
	
	tactical_scan_cooldown = 0.15 # Scan roughly 6 times a second [PDF: 0.1.7]
	if not is_instance_valid(player_character): return
	
	var all_enemies = []
	var target_guard: Node3D = null
	
	# 1. CHECK IF EIRA IS ACTIVELY CROUCHING AND CLOSING IN ON A GUARD [PDF: 0.1.7]
	if player_character.get("is_crouching"):
		all_enemies = get_tree().get_nodes_in_group("EnemyGroup")
		for enemy in all_enemies:
			if is_instance_valid(enemy) and "current_phase" in enemy:
				if player_character.global_position.distance_to(enemy.global_position) <= 2.5:
					# Match target patrol phase enum names
					if "PatrolPhase" in enemy:
						if enemy.current_phase == enemy.PatrolPhase.MARCHING or enemy.current_phase == enemy.PatrolPhase.INVESTIGATING:
							target_guard = enemy
							break

	# 2. IF NO TAKEDOWN IS IMMINENT, REVERT TO STANDARD BEHAVIOR [PDF: 0.1.7]
	if not is_instance_valid(target_guard):
		if current_stealth_mood != CompanionStealthState.IDLE_FOLLOW:
			current_stealth_mood = CompanionStealthState.IDLE_FOLLOW
			reset_smudge_mesh_posture(delta)
		else:
			# Maintain standard neutral capsule values when idle
			if is_instance_valid(primitive_visual_mesh):
				primitive_visual_mesh.scale = primitive_visual_mesh.scale.lerp(Vector3.ONE, 10.0 * delta)
				primitive_visual_mesh.position.y = lerp(primitive_visual_mesh.position.y, 0.0, 10.0 * delta)
		return

	# 3. SCAN SYSTEM: IS ANY OTHER GUARD WATCHING OUR TARGET? [PDF: 0.1.7, 0.1.8]
	var is_anybody_watching_him: bool = false
	all_enemies = get_tree().get_nodes_in_group("EnemyGroup")
	
	for witness in all_enemies:
		if is_instance_valid(witness) and witness != target_guard and "current_phase" in witness and witness.has_node("VisionSensor3D"):
			# Skip stun or dizzy guards since they can't look up alarms [PDF: 0.1.8]
			if "PatrolPhase" in witness:
				if witness.current_phase == witness.PatrolPhase.STUNNED or witness.current_phase == witness.PatrolPhase.DIZZY:
					continue
					
			var w_sensor = witness.vision_sensor
			var dist_to_target: float = witness.global_position.distance_to(target_guard.global_position)
			
			if dist_to_target <= w_sensor.vision_range:
				var forward_vector: Vector3 = -witness.global_transform.basis.z.normalized()
				var dir_to_target: Vector3 = target_guard.global_position - witness.global_position
				var angle: float = rad_to_deg(forward_vector.angle_to(dir_to_target.normalized()))
				
				if angle <= w_sensor.vision_angle:
					var space_state = get_world_3d().direct_space_state
					var query = PhysicsRayQueryParameters3D.create(witness.global_position + Vector3(0, 0.5, 0), target_guard.global_position + Vector3(0, 0.5, 0))
					query.exclude = [witness.get_rid(), self.get_rid()]
					var hit_data = space_state.intersect_ray(query)
					if hit_data.is_empty() or hit_data["collider"] == target_guard:
						is_anybody_watching_him = true
						break

	# 4. MUTATE SMUDGE'S COMPANION BODY POSTURE RESISTORS [PDF: 0.1.9]
	if is_anybody_watching_him:
		current_stealth_mood = CompanionStealthState.COWER_DANGER
		execute_smudge_cower_animation(target_guard.global_position, delta)
	else:
		current_stealth_mood = CompanionStealthState.POINT_SAFE
		execute_smudge_point_animation(target_guard.global_position, delta)

# =============================================================================
#     DYNAMIC CINEMATIC MESH DISTORTIONS
# =============================================================================
func execute_shadow_slip_reposition(target_pos: Vector3) -> void:
	global_position = target_pos
	velocity = Vector3.ZERO
	if is_instance_valid(primitive_visual_mesh):
		primitive_visual_mesh.scale = Vector3(0.1, 2.5, 0.1) # Extreme flash stretch

func execute_smudge_point_animation(look_target: Vector3, delta: float) -> void:
	# SAFE POINT POSTURE: Spin head forward and stretch his cylinder body toward the target guard! [PDF: 0.1.9]
	var dir = (look_target - global_position).normalized()
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
		
	# Procedural mesh stretching: make his model elongated and focused [PDF: 0.1.9]
	if is_instance_valid(primitive_visual_mesh):
		primitive_visual_mesh.scale = primitive_visual_mesh.scale.lerp(Vector3(0.7, 1.4, 1.4), 10.0 * delta)
		primitive_visual_mesh.position.y = lerp(primitive_visual_mesh.position.y, 0.2, 10.0 * delta)

func execute_smudge_cower_animation(look_target: Vector3, delta: float) -> void:
	# DANGER COWER POSTURE: Turn body completely around backward away from danger zone and pancake! [PDF: 0.1.9]
	var dir = (look_target - global_position).normalized()
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
		
	# Procedural mesh squashing: pancake him flat right onto the floor like a terrified ball! [PDF: 0.1.9, 0.1.10]
	if is_instance_valid(primitive_visual_mesh):
		primitive_visual_mesh.scale = primitive_visual_mesh.scale.lerp(Vector3(1.6, 0.35, 1.6), 10.0 * delta)
		# Lower his visual center to sit flush against the floor tile plane so he doesn't float
		primitive_visual_mesh.position.y = lerp(primitive_visual_mesh.position.y, -0.45, 10.0 * delta)

func reset_smudge_mesh_posture(delta: float) -> void:
	if is_instance_valid(primitive_visual_mesh):
		primitive_visual_mesh.scale = primitive_visual_mesh.scale.lerp(Vector3.ONE, 10.0 * delta)
		primitive_visual_mesh.position.y = lerp(primitive_visual_mesh.position.y, 0.0, 10.0 * delta)
