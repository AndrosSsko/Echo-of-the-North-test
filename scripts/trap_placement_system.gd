extends Node3D
class_name TrapPlacementSystem

@export var max_rope_reach_limit: float = 7.0
@export var proximity_search_distance: float = 4.0
@export var tactical_cooldown_duration: float = 0.4

@onready var preview_main_housing: Node3D = $"../../EiraVisualCapsuleMesh/AimIndicators/Wall_Trap_Pointer/Preview_Main_Housing"
@onready var preview_stone_bolt: Node3D = $"../../EiraVisualCapsuleMesh/AimIndicators/Wall_Trap_Pointer/Preview_Stone_Bolt"
@onready var preview_rope_visual: MeshInstance3D = $"../../EiraVisualCapsuleMesh/AimIndicators/Wall_Trap_Pointer/Preview_Rope_Visual"
@onready var wall_trap_pointer_folder: Node3D = $"../../EiraVisualCapsuleMesh/AimIndicators/Wall_Trap_Pointer"

var is_actively_placing: bool = false
var is_placement_valid: bool = false
var calculated_pos_a: Vector3 = Vector3.ZERO
var calculated_pos_b: Vector3 = Vector3.ZERO
var calculated_normal_a: Vector3 = Vector3.ZERO
var calculated_normal_b: Vector3 = Vector3.ZERO

var player_character: CharacterBody3D = null
var deployment_lockout_cooldown_timer: float = 0.0

func _ready() -> void:
	player_character = get_parent().get_parent() as CharacterBody3D
	_shut_down_all_previews()

func start_aiming() -> void:
	if deployment_lockout_cooldown_timer > 0.0: return
	if not is_instance_valid(player_character): return
	
	# === FIXED AMMUNITION VALVE: BLOCK PLACEMENT AT ZERO AMMO ===
	# Safely lookup her master dictionary records using the strict text key string name
	var remaining_traps_count: int = player_character.current_ammo_deck_record.get("Tripwire Trap", 0)
	if remaining_traps_count <= 0:
		_shut_down_all_previews()
		return # Reject placement completely! No holographic previews will turn on!
	
	is_actively_placing = true
	if is_instance_valid(wall_trap_pointer_folder):
		wall_trap_pointer_folder.visible = true

func stop_aiming_and_cancel() -> void:
	is_actively_placing = false
	_shut_down_all_previews()

func execute_final_deployment() -> void:
	if not is_actively_placing: return
	is_actively_placing = false
	
	if is_placement_valid and is_instance_valid(player_character):
		# Verify she has ammo left on the exact frame of execution
		var remaining_traps_count: int = player_character.current_ammo_deck_record.get("Tripwire Trap", 0)
		if remaining_traps_count <= 0:
			_shut_down_all_previews()
			return
			
		var active_card = player_character.equipped_gadgets_deck[player_character.current_selected_gadget_index]
		if is_instance_valid(active_card) and active_card.projectile_scene_file:
			var trap_scene_instance = active_card.projectile_scene_file.instantiate() as Node3D
			get_tree().current_scene.add_child(trap_scene_instance)
			
			if trap_scene_instance.has_method("initialize_tripwire"):
				trap_scene_instance.initialize_tripwire(calculated_pos_a, calculated_pos_b)
				
			# === FIXED SYNC: FORCED SUBTRACTION VIA EXPLICIT DICTIONARY KEY ===
			player_character.current_ammo_deck_record["Tripwire Trap"] -= 1
			
			# Force-update her inspector helper variables and HUD labels synchronously
			player_character.trap_ammo = player_character.current_ammo_deck_record["Tripwire Trap"]
			player_character.update_ammo_hud_display()
			
			print("🪤 TRAP ENGINE: Mounted successfully! Remaining ammo: ", player_character.trap_ammo)
			deployment_lockout_cooldown_timer = tactical_cooldown_duration
	else:
		print("⚠️ TRAP ENGINE: Deployment failed. Stand closer to a structural wall face.")
		
	_shut_down_all_previews()

