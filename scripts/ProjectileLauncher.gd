extends Node3D

signal ammo_updated

func fire_selected_gadget(active_card: GadgetResource, player_node: CharacterBody3D, charge_ratio: float, aim_rig: Node3D) -> void:
	if not is_instance_valid(active_card) or not is_instance_valid(active_card.projectile_scene_file): return
	if not is_instance_valid(player_node): return

	var throw_direction: Vector3 = -player_node.global_transform.basis.z.normalized()
	if is_instance_valid(aim_rig):
		throw_direction = -aim_rig.global_transform.basis.z.normalized()
		throw_direction.y = 0.0
		throw_direction = throw_direction.normalized()

	# Spatial mouse intercept data capture
	var camera = player_node.get_viewport().get_camera_3d()
	var _target_mouse_world_point = null
	if is_instance_valid(camera) and not player_node.is_controller_actively_aiming:
		var mouse_pos = player_node.get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_normal = camera.project_ray_normal(mouse_pos)
		
		var ray_end = ray_origin + (ray_normal * 100.0)
		var ray_param = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		ray_param.exclude = [player_node.get_rid()]
		var result = player_node.get_world_3d().direct_space_state.intersect_ray(ray_param)
		if not result.is_empty():
			_target_mouse_world_point = result["position"]

	var active_lob_distance: float = 8.0
	if "master_tactical_lob_distance" in player_node:
		active_lob_distance = player_node.master_tactical_lob_distance
	
	active_lob_distance = clampf(active_lob_distance, 1.5, 14.0)

	# Instantiate the physical object payload [PDF: 0.1.62]
	var object_instance = active_card.projectile_scene_file.instantiate()
	get_tree().current_scene.add_child(object_instance)
	object_instance.global_position = player_node.global_position + Vector3(0.0, 0.8, 0.0) + (throw_direction * 0.6)
	if object_instance.has_method("add_collision_exception_with"):
		object_instance.add_collision_exception_with(player_node)

	# Dispatch spatial impulse speeds based on trajectory modes [PDF: 0.1.62]
	if active_card.project_parabolic_lob_arc:
		var gravity_accel: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		
		# Calculates the exact velocity matching her indicator ribbon bounds perfectly!
		var accurate_launch_strength: float = sqrt((active_lob_distance * gravity_accel) / sin(2.0 * deg_to_rad(45.0)))
		var accurate_velocity: Vector3 = (throw_direction + Vector3(0.0, 0.45, 0.0)).normalized() * accurate_launch_strength
		
		if object_instance.has_method("apply_central_impulse"):
			object_instance.apply_central_impulse(accurate_velocity)
		elif "Launch_Direction" in object_instance:
			object_instance.Launch_Direction = accurate_velocity
		if "is_active" in object_instance: 
			object_instance.is_active = true
	else:
		# Standard direct fire launch impulse configurations [PDF: 0.1.62]
		var dynamic_speed_impulse: float = active_card.throw_impulse * lerpf(0.7, 1.6, charge_ratio)
		if object_instance.has_method("initialize_bola_flight"):
			object_instance.initialize_bola_flight(throw_direction, dynamic_speed_impulse)
		elif object_instance.has_method("apply_central_impulse"):
			object_instance.apply_central_impulse(throw_direction * dynamic_speed_impulse)
		if "charge_level" in object_instance: 
			object_instance.charge_level = charge_ratio
			
	# Notify parent nodes to update ammunition data limits seamlessly
	ammo_updated.emit(active_card.display_name)
