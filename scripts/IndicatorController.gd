extends Node3D

@export var indicator_rig: Node3D
@export var player_reference: CharacterBody3D

func update_visual_indicators(is_aiming: bool, aim_dir: Vector3, charge_timer: float, delta: float) -> void:
	if not is_instance_valid(indicator_rig) or not is_instance_valid(player_reference): return
	
	var flat_pointer = indicator_rig.get_node_or_null("Aim_Line_Pointer")
	var lob_pointer = indicator_rig.get_node_or_null("Lob_Line_Pointer")
	
	var _look_axis: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var is_controller_aiming: bool = Input.get_vector("look_left", "look_right", "look_up", "look_down").length_squared() > 0.04
	var _should_aim: bool = is_aiming or is_controller_aiming
	
	# STRICT VISIBILITY SHUTTER GATE: Completely wipes out ghost pointers when running!
	if flat_pointer: flat_pointer.visible = false
	if lob_pointer: lob_pointer.visible = false

	var is_lob: bool = false
	var deck = player_reference.equipped_gadgets_deck
	var idx = player_reference.current_selected_gadget_index
	
	if not deck.is_empty() and idx < deck.size():
		var active_card = deck[idx]
		if is_instance_valid(active_card): 
			is_lob = active_card.project_parabolic_lob_arc
			
	# Enforce absolute unique separation switches
	if is_lob:
		if flat_pointer: flat_pointer.visible = false
		if lob_pointer: lob_pointer.visible = true
		
		# Explicitly awaken the line visual node so LobPredictor can paint the path
		var line_visual_node = indicator_rig.get_node_or_null("Lob_Line_Pointer/Line_Visual")
		if is_instance_valid(line_visual_node): line_visual_node.visible = true
		return 
	else:
		if flat_pointer: flat_pointer.visible = true
		if lob_pointer: lob_pointer.visible = false
		
		# FIXED HARD RESET GATE: Forcefully shut off the lob visual decal!
		# This completely halts your automated LobPredictor script from drawing ghost wind ribbons!
		var line_visual_node = indicator_rig.get_node_or_null("Lob_Line_Pointer/Line_Visual")
		if is_instance_valid(line_visual_node): line_visual_node.visible = false
		
	# Process our direct-fire wind tunnel mesh dimensions
	var laser_mesh_node = flat_pointer.get_node_or_null("Line_Visual") as Node3D
	if is_instance_valid(laser_mesh_node):
		laser_mesh_node.visible = true
		
		var max_charge_time: float = 1.5
		var charge_ratio = clampf(charge_timer / max_charge_time, 0.0, 1.0)
		var max_laser_range = lerpf(2.5, 15.0, charge_ratio) if is_aiming else 15.0
		var width_grow = lerpf(0.5, 1.3, charge_ratio) if is_aiming else 0.5
		
		var space_state = get_world_3d().direct_space_state
		var laser_start = player_reference.global_position + Vector3(0.0, 0.8, 0.0)
		var laser_end = laser_start + aim_dir * max_laser_range
		
		var ray_param = PhysicsRayQueryParameters3D.create(laser_start, laser_end)
		ray_param.exclude = [player_reference.get_rid()]
		var ray_result = space_state.intersect_ray(ray_param)
		
		var actual_laser_length = max_laser_range
		if not ray_result.is_empty():
			actual_laser_length = laser_start.distance_to(ray_result["position"])
			
		# RE-ALIGNED TRANSFORMS FOR FLAT BLENDER EXPORTS
		laser_mesh_node.scale.y = actual_laser_length
		laser_mesh_node.scale.x = width_grow
		laser_mesh_node.scale.z = width_grow
		
		if is_aiming:
			var dynamic_spin_speed = lerpf(1.5, 7.0, charge_ratio)
			laser_mesh_node.rotate_z(dynamic_spin_speed * delta)
			
		laser_mesh_node.global_position = laser_start + (aim_dir * (actual_laser_length / 2.0))
		
		# Prevent cross-axis matrix shearing completely
		var target_basis = Basis()
		target_basis.z = aim_dir
		target_basis.x = Vector3.UP.cross(target_basis.z).normalized()
		target_basis.y = target_basis.z.cross(target_basis.x).normalized()
		laser_mesh_node.global_transform.basis = target_basis