func _physics_process(delta: float) -> void:
	if deployment_lockout_cooldown_timer > 0.0:
		deployment_lockout_cooldown_timer -= delta
		
	if not is_actively_placing or not is_instance_valid(player_character): return
	
	var space_state = get_world_3d().direct_space_state
	var eye_origin: Vector3 = player_character.global_position + Vector3(0.0, 0.4, 0.0)
	
	var forward_heading: Vector3 = -player_character.global_transform.basis.z.normalized()
	if is_instance_valid(player_character.eira_body_mesh):
		forward_heading = -player_character.eira_body_mesh.global_transform.basis.z.normalized()

	var global_exclusion_array: Array = []
	global_exclusion_array.append(player_character.get_rid())
	
	# Try Path A: Direct scene root tree fallback search
	var smudge_node = get_tree().current_scene.find_child("Smudge", true, false)
	
	# Try Path B: Symmetrical parent sibling directory lookup matching player.gd [PDF: 0.1.28]
	if not is_instance_valid(smudge_node) and is_instance_valid(player_character):
		smudge_node = player_character.get_node_or_null("../Smudge")
		
	# Inject his RID if found successfully through either file directory track
	if is_instance_valid(smudge_node) and smudge_node is CollisionObject3D:
		global_exclusion_array.append(smudge_node.get_rid())
	
	# Try Path C: Case-insensitive fallback group sweeps
	var all_potential_pets = get_tree().get_nodes_in_group("PetGroup")
	for pet_node in all_potential_pets:
		if pet_node is CollisionObject3D and not pet_node.get_rid() in global_exclusion_array: 
			global_exclusion_array.append(pet_node.get_rid())
			
	# Filter out patrolling human guards smoothly
	var guards_list = get_tree().get_nodes_in_group("EnemyGroup")
	for guard_node in guards_list:
		if guard_node is CollisionObject3D: 
			global_exclusion_array.append(guard_node.get_rid())

	# =============================================================================
	#     1. THE MAGNETIC MULTI-RAY ANGULAR RADAR SWEEP
	# =============================================================================
	var closest_hit_data: Dictionary = {}
	var shortest_hit_distance: float = 999.0
	
	var sweep_rays_count: int = 7
	var sweep_fov_angle: float = 90.0 
	var start_angle: float = -sweep_fov_angle * 0.5
	var angle_increment: float = sweep_fov_angle / float(sweep_rays_count - 1)
	
	for i in range(sweep_rays_count):
		var ray_angle_rad: float = deg_to_rad(start_angle + (i * angle_increment))
		var search_dir: Vector3 = forward_heading.rotated(Vector3.UP, ray_angle_rad).normalized()
		
		var radar_query = PhysicsRayQueryParameters3D.create(eye_origin, eye_origin + (search_dir * proximity_search_distance))
		radar_query.exclude = global_exclusion_array
		radar_query.collision_mask = 1
		
		var radar_hit = space_state.intersect_ray(radar_query)
		if not radar_hit.is_empty():
			var hit_norm = radar_hit["normal"]
			if abs(hit_norm.dot(Vector3.UP)) < 0.15:
				var dist: float = eye_origin.distance_to(radar_hit["position"])
				if dist < shortest_hit_distance:
					shortest_hit_distance = dist
					closest_hit_data = radar_hit

	if closest_hit_data.is_empty():
		_hide_all_holograms()
		return
		
	var pos_a: Vector3 = closest_hit_data["position"]
	var normal_a: Vector3 = closest_hit_data["normal"]
	pos_a.y = player_character.global_position.y + 0.4

	# =============================================================================
	#     2. PERPENDICULAR CORRIDOR BRIDGE SEARCH (FIND OPPOSITE WALL B)
	# =============================================================================
	var project_harpoon_dir: Vector3 = normal_a.normalized()
	var wall_b_query = PhysicsRayQueryParameters3D.create(pos_a + (project_harpoon_dir * 0.05), pos_a + (project_harpoon_dir * (max_rope_reach_limit + 0.5)))
	wall_b_query.exclude = global_exclusion_array
	wall_b_query.collision_mask = 1
	var wall_b_hit = space_state.intersect_ray(wall_b_query)
	
	if wall_b_hit.is_empty():
		_hide_all_holograms()
		return
		
	var pos_b: Vector3 = wall_b_hit["position"]
	pos_b.y = pos_a.y
	
	var rope_span_distance: float = pos_a.distance_to(pos_b)
	if rope_span_distance > max_rope_reach_limit or rope_span_distance < 1.0:
		_hide_all_holograms()
		return

	# =============================================================================
	#     3. APPLY ABSOLUTE MATRIX TRANSFORMS TO BLUE MESHES
	# =============================================================================
	is_placement_valid = true
	calculated_pos_a = pos_a
	calculated_pos_b = pos_b
	calculated_normal_a = normal_a
	calculated_normal_b = wall_b_hit["normal"]
	
	if is_instance_valid(preview_main_housing):
		preview_main_housing.visible = true
		preview_main_housing.global_position = pos_a
		preview_main_housing.look_at(pos_a + normal_a, Vector3.UP)
		
	if is_instance_valid(preview_stone_bolt):
		preview_stone_bolt.visible = true
		preview_stone_bolt.global_position = pos_b
		preview_stone_bolt.look_at(pos_b + wall_b_hit["normal"], Vector3.UP)
		
	if is_instance_valid(preview_rope_visual):
		preview_rope_visual.visible = true
		preview_rope_visual.global_position = pos_a.lerp(pos_b, 0.5)
		preview_rope_visual.look_at(pos_b, Vector3.UP)
		preview_rope_visual.scale = Vector3(1.0, 1.0, rope_span_distance)

func _hide_all_holograms() -> void:
	is_placement_valid = false
	if is_instance_valid(preview_main_housing): preview_main_housing.visible = false
	if is_instance_valid(preview_rope_visual): preview_rope_visual.visible = false
	if is_instance_valid(preview_stone_bolt): preview_stone_bolt.visible = false

func _shut_down_all_previews() -> void:
	is_placement_valid = false
	_hide_all_holograms()
	if is_instance_valid(wall_trap_pointer_folder): wall_trap_pointer_folder.visible = false
