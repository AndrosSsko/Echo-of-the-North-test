extends Node3D

@export var indicator_rig: Node3D
@export var camera_reference: Camera3D
@export var wind_ribbon_blueprint: PackedScene = preload("res://scenes/vfx/wind_ribbon_node.tscn")
@export var max_path_markers: int = 8

var active_lob_distance: float = 8.0
var marker_pool_array: Array[Node3D] = []
var floating_animation_clock: float = 0.0

func _ready() -> void:
	for child in get_children():
		if child.name.begins_with("WindRibbon_"): child.queue_free()
	if is_instance_valid(wind_ribbon_blueprint):
		for i in range(max_path_markers):
			var ribbon = wind_ribbon_blueprint.instantiate() as Node3D
			add_child(ribbon)
			ribbon.name = "WindRibbon_" + str(i)
			ribbon.visible = false
			marker_pool_array.append(ribbon)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(indicator_rig): return
	var target_decal = indicator_rig.get_node_or_null("Lob_Line_Pointer/Line_Visual") as Decal
	if not is_instance_valid(target_decal): return

	var player_node = get_parent().get_parent() as CharacterBody3D
	if not is_instance_valid(player_node): return

	# Strict Shutter Visibility Check: Safely sleeps if not actively aiming [PDF: 0.1.64]
	if not player_node.is_actively_aiming_gadget or not target_decal.visible:
		for ribbon in marker_pool_array: ribbon.visible = false
		return

	var player_pos: Vector3 = player_node.global_position
	var active_cam = camera_reference if is_instance_valid(camera_reference) else get_viewport().get_camera_3d()
	if not is_instance_valid(active_cam): return

	# =============================================================================
	#     1. IDENTIFY SURFACE INTERSECTIONS & DATA BRIDGING [PDF: 0.1.64]
	# =============================================================================
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = active_cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = active_cam.project_ray_normal(mouse_pos)
	
	# Generate a clean, stable flat plane locked tightly to her current boot height [PDF: 0.1.64]
	var flat_horizon_height_plane = Plane(Vector3.UP, player_node.global_position.y)
	var target_mouse_world_point = flat_horizon_height_plane.intersects_ray(ray_origin, ray_normal)

	var throw_direction: Vector3 = -global_transform.basis.z.normalized()
	var aim_controller_node = get_parent().get_node_or_null("AimController")
	if is_instance_valid(aim_controller_node):
		throw_direction = aim_controller_node.aim_direction

	# EVALUATE RANGE MODIFIERS RELATIVE TO ACTIVE HARDWARE CHANNELS [PDF: 0.1.64, 0.1.65]
	if player_node.is_controller_actively_aiming:
		# GAMEPAD MODE: Direct 1:1 coupling to your synchronized master variable [PDF: 0.1.64]
		active_lob_distance = player_node.master_tactical_lob_distance
	else:
		# MOUSE MODE: Dynamic length tracking relative to your desktop cursor coordinates! [PDF: 0.1.65]
		if target_mouse_world_point:
			var distance_vector: Vector3 = target_mouse_world_point - player_pos
			distance_vector.y = 0.0
			active_lob_distance = distance_vector.length()
			
			# Synchronize her master variable back to match mouse distance sweeps cleanly [PDF: 0.1.65]
			player_node.master_tactical_lob_distance = clampf(active_lob_distance, 1.5, 14.0)
			if distance_vector.length_squared() > 0.1:
				throw_direction = distance_vector.normalized()
				
	# Lock her projection paths inside your safe design constraints [PDF: 0.1.65]
	active_lob_distance = clampf(player_node.master_tactical_lob_distance, 1.5, 14.0)

	# =============================================================================
	#     2. INTRODUCE THE ADVANCED VECTOR BOUNCE SIMULATOR MATRIX [PDF: 0.1.65]
	# =============================================================================
	var gravity_accel: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var adaptive_launch_strength: float = sqrt((active_lob_distance * gravity_accel) / sin(2.0 * deg_to_rad(45.0)))
	
	var start_pos: Vector3 = player_pos + Vector3(0.0, 0.8, 0.0) + (throw_direction * 0.6)
	var trajectory_velocity: Vector3 = (throw_direction + Vector3(0.0, 0.45, 0.0)).normalized() * adaptive_launch_strength
	
	var simulated_position: Vector3 = start_pos
	var step_time_delta: float = (active_lob_distance / adaptive_launch_strength) / float(max_path_markers)
	var terminal_landing_coordinate: Vector3 = start_pos + (throw_direction * active_lob_distance)
	
	var simulated_path_nodes: Array[Vector3] = [start_pos]
	var active_bounces_simulated: int = 0
	var max_simulated_bounces: int = 2
	
	# Instantiate our direct world space state query reference tracker [PDF: 0.1.65]
	var world_space_query = get_world_3d().direct_space_state

	for step in range(max_path_markers * 2):
		if simulated_path_nodes.size() >= max_path_markers: break
		
		var next_simulated_position: Vector3 = simulated_position + (trajectory_velocity * step_time_delta)
		trajectory_velocity.y -= gravity_accel * step_time_delta
		
		var collision_ray = PhysicsRayQueryParameters3D.create(simulated_position, next_simulated_position)
		collision_ray.exclude = [player_node.get_rid()]
		var ray_hit = world_space_query.intersect_ray(collision_ray)
		
		if not ray_hit.is_empty():
			var hit_point: Vector3 = ray_hit["position"]
			var hit_normal: Vector3 = ray_hit["normal"]
			
			# CASE A: Hit flat ground floor tiles -> Terminate loop 
			if hit_normal.dot(Vector3.UP) > 0.6:
				terminal_landing_coordinate = hit_point
				simulated_path_nodes.append(terminal_landing_coordinate)
				break
			# CASE B: Hit a vertical masonry wall face -> Execute vector bounce deflection! 
			elif active_bounces_simulated < max_simulated_bounces:
				active_bounces_simulated += 1
				simulated_position = hit_point + (hit_normal * 0.05)
				
				# Mathematical standard elasticity reflection 
				trajectory_velocity = trajectory_velocity.bounce(hit_normal) * 0.65
				simulated_path_nodes.append(hit_point)
				continue
			else:
				terminal_landing_coordinate = hit_point
				simulated_path_nodes.append(terminal_landing_coordinate)
				break
				
		simulated_position = next_simulated_position
		simulated_path_nodes.append(simulated_position)

	# =============================================================================
	#     3. CONVERT TRANSFORMS AND DRAW THE WIND RIPPLES 
	# =============================================================================
	floating_animation_clock += delta
	for i in range(marker_pool_array.size()):
		var ribbon = marker_pool_array[i]
		if i < simulated_path_nodes.size():
			ribbon.visible = true
			var stagger_offset: float = float(i) * 0.4
			var wave_speed = 6.0 if active_bounces_simulated > 0 else 4.0
			var vertical_wave_sine = sin((floating_animation_clock * wave_speed) + stagger_offset) * 0.05
			
			ribbon.global_position = simulated_path_nodes[i] + Vector3(0.0, vertical_wave_sine, 0.0)
			
			var next_target: Vector3 = terminal_landing_coordinate
			if i < simulated_path_nodes.size() - 1: next_target = simulated_path_nodes[i + 1]
			
			var target_dir: Vector3 = (next_target - ribbon.global_position).normalized()
			var safe_sky: Vector3 = Vector3.UP
			if abs(target_dir.dot(Vector3.UP)) > 0.99: safe_sky = -global_transform.basis.z.normalized()
			
			ribbon.look_at(next_target, safe_sky)
			var size_scale: float = lerpf(1.3, 0.35, float(i) / float(max_path_markers))
			ribbon.scale = Vector3(size_scale, size_scale, size_scale)
		else:
			ribbon.visible = false
			
	# Update target floor decal indicators cleanly 
	if is_instance_valid(target_decal):
		target_decal.global_position = terminal_landing_coordinate
